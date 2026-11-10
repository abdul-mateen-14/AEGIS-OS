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

# ---------------- boot ----------------
KERNEL_ARGS = ("boot=live components quiet splash vt.global_cursor_default=0 "
               "loglevel=3 hostname=aegis username=aegis autologin "
               "console=ttyS0,115200n8 plymouth.ignore-serial-consoles "
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

    def login(self, user="aegis", passwords=("", "aegis", "live", "root", "ubuntu")):
        """Open a shell on the serial console. Marker-2 trick: a real shell
        evaluates $((1+1)); a login prompt echoes it literally and logs a
        FAILED LOGIN, so a plain substring match cannot false-positive."""
        self.buf = b""
        for _ in range(4):
            self.send("\n"); self._drain(1.5)
            if b"login:" in self.buf:
                break
        if b"login:" not in self.buf:
            return False
        for pw in passwords:
            self.send(user + "\n"); self._drain(2.5)
            if b"Password" in self.buf:
                self.send(pw + "\n"); self._drain(3)
            self.buf = b""
            self.send("echo MARKER-$((1+1))\n"); self._drain(3)
            if b"MARKER-2" in self.buf and b"FAILED LOGIN" not in self.buf:
                return True
            # back at the login prompt after a failed attempt — retry next pw
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
    pre-desktop boot frame's centre region for bright (non-ink) pixels and
    logs the best frame. The v0.6.13 run only looked at boot-00/01 — both
    were still SeaBIOS/console frames, so the plymouth window (which opens
    between the last pre-desktop frame and the desktop frame) went unseen.
    LOG-LEVEL for this tag: the brief keeps ubuntu-text as fallback until
    boot-capture PROVES the mark theme; the hard assert lands the tag after
    a capture shows it."""
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
            im = Image.open(path).convert("RGB")
            W, H = im.size
            box = im.crop((W // 2 - 250, max(0, H // 2 - 250),
                           W // 2 + 250, min(H, H // 2 + 250)))
            bright = sum(1 for p in box.getdata()
                         if max(p) > 70)
            total = (box.width * box.height)
            pct = bright * 100 // total
            log(f"splash {name}: centre bright pixels = {bright}/{total} ({pct}%)")
            if best is None or pct > best[1]:
                best = (name, pct)
        except Exception as e:
            log(f"splash {name}: unreadable ({e})")
    if best and best[1] >= 1:
        log(f"splash: best frame {best[0]} at {best[1]}% centre brightness "
            f"— consistent with the mark splash (assert lands next tag)")
    else:
        log("splash: every pre-desktop frame is ink-black in the centre — "
            "the mark splash did NOT paint (ubuntu-text fallback, console, "
            "or the window fell between frames); review the boot frames "
            "before claiming W14")

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
        if present >= desktop_ready_threshold():
            return n
        n += 1; time.sleep(5 if n < 12 else 20)
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

    def open_app(idx, name, wait_s=25):
        for attempt in range(2):
            # dock is always expanded — park the pointer high so the tray is
            # at rest, then click the tile (magnification starts on arrival)
            q.mouse_abs(W // 2, int(H * NEUTRAL_Y), W, H)
            time.sleep(0.8)
            q.click(*tiles[idx], W, H)
            time.sleep(wait_s)
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
        if serial.login():
            log("serial login OK — seeding review fixtures")
            seed_review_files(serial)
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
    if open_app(0, "02-files"):            # Files
        opens["files"] = True
        q.key("alt", "f4"); time.sleep(5)
    if open_app(1, "03-terminal", wait_s=18):   # Terminal
        opens["terminal"] = True
        q.key("alt", "f4"); time.sleep(5)
    # W9 — the dock shrank to 7 tiles (web tiles gone): Settings sits at
    # index 5, before only Files/Terminal/Browser/OS/CoreX.
    if open_app(5, "04-settings", wait_s=30):   # Settings
        opens["settings"] = True
        q.key("alt", "f4"); time.sleep(5)

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
    # anchored top-right (margins 40 top / 10 right), sheet margins 16,
    # header 30, 12 px gaps, grid 64+12+64, then the 44 px DND wide tile —
    # its 36x20 switch rides the right end (rightMargin 14). On the 1280x800
    # capture the switch centre lands at (W-58, 272); the second click
    # restores the off state.
    try:
        q.click(W - 58, 272, W, H)        # DND switch
        time.sleep(2)
        q.shot("05b-control-center-dnd")
        log("05b-control-center-dnd captured (DND on)")
        q.click(W - 58, 272, W, H)        # restore off
        time.sleep(1.5)
    except Exception as e:
        log(f"dnd toggle capture failed: {e}")

    # W14 proof step — did the mark splash paint? (log-level this tag;
    # the hard assert lands once a capture proves the theme.)
    splash_report(OUT, n)

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
