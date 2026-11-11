#!/usr/bin/env python3
"""Boot-capture: boots an Aegis OS ISO in QEMU, drives the shell over QMP and
captures screenshots: silent boot timeline, home desktop, Files, Terminal,
Settings and Control Center. Designed for CI runners; also runs locally.

If the desktop does not come up, the script logs into the guest over the
serial console (interactive socket chardev), dumps diagnostics, and attempts
live recovery (start SDDM / isolate graphical.target) before giving up.

Usage: python3 boot-capture.py <iso> [screenshot-dir]
"""
import json, os, re, shutil, socket, subprocess, sys, time

ISO = sys.argv[1] if len(sys.argv) > 1 else "iso/AegisOS.iso"
OUT = sys.argv[2] if len(sys.argv) > 2 else "screenshots"
SOCK = "/tmp/aegis-qmp.sock"
SERIAL_SOCK = "/tmp/aegis-serial.sock"
ABS_MAX = 0x7FFF          # QMP abs input range for absolute pointer devices
DESKTOP_TIMEOUT = 1200    # KVM boots in ~3 min; TCG needs more
NEUTRAL_Y = 0.30          # pointer parking spot (screen fraction) — away from the dock

def expected_tiles():
    """Dock tile count from the repo's own config (v0.4.0: 13 apps)."""
    try:
        cfg = json.load(open("shell/packaging/config.json"))
        return sum(1 for a in cfg["apps"] if a.get("type") != "separator")
    except Exception:
        return 13

def log(msg):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)

# ---------------- QMP ----------------
class QMP:
    def __init__(self, path, tries=30):
        last = None
        for _ in range(tries):
            try:
                self.s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                self.s.connect(path)
                break
            except (FileNotFoundError, ConnectionRefusedError) as e:
                last = e; time.sleep(1)
        else:
            raise RuntimeError(f"cannot connect QMP socket: {last}")
        self.f = self.s.makefile("rw", encoding="utf-8", newline="\n")
        self.greeting = json.loads(self.f.readline())
        self._cmd("qmp_capabilities")

    def _read_until_return(self):
        while True:
            line = self.f.readline()
            if not line:
                raise RuntimeError("QMP EOF")
            msg = json.loads(line)
            if "return" in msg or "error" in msg:
                return msg

    def _cmd(self, name, args=None):
        c = {"execute": name}
        if args:
            c["arguments"] = args
        self.f.write(json.dumps(c) + "\n"); self.f.flush()
        return self._read_until_return()

    def shot(self, name):
        ppm = f"{OUT}/{name}.ppm"
        r = self._cmd("screendump", {"filename": ppm})
        if "error" in r:
            raise RuntimeError(f"screendump failed: {r}")
        for _ in range(50):
            if os.path.exists(ppm) and os.path.getsize(ppm) > 1000:
                break
            time.sleep(0.1)
        from PIL import Image
        Image.open(ppm).save(f"{OUT}/{name}.png")
        os.remove(ppm)

    def mouse_abs(self, x_px, y_px, W, H):
        x = round(x_px * ABS_MAX / max(1, W - 1))
        y = round(y_px * ABS_MAX / max(1, H - 1))
        self._cmd("input-send-event", {"events": [
            {"type": "abs", "data": {"axis": "x", "value": x}},
            {"type": "abs", "data": {"axis": "y", "value": y}}]})

    def click(self, x_px, y_px, W, H):
        self.mouse_abs(x_px, y_px, W, H)
        time.sleep(0.12)
        self._cmd("input-send-event", {"events": [
            {"type": "btn", "data": {"down": True, "button": "left"}}]})
        time.sleep(0.12)
        self._cmd("input-send-event", {"events": [
            {"type": "btn", "data": {"down": False, "button": "left"}}]})

    def key(self, *qcodes):
        down = [{"type": "key", "data": {"down": True, "key": {"type": "qcode", "data": q}}} for q in qcodes]
        self._cmd("input-send-event", {"events": down}); time.sleep(0.08)
        up = [{"type": "key", "data": {"down": False, "key": {"type": "qcode", "data": q}}} for q in reversed(qcodes)]
        self._cmd("input-send-event", {"events": up})

# ---------------- image helpers ----------------
from PIL import Image

def metrics(png):
    im = Image.open(png).convert("HSV").resize((160, 100))
    px = list(im.getdata())
    return sum(p[1] for p in px) / len(px), sum(p[2] for p in px) / len(px)

def thumb(png):
    return Image.open(png).convert("RGB").resize((160, 100))

def diff_px(a, b):
    pa, pb = a.load(), b.load()
    t = n = 0
    for y in range(100):
        for x in range(160):
            ra, ga, ba = pa[x, y]; rb, gb, bb = pb[x, y]
            t += abs(ra - rb) + abs(ga - gb) + abs(ba - bb); n += 1
    return t / n / 3

def window_hairline(png, scan_to=260):
    """T7 anchor — the window's top hairline. Both anatomies draw one: the
    Files CSD GlassPanel borders white @ 0.14, the aurorae AegisLights
    frame's top edge stroke is the same white @ 0.14. A hairline row is a
    long qualifying run (lum 36..110, >= 60% of the best run) that also
    SPIKES above its vertical neighbours (>= 10 lum) — wallpaper gradient
    rows run long but never spike. The TOPMOST such row wins: the Files
    toolbar hairline (top+96) and the aurorae band-bottom hairline
    (top+43) are equally long but strictly lower. Returns
    (y, x_run_start, run_len) or None."""
    im = Image.open(png).convert("L")
    W, H = im.size
    px = im.load()
    runs = {}
    best_len = 0
    for y in range(40, min(H, scan_to)):
        cur = run_start = run_best_start = 0
        run_best = 0
        for x in range(W):
            v = px[x, y]
            if 36 <= v <= 150:
                if cur == 0:
                    run_start = x
                cur += 1
                if cur > run_best:
                    run_best, run_best_start = cur, run_start
            else:
                cur = 0
        if run_best >= 300:
            runs[y] = (run_best, run_best_start)
            best_len = max(best_len, run_best)
    if best_len == 0:
        return None
    threshold = 0.6 * best_len
    for y in sorted(runs):
        run_len, run_start = runs[y]
        if run_len < threshold:
            continue
        # spike test over the run's own columns
        probe = range(run_start + 10, run_start + run_len - 10, 7)
        here = above = below = n = 0
        for x in probe:
            here += px[x, y]
            above += px[x, max(0, y - 4)]
            below += px[x, min(H - 1, y + 4)]
            n += 1
        if n and here - (above + below) / 2 >= 10 * n:
            return (y, run_start, run_len)
    return None

def red_dot(png, top, x_hint):
    """T7 — the close (red) dot inside the title band: first red blob run
    in y [top, top+44], x [x_hint-4, x_hint+160]. Returns
    (left_x, centre_y, width) or None."""
    im = Image.open(png).convert("RGB")
    px = im.load()
    x0, x1 = max(0, x_hint - 4), min(im.size[0], x_hint + 160)
    y0, y1 = max(0, top), min(im.size[1], top + 44)
    cols = []
    for x in range(x0, x1):
        ys = [y for y in range(y0, y1)
              if (lambda p: p[0] > 180 and p[1] < 140 and p[2] < 120
                  and p[0] - p[2] > 60)(px[x, y])]
        cols.append((x, ys))
    run = None
    for x, ys in cols:
        if len(ys) >= 3:
            if run is None:
                run = [x, x, ys]
            else:
                run[1] = x; run[2] += ys
        else:
            if run and run[1] - run[0] >= 7:
                break
            run = None
    if not run or run[1] - run[0] < 7:
        return None
    xs, xe, ys = run
    cy = sum(ys) / len(ys)
    return (xs, cy, xe - xs + 1)

def band_median_lum(png, top, x0, x1):
    """T7 — median luminance of the title band interior (dots and caption
    are a minority; median tracks the glass fill)."""
    im = Image.open(png).convert("L")
    box = im.crop((x0 + 40, top + 8, x1 - 40, top + 36))
    vals = sorted(box.getdata())
    return vals[len(vals) // 2]

def band_left_edge(png, dot_x, dot_cy):
    """T7 — window left edge: walk left along the dot's centre row across
    the FLAT title band (|lum − band ref| <= 4) and stop at the first
    outlier — the side border or the wallpaper. The aurorae band and the
    Files GlassPanel both span the full window width, so the flat run ends
    at the frame. Returns the first band pixel + 1 (the border pixel)."""
    im = Image.open(png).convert("L")
    px = im.load()
    y = int(round(dot_cy))
    ref = sorted(px[x, y] for x in range(dot_x + 60, min(im.size[0], dot_x + 260)))
    ref = ref[len(ref) // 2]
    x = max(0, dot_x - 2)   # skip the dot's own AA fringe before walking
    while x > max(0, dot_x - 60) and abs(px[x - 1, y] - ref) <= 4:
        x -= 1
    return x

def header_geometry_assert(files_png, terminal_png):
    """T7 — ONE traffic-light anatomy, asserted on the capture set. The
    W10/6.6-v2 theme (ButtonMarginTop 6, TitleEdgeLeft 18, TitleBorderRight
    78) must make the aurorae terminal band behave like the Files CSD band:
      · close dot vertically centred on the caption (centre ~ top + 22),
        and the same within 2 px across the two windows;
      · close dot inset from the window's LEFT EDGE ~14 px in BOTH. The
        hairline run starts after the rounded corner, so the window left
        edge is estimated as run_start − corner_radius (Files 18, aurorae
        12); parity within 4 px, absolute within 14±5 (the old
        TitleEdgeLeft 24 measured the dot at 20 and fails this);
      · dot diameter ~12 px (the W10 "size one" regression guard);
      · terminal band luminance in the flat-ink class (<= 32): the old
        #343740 gradient read 44-55 and is what the user reported as the
        bright band coming back.
    Any miss is a failed release (brief §1: captures must assert)."""
    for path in (files_png, terminal_png):
        if not os.path.exists(path):
            log(f"header assert: missing capture {path} — cannot verify")
            sys.exit(1)
    report = {}
    for label, path in (("files", files_png),
                        ("terminal", terminal_png)):
        hl = window_hairline(path)
        if hl is None:
            log(f"header assert: no window hairline in {label} capture")
            sys.exit(1)
        y, xl, runw = hl
        dot = red_dot(path, y, xl - 40)
        if dot is None:
            log(f"header assert: no red dot near hairline in {label} "
                f"(hairline y={y} x={xl})")
            sys.exit(1)
        dx, dcy, dw = dot
        win_left = band_left_edge(path, dx, dcy)
        report[label] = dict(top=y, left=win_left, dot_x=dx,
                             dot_cy=dcy, dot_w=dw,
                             inset=dx - win_left, drop=dcy - y,
                             band=band_median_lum(path, y, win_left,
                                                  win_left + min(runw, 900)))
        log(f"header assert {label}: hairline y={y} x_start={xl} "
            f"win_left≈{win_left} dot_x={dx} dot_cy={dcy:.1f} dot_w={dw} "
            f"inset={dx - win_left} drop={dcy - y:.1f} band_lum={report[label]['band']}")
    f, t = report["files"], report["terminal"]
    fails = []
    for label, r in (("files", f), ("terminal", t)):
        if abs(r["dot_w"] - 12) > 3:
            fails.append(f"{label} dot width {r['dot_w']} != 12±3 (W10)")
        if abs(r["drop"] - 22) > 4:
            fails.append(f"{label} dot drop {r['drop']:.1f} != top+22±4 "
                         "(caption centre)")
        if not 9 <= r["inset"] <= 19:
            fails.append(f"{label} dot inset {r['inset']} outside 14±5")
    if abs(f["drop"] - t["drop"]) > 2:
        fails.append(f"dot drop parity off: files {f['drop']:.1f} vs "
                     f"terminal {t['drop']:.1f}")
    if abs(f["inset"] - t["inset"]) > 4:
        fails.append(f"dot inset parity off: files {f['inset']} vs "
                     f"terminal {t['inset']} (TitleEdgeLeft)")
    if t["band"] > 32:
        fails.append(f"terminal band lum {t['band']} > 32 — bright title "
                     "band regression (T5)")
    if fails:
        for msg in fails:
            log("ASSERT FAILED: " + msg)
        log("capture complete (FAILED release)")
        sys.exit(1)
    log("header geometry assert PASS — one traffic-light anatomy across "
        "CSD and aurorae windows")

# ---------------- boot ----------------
# console=tty1 FIRST: plymouth needs a local (non-serial) console to bind
# (plymouth.ignore-serial-consoles skips ttyS0); the serial stays LAST so
# /dev/console — where systemd status and casper diagnostics land — keeps
# feeding the harness serial log. This mirrors the Ubuntu live-ISO pattern
# (console=tty1 console=ttyS0...).
# plymouth.debug=file: — plymouthd's own switch (libply reads it from
# /proc/cmdline): boot-phase renderer decisions land in a file that
# survives switch-root, so the probe can read WHY the splash did or did
# not paint. plymouth.debug=stream:/dev/ttyS0 — the SAME trace piped
# straight into the serial console, where the harness logs every byte:
# no permissions, no dump step, the renderer decision lands in serial.log
# in real time. Remove both once W14 is proven and the gate is green.
KERNEL_ARGS = ("boot=live components quiet splash vt.global_cursor_default=0 "
               "loglevel=3 hostname=aegis username=aegis autologin "
               "console=tty1 console=ttyS0,115200n8 "
               "plymouth.ignore-serial-consoles "
               "plymouth.debug=stream:/dev/ttyS0 "
               "plymouth.debug=file:/run/plymouth-boot-debug.log "
               "systemd.journald.forward_to_console=true systemd.show_status=yes")

def extract_kernel_initrd():
    """Pull /live/vmlinuz + /live/initrd.img out of the ISO so we can boot
    with console=ttyS0 and interact with the guest over serial."""
    import pycdlib
    iso = pycdlib.PyCdlib()
    iso.open(ISO)
    for rr, local in (("/live/vmlinuz", "vmlinuz"),
                      ("/live/initrd.img", "initrd.img")):
        if not os.path.exists(local):
            iso.get_file_from_iso(local, rr_path=rr)
            log(f"extracted {rr} -> {local} ({os.path.getsize(local)} bytes)")
    iso.close()
    return "vmlinuz", "initrd.img"

def start_qemu(accel, gpu):
    cmd = ["qemu-system-x86_64", *accel, "-m", "4096", "-smp", "4",
           "-device", gpu, "-display", "none",
           "-device", "qemu-xhci", "-device", "usb-tablet",
           "-nic", "none", "-cdrom", ISO, "-boot", "d", "-no-reboot",
           "-qmp", f"unix:{SOCK},server,nowait",
           "-chardev", f"socket,id=ser0,path={SERIAL_SOCK},server=on,wait=off,logfile=serial.log",
           "-serial", "chardev:ser0"]
    try:
        kern, initrd = extract_kernel_initrd()
        cmd += ["-kernel", kern, "-initrd", initrd, "-append", KERNEL_ARGS]
        log("booting kernel directly with interactive serial console")
    except Exception as e:
        log(f"kernel extraction failed ({e}) — booting via BIOS, serial log only")
    log("qemu: " + " ".join(cmd))
    qf = open("qemu.log", "w")
    proc = subprocess.Popen(cmd, stdout=qf, stderr=subprocess.STDOUT)
    time.sleep(3)
    if proc.poll() is not None:
        log(f"qemu exited immediately (rc={proc.returncode}); qemu.log:")
        try:
            for line in open("qemu.log"):
                log("  | " + line.rstrip())
        except OSError:
            pass
        return None
    return proc

def start_qemu_with_fallback():
    # virgl (virtio-vga-gl) gives the guest real OpenGL — KWin then enables
    # GL compositing and loads GL effects (KDE-Rounded-Corners needs
    # effects->isOpenGLCompositing()). Plain virtio-vga has no guest GL:
    # KWin drops to software compositing and GL effects never load.
    devices = ("virtio-vga-gl", "virtio-vga")
    chains = (["-enable-kvm", "-cpu", "host"],
              ["-accel", "tcg,thread=multi", "-cpu", "max"])
    for gpu in devices:
        for accel in chains:
            log(f"trying gpu={gpu} accelerator={accel[0]}")
            for p in (SOCK, SERIAL_SOCK):
                if os.path.exists(p):
                    os.remove(p)
            proc = start_qemu(accel, gpu)
            if proc:
                log(f"accelerator in use: {accel[0]}; gpu: {gpu}")
                return proc
    raise RuntimeError("qemu failed to start under every accelerator — see qemu.log")

# ---------------- serial console ----------------
class Serial:
    """Interactive serial console over the chardev socket."""

    def __init__(self, path, tries=20):
        last = None
        for _ in range(tries):
            try:
                self.s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                self.s.connect(path)
                break
            except (FileNotFoundError, ConnectionRefusedError) as e:
                last = e; time.sleep(1)
        else:
            raise RuntimeError(f"cannot connect serial socket: {last}")
        self.s.settimeout(2)
        self.buf = b""

    def _drain(self, settle=1.5):
        deadline = time.time() + settle
        while time.time() < deadline:
            try:
                d = self.s.recv(4096)
                if not d:
                    break
                self.buf += d
                deadline = time.time() + 0.5
            except socket.timeout:
                pass
        return self.buf

    def send(self, text):
        self.s.send(text.encode())

    def login(self, user="aegis", passwords=("aegis", "", "live", "root", "ubuntu")):
        """Open a shell on the serial console. Marker-2 trick: a real shell
        evaluates $((1+1)); a login prompt echoes it literally and logs a
        FAILED LOGIN, so a plain substring match cannot false-positive.

        Three console states are handled: a getty 'login:' prompt, an
        ALREADY-AUTOLOGGED shell (autologin consumed the prompt), and the
        boot-spam phase where neither exists yet. The v0.6.14 capture
        exposed the desync trap: the marker probe must ONLY be typed when
        a shell prompt is actually on screen — typed at the getty prompt it
        becomes the next USERNAME ('aegis login: echo MARKER-...') and
        every later credential lands in the wrong field until getty times
        out 60 s later. 'aegis' is the working live password (empty fails:
        'FAILED LOGIN 1 FOR aegis, Authentication failure' on the v0.6.14
        run); Ctrl-U (\x15) resyncs a half-typed line before each try."""
        self.buf = b""
        shell_rx = re.compile(rb"[$#] ?\r?$")
        for _ in range(5):
            self.buf = b""                       # fresh window per probe
            self.send("\n"); self._drain(1.5)
            if b"login:" in self.buf:
                break
            if shell_rx.search(self.buf):
                # an autologin shell owns the console — the marker is safe now
                self.send("echo MARKER-$((1+1))\n"); self._drain(2.5)
                if (b"MARKER-2" in self.buf
                        and b"FAILED LOGIN" not in self.buf):
                    return True
                break
        if b"login:" not in self.buf and not shell_rx.search(self.buf):
            return False
        for pw in passwords:
            self.buf = b""                       # stale text must not match
            self.send("\x15"); self._drain(0.4)   # Ctrl-U: kill stale input
            self.send(user + "\n"); self._drain(2.5)
            if b"Password" not in self.buf:
                # no password prompt: either the shell just opened or the
                # prompt is mid-resync — only probe with a shell prompt up
                if shell_rx.search(self.buf):
                    self.send("echo MARKER-$((1+1))\n"); self._drain(2.5)
                    if (b"MARKER-2" in self.buf
                            and b"FAILED LOGIN" not in self.buf):
                        return True
                continue
            self.send(pw + "\n"); self._drain(3)
            if (b"Login incorrect" in self.buf
                    or b"FAILED LOGIN" in self.buf):
                continue
            self.send("echo MARKER-$((1+1))\n"); self._drain(2.5)
            if (b"MARKER-2" in self.buf
                    and b"FAILED LOGIN" not in self.buf):
                return True
        return False

    def run(self, cmd, settle=3.0):
        self.send(cmd + "\n"); self._drain(settle)
        out = self.buf.decode(errors="replace")
        # keep only the response after the echoed command
        idx = out.rfind(cmd)
        return out[idx + len(cmd):] if idx >= 0 else out

def seed_review_files(serial):
    """W2 review fixtures: one file of each kind tint directly in $HOME, so
    the 02-files capture shows the §8.1 kind map live (folders blue · PDF red
    · archive amber · image purple · audio pink · text blue)."""
    fixtures = [
        ("report.pdf",
         "JVBERi0xLjQKMSAwIG9iajw8L1R5cGUvQ2F0YWxvZz4+ZW5kb2JqCnRyYWlsZXI8PC9Sb290IDEgMCBSPj4K"),
        ("photo.png",
         "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="),
        ("archive.zip", "UEsDBAoAAAAAAA=="),
        ("track.mp3", "SUQzBAAAAAAAIABRT1Y="),
        ("notes.txt", "QWVnaXMgT1MgcmV2aWV3IGZpeHR1cmUu"),
    ]
    try:
        serial.run("mkdir -p ~/Documents ~/Downloads ~/Music ~/Pictures ~/Videos",
                   settle=2)
        for name, b64 in fixtures:
            out = serial.run(
                f"echo {b64} | base64 -d > $HOME/{name}; echo SEEDED-{name}",
                settle=2)
            log(f"seed {name}: {'ok' if 'SEEDED-' + name in out else 'FAILED'}")
        serial.run("sync", settle=2)
        out = serial.run("ls $HOME", settle=3)
        log("home: " + " ".join(out.strip().split())[:200])
    except Exception as e:
        log(f"seed failed: {e}")

def serial_diagnose(serial):
    diag_cmds = [
        "echo ===TARGET===; systemctl get-default; systemctl is-active display-manager sddm",
        "echo ===SDDMCONF===; cat /etc/sddm.conf 2>&1; echo ---; ls -la /etc/sddm.conf.d/ 2>&1; cat /etc/sddm.conf.d/*.conf 2>&1",
        "echo ===SDDMLOG===; sudo journalctl -u sddm -b --no-pager 2>&1 | tail -40",
        "echo ===SESSIONLOG===; sudo journalctl -b --no-pager 2>&1 | grep -Ei 'kwin|aegis-shell|dbus-run|sddm-helper|aegis-session' | tail -40",
        "echo ===KWIN===; ls -la /usr/bin/kwin_wayland /usr/bin/aegis-shell 2>&1; sudo -u aegis XDG_RUNTIME_DIR=/run/user/1000 kwin_wayland --version 2>&1 | head -4",
        "echo ===KWINRUN===; ls -la /dev/dri/ 2>&1; cat /etc/sddm/wayland-session 2>&1 | head -20; sed -n '20,60p' /usr/bin/aegis-session",
        "echo ===KWINTEST===; sudo -u aegis sh -c 'export XDG_RUNTIME_DIR=/run/user/1000; timeout 8 kwin_wayland --xwayland 2>&1 | head -25'; echo KWIN-TEST-DONE",
        "echo ===SESSLOG===; cat /tmp/aegis-session.log 2>&1 | tail -50",
        "echo ===DRMSEAT===; sudo udevadm info /dev/dri/card0 2>&1 | grep -E 'TAGS|seat|ID_' | head -8; loginctl list-sessions --no-pager 2>&1",
        "echo ===LDD===; ldd /usr/bin/kwin_wayland 2>&1 | grep -i 'not found'; ldd /usr/bin/aegis-shell 2>&1 | grep -i 'not found'; echo LDD-DONE",
        "echo ===SDDMDOTLOG===; sudo tail -40 /var/log/sddm.log 2>&1; sudo ls -la /var/lib/sddm/ /home/aegis/.local/share/sddm/ 2>&1",
        "echo ===FAILED===; systemctl --failed --no-pager | head -12",
        "echo ===SESS===; loginctl list-sessions --no-pager 2>&1; ls /usr/share/wayland-sessions/ 2>&1",
        "echo ===PROCS===; ps aux | grep -Ei 'sddm|kwin|aegis|Xorg|wayland' | grep -v grep",
    ]
    blob = []
    for c in diag_cmds:
        out = serial.run(c, settle=4)
        blob.append(out)
        log("serial-diag: " + out.strip().replace("\n", " | ")[:400])
    open("serial-diag.txt", "w").write("\n".join(blob))
    joined = "\n".join(blob)
    return {
        "dm_active": ("active" in joined.split("===DM===")[-1].split("===GRAPHICAL===")[0]),
        "journal": joined,
    }

def app_diag(serial):
    """Guest-side diagnostics AFTER the app-launch choreography. The desktop
    being up says nothing about the first-party apps: if windows never mapped
    (or the dock vanished mid-run), only the guest journal can say why.
    Output goes to the workflow log and serial-diag.txt (an artifact).
    Returns the two foreground QML-probe outputs so main() can ASSERT —
    §1: an ISO whose apps do not open is a failed release, not a capture."""
    diag_cmds = [
        "echo ===PROCS===; ps aux | grep -Ei 'aegis|kwin|corex|dolphin|chromium' | grep -v grep | head -20",
        "echo ===SESSLOG===; tail -n 80 /tmp/aegis-session.log 2>&1",
        "echo ===SETTINGS-ERR===; tail -40 /tmp/aegis-settings.err 2>&1",
        # §1 — foreground probes. The guest CLASSIFIES its own stderr and
        # prints a verdict token: PROBE-S-''CLEAN or PROBE-S-''DIRTY. The
        # tokens are SPLIT inside the typed command (the shell strips the
        # empty quotes) so the serial echo can never contain the literal.
        # The verdicts are read from the RAW serial buffer — Serial.run's
        # rfind strip removes everything before a LATER command's echo, and
        # on the second v0.6.13 run it ate the files probe's closing
        # sentinel outright (the files section stayed open and swallowed
        # the benign 'ls: cannot access' from KWIN-PLUGINS). timeout -k 2
        # bounds a hung app at ~8 s (the files probe once lingered past its
        # 6 s settle and desynchronized the whole diag loop), and libEGL
        # dri2 warnings are excluded from the verdict — every Qt app on the
        # GPU-less runner prints them.
        "echo ===QP''S===; export XDG_RUNTIME_DIR=/run/user/$(id -u); "
        "WAYLAND_DISPLAY=wayland-0 timeout -k 2 6 aegis-apps settings 8 "
        ">/tmp/qml-probe.err 2>&1; if grep -qvi 'libEGL warning' "
        "/tmp/qml-probe.err; then echo PROBE-S-''DIRTY; else echo "
        "PROBE-S-''CLEAN; fi",
        "echo ===QP''F===; export XDG_RUNTIME_DIR=/run/user/$(id -u); "
        "WAYLAND_DISPLAY=wayland-0 timeout -k 2 6 aegis-apps files "
        ">/tmp/qml-probe-files.err 2>&1; if grep -qvi 'libEGL warning' "
        "/tmp/qml-probe-files.err; then echo PROBE-F-''DIRTY; else echo "
        "PROBE-F-''CLEAN; fi",
        "echo ===JRN-SHELL===; sudo journalctl -b --no-pager 2>&1 | grep -aiE 'aegis-(shell|apps|session|files|settings)|QQml|qrc:' | tail -50",
        "echo ===JRN-KWIN===; sudo journalctl -b --no-pager 2>&1 | grep -ai 'kwin' | grep -aivE 'information|Rendering|colorProfile|ColorManagement' | tail -40",
        "echo ===JRN-CRASH===; sudo journalctl -b --no-pager 2>&1 | grep -aiE 'segfault|signal 11|coredump|abrt|general protection' | tail -20",
        "echo ===COREDUMPCTL===; coredumpctl list --no-pager 2>&1 | tail -10",
        "echo ===KWINRC===; cat /etc/xdg/kwinrc 2>&1",
        "echo ===KWIN-PLUGINS===; ls /usr/lib/x86_64-linux-gnu/qt6/plugins/kwin/effects/plugins/ 2>&1; ls /usr/lib/qt6/plugins/kwin/effects/plugins/ 2>&1; echo PLUGINS-DONE",
        # W14 — did the splash renderer really run? The boot frames keep
        # missing the (short) plymouth window on the ~10 s KVM boot, so the
        # journal is the evidence: theme selected, service state, plugin.
        "echo ===PLYMOUTH===; plymouth-set-default-theme 2>&1; "
        "systemctl status plymouth-start.service --no-pager 2>&1 | head -8; "
        "ls /usr/lib/*/plymouth/two-step.so 2>&1; "
        "ls /usr/share/plymouth/themes/aegis-mark/ 2>&1; "
        "sudo journalctl -b --no-pager 2>&1 | grep -ai plymouth | tail -15",
    ]
    blob = []
    for c in diag_cmds:
        # probe commands get a 12 s settle: the timeout -k bound is 8 s, so
        # the verdict always lands inside the drain window
        out = serial.run(c, settle=12 if "timeout -k" in c else 6)
        blob.append(out)
        log("app-diag: " + out.strip().replace("\n", " | ")[:400])
    open("serial-diag.txt", "w").write("\n".join(blob))
    # §1 — verdicts are read from the RAW serial stream: echoes carry only
    # the split forms (PROBE-F-''DIRTY), so a literal token can only be a
    # printed verdict. The rfind strip cannot lose them here.
    raw = serial.buf.decode(errors="replace")
    probes = {}
    for name, tok, path in (("settings", "PROBE-S", "/tmp/qml-probe.err"),
                            ("files", "PROBE-F", "/tmp/qml-probe-files.err")):
        if tok + "-DIRTY" in raw:
            fetch = serial.run(
                f"grep -vi 'libEGL warning' {path} | head -10", settle=3)
            log(f"probe {name}: DIRTY — " + fetch.strip()[:300])
            probes[name] = fetch
        elif tok + "-CLEAN" in raw:
            log(f"probe {name}: CLEAN")
            probes[name] = ""
        else:
            log(f"probe {name}: VERDICT MISSING — probe chain never "
                "completed; treating as a harness failure")
            probes[name] = (f"QML probe ({name}) verdict missing — the "
                            "probe chain failed to complete")
    return probes

def probe_failed(text):
    """True when a foreground QML probe printed a real error (the classes
    that shipped v0.6.9-v0.6.12 all say error/Cannot/Unexpected/Failed).
    Benign Qt notices without those markers do not red a release. The
    libEGL dri2 notice is belt-and-braces here too — the probe commands
    already grep it out, and every Qt app on the GPU-less runner prints it."""
    lines = [ln for ln in text.splitlines()
             if "libegl warning" not in ln.lower()
             and "egl: failed to create dri2" not in ln.lower()]
    text = "\n".join(lines).replace("===", "")
    if not text.strip():
        return False
    low = text.lower()
    return any(m in low for m in
               ("error", "cannot", "unexpected", "failed", "invalid",
                "not a type", "is not installed"))

def splash_report(out_dir, last=-1):
    """W14 proof step — did the boot splash paint the mark? Scans EVERY
    pre-desktop boot frame for the aegis-mark splash SIGNATURE:
      · ink background — the corner pixel must sit on 0x08090C (±5);
        a console (0,0,0) or the wallpaper (grey-blue) fails this alone;
      · accent progress line — saturated 0x3E8BFF-class pixels in the
        progress band (y ≈ 0.61 H, centred), OR
      · watermark — near-white mark pixels in the centre band (y ≈ 0.46 H).
    The v0.6.20 heuristic called a 4%-bright CONSOLE frame "consistent
    with the mark splash" — text pixels fooled the brightness counter and
    the assert would have gone off on a false positive. Returns True when
    at least one frame carries the signature; the caller turns a miss
    into a failed release (brief §1: captures must assert)."""
    def signature(png):
        im = Image.open(png).convert("RGB")
        W, H = im.size
        corner = im.getpixel((5, H - 6))
        inked = (abs(corner[0] - 8) <= 5 and abs(corner[1] - 9) <= 5
                 and abs(corner[2] - 12) <= 5)
        if not inked:
            return None
        # progress band — accent-blue pixels (b >> r, mid green)
        band = im.crop((W // 2 - 140, int(H * 0.56),
                        W // 2 + 140, int(H * 0.66)))
        line = sum(1 for p in band.getdata()
                   if p[2] > 200 and 60 < p[1] < 190 and p[2] - p[0] > 100)
        # watermark band — near-white mark pixels
        wm = im.crop((W // 2 - 150, int(H * 0.38),
                      W // 2 + 150, int(H * 0.54)))
        white = sum(1 for p in wm.getdata() if min(p) > 150)
        return (line, white)

    best = None
    n = 0
    while True:
        if 0 <= last <= n:
            break
        name = f"boot-{n:02d}"
        path = os.path.join(out_dir, name + ".png")
        if not os.path.exists(path):
            break
        n += 1
        try:
            sig = signature(path)
            if sig is None:
                log(f"splash {name}: background is not ink — console or "
                    "desktop frame")
                continue
            line, white = sig
            log(f"splash {name}: INK background — progress-line px {line}, "
                f"watermark px {white}")
            if best is None or line + white > best[1]:
                best = (name, line + white, line, white)
        except Exception as e:
            log(f"splash {name}: unreadable ({e})")
    if best and (best[2] >= 40 or best[3] >= 500):
        log(f"splash: MARK SPLASH CONFIRMED on {best[0]} "
            f"(progress px {best[2]}, watermark px {best[3]})")
        return True
    log("splash: no boot frame carries the mark splash signature — "
        "plymouth did not paint ink + mark + progress line; W14 NOT met")
    return False

def serial_recover(serial, q, W=1280, H=800):
    log("attempting live recovery over serial")
    # The known failure: casper writes an empty Session= into /etc/sddm.conf
    # which overrides zz-aegis-live.conf and aborts SDDM autologin. Drop the
    # empty line and restart the display manager.
    out = serial.run(
        "sudo sed -i '/^Session=[[:space:]]*$/d' /etc/sddm.conf 2>&1; "
        "sudo systemctl restart sddm 2>&1; echo RECOVERY-DONE", settle=8)
    log("recovery: " + out.strip().replace("\n", " | ")[:300])
    if "RECOVERY-DONE" not in out:
        return False
    # give the greeter/shell up to 5 minutes to appear
    for i in range(15):
        time.sleep(20)
        try:
            q.shot("recover")
            _, present = dock_geometry(f"{OUT}/recover.png")
            sat, val = metrics(f"{OUT}/recover.png")
            log(f"recover-{i}: sat={sat:.1f} val={val:.1f} dock-slots={present}")
            if present >= desktop_ready_threshold():
                return True
        except Exception as e:
            log(f"recovery probe failed: {e}")
    return False

# ---------------- choreography ----------------
def dock_geometry(png):
    """Dock tile centers computed GEOMETRICALLY from Tokens.qml + config.

    The v0.4.x dock is an always-expanded light glass tray: brightness-gap
    clustering cannot separate 64 px icons from the tray glass, and column
    means sit right on any fixed threshold. But the dock is deterministic:
    centered horizontally, fixed pitch (tileWidth + tileGap), fixed icon
    row height — so we parse the tokens out of the repo and lay the tile
    centers out arithmetically. A brightness/saturation sanity check per
    slot tells whether the desktop is really up (returns n_present)."""
    im = Image.open(png).convert("RGB")
    W, H = im.size

    def token(name, default):
        try:
            for line in open("shell/src/qml/Tokens.qml"):
                m = re.search(rf"readonly property int {name}:\s*(\d+)", line)
                if m:
                    return int(m.group(1))
        except OSError:
            pass
        return default

    B = token("tileWidth", 76)
    gap = token("tileGap", 2)
    pad = token("trayPadding", 12)
    n = expected_tiles()

    row_w = n * B + (n - 1) * gap
    tray_w = row_w + 2 * pad
    x0 = W // 2 - tray_w // 2
    y = H - 50                          # icon mid: tray bottom-anchored row
    centers = [(x0 + pad + i * (B + gap) + B // 2, y) for i in range(n)]

    # sanity: how many slots actually hold an icon? (white glyphs raise
    # max brightness; colourful tiles raise saturation)
    present = 0
    for cx, cy in centers:
        box = im.crop((max(0, cx - 32), max(0, cy - 40),
                       min(W, cx + 32), min(H, cy + 40)))
        hsv = box.convert("HSV")
        vals = list(hsv.getdata())
        if max(v[2] for v in vals) > 100 or sum(1 for v in vals if v[1] > 60) > 25:
            present += 1
    return centers, present


def find_tiles(png):
    """Stable tile center list (geometric) — used for clicking."""
    centers, _ = dock_geometry(png)
    return centers

def desktop_ready_threshold():
    """Readiness margin — the dock has 7 real tiles post-W9 (web tiles gone,
    Tier B debs resolve), so a fixed '8 slots' check would never fire. The
    threshold scales with the config: full model minus two for tolerance."""
    return max(4, expected_tiles() - 2)

def wait_desktop(q, proc, timeout=DESKTOP_TIMEOUT):
    """Desktop readiness = at least (tiles - 2) of the geometric dock slots
    hold an icon."""
    n = 0; t0 = time.time()
    while time.time() - t0 < timeout:
        if proc.poll() is not None:
            log(f"qemu died mid-boot (rc={proc.returncode}); qemu.log tail:")
            try:
                for line in list(open("qemu.log"))[-25:]:
                    log("  | " + line.rstrip())
            except OSError:
                pass
            sys.exit(3)
        try:
            q.shot(f"boot-{n:02d}")
        except Exception as e:
            log(f"shot failed: {e}"); time.sleep(10); continue
        png = f"{OUT}/boot-{n:02d}.png"
        sat, val = metrics(png)
        present = 0
        try:
            _, present = dock_geometry(png)
        except Exception:
            pass
        log(f"boot-{n:02d}: sat={sat:.1f} val={val:.1f} dock-slots={present} t={time.time() - t0:.0f}s")
        if present >= desktop_ready_threshold() and val >= 30:
            # val >= 30 — the desktop gate. The v0.6.20 run "reached the
            # desktop" at t=9 s because the geometric slot heuristic read
            # five "tiles" in the casper console text (sat=0.3 val=13.7);
            # the real wallpaper carries val ≈ 63. A text console is not
            # the desktop.
            return n
        n += 1; time.sleep(1 if n < 12 else (5 if n < 20 else 20))
    return -1

def main():
    os.makedirs(OUT, exist_ok=True)
    proc = start_qemu_with_fallback()
    q = QMP(SOCK)
    log("QMP connected")
    n = wait_desktop(q, proc)
    serial = None
    if n < 0:
        log("desktop did not appear — opening the serial console")
        try:
            serial = Serial(SERIAL_SOCK)
            if serial.login():
                log("serial login OK")
                info = serial_diagnose(serial)
                if serial_recover(serial, q):
                    log("recovery worked — desktop is up")
                    n = 0
            else:
                log("serial login FAILED — dumping what we have")
                log("serial buffer tail: " + serial.buf[-800:].decode(errors="replace"))
        except Exception as e:
            log(f"serial diagnostics failed: {e}")
    if n < 0:
        log("DESKTOP NEVER APPEARED — serial dump:")
        try:
            for line in open("serial.log", errors="replace").readlines()[-60:]:
                log("  | " + line.rstrip()[:200])
        except OSError:
            log("  (serial.log empty or missing)")
        q.shot("zz-final")
        sys.exit(1)

    time.sleep(10)                       # settle desktop animations
    W, H = Image.open(f"{OUT}/boot-{n:02d}.png").size
    q.mouse_abs(W // 2, int(H * NEUTRAL_Y), W, H)   # park pointer away from dock
    time.sleep(2.5)
    q.shot("01-home")

    # Guard: the wallpaper fade-in can leave the first frame black — a black
    # 01-home shipped in the v0.4.1/v0.4.3/v0.5.1 docs folders. Re-shoot
    # until the frame carries real content (mean HSV V above threshold).
    def frame_mean(png):
        im = Image.open(png).convert("HSV")
        px = list(im.getdata())
        return sum(v[2] for v in px) / max(1, len(px))

    for _ in range(6):
        if frame_mean(f"{OUT}/01-home.png") > 25:
            break
        time.sleep(1.5)
        q.shot("01-home")

    # macOS dock magnification + tooltip: glide into a center tile (a
    # two-step entry reliably fires the Wayland enter/leave sequence; a
    # single teleport occasionally misses the hover — v0.4.1 frames), let
    # the springs settle, then capture the wave and the black label bubble.
    home = thumb(f"{OUT}/01-home.png")
    tiles = find_tiles(f"{OUT}/01-home.png")
    log(f"resolution {W}x{H}; dock slots: {len(tiles)} (geometric)")
    hover = tiles[len(tiles) // 2]
    q.mouse_abs(hover[0], hover[1] - 90, W, H)
    time.sleep(0.6)
    q.mouse_abs(*hover, W, H)
    time.sleep(2.2)
    q.shot("01b-dock-magnify")
    q.mouse_abs(W // 2, int(H * NEUTRAL_Y), W, H)
    time.sleep(1.0)

    def open_app(name, cmd, wait_s=25, click_idx=None):
        """Launch via the shell's DBus surface (Util.launch is exported by
        ExportAllInvokables on org.aegis.Shell) — deterministic, no pixel
        geometry. The old dock-tile click raced the magnification
        animation: the geometric layout assumes the 7-slot config, the W9
        dock shows 6 tiles, and every center sits half a pitch left of the
        real tile (the v0.6.18 run lost that race and konsole never
        opened). Falls back to the geometric click when the serial console
        is unavailable."""
        for attempt in range(2):
            launched = False
            try:
                if serial is not None:
                    out = serial.run(
                        # the shell's bus is the dbus-run-session private
                        # session, NOT the systemd --user bus at
                        # $XDG_RUNTIME_DIR/bus ("The name org.aegis.Shell
                        # was not provided by any .service files" on the
                        # v0.6.19 run) — read the real address from the
                        # shell's own environment
                        "export XDG_RUNTIME_DIR=/run/user/$(id -u); "
                        "SHELLPID=$(pgrep -f '/usr/bin/aegis-shell' | head -1); "
                        "export DBUS_SESSION_BUS_ADDRESS=$(tr '\\0' '\\n' "
                        "< /proc/$SHELLPID/environ "
                        "| grep '^DBUS_SESSION_BUS_ADDRESS=' | head -1 "
                        "| cut -d= -f2-); "
                        "busctl --user call org.aegis.Shell /org/aegis/Shell "
                        f"org.aegis.Shell launch s \"{cmd}\" 2>&1; "
                        f"echo LAUNCH-{name}-OK", settle=3)
                    launched = (f"LAUNCH-{name}-OK" in out
                                and "Call failed" not in out)
                    log(f"{name}: dbus launch -> " +
                        out.strip().replace("\n", " | ")[-160:])
            except Exception as e:
                log(f"{name}: dbus launch failed ({e})")
            if launched:
                time.sleep(wait_s)
            elif click_idx is not None:
                # dock is always expanded — park the pointer high so the
                # tray is at rest, then click the tile (magnification
                # starts on arrival)
                q.mouse_abs(W // 2, int(H * NEUTRAL_Y), W, H)
                time.sleep(0.8)
                q.click(*tiles[click_idx], W, H)
                time.sleep(wait_s)
            else:
                continue
            q.shot(name)
            d = diff_px(thumb(f"{OUT}/{name}.png"), home)
            try:
                slots = dock_geometry(f"{OUT}/{name}.png")[1]
            except Exception:
                slots = -1
            log(f"{name}: diff-vs-home={d:.1f} dock-slots={slots}")
            if d > 6:
                return True
            log(f"{name} attempt {attempt + 1}: screen looks unchanged, retrying")
            q.mouse_abs(W // 2, H // 2, W, H)
            time.sleep(2)
        return False

    # serial console up EARLY now: the W2 capture needs mixed file types in
    # $HOME (kind tints) and the W6 review needs the Aegis ID pane shot.
    serial = None
    try:
        serial = Serial(SERIAL_SOCK)
        ok = serial.login()
        if not ok:
            # a fast KVM boot can beat the serial getty — one grace pass
            time.sleep(20)
            ok = serial.login()
        if ok:
            log("serial login OK — seeding review fixtures")
            seed_review_files(serial)
            # W14 diagnostic — the boot-phase plymouthd debug log survives
            # switch-root in /run. Dump it FIRST so a later gate failing
            # still leaves the renderer decision in the workflow log.
            try:
                dbg = serial.run(
                    "sudo sh -c 'ls -la /run/plymouth-boot-debug.log 2>&1; "
                    "grep -aiE \"renderer|drm|device|error|fail|splash|plugin|"
                    "two-step|console|master\" /run/plymouth-boot-debug.log "
                    "2>&1 | head -40'; echo BOOT-DEBUG-READ", settle=10)
                log("plymouth boot debug: "
                    + dbg.strip().replace("\n", " | ")[-1500:])
            except Exception as e:
                log(f"plymouth boot debug dump failed: {e}")
        else:
            serial = None
            log("serial login FAILED — no fixtures, no Aegis ID pane shot")
    except Exception as e:
        log(f"early serial setup failed: {e}")

    # alt+F4 only after a window really opened: with no app window focused,
    # the close lands on the focused shell layer surface (the v0.6.5 boot
    # test lost dock -> island -> panel to exactly this cascade).
    # §1 — every open is RECORDED; a miss is a failed release (asserted below).
    opens = {}
    if open_app("02-files", "aegis-files", click_idx=0):       # Files
        opens["files"] = True
        q.key("alt", "f4"); time.sleep(5)
    if open_app("03-terminal", "konsole", wait_s=18, click_idx=1):   # Terminal
        opens["terminal"] = True
        q.key("alt", "f4"); time.sleep(5)
    # W9 — the dock shrank to 7 tiles (web tiles gone): Settings sits at
    # index 5, before only Files/Terminal/Browser/OS/CoreX.
    if open_app("04-settings", "aegis-settings", wait_s=30, click_idx=5):   # Settings
        opens["settings"] = True
        q.key("alt", "f4"); time.sleep(5)

    # T7 — one traffic-light anatomy, asserted on the two fresh captures
    # (Files CSD shell band vs Terminal aurorae band). Runs BEFORE anything
    # else can cover the windows; a miss fails the release right here.
    try:
        header_geometry_assert(f"{OUT}/02-files.png", f"{OUT}/03-terminal.png")
    except SystemExit:
        raise
    except Exception as e:
        log(f"header geometry assert crashed: {e}")
        sys.exit(1)

    # W6 review evidence — the Aegis ID pane, launched straight from the
    # serial shell ("aegis-settings 8") so no in-window clicking is needed.
    if serial:
        try:
            # stderr is GOLD when the QML fails to compile — keep it in the
            # guest FS so the app_diag section below can print it verbatim.
            out = serial.run(
                "export XDG_RUNTIME_DIR=/run/user/$(id -u); "
                "WAYLAND_DISPLAY=wayland-0 nohup aegis-settings 8 "
                ">/tmp/aegis-settings.err 2>&1 & echo PANE8-LAUNCHED", settle=3)
            log("pane8: " + out.strip().replace("\n", " | ")[-120:])
            time.sleep(18)
            q.shot("04b-aegis-id")
            log("04b-aegis-id captured")
            q.key("alt", "f4"); time.sleep(5)
        except Exception as e:
            log(f"aegis-id pane capture failed: {e}")

    q.click(W - 60, 14, W, H)            # panel right cluster -> Control Center
    time.sleep(3)
    q.shot("05-control-center")

    # W13 acceptance — DND on AND off. The CC sheet is deterministic: 348 px
    # anchored top-right, BUT KWin places the layer surface below the
    # panel's 28 px exclusive zone (measured on the v0.6.13 captures: sheet
    # top border at y=68, not the margin-40 the QML math suggests). Sheet
    # margins 16, header 30, 12 px gaps, grid 64+12+64, then the 44 px DND
    # wide tile centered at y=300 with its 36x20 switch riding the right
    # end (knob measured at x ≈ 1206-1222 on the v0.6.20 capture).
    # v0.6.21: the QML bug is fixed (the whole tile toggles again), but the
    # capture now clicks the SWITCH and then ASSERTS the frame actually
    # changed — five tags (v0.6.15-v0.6.20) shipped identical "DND on"
    # captures because the click hit the dead tile body and nothing ever
    # verified the pixels moved. Brief §1: captures must assert.
    try:
        home = Image.open(f"{OUT}/05-control-center.png").convert("RGB")

        def frame_diff(a, b):
            # diff only inside the CC sheet (x > W-380, y 40..540): the
            # switch move + bell fill live there; sampling every 4 px. The
            # panel clock is EXCLUDED (y < 40) — a minute rollover between
            # the two shots would otherwise fake a pass. Calibrated on the
            # v0.6.21 run: a real toggle moves diff to ≈ 0.35, no toggle
            # measures exactly 0.00 — the old 1.0 bar failed a working
            # toggle and the retry then clicked it back off.
            pa, pb = a.load(), b.load()
            Wd, Hd = a.size
            x0 = max(0, Wd - 380)
            t = n = 0
            for y in range(40, min(Hd, 540), 4):
                for x in range(x0, Wd, 4):
                    t += sum(abs(pa[x, y][c] - pb[x, y][c]) for c in range(3))
                    n += 1
            return t / n / 3

        def dnd_capture(pos, name):
            q.click(pos[0], pos[1], W, H)
            time.sleep(2)
            q.shot(name)
            return Image.open(f"{OUT}/{name}.png").convert("RGB")

        SWITCH = (W - 64, 300)            # the 36x20 switch, right end
        BODY = (W - 180, 300)             # tile body (the new tile-wide
                                          # MouseArea makes it live)
        dnd_on = dnd_capture(SWITCH, "05b-control-center-dnd")
        moved = frame_diff(home, dnd_on)
        if moved < 0.15:
            log(f"dnd assert: frame did not move (diff={moved:.2f}) — "
                "retrying on the tile body")
            dnd_on = dnd_capture(BODY, "05b-control-center-dnd")
            moved = frame_diff(home, dnd_on)
        if moved < 0.15:
            log(f"RELEASE GATE: DND toggle produced no frame change "
                "(diff=%.2f) — the tile does not respond; failing" % moved)
            sys.exit(1)
        log(f"05b-control-center-dnd captured (DND on, diff={moved:.1f})")
        # restore off and confirm the sheet settled back
        q.click(SWITCH[0], SWITCH[1], W, H)
        time.sleep(1.5)
    except SystemExit:
        raise
    except Exception as e:
        log(f"dnd toggle capture failed: {e}")
        sys.exit(1)

    # W14 proof step — the hard assert. The brief: "keep ubuntu-text as
    # fallback until boot-capture proves the new theme". The signature
    # check (ink background + accent progress line / watermark pixels)
    # passed on this tag means the mark splash is REAL; a miss fails the
    # release instead of shipping console text as "boot splash". The exit
    # fires AFTER the gpu/plymouth probe below so the failure log always
    # carries the /dev/dri + journal diagnostics that explain the miss.
    splash_ok = splash_report(OUT, n)

    # W14 experiment — CAN plymouthd render at all in this VM? The boot
    # frames show casper's console text over the whole plymouth window
    # (the journal says plymouthd ran and show-splash exited 0), so the
    # renderer never took the display at boot. A fresh debug-enabled
    # plymouthd + show-splash on the idle session separates a broken
    # renderer (frame stays desktop, debug log says why) from a boot-time
    # handoff race (frame shows the mark and the assert can land).
    try:
        if serial is None:
            serial = Serial(SERIAL_SOCK)
            if not serial.login():
                raise RuntimeError("serial login failed for the splash probe")
        out = serial.run(
            "ls -la /dev/dri 2>&1; lsmod | grep -E 'virtio_gpu|bochs' 2>&1; "
            "journalctl -b --no-pager 2>/dev/null | grep -aiE 'plymouth|renderer' "
            "| head -12; echo GPU-PROBE", settle=6)
        log("gpu/plymouth probe: " + out.strip().replace("\n", " | ")[-700:])
        serial.run("sudo plymouth quit 2>&1; pkill plymouthd 2>/dev/null; "
                   "echo OLD-QUIT", settle=3)
        serial.run("sudo plymouthd --mode=boot --debug "
                   "--debug-file=/tmp/plymouthd-debug.log 2>&1; echo DAEMON-UP",
                   settle=3)
        out = serial.run("sudo plymouth show-splash 2>&1; echo SPLASH-SHOWN",
                         settle=4)
        log("splash probe: " + out.strip().replace("\n", " | ")[-120:])
        time.sleep(2.5)
        # B2 — this is the LIVE show-splash EXPERIMENT (a plymouthd started
        # on the idle session), not boot evidence. The old name
        # "07-plymouth-test" read as a boot splash capture while the frame
        # actually shows whatever the idle-session renderer managed to
        # paint (often the desktop or casper console text — the "terminal
        # lines are back" report). Boot evidence is and stays the boot-NN
        # frames judged by splash_report(); keep this probe unambiguous.
        q.shot("07-live-splash-probe")
        log("07-live-splash-probe captured (idle-session show-splash "
            "EXPERIMENT — not boot evidence)")
        try:
            im = Image.open(f"{OUT}/07-live-splash-probe.png").convert("RGB")
            Wp, Hp = im.size
            box = im.crop((Wp // 2 - 250, max(0, Hp // 2 - 250),
                           Wp // 2 + 250, min(Hp, Hp // 2 + 250)))
            bright = sum(1 for p in box.getdata() if max(p) > 70)
            total = box.width * box.height
            log(f"plymouth-test centre brightness: {bright * 100 // total}%")
        except Exception as e:
            log(f"plymouth-test metric failed: {e}")
        dbg = serial.run(
            "grep -aiE 'renderer|drm|error|fail|head|plugin|two-step' "
            "/tmp/plymouthd-debug.log 2>&1 | head -25; echo DEBUG-READ",
            settle=4)
        log("plymouthd debug: " + dbg.strip().replace("\n", " | ")[:600])
        serial.run("sudo plymouth quit 2>&1; pkill plymouthd 2>/dev/null; "
                   "echo CLEAN", settle=3)
    except Exception as e:
        log(f"plymouth live splash probe failed: {e}")

    if not splash_ok:
        log("RELEASE GATE: the boot splash never painted the mark — "
            "failing the capture run (W14)")
        sys.exit(1)

    # Post-capture diagnostics over the serial console: if apps failed to
    # open or the dock vanished during the choreography, the guest journal
    # holds the reason (QML load failures, segfaults, KWin effect errors).
    probes = {"settings": "", "files": ""}
    try:
        if serial is None:
            serial = Serial(SERIAL_SOCK)
            if not serial.login():
                raise RuntimeError("serial login failed")
        log("serial OK — app diagnostics follow")
        probes = app_diag(serial)
    except Exception as e:
        log(f"post-capture diagnostics failed: {e}")

    # §1 — the release gate: every first-party app must really open, and the
    # foreground QML probes must come back clean. "A release whose capture
    # shows a wallpaper and a dock but no window is a FAILED release."
    failures = []
    for app in ("files", "terminal", "settings"):
        if not opens.get(app):
            failures.append(f"{app} window never opened (screen unchanged)")
    for name, text in probes.items():
        if probe_failed(text):
            failures.append(f"QML probe ({name}) reported a load error")
    if failures:
        for f in failures:
            log("ASSERT FAILED: " + f)
        log("capture complete (FAILED release)")
        q._cmd("quit")
        sys.exit(1)

    log("capture complete")
    q._cmd("quit")

if __name__ == "__main__":
    main()
