#!/usr/bin/env python3
"""Boot-capture: boots an Aegis OS ISO in QEMU, drives the shell over QMP and
captures screenshots: silent boot timeline, home desktop, Files, Terminal,
Settings and Control Center. Designed for CI runners; also runs locally.

If the desktop does not come up, the script logs into the guest over the
serial console (interactive socket chardev), dumps diagnostics, and attempts
live recovery (start SDDM / isolate graphical.target) before giving up.

Usage: python3 boot-capture.py <iso> [screenshot-dir] [--vmware-boot-check]
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

    def drag(self, x0, y0, x1, y1, W, H, steps=14):
        # T15-D7 (W44) — press, glide, release: the resize probes need a
        # REAL edge drag (press on the 8 px strip, motion, release), which
        # click() cannot express. Steps keep the motion events flowing —
        # a teleport from press to release reads as a click-and-move.
        self.mouse_abs(x0, y0, W, H)
        time.sleep(0.15)
        self._cmd("input-send-event", {"events": [
            {"type": "btn", "data": {"down": True, "button": "left"}}]})
        time.sleep(0.15)
        for i in range(1, steps + 1):
            x = x0 + (x1 - x0) * i / steps
            y = y0 + (y1 - y0) * i / steps
            self.mouse_abs(x, y, W, H)
            time.sleep(0.05)
        time.sleep(0.15)
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

def knob_centers(png, x0=380, x1=1100, y0=190, y1=640):
    """T15-D4 — white 20 px knob blobs in the pane body, clustered by row
    (each GlassSwitch row contributes one). The scan is pane-wide because
    the wallpaper pane stacks its switches on the LEFT while rows with a
    label (displays Presentation, effects rows) carry them at the RowLayout
    position after the label. The knob is pure white (255) — the fg text
    tops out at 242. Module level: shared by the W39 toggle probes AND the
    T13-D29 presentation click (the first run proved the old 402..458
    scan misses the moved knob)."""
    im = Image.open(png).convert("RGB")
    px = im.load()
    pts = [(x, y) for y in range(y0, min(y1, im.size[1]))
           for x in range(x0, min(x1, im.size[0]))
           if min(px[x, y]) > 250]
    if not pts:
        return []
    pts.sort(key=lambda p: p[1])
    clusters = []
    cur = [pts[0]]
    for p in pts[1:]:
        if p[1] - cur[-1][1] <= 12:
            cur.append(p)
        else:
            clusters.append(cur)
            cur = [p]
    clusters.append(cur)
    out = []
    for cl in clusters:
        if len(cl) < 50:
            continue
        xs = [p[0] for p in cl]
        ys = [p[1] for p in cl]
        out.append(((min(xs) + max(xs)) // 2,
                    (min(ys) + max(ys)) // 2))
    return out

def drag_right_edge(q, png, out_name, W, H, home_ref=None):
    """T15-D7 (W44) — the right-edge resize drag with the TRUE edge aim.
    The top hairline stops 6-7 px short of the window's real right edge
    (the r18 corners turn the stroke down), so the 8 px strip lives
    AROUND hairline_end + 6: press at run_end + 2 first, retry at +6.
    Returns the growth in px (0 = the drag resized nothing)."""
    st = window_hairline(png)
    if not st:
        log(f"w44 {out_name}: no window hairline found")
        return 0
    top, x0, run_len = st
    ry = min(top + 200, H - 40)
    # the interactive ring depends on the declared border size (W44: 4 px
    # sides under Tiny) — aim ladder covers the strip and one step either
    # side so a ±2 px frame-geometry drift cannot fool the probe
    for extra in (6, 2, 10):
        rx = x0 + run_len + extra
        log(f"w44 {out_name}: dragging right edge at x={rx} "
            f"(hairline end {x0 + run_len}, y={ry})")
        q.drag(rx, ry, rx + 160, ry, W, H)
        time.sleep(2.5)
        q.shot(out_name)
        st2 = window_hairline(f"{OUT}/{out_name}.png")
        if st2:
            grew = st2[2] - st[2]
            log(f"w44 {out_name}: run {st[2]} -> {st2[2]} (grew {grew} px)")
            if grew >= 100:
                return grew
        else:
            log(f"w44 {out_name}: hairline lost after the drag")
    return 0

def traffic_lights_triple(png, top, x0):
    """T15-D3 (W38) — the three traffic lights inside a titleband.
    Scans y [top, top+44], x [x0, x0+200] for the macOS hue families
    (close #FF5F57, min #FEBC2E, max #28C840) and returns [(x, y) x3]
    in close/min/max order, or None when any hue is missing — the
    "cannot close / no traffic lights" report becomes a red verdict."""
    im = Image.open(png).convert("RGB")
    px = im.load()
    W, H = im.size
    y0, y1 = max(0, top), min(H, top + 44)
    x1s = min(W, x0 + 200)

    def hue_pixels(match):
        pts = []
        for y in range(y0, y1):
            for x in range(max(0, x0), x1s):
                if match(px[x, y]):
                    pts.append((x, y))
        return pts

    out = []
    for match in (
        lambda p: p[0] > 200 and 60 < p[1] < 140 and 40 < p[2] < 130,
        lambda p: p[0] > 200 and p[1] > 150 and p[2] < 130,
        lambda p: p[0] < 130 and p[1] > 150 and p[2] < 130,
    ):
        pts = hue_pixels(match)
        if len(pts) < 25:
            return None
        xs = sum(p[0] for p in pts) // len(pts)
        ys = sum(p[1] for p in pts) // len(pts)
        out.append((xs, ys))
    return out

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
    """T7 — window left edge: walk left along the dot's centre row from just
    outside the close dot's RED SPAN (measured on that row — the dot is
    10-12 px wide and dot_x is the mean over rows, which can sit inside the
    span; v0.6.27's walk died on its own dot's AA fringe), following LOCAL
    gradient (|Δ| <= 6 per pixel). The glass band drifts slowly over a
    gradient wallpaper (a global ref stopped the v0.6.27 walk 2 px after
    the dot), while the window edge is a STEP — the frame's edge stroke
    (lum 90-140) or the CSD border. Stop at the first step; the returned x
    is the last glass pixel."""
    rgb = Image.open(png).convert("RGB")
    im = Image.open(png).convert("L")
    pl, px = rgb.load(), im.load()
    y = int(round(dot_cy))
    dx = int(dot_x)
    # anchor just left of the red span (r>150, g<110, b<110 — the same
    # criterion red_dot uses)
    rx = None
    for x0 in range(dx - 40, dx + 6):
        r, g, b = pl[x0, y]
        if r > 150 and g < 110 and b < 110:
            rx = x0
            break
    x = (rx - 2) if rx is not None else dx - 2
    prev = px[x, y]
    while x > max(0, dx - 120):
        nxt = px[x - 1, y]
        if abs(nxt - prev) > 6:
            break
        prev = nxt
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

def start_qemu(accel, gpu, append=""):
    cmd = ["qemu-system-x86_64", *accel, "-m", "4096", "-smp", "4",
           "-device", gpu, "-display", "none",
           "-device", "qemu-xhci", "-device", "usb-tablet",
           "-device", "virtio-net-pci,netdev=n0", "-netdev", "user,id=n0",
           "-cdrom", ISO, "-boot", "d", "-no-reboot",
           "-qmp", f"unix:{SOCK},server,nowait",
           "-chardev", f"socket,id=ser0,path={SERIAL_SOCK},server=on,wait=off,logfile=serial.log",
           "-serial", "chardev:ser0"]
    try:
        kern, initrd = extract_kernel_initrd()
        cmd += ["-kernel", kern, "-initrd", initrd, "-append", KERNEL_ARGS + append]
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

def start_qemu_vmware():
    # T15-D1 (W41) — the SECOND hypervisor family. Every green gate above
    # was earned on virtio; the user demos on VMware Workstation, whose
    # SVGA II device needs the vmwgfx module in the initramfs (review §0:
    # without it plymouthd gets no DRM master and runs headless the whole
    # boot — the user's Screenshot (23).png is exactly that console). QEMU
    # emulates the same device (-device vmware-svga == -vga vmware), so CI
    # exercises the user's path with no Workstation. Rule going forward:
    # one boot run per hypervisor family the user demos on.
    # W48-F2 — force a sane mode for the variant. Run-92 forensics: the
    # emulated SVGA leaves the console in a 720x400 TEXT mode — no KMS
    # connector ever exists (/sys/class/drm is empty, /dev/dri absent),
    # so the ruling's video=<connector>:1280x800-32 pin has no connector
    # name to attach to; the only mode-setting path on this device is the
    # SeaBIOS vgabios-vmware VBE, reached through the bzImage's own
    # real-mode setup. vga=791 pins 1024x768x16: when VBE lands,
    # screen_info yields a sysfb simple-framebuffer, simpledrm binds
    # card0, plymouthd owns a real DRM master and the leg upgrades itself
    # into splash/desktop-provable; when VBE fails the boot is exactly
    # today's text console — no risk either way. vmware_boot_check prints
    # /sys/class/drm every run so a future binding names itself.
    chains = (["-enable-kvm", "-cpu", "host"],
              ["-accel", "tcg,thread=multi", "-cpu", "max"])
    for accel in chains:
        log(f"trying gpu=vmware-svga accelerator={accel[0]}")
        for p in (SOCK, SERIAL_SOCK):
            if os.path.exists(p):
                os.remove(p)
        proc = start_qemu(accel, "vmware-svga", " vga=791")
        if proc:
            log(f"accelerator in use: {accel[0]}; gpu: vmware-svga")
            return proc
    raise RuntimeError("qemu failed to start with vmware-svga — see qemu.log")

def vmware_boot_check():
    """T15-D1 (W41), W48 rework — the VMware-variant boot gate. Boots the
    same ISO once under -device vmware-svga and asserts what the emulated
    device can PROVE: vmwgfx loaded in the guest, plymouthd carrying no
    DRM-master/renderer failure lines, and a live serial session. Run-92
    forensics (v0.6.58): the emulated SVGA console is a 720x400 TEXT mode
    — vmwgfx loads but never binds (no /dev/dri at all), plymouthd paints
    nothing (zero splash-signature frames) and the dock-gate math needs a
    ~960 px dock the 720 px mode can never host. So per W48-F1 the
    desktop-appear gate is a warn-only diagnostic riding the serial
    substitutes (sddm active, kwin pgrep count, kwin's EGL/gbm/drm
    journal lines), and a splash miss DEMOTES to a warning when the
    guest provably has no display surface (no /dev/dri card, no /dev/fb0)
    but stays a HARD failure when a surface existed and the mark still
    missed. The W41 splash claim on real VMware closes on the user's
    Workstation re-test (W41 reopen ruling), not on this lane; the
    virtio run stays the release-blocking gate."""
    os.makedirs(OUT, exist_ok=True)
    proc = start_qemu_vmware()
    q = QMP(SOCK)
    log("QMP connected (vmware-svga)")
    n = wait_desktop(q, proc, timeout=360)   # W48-F1: own 6-minute budget
    desktop_ok = n >= 0
    vmwgfx_loaded = False
    plymouth_clean = None      # None = journal check never ran (serial lost)
    display_capable = None     # None = serial never ran (probe unknown)
    sddm_state = kwin_procs = None
    try:
        serial = Serial(SERIAL_SOCK)
        if serial.login():
            log("serial login OK (vmware variant)")
            out = serial.run(
                "lsmod | grep vmwgfx | head -2; echo VMWGFX-END; "
                "ls -la /dev/dri 2>&1 | head -4; echo DRI-END; "
                "ls /sys/class/drm/ 2>&1; echo DRM-CLASS-END; "
                "ls -la /dev/fb0 2>&1 | head -2; echo FB-END; "
                "systemctl is-active sddm; echo SDDM-END; "
                "pgrep -c kwin_wayland; echo KWIN-END; "
                "journalctl -b --no-pager 2>/dev/null | grep -ai plymouth "
                "| grep -aiE 'drm|master|headless|render|fail|error' "
                "| head -12; echo PLY-JRN-END; "
                "journalctl -b --no-pager 2>/dev/null | grep -ai kwin "
                "| grep -aiE 'egl|gbm|drm' | head -8; echo KWIN-JRN-END",
                settle=10)
            seg = out.split("VMWGFX-END")[0]
            vmwgfx_loaded = "vmwgfx" in seg
            log("vmware variant: vmwgfx "
                + ("IS loaded" if vmwgfx_loaded
                   else "NOT loaded — the initramfs force-load missed it"))
            if "DRI-END" in out:
                dri = out.split("DRI-END")[0].split("VMWGFX-END")[-1].strip()
                has_dri = ("cannot access" not in dri
                           and "No such file" not in dri)
            else:
                has_dri = False
            if "FB-END" in out:
                fb = out.split("FB-END")[0].split("DRM-CLASS-END")[-1].strip()
                has_fb = ("cannot access" not in fb
                          and "No such file" not in fb)
            else:
                has_fb = False
            display_capable = has_dri or has_fb
            if "DRM-CLASS-END" in out:
                drmcls = (out.split("DRM-CLASS-END")[0]
                          .split("DRI-END")[-1].strip())
                log("vmware variant: /sys/class/drm connectors: "
                    + (drmcls.replace("\n", " ") if drmcls
                       else "(none — the W48-F2 vga pin did not land a "
                            "KMS mode)"))
            if "SDDM-END" in out:
                sddm_state = (out.split("SDDM-END")[0]
                              .split("FB-END")[-1].strip())
            if "KWIN-END" in out:
                kwin_procs = (out.split("KWIN-END")[0]
                              .split("SDDM-END")[-1].strip())
            log("vmware variant serial substitutes: "
                f"sddm={sddm_state} kwin_procs={kwin_procs} "
                f"display_capable={display_capable} "
                "(W48-F1 — diagnosed, not asserted)")
            if "PLY-JRN-END" in out:
                jrn = (out.split("PLY-JRN-END")[0]
                       .split("KWIN-END")[-1].strip())
                plymouth_clean = len(jrn) == 0
                if jrn:
                    log("plymouthd journal failure lines: "
                        + jrn.replace("\n", " | ")[:400])
                else:
                    log("plymouthd journal: no DRM-master/renderer failure "
                        "lines")
            if "KWIN-JRN-END" in out:
                kj = (out.split("KWIN-JRN-END")[0]
                      .split("PLY-JRN-END")[-1].strip())
                if kj:
                    log("kwin drm/egl journal (diagnostic): "
                        + kj.replace("\n", " | ")[:300])
            q.shot("vmw-desktop")
        else:
            log("serial login FAILED on the vmware variant")
    except Exception as e:
        log(f"vmware variant serial diag failed: {e}")
    if not desktop_ok:
        log("desktop never appeared under vmware-svga (W48-F1 diagnostic "
            "— the serial substitutes above are the authoritative read); "
            "serial.log tail:")
        try:
            for line in list(open("serial.log"))[-40:]:
                log("  | " + line.rstrip()[:200])
        except OSError:
            pass
    splash_ok = splash_report(OUT, n if desktop_ok else -1)
    failures = []
    if not vmwgfx_loaded:
        failures.append("vmware variant: vmwgfx never loaded in the guest "
                        "— the 0200 initramfs force-load list misses it")
    if plymouth_clean is False:
        failures.append("vmware variant: the journal carries plymouthd "
                        "DRM-master/renderer failure lines — headless boot, "
                        "the exact Screenshot (23).png console flood")
    if not splash_ok:
        if display_capable is False:
            log("vmware variant: splash miss DEMOTED to a diagnostic — "
                "the guest provably has no display surface (no /dev/dri "
                "card, no /dev/fb0): the emulated SVGA leaves a 720x400 "
                "text console and plymouthd has nothing to own. The W41 "
                "splash claim closes on the user's real Workstation "
                "re-test (W41 reopen ruling).")
        else:
            failures.append("vmware variant: the mark splash never painted "
                            "on the vmware-svga frames — W41 NOT met")
    if failures:
        for f in failures:
            log("ASSERT FAILED: " + f)
        log("vmware boot variant complete (FAILED — W41 gate red)")
        q._cmd("quit")
        sys.exit(1)
    log("vmware boot variant complete (W41 gate green)")
    q._cmd("quit")

# ---------------- serial console ----------------
# T13-D10 — the serial console's bash emits shell-integration OSC 3008
# markers and ANSI color codes around every command and its output. On the
# v0.6.45 run the resolved-Exec parser read `splitlines()[-1]` of that
# stream and got `]3008;end=...;exit=success` — an OSC fragment — and the
# harness then launched THAT string over DBus (Util.launch even created a
# log file named after it, escape bytes included). Every parsed value off
# this channel is now stripped of CSI/OSC/other escape sequences first.
ANSI_RE = re.compile(
    r"\x1b\[[0-9;?]*[ -/]*[@-~]"          # CSI sequences (colors, ?2004h…)
    r"|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)"  # OSC sequences (3008, 0;title…)
    r"|\x1b[@-Z\\-_]"                      # other single-char escapes
)


def strip_ansi(text):
    return ANSI_RE.sub("", text)


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
        # T11-D5b — the settle is a HARD MINIMUM: the old version reset the
        # deadline to now+0.5 s on every received chunk, so a command whose
        # output trails (the QML probes run a silent ~8 s timeout chain)
        # drained ~0.6 s in and the runner typed the NEXT commands while the
        # guest's foreground was still busy — the queued lines were never
        # echoed or executed (v0.6.29 lost VERDICTS, WRAPPERS and the five
        # JRN/KWINRC diagnostics between the monitor probe and KWIN-PLUGINS;
        # the whole run went red on verdicts that were harness losses, not
        # product errors).
        deadline = time.time() + settle
        while time.time() < deadline:
            try:
                d = self.s.recv(4096)
                if not d:
                    break
                self.buf += d
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
        out = out[idx + len(cmd):] if idx >= 0 else out
        # T13-D10 — shell-integration OSC markers and color codes are
        # noise on every parsed value; strip before any caller reads this
        return strip_ansi(out)

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
        "/tmp/qml-probe.err; then echo DIRTY > /tmp/pv-s; else echo CLEAN "
        "> /tmp/pv-s; fi",
        "echo ===QP''F===; export XDG_RUNTIME_DIR=/run/user/$(id -u); "
        "WAYLAND_DISPLAY=wayland-0 timeout -k 2 6 aegis-apps files "
        ">/tmp/qml-probe-files.err 2>&1; if grep -qvi 'libEGL warning' "
        "/tmp/qml-probe-files.err; then echo DIRTY > /tmp/pv-f; else echo "
        "CLEAN > /tmp/pv-f; fi",
        # T11 — the four M3 apps join the foreground probes. Music's DIRTY
        # verdict additionally ignores audio/multimedia chatter (pipewire /
        # pulse / gstreamer / alsa / qt.multimedia / ffmpeg): MediaPlayer is
        # constructed at startup and a headless VM prints benign audio and
        # backend-banner lines (v0.6.30 went red on the harmless
        # "qt.multimedia.ffmpeg: Using Qt multimedia..." banner), while a
        # real QML load failure still says error/Cannot and stays DIRTY.
        "echo ===QP''M===; export XDG_RUNTIME_DIR=/run/user/$(id -u); "
        "WAYLAND_DISPLAY=wayland-0 timeout -k 2 6 aegis-apps music "
        ">/tmp/qml-probe-music.err 2>&1; if grep -qvi -e 'libEGL warning' "
        "-e 'pipewire' -e 'pulse' -e 'gstreamer' -e 'alsa' "
        "-e 'qt.multimedia' -e 'ffmpeg' "
        "/tmp/qml-probe-music.err; then echo DIRTY > /tmp/pv-m; else echo "
        "CLEAN > /tmp/pv-m; fi",
        "echo ===QP''C===; export XDG_RUNTIME_DIR=/run/user/$(id -u); "
        "WAYLAND_DISPLAY=wayland-0 timeout -k 2 6 aegis-apps calculator "
        ">/tmp/qml-probe-calculator.err 2>&1; if grep -qvi 'libEGL warning' "
        "/tmp/qml-probe-calculator.err; then echo DIRTY > /tmp/pv-c; else "
        "echo CLEAN > /tmp/pv-c; fi",
        "echo ===QP''E===; export XDG_RUNTIME_DIR=/run/user/$(id -u); "
        "WAYLAND_DISPLAY=wayland-0 timeout -k 2 6 aegis-apps editor "
        ">/tmp/qml-probe-editor.err 2>&1; if grep -qvi 'libEGL warning' "
        "/tmp/qml-probe-editor.err; then echo DIRTY > /tmp/pv-e; else echo "
        "CLEAN > /tmp/pv-e; fi",
        "echo ===QP''N===; export XDG_RUNTIME_DIR=/run/user/$(id -u); "
        "WAYLAND_DISPLAY=wayland-0 timeout -k 2 6 aegis-apps monitor "
        ">/tmp/qml-probe-monitor.err 2>&1; if grep -qvi 'libEGL warning' "
        "/tmp/qml-probe-monitor.err; then echo DIRTY > /tmp/pv-n; else echo "
        "CLEAN > /tmp/pv-n; fi",
        # T11-D5 — one short read returns all six verdicts from the guest's
        # verdict FILES: the v0.6.28 run lost two in-band verdict tokens
        # (music, monitor) to serial-buffer desync when a probe chain ran
        # long and a later echo swallowed the token. File-based verdicts
        # cannot desync.
        "echo ===VERDICTS===; for f in s f m c e n; do echo PV-$f=$(cat "
        "/tmp/pv-$f 2>/dev/null || echo MISSING); done",
        # T11-D5 — the four M3 wrappers were never verified in the guest:
        # prove they exist, are executable, and are what the dock execs.
        "echo ===WRAPPERS===; ls -la /usr/bin/aegis-files /usr/bin/aegis-settings "
        "/usr/bin/aegis-music /usr/bin/aegis-calculator /usr/bin/aegis-editor "
        "/usr/bin/aegis-monitor 2>&1; echo WRAPPERS-DONE",
        "echo ===JRN-SHELL===; sudo journalctl -b --no-pager 2>&1 | grep -aiE 'aegis-(shell|apps|session|files|settings)|QQml|qrc:' | tail -50",
        "echo ===JRN-KWIN===; sudo journalctl -b --no-pager 2>&1 | grep -ai 'kwin' | grep -aivE 'information|Rendering|colorProfile|ColorManagement' | tail -40",
        "echo ===JRN-CRASH===; sudo journalctl -b --no-pager 2>&1 | grep -aiE 'segfault|signal 11|coredump|abrt|general protection' | tail -20",
        "echo ===COREDUMPCTL===; coredumpctl list --no-pager 2>&1 | tail -10",
        "echo ===KWINRC===; cat /etc/xdg/kwinrc 2>&1",
        "echo ===KDEGLOBALS===; cat /etc/xdg/kdeglobals 2>&1",
        # T13 D29 — the USER kdeglobals is what setDarkMode writes and
        # what the dark-tile gate greps; the skeleton dump above cannot
        # answer "did the write land". Ownership in the listing answers
        # the write-permission question too.
        "echo ===USER-KDEGLOBALS===; ls -la ~/.config/kdeglobals 2>&1; "
        "cat ~/.config/kdeglobals 2>&1; echo USER-KG-END",
        "echo ===SDDM-THEME===; ls /usr/share/sddm/themes/aegis/ 2>&1",
        # W20 — did KWin really load the windowwatch script? busctl asks
        # the scripting manager directly; the island auto-hide assert
        # below proves the whole chain end to end.
        "echo ===KWIN-SCRIPTS===; busctl --user call org.kde.KWin "
        "/Scripting org.kde.kwin.Scripting isScriptLoaded s "
        "aegis-windowwatch 2>&1",
        "echo ===KWIN-EFFECTS===; busctl --user call org.kde.KWin "
        "/Effects org.kde.KWin.isEffectLoaded s aegis-dockzoom 2>&1",
        # W20/W21 — the plugins print their load markers at KWin startup;
        # the journal is the proof the CODE ran (isScriptLoaded only
        # proves the registration)
        "echo ===KWIN-LOADS===; sudo journalctl -b --no-pager 2>&1 | "
        "grep -ai 'aegis-windowwatch: loaded\\|aegis-dockzoom: loaded' "
        "| tail -6",
        "echo ===KWIN-PLUGINS===; ls /usr/lib/x86_64-linux-gnu/qt6/plugins/kwin/effects/plugins/ 2>&1; ls /usr/lib/qt6/plugins/kwin/effects/plugins/ 2>&1; echo PLUGINS-DONE",
        # T13 W24 — the launch logs (one file per app head, rotated):
        # the VM review's diagnosability ask, visible in CI. Qt's
        # StateLocation APPENDS the app name, so the shell's logs live at
        # ~/.local/state/aegis-shell/... — glob both shapes. T13-D10 —
        # per-file walk with an explicit header: the old tail|head cap cut
        # corex's entry out of the dump entirely, and escape-byte FILE
        # NAMES (the OSC-garbage launch logs) must still be listed.
        "echo ===LAUNCH-LOGS===; for f in /home/aegis/.local/state/*/aegis/launch/*.log; do "
        '[ -f "$f" ] || continue; echo "### LOGFILE: $f"; tail -n 14 "$f"; done; echo LAUNCH-LOGS-END',
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
    verdict_out = ""
    for c in diag_cmds:
        # probe commands get a 12 s settle: the timeout -k bound is 8 s, so
        # the verdict always lands inside the drain window
        out = serial.run(c, settle=12 if "timeout -k" in c else 6)
        blob.append(out)
        if "===VERDICTS===" in c:
            verdict_out = out
        log("app-diag: " + out.strip().replace("\n", " | ")[:400])
    open("serial-diag.txt", "w").write("\n".join(blob))
    # §1 — verdicts come from the guest's /tmp/pv-* files (see the
    # VERDICTS diag command): in-band tokens desynced twice on v0.6.28.
    # T11-D6 — name-to-verdict-token MAP, not name[0]: music and monitor
    # both start with m, so the old regex read PV-m for BOTH probes —
    # the monitor's own verdict file (pv-n) was never parsed and a
    # DIRTY monitor went unseen (v0.6.33 run 43134801060 logged
    # "probe monitor: CLEAN" while the guest said PV-n=DIRTY; the
    # monitor probe has been unverified since the file verdicts landed).
    tokens = {"settings": "s", "files": "f", "music": "m",
              "calculator": "c", "editor": "e", "monitor": "n"}
    probes = {}
    for name, path, extra in (
            ("settings", "/tmp/qml-probe.err", ""),
            ("files", "/tmp/qml-probe-files.err", ""),
            ("music", "/tmp/qml-probe-music.err",
             "-e pipewire -e pulse -e gstreamer -e alsa "
             "-e qt.multimedia -e ffmpeg"),
            ("calculator", "/tmp/qml-probe-calculator.err", ""),
            ("editor", "/tmp/qml-probe-editor.err", ""),
            ("monitor", "/tmp/qml-probe-monitor.err", "")):
        m = re.search(rf"PV-{tokens[name]}=(\w+)", verdict_out)
        verdict = m.group(1) if m else "MISSING"
        if verdict == "CLEAN":
            log(f"probe {name}: CLEAN")
            probes[name] = ""
        elif verdict == "DIRTY":
            fetch = serial.run(
                f"grep -vi 'libEGL warning' {extra} {path} | head -10",
                settle=3)
            log(f"probe {name}: DIRTY — " + fetch.strip()[:300])
            probes[name] = fetch
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

def config_assert(diag_path):
    """W23.1 — assert the decoration config, don't just dump it. The run
    log printed ===KWINRC=== for nine releases and NOTHING failed on
    drift — the same shipped-green class as the v0.6.20 boot regression
    (a sync-includes slip regresses the theme and the run stays green).
    Every needle below is a shipped ruling: W10/W11 anatomy, Table 18
    corners, M3 Depth, W20 window tracking, W21 dock zoom, W18 fonts."""
    try:
        blob = open(diag_path, errors="replace").read()
    except OSError:
        return ["serial-diag.txt missing — the decoration config was "
                "never verified"]
    failures = []

    def section(header):
        # The serial lines carry escape prefixes and the markers land
        # mid-line ("...cwd=/home/aegis\===KWINRC==="), so a line-anchored
        # regex cannot cut the sections. Scan lines: a section starts at
        # the line carrying ===header=== and ends at the next ===MARKER===
        # line. (The first cut used a lazy lookahead that stopped the
        # capture at the FIRST newline — every needle failed on a
        # perfectly healthy config, caught by the offline simulation.)
        out = []
        active = False
        marker = "===" + header + "==="
        for ln in blob.splitlines():
            if "===" in ln:
                if marker in ln:
                    active = True
                    continue
                if active:
                    break
            if active:
                out.append(ln)
        return "\n".join(out)

    kwinrc = section("KWINRC")
    kde = section("KDEGLOBALS")
    if not kwinrc:
        return ["===KWINRC=== dump missing from the serial diag"]

    def need(text, needle, what):
        if needle not in text:
            failures.append(what)

    need(kwinrc, "theme=__aurorae__svg__AegisLights",
         "decoration theme is not AegisLights")
    need(kwinrc, "ButtonsOnLeft=XIA",
         "ButtonsOnLeft drifted from XIA (close dot must lead on the left)")
    # T15-D7 (W44) — None was PROVEN non-resizable by the edge-drag probe
    # (two runs, 0 px growth on Konsole); the review ruling flips to Tiny
    # (4 px strips, the 44 px titleband and W10 metrics unchanged).
    need(kwinrc, "BorderSize=Tiny",
         "BorderSize drifted (W44 resize ruling — Tiny after None proved "
         "non-resizable)")
    need(kwinrc, "kwin4_effect_shapecornersEnabled=true",
         "ShapeCorners effect disabled (Table 18 r18 corners)")
    need(kwinrc, "aegis-windowwatchEnabled=true",
         "aegis-windowwatch script disabled (W20 island predicate — "
         "the key is the VERBATIM plugin id + Enabled)")
    need(kwinrc, "aegis-dockzoomEnabled=true",
         "aegis-dockzoom effect disabled (W21 dock zoom — verbatim id "
         "+ Enabled)")
    need(kwinrc, "scaleEnabled=false",
         "stock scale effect re-enabled (it conflicts with aegis-dockzoom)")
    need(kwinrc, "Number=4",
         "workspace count drifted from 4 (M3 Depth)")
    if not kde:
        failures.append("===KDEGLOBALS=== dump missing (W18 font pin)")
    else:
        need(kde, "activeFont=Montserrat",
             "kdeglobals [WM] activeFont missing (W18 caption font)")
        if not re.search(r"^font=Montserrat", kde, re.M):
            failures.append("kdeglobals [General] font missing "
                            "(W18 body font)")
    # W20 — the windowwatch script must be LOADED inside KWin (the kwinrc
    # key alone proves intent, not the load)
    scripts = section("KWIN-SCRIPTS")
    if scripts and "true" not in scripts.lower():
        failures.append("aegis-windowwatch is not loaded in KWin "
                        "(isScriptLoaded said: "
                        + scripts.strip()[:60] + ")")
    # NOTE: the print()-marker gate was removed — KWin script print()
    # does not reach journald on this stack (v0.6.37 run 6: the markers
    # were in the scripts, absent from the journal). The
    # island_autohide_assert is the end-to-end proof; the prints stay in
    # the scripts for manual debugging.
    return failures

def greeter_assert(out_dir, last_frame):
    """W23.2 — the SDDM greeter pixel signature (clock/progress devices).
    NOT WIRED INTO THE GATE: the v0.6.35 boot run proved the live ISO
    NEVER SHOWS the greeter — SDDM autologins straight into the session
    (serial log: sddm-helper --start dbus-run-session --aegis-session
    --autologin, no sddm-greeter process at all), and boot-14/15/16 are
    the pure-black SDDM-to-session handoff gap, not a broken greeter.
    The reviewer's mark+clock+progress verification applies to the
    INSTALLED path (no autologin); the boot gate instead asserts the
    theme FILES ship (sddm_theme_assert below) — a sync-includes slip
    still goes red. Keep this function for that future gate."""
    n = 0
    best = None
    while True:
        if last_frame > 0 and n >= last_frame:
            break
        path = os.path.join(out_dir, f"boot-{n:02d}.png")
        if not os.path.exists(path):
            break
        im = Image.open(path).convert("RGB")
        W, H = im.size
        clock = im.crop((W // 2 - 160, int(H * 0.14),
                         W // 2 + 160, int(H * 0.27)))
        bright = sum(1 for p in clock.getdata() if min(p) > 150)
        margin = im.crop((0, int(H * 0.14), int(W * 0.15), int(H * 0.27)))
        edge = sum(1 for p in margin.getdata() if min(p) > 150)
        line = im.crop((W // 2 - 80, int(H * 0.09),
                        W // 2 + 80, int(H * 0.16)))
        accent = sum(1 for p in line.getdata()
                     if p[2] > 200 and 60 < p[1] < 190 and p[2] - p[0] > 100)
        score = (bright, accent)
        if best is None or sum(score) > sum(best[1]):
            best = (n, score)
        if bright >= 300 and edge <= 40:
            log(f"greeter: clock confirmed on boot-{n:02d} "
                f"(bright px {bright}, left margin px {edge}, "
                f"accent px {accent})")
            return True
        if accent >= 25:
            log(f"greeter: accent progress confirmed on boot-{n:02d} "
                f"(accent px {accent}, bright px {bright})")
            return True
        n += 1
    if best:
        log(f"greeter: best candidate boot-{best[0]:02d} — clock px "
            f"{best[1][0]}, accent px {best[1][1]} (below thresholds)")
    return False

def sddm_theme_assert(diag_path):
    """W23.2 (revised after the autologin finding) — the greeter is never
    rendered on the live path (SDDM autologins straight into the
    session; boot-14/15/16 pure black is the handoff gap), so the gate
    verifies the THEME SHIPS: ===SDDM-THEME=== must list the aegis
    theme's files (Main.qml, mark.png, metadata.desktop). A
    sync-includes slip that drops the theme still fails the release."""
    try:
        blob = open(diag_path, errors="replace").read()
    except OSError:
        return ["serial-diag.txt missing — the SDDM theme was never "
                "verified"]
    marker = "===SDDM-THEME==="
    section = []
    active = False
    for ln in blob.splitlines():
        if "===" in ln:
            if marker in ln:
                active = True
                continue
            if active:
                break
        if active:
            section.append(ln)
    text = "\n".join(section)
    failures = []
    for needle, what in (("Main.qml", "SDDM theme Main.qml missing"),
                         ("mark.png", "SDDM theme mark.png missing"),
                         ("metadata.desktop",
                          "SDDM theme metadata.desktop missing")):
        if needle not in text:
            failures.append(what + " (a sync-includes slip?)")
    return failures

def tint_assert(files_png):
    """W16 — the report.pdf card must render the tinted doc-page glyph
    (#FA2D48). MEASURED decomposition on the v0.6.35 boot captures:
    broken build = 237 px (the pre-colored music glyph's edge AA 223 + a
    14 px sidebar artifact — the pdf icon was BLUE then); fixed build =
    395 px (the same 237 + ~158 for the red doc-page outline stroke at
    44 px). Gate at 300 — dead center between the two measured states.
    Tolerance ±14/channel keeps the traffic-light red (255,95,87) out
    (its green is 50 away)."""
    im = Image.open(files_png).convert("RGB")
    hits = 0
    for p in im.getdata():
        if (abs(p[0] - 250) <= 14 and abs(p[1] - 45) <= 14
                and abs(p[2] - 72) <= 14):
            hits += 1
    return hits

def monitor_card_assert(monitor_png):
    """W17 — the Monitor capture must show REAL data, never the
    honest-looking lies (v0.6.34 shipped an empty Cores card and
    '0.0 GB of 0.0 GB'). The StatCard fill bars and the per-core strips
    paint EXACTLY Tokens.accent (62,139,255) — a ±10 window around it
    (measured: 5 px on the broken v0.6.34 capture; the loose ±window
    matched wallpaper waves at 420). Healthy fills on the loaded runner
    give hundreds of exact-accent px; a total parse failure zeroes every
    fill and the assert goes red. The partial-failure case (one source
    dead) is covered by the probe verdicts: MonitorBackend warns
    'failed to read' per dead source and probe_failed() arbitrates."""
    im = Image.open(monitor_png).convert("RGB")
    hits = 0
    for p in im.getdata():
        if (52 <= p[0] <= 72 and 129 <= p[1] <= 149
                and 245 <= p[2] <= 255):
            hits += 1
    return hits

def island_autohide_assert(home_png, files_png):
    """W20 — the island auto-hide chain proven END TO END: the idle
    island VISIBLE on the empty home (the white mark reads ~27 px in the
    top-center region), HIDDEN once a window is open (KWin script ->
    DBus -> Util.workspaceWindows -> dissolve). The v0.6.35 first run
    exposed a silent break exactly here: the script called DBus path /
    while Util registers /org/aegis/Shell, so the island never hid and
    nothing went red — the class of shipped-green regression this
    assert exists to kill. The mark is the only bright thing in that
    region on the ink sky."""
    def bright(png):
        im = Image.open(png).convert("RGB")
        W, H = im.size
        n = 0
        for y in range(int(H * 0.037), int(H * 0.078)):
            for x in range(int(W * 0.45), int(W * 0.55)):
                if min(im.getpixel((x, y))) > 120:
                    n += 1
        return n
    return bright(home_png), bright(files_png)

def magnify_clearance_assert(home_png, mag_png):
    """V1 — the pill padding must grow by the field delta: the end tiles
    gain clearance while magnified (v0.6.34 kept the rest clearance —
    Files at 3-4 px kissing the rounded corner). Self-calibrating: the
    magnified clearance must beat the REST clearance by ≥ 8 px. The
    first tile is the Files folder (blue glyph) by config."""
    def clearance(png):
        im = Image.open(png).convert("RGB")
        W, H = im.size
        y = H - 20                       # through the pill body
        def lum(p):
            return (p[0] * 299 + p[1] * 587 + p[2] * 114) // 1000
        prev = None
        left = None
        # the FIXED pill grows leftward past W/5 when the field is live
        # (v0.6.35: edge at 246 — a scan starting at 256 found nothing)
        # — start from W/10
        for x in range(W // 10, W // 2):
            l = lum(im.getpixel((x, y)))
            if prev is not None and abs(l - prev) > 14:
                left = x
                break
            prev = l
        if left is None:
            return None
        blues = [x for x in range(left - 4, min(left + 130, W))
                 if (lambda p: p[2] > 150 and p[2] - p[0] > 40)(
                     im.getpixel((x, H - 47)))]
        if not blues:
            return None
        return blues[0] - left

    rest = clearance(home_png)
    mag = clearance(mag_png)
    if rest is None or mag is None:
        return (None, None)
    return (rest, mag)

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
def dock_geometry(png, n_override=None):
    """Dock tile centers computed GEOMETRICALLY from Tokens.qml + config.

    The v0.4.x dock is an always-expanded light glass tray: brightness-gap
    clustering cannot separate 64 px icons from the tray glass, and column
    means sit right on any fixed threshold. But the dock is deterministic:
    centered horizontally, fixed pitch (tileWidth + tileGap), fixed icon
    row height — so we parse the tokens out of the repo and lay the tile
    centers out arithmetically. A brightness/saturation sanity check per
    slot tells whether the desktop is really up (returns n_present).
    T11-D5: n_override lets the caller lay out the map for the tile count
    the GUEST actually shows (Tier B slots drop when their deb is missing
    — the v0.6.28 build lost the Browser deb to a 404, the dock showed 10
    tiles while the config said 11, and every click after the separator
    landed half a pitch off, usually in the 2 px gap between tiles)."""
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
    n = n_override if n_override else expected_tiles()

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


def resolved_tile_cmds(serial):
    """T11-D5 — the tile list the GUEST actually shows, in dock order.

    The dock drops Tier B slots whose product is not installed (W8) and
    re-lays-out the survivors, so the config count can disagree with the
    real dock — the v0.6.28 ISO lost the Browser deb (404) and every
    geometric click after the separator missed. Ask the guest directly:
    for each config slot in order, Tier A is always present, Tier B is
    present iff its binary is on PATH (the W8 rule approximated by
    command -v; the three Tier B products always ship binaries).
    Returns the present cmds in dock order, or None when serial is
    unavailable or the reply is garbled — the caller then keeps the
    config-derived map."""
    if serial is None:
        return None
    try:
        cfg = json.load(open("shell/packaging/config.json"))
        slots = [(bool(a.get("resolve")), a.get("cmd", ""))
                 for a in cfg.get("apps", [])
                 if a.get("type") != "separator"]
    except Exception as e:
        log(f"resolved_tile_cmds: config unreadable ({e})")
        return None
    tests = []
    # faithful W8 entry probe — the dock shows a Tier B slot iff a
    # non-hidden Application entry's Exec basename (quotes stripped, may
    # point into /opt) or TryExec matches the cmd head, else iff the binary
    # is on PATH. command -v alone is NOT the W8 rule: the Aegis Browser
    # deb ships the entry with an /opt Exec and no PATH binary, so the
    # v0.6.29 harness read 10 tiles while the dock showed 11.
    # D18 — the Exec head parse is quote-aware: awk '{print $1}' splits
    # INSIDE a quoted path (CoreX: "/opt/CoreX Terminal/corex-terminal")
    # and the basename read CoreX. The v0.6.49 run proved the same bug
    # lives in BOTH the entryhit prelude and the Tier B resolution walk.
    prelude = (
        r"""execbase() { l=$(sed -n 's/^Exec=//p' "$1" 2>/dev/null | head -1); """
        r"""if [ "${l#\"}" != "$l" ]; then """
        r"""e=$(printf '%s' "${l#\"}" | cut -d'"' -f1); """
        r"""else e=$(printf '%s' "$l" | awk '{print $1}'); fi; """
        r"""printf '%s' "${e##*/}"; }"""
    )
    prelude += (
        "\nentryhit() { c=$1; for d in /usr/share/applications/*.desktop; do "
        "ex=$(execbase \"$d\"); "
        "te=$(sed -n 's/^TryExec=//p' \"$d\" 2>/dev/null | head -1); "
        "[ \"$ex\" = \"$c\" ] && return 0; "
        "[ \"$te\" = \"$c\" ] && return 0; done; "
        "command -v \"$c\" >/dev/null 2>&1; }")
    for resolve, cmd in slots:
        head = cmd.split(" ")[0]
        if resolve:
            tests.append(f"if entryhit {head}; then echo TILE {head}; fi")
        else:
            tests.append(f"echo TILE {head}")
    try:
        out = serial.run(prelude + "; " + "; ".join(tests)
                         + "; echo TILE-ORDER-END", settle=14)
    except Exception as e:
        log(f"resolved_tile_cmds: serial probe failed ({e})")
        return None
    if "TILE-ORDER-END" not in out:
        log("resolved_tile_cmds: reply garbled — keeping the config map")
        return None
    cmds = re.findall(r"TILE (\S+)", out)
    if not cmds:
        return None
    return cmds

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
        n += 1; time.sleep(1 if n < 12 else (2.5 if n < 26 else 20))
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
    tile_index = {}                       # cmd -> dock position (guest-resolved)
    log(f"resolution {W}x{H}; dock slots: {len(tiles)} (geometric)")
    hover = tiles[len(tiles) // 2]
    q.mouse_abs(hover[0], hover[1] - 90, W, H)
    time.sleep(0.6)
    q.mouse_abs(*hover, W, H)
    time.sleep(2.2)
    q.shot("01b-dock-magnify")
    q.mouse_abs(W // 2, int(H * NEUTRAL_Y), W, H)
    time.sleep(1.0)

    # T13 D24 (W35) — the pinned launcher shortcut: Meta+Space opens the
    # launcher through the aegis-shortcuts KWin script + kglobalacceld
    # (registered via registerShortcut at session start; the binding also
    # lands in the user's kglobalshortcutsrc as file-assertable state).
    # Escape dismisses (the launcher's own grammar).
    try:
        q.key("meta_l", "spc")
        time.sleep(2.5)
        q.shot("01c-launcher-shortcut")
        d = diff_px(thumb(f"{OUT}/01c-launcher-shortcut.png"), home)
        log(f"01c-launcher-shortcut: diff-vs-home={d:.1f} "
            "(Meta+Space via the aegis-shortcuts script)")
        q.key("esc")
        time.sleep(1.5)
    except Exception as e:
        log(f"launcher shortcut capture failed: {e}")

    def open_app(name, cmd, wait_s=25, click_idx=None, launch_cmd=None):
        """Launch an app and capture it. Ladder (T11-D5):
        1. the session API over DBus — Util.launch on org.aegis.Shell (the
           Q_CLASSINFO D-Bus Interface fix; before it, Qt exported the
           invokables as the generated local.aegis.Util interface and
           EVERY busctl call failed with "No such interface" while the
           geometric click fallback silently did the work),
        2. nohup from the serial shell — the same binary the dock execs,
           independent of the bus AND of the dock geometry (the proven
           04b-aegis-id pane mechanism),
        3. geometric dock click — built from the guest's real tile list
           when the serial answer arrived, the config count otherwise.
        T13 W24 — launch_cmd="desktop" resolves the FULL Exec= from the
        guest's .desktop first (the Tier B debs install into /opt with
        bare heads that are not on PATH; the dock launches the resolved
        Exec and the probe must prove THE SAME path works)."""
        lc = cmd
        if launch_cmd == "desktop" and serial is not None:
            try:
                # T13-D10 — marker-bounded resolution. The old version read
                # splitlines()[-1] of the raw serial stream and got the
                # shell-integration OSC fragment instead of the Exec line
                # (the v0.6.45 run then LAUNCHED that garbage over DBus —
                # Util.launch even created a launch log named after it).
                # run() now strips escapes; the sentinels bound the value.
                out = serial.run(
                    "echo EXEC-RES-START; "
                    # D10/v0.6.46 run — the deb entry is not always named
                    # after the command head (the browser ships
                    # aegis-browser.desktop / org.aegisbrowser.Aegis, not
                    # aegis-browser-stable.desktop): walk every entry the
                    # way the W8 entryhit rule does and take the first
                    # Exec whose basename matches the head. D18 — the
                    # basename is QUOTE-AWARE: awk $1 split inside the
                    # quoted CoreX path and the walk never matched it.
                    r"""execbase() { l=$(sed -n 's/^Exec=//p' "$1" """
                    r"""2>/dev/null | head -1); """
                    r"""if [ "${l#\"}" != "$l" ]; then """
                    r"""e=$(printf '%s' "${l#\"}" | cut -d'"' -f1); """
                    r"""else e=$(printf '%s' "$l" | awk '{print $1}'); fi; """
                    r"""printf '%s' "${e##*/}"; }; """
                    "for d in /usr/share/applications/*.desktop; do "
                    f"ex=$(execbase \"$d\"); [ \"$ex\" = \"{cmd}\" ] "
                    "&& sed -n 's/^Exec=//p' \"$d\" | head -1 | "
                    "cut -d= -f2- && break; done; "
                    "echo EXEC-RES-END", settle=3)
                m = re.search(r"EXEC-RES-START\r?\n(.*?)\r?\nEXEC-RES-END",
                              out, re.S)
                lines = [ln.strip() for ln in
                         (m.group(1).splitlines() if m else [])
                         if ln.strip()]
                resolved = lines[0] if lines else ""
                if resolved and "not found" not in resolved \
                        and not ANSI_RE.search(resolved):
                    log(f"{name}: resolved Exec: {resolved}")
                    # T13-D10 — attempt 0 rides the dock's ACTUAL launch
                    # line: dockApps prefixes every Tier B resolved Exec
                    # with the W25 electron guard. Launching the raw Exec
                    # here would test a path no user ever exercises (and
                    # in a VM the sandbox FATAL is exactly why the guard
                    # exists).
                    lc = f"aegis-electron-launch {resolved}"
                else:
                    log(f"{name}: Exec resolution empty or dirty — "
                        "using the bare head (all three debs install the "
                        "/usr/bin symlink)")
            except Exception as e:
                log(f"{name}: Exec resolution failed ({e}) — using the cmd")
        # dynamic lookup wins (guest-resolved order); the passed index is
        # only the serial-less / rebuild-failed fallback against the config
        # count
        idx = tile_index.get(cmd, click_idx)
        for attempt in range(2):
            launched = False
            try:
                # T13 W24 — attempt 0 launches the resolved Exec over the
                # bus; attempt 1 goes through the DOCK ITSELF (the
                # resolver + the W25 electron wrapper live in Util's
                # dockApps) — the click is the real user path and the
                # last resort before the honest red.
                if attempt == 1 and launch_cmd == "desktop":
                    launched = False
                elif serial is not None:
                    # (1) the shell's bus is the dbus-run-session private
                    # session, NOT the systemd --user bus at
                    # $XDG_RUNTIME_DIR/bus ("The name org.aegis.Shell was
                    # not provided by any .service files" on the v0.6.19
                    # run) — read the real address from the shell's own
                    # environment
                    out = serial.run(
                        "export XDG_RUNTIME_DIR=/run/user/$(id -u); "
                        "SHELLPID=$(pgrep -f '/usr/bin/aegis-shell' | head -1); "
                        "export DBUS_SESSION_BUS_ADDRESS=$(tr '\\0' '\\n' "
                        "< /proc/$SHELLPID/environ "
                        "| grep '^DBUS_SESSION_BUS_ADDRESS=' | head -1 "
                        "| cut -d= -f2-); "
                        "busctl --user call org.aegis.Shell /org/aegis/Shell "
                        f"org.aegis.Shell launch s \"{lc}\" 2>&1; "
                        f"echo LAUNCH-{name}-OK", settle=3)
                    launched = (f"LAUNCH-{name}-OK" in out
                                and "Call failed" not in out)
                    log(f"{name}: dbus launch -> " +
                        out.strip().replace("\n", " | ")[-160:])
                    # (2) nohup fallback — the launch ladder must not
                    # depend on one mechanism (the v0.6.28 run red on
                    # exactly this single point of failure)
                    if not launched:
                        out = serial.run(
                            "export XDG_RUNTIME_DIR=/run/user/$(id -u); "
                            "WAYLAND_DISPLAY=wayland-0 nohup "
                            f"{lc} >/tmp/aegis-launch-{name}.err 2>&1 & "
                            f"echo LAUNCH-{name}-OK", settle=3)
                        launched = f"LAUNCH-{name}-OK" in out
                        log(f"{name}: nohup launch -> " +
                            out.strip().replace("\n", " | ")[-120:])
            except Exception as e:
                log(f"{name}: serial launch failed ({e})")
            if launched:
                time.sleep(wait_s)
            elif idx is not None:
                # dock is always expanded — park the pointer high so the
                # tray is at rest, then click the tile (magnification
                # starts on arrival)
                q.mouse_abs(W // 2, int(H * NEUTRAL_Y), W, H)
                time.sleep(0.8)
                q.click(*tiles[idx], W, H)
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
            # T13-D10 — a red capture says only "no window". The liveness
            # line says WHY it stayed red: process alive (slow paint or a
            # hung renderer) vs process dead (crashed or never started).
            if serial is not None:
                try:
                    lv = serial.run(
                        f"pgrep -af '{cmd.split(' ')[0]}' | head -3; "
                        "echo LIVENESS-END", settle=2)
                    lv = lv.strip()
                    lv = lv[:lv.index("LIVENESS-END")].strip() \
                        if "LIVENESS-END" in lv else lv
                    log(f"{name}: liveness: "
                        + (lv.replace("\n", " | ")[-200:] if lv
                           else "no process alive"))
                except Exception as e:
                    log(f"{name}: liveness probe failed ({e})")
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
            # T11-D5 — rebuild the click map from what the guest really
            # shows: Tier B slots drop when their deb is missing (the
            # v0.6.28 ISO lost the Browser deb and the map ran half a
            # pitch off for every tile after the separator)
            real_cmds = resolved_tile_cmds(serial)
            if real_cmds:
                try:
                    tiles = dock_geometry(f"{OUT}/01-home.png",
                                          n_override=len(real_cmds))[0]
                    tile_index.clear()
                    for i, c in enumerate(real_cmds):
                        tile_index.setdefault(c, i)
                    log(f"click map rebuilt from the guest: "
                        f"{len(real_cmds)} tiles ({', '.join(real_cmds)})")
                except Exception as e:
                    log(f"click map rebuild failed ({e}) — keeping config map")
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

    # W20 evidence — what does the shell ACTUALLY see right now, BEFORE
    # any app window opens? The island auto-hide assert reads the pixels;
    # this reads the state: workspaceWindows + the window ids the KWin
    # script pushed. If the idle island hid, this names the surface the
    # script mis-counts (the v0.6.36 run: the island hid at home).
    # T13 D20 — the W20 evidence dump is now a FUNCTION: the W27 probe
    # calls it twice (after the minimize and after the dock re-click) and
    # the verdicts parse the payload instead of eyeballing a log line.
    def dump_window_state():
        """The live window payload the windowwatch script pushed
        (Util.windowListRaw). Returns the parsed dict, or None when the
        serial console or the payload is unavailable. The shell lives on
        the dbus-run-session bus, NOT the systemd user bus — the address
        comes from the shell's own environ (the earlier dump grepped
        aegis-session and matched the dbus-run-session PARENT, whose
        environ lacks the address)."""
        if serial is None:
            return None
        try:
            dbg = serial.run(
                "A=$(cat /proc/$(pgrep -f aegis-shell | head -1)/environ "
                "2>/dev/null | tr '\\0' '\\n' | grep "
                "^DBUS_SESSION_BUS_ADDRESS= | cut -d= -f2-); "
                "A=${A:-unix:path=$XDG_RUNTIME_DIR/bus}; "
                "echo ===AEGIS-WINDOWS===; "
                "busctl --address=$A call org.aegis.Shell /org/aegis/Shell "
                "org.aegis.Shell windowListRaw 2>&1; "
                "echo WINDBG-END", settle=8)
            m = re.search(r"===AEGIS-WINDOWS===\r?\n(.*?)\r?\nWINDBG-END",
                          dbg, re.S)
            if not m:
                return None
            payload = m.group(1).strip()
            # T13 D29 — busctl prints string replies as: s "{...}" (the
            # type letter, then the string QUOTED with inner quotes
            # escaped — verified on the v0.6.50 raw diag). The v0.6.52
            # parser only handled the bare-quote form, so every dump
            # died at json char 0 and all three W27 verdicts ran on
            # None. Unescape in the safe order (protect \\, unquote \",
            # restore \\) and log a raw excerpt when parsing still
            # fails so the next postmortem sees the reply verbatim.
            if payload.startswith("s "):
                payload = payload[2:].strip()
            if payload.startswith('"') and payload.endswith('"'):
                payload = (payload[1:-1].replace("\\\\", "\x00")
                           .replace('\\"', '"').replace("\x00", "\\"))
            if not payload:
                # windowListRaw empty = the script pushed nothing yet
                # (a fresh idle home before the first window event)
                return None
            try:
                return json.loads(payload)
            except (ValueError, TypeError) as e:
                log(f"window-state payload unparseable ({e}): "
                    f"raw[:140]={payload[:140]!r}")
                return None
        except Exception as e:
            log(f"window-state dump failed: {e}")
            return None

    st0 = dump_window_state()
    if st0 is not None:
        log("window-state dump: " + json.dumps(st0))

    # alt+F4 only after a window really opened: with no app window focused,
    # the close lands on the focused shell layer surface (the v0.6.5 boot
    # test lost dock -> island -> panel to exactly this cascade).
    # §1 — every open is RECORDED; a miss is a failed release (asserted below).
    opens = {}
    w27_minimized = False
    w27_restored = False
    w44_files_ok = False
    w44_terminal_ok = False
    w38_lights_ok = False
    w38_close_ok = False
    if open_app("02-files", "aegis-files", click_idx=0):       # Files
        opens["files"] = True
        # T13 D20 (W27) — the restore probe: minimize via the pinned
        # Meta+M, dump the payload (allIds keeps the class, ids loses it,
        # active empties), click the Files dock tile, dump again (active
        # == aegis-files). File-based, like every other verdict.
        try:
            q.key("meta_l", "m")
            time.sleep(2.5)
            st1 = dump_window_state()
            if st1 is not None:
                log("w27 after minimize: " + json.dumps(st1))
                w27_minimized = (
                    "aegis-files" in st1.get("allIds", [])
                    and "aegis-files" not in st1.get("ids", [])
                    and st1.get("active", "") != "aegis-files")
            q.mouse_abs(W // 2, int(H * NEUTRAL_Y), W, H)
            time.sleep(0.8)
            files_idx = tile_index.get("aegis-files", 0)
            q.click(*tiles[files_idx], W, H)
            time.sleep(6)
            # D28 diagnostic — did the shell actually write the request?
            # The v0.6.51 run showed active:"" after the click with no
            # visibility into the transport; this names the shell side
            # (the file write) vs the script side (the activation).
            if serial is not None:
                try:
                    req = serial.run(
                        "grep -A3 Script-aegis-windowwatch "
                        "~/.config/kwinrc 2>/dev/null; echo REQ-END",
                        settle=2)
                    log("w27 activate request: "
                        + req.strip().replace("\n", " | ")[:220])
                except Exception as e:
                    log(f"w27 request dump failed: {e}")
            st2 = dump_window_state()
            if st2 is not None:
                log("w27 after dock click: " + json.dumps(st2))
                w27_restored = (st2.get("active") == "aegis-files"
                                and st2.get("count", 0) >= 1)
            q.shot("02b-files-restored")
            d = diff_px(thumb(f"{OUT}/02b-files-restored.png"), home)
            log(f"02b-files-restored: diff-vs-home={d:.1f}")
        except Exception as e:
            log(f"w27 probe failed: {e}")
        # T15-D7 (W44) — the CSD resize proof: drag the Files window's
        # RIGHT edge +160 px and assert the top-hairline run grew >= 100 px
        # (the 8 px strip must be a real target, not a claim). The aim
        # corrects for the corner radius: the hairline ends ~7 px short of
        # the true edge (the first run missed the strip by 2 px).
        try:
            grew = drag_right_edge(q, f"{OUT}/02b-files-restored.png",
                                   "02c-files-resized", W, H)
            w44_files_ok = grew >= 100
        except Exception as e:
            log(f"w44 files resize probe failed: {e}")
        q.key("alt", "f4"); time.sleep(5)
    if open_app("03-terminal", "konsole", wait_s=18, click_idx=1):   # Terminal
        opens["terminal"] = True
        # the terminal STAYS OPEN for the D24 typing probe below
    # T11 — the dock grew to 11 tiles (M3 apps joined after the separator):
    # Files 0, Terminal 1, Browser 2, OS 3, CoreX 4, Music 5, Calculator 6,
    # Editor 7, Monitor 8, Store 9, Settings 10, Trash 11 — config order
    # (T14 added the Store slot; 12 tiles, tray width 728 px on 1280). The
    # click fallback uses the GUEST-resolved order via tile_index (a missing
    # Tier B deb drops the slot and shifts everything); the hardcoded
    # indices below are only the fallback for a full install.
    if open_app("04-settings", "aegis-settings", wait_s=30, click_idx=10):   # Settings
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

    # T13 D24 (W35) — the typing probe, right after the T7 header assert
    # while the terminal is still the focused window: real keystrokes over
    # the harness keyboard channel must produce a file — the whole chain
    # (QEMU input, Wayland/XKB layout, KWin routing, konsole focus, the
    # shell inside) under one verdict. File-based, per the review's
    # "keyboard keys not working" surface.
    xkb_ok = False
    if serial is not None:
        try:
            serial.run("rm -f /tmp/aegis-xkb-ok; echo XKB-CLEAN", settle=2)
            q.click(640, 400, W, H)
            time.sleep(1.2)
            # q.key(*codes) is a CHORD (all down, all up) — type one
            # character per call
            for ch in "touch /tmp/aegis-xkb-ok":
                code = {" ": "spc", "/": "slash", "-": "minus"}.get(ch, ch)
                q.key(code)
                time.sleep(0.04)
            q.key("ret")
            time.sleep(2.0)
            out = serial.run("test -f /tmp/aegis-xkb-ok && echo XKB-OK "
                             "|| echo XKB-MISS", settle=2)
            xkb_ok = "XKB-OK" in out
            log("xkb typing probe: "
                + ("PASS" if xkb_ok else "FAIL — " + out.strip()[-100:]))
        except Exception as e:
            log(f"xkb typing probe failed: {e}")

    # T15-D7 (W44.2) — the DECORATED window resize proof: the same edge
    # drag on Konsole (aurorae band). kwinrc carries BorderSize=None and
    # the shipped comment claims the resize-only borders still exist —
    # this probe is that claim's proof. A red here flips the ruling to
    # BorderSize=Tiny (review W44.2), not another silent carry-over.
    try:
        q.shot("03b-term-before")
        grew = drag_right_edge(q, f"{OUT}/03b-term-before.png",
                               "03b-term-resized", W, H)
        w44_terminal_ok = grew >= 100
    except Exception as e:
        log(f"w44 terminal resize probe failed: {e}")
    if opens.get("terminal"):
        q.key("alt", "f4")
        time.sleep(5)

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

    # T13 D21/D23 — the Displays and Drivers panes, launched straight from
    # the serial shell (the 04b-aegis-id mechanism). The settings window
    # geometry is deterministic (x190..1089, y95..733 measured on the
    # v0.6.50 captures for BOTH the dock launch and the serial launch) but
    # the pane-internal row positions are NOT modeled anymore — the
    # switch click is self-calibrating (knob scan below, T13 D29).
    presentation_on = False
    if serial is not None:
        try:
            serial.run("rm -f ~/.local/state/aegis-shell/aegis/presentation; "
                       "echo PRES-CLEAN", settle=2)
            serial.run("export XDG_RUNTIME_DIR=/run/user/$(id -u); "
                       "WAYLAND_DISPLAY=wayland-0 nohup aegis-settings 4 "
                       ">/tmp/aegis-settings4.err 2>&1 & echo PANE4-LAUNCHED",
                       settle=3)
            time.sleep(16)
            q.shot("04l-displays")
            d = diff_px(thumb(f"{OUT}/04l-displays.png"), home)
            log(f"04l-displays: diff-vs-home={d:.1f}")

            # T13 D29 — the v0.6.52 click used a modeled point (434, 207)
            # and missed by ~150 px (the real GlassSwitch indicator sits
            # at (433, 359) on the v0.6.52 capture — the pane body starts
            # below the AppWindow 44 px titlebar + 52 px toolbar strip,
            # which the model did not carry). The click is now
            # SELF-CALIBRATING: the GlassSwitch knob is a 20 px PURE
            # white blob (255, 255, 255 — the fg text tops out at 242);
            # the shared module-level knob_centers() scans the whole pane
            # (the first T15 run proved the old 402..458 column misses —
            # the labeled rows carry the switch AFTER the label, and the
            # W39.3 fillers moved every row up). Click cluster[0]: the
            # Presentation row is the displays pane's first switch row.
            cs = knob_centers(f"{OUT}/04l-displays.png")
            log(f"presentation knob clusters: {cs}")
            kc = cs[0] if cs else (433, 359)
            q.click(kc[0], kc[1], W, H)
            time.sleep(2.5)
            q.shot("04l2-displays-on")
            out = serial.run("grep presentation= "
                             "~/.local/state/aegis-shell/aegis/presentation "
                             "2>/dev/null; echo PRES-END", settle=2)
            presentation_on = "presentation=on" in out
            log("presentation state: "
                + ("ON (file verdict)" if presentation_on
                   else "MISSING — the toggle click did not land"))
            # restore off — re-scan (the knob moved to the track's right
            # end); cluster[0] again
            cs2 = knob_centers(f"{OUT}/04l2-displays-on.png")
            kc2 = cs2[0] if cs2 else (433, 359)
            q.click(kc2[0], kc2[1], W, H)
            time.sleep(1.5)
            q.key("alt", "f4")
            time.sleep(5)
        except Exception as e:
            log(f"displays pane capture failed: {e}")
        try:
            serial.run("export XDG_RUNTIME_DIR=/run/user/$(id -u); "
                       "WAYLAND_DISPLAY=wayland-0 nohup aegis-settings 3 "
                       ">/tmp/aegis-settings3.err 2>&1 & echo PANE3-LAUNCHED",
                       settle=3)
            time.sleep(16)
            q.shot("04m-drivers")
            d = diff_px(thumb(f"{OUT}/04m-drivers.png"), home)
            log(f"04m-drivers: diff-vs-home={d:.1f} (W33 real inventory)")
            q.key("alt", "f4")
            time.sleep(5)
        except Exception as e:
            log(f"drivers pane capture failed: {e}")

    # T15-D4 (W39) — the Settings toggles are REAL: the boot gate clicks
    # them and asserts the config/state file change (the W37 verdict
    # pattern). Rotate-wallpapers-daily -> tokens.conf; Focus-dim and the
    # effect rows -> the governor.conf override map (Governor.setEffect).
    w39_rotate_ok = False
    w39_dim_ok = False
    w39_effects_ok = False
    wired_ok = False
    browser_default_ok = False
    if serial is not None:
        try:
            def click_knob(png, idx):
                cs = knob_centers(png)
                log(f"w39 knobs: {cs}")
                if idx < len(cs):
                    q.click(cs[idx][0], cs[idx][1], W, H)
                    time.sleep(2.5)
                    return True
                return False

            # wallpaper pane (0): rotate daily first, focus-dim second
            serial.run("export XDG_RUNTIME_DIR=/run/user/$(id -u); "
                       "WAYLAND_DISPLAY=wayland-0 nohup aegis-settings 0 "
                       ">/tmp/aegis-settings0.err 2>&1 & echo PANE0-LAUNCHED",
                       settle=3)
            time.sleep(16)
            q.shot("04n-wallpaper")
            if click_knob(f"{OUT}/04n-wallpaper.png", 0):
                out = serial.run("grep -c '^wallpaperRotateDaily=true' "
                                 "~/.config/aegis/tokens.conf 2>/dev/null; "
                                 "echo ROT-END", settle=2)
                w39_rotate_ok = out.split("ROT-END")[0].strip() == "1"
                log("w39 rotate toggle: "
                    + ("tokens.conf verdict PASS" if w39_rotate_ok
                       else "FAIL — " + out.strip()[-80:]))
                q.shot("04n2-wallpaper-on")
                # restore off — the knob moved; re-scan
                click_knob(f"{OUT}/04n2-wallpaper-on.png", 0)
            if click_knob(f"{OUT}/04n-wallpaper.png", 1):
                out = serial.run("grep -c 'wallpaperDim=true' "
                                 "~/.config/aegis/governor.conf 2>/dev/null; "
                                 "echo DIM-END", settle=2)
                w39_dim_ok = out.split("DIM-END")[0].strip() == "1"
                log("w39 focus-dim toggle: "
                    + ("governor.conf verdict PASS" if w39_dim_ok
                       else "FAIL — " + out.strip()[-80:]))
                q.shot("04n3-wallpaper-dim")
                # the dim knob is cluster index 1 (rotate row sits above
                # it and its knob is back on the left after the restore)
                click_knob(f"{OUT}/04n3-wallpaper-dim.png", 1)
            q.key("alt", "f4"); time.sleep(5)

            # effects pane (2): blurLive first row. The knob may already
            # be ON (tier A runs blurLive) — clicking writes the override
            # of the OPPOSITE polarity, so the verdict is the override
            # KEY existing in governor.conf, not its value.
            serial.run("export XDG_RUNTIME_DIR=/run/user/$(id -u); "
                       "WAYLAND_DISPLAY=wayland-0 nohup aegis-settings 2 "
                       ">/tmp/aegis-settings2.err 2>&1 & echo PANE2-LAUNCHED",
                       settle=3)
            time.sleep(16)
            q.shot("04o-effects")
            if click_knob(f"{OUT}/04o-effects.png", 0):
                out = serial.run("grep -cE '^blurLive=(true|false)' "
                                 "~/.config/aegis/governor.conf 2>/dev/null; "
                                 "echo EFF-END", settle=2)
                w39_effects_ok = out.split("EFF-END")[0].strip() == "1"
                log("w39 effects toggle: "
                    + ("governor.conf override verdict PASS" if w39_effects_ok
                       else "FAIL — " + out.strip()[-80:]))
                q.shot("04o2-effects-toggled")
                click_knob(f"{OUT}/04o2-effects-toggled.png", 0)
            q.key("alt", "f4"); time.sleep(5)
        except Exception as e:
            log(f"w39 toggle probes failed: {e}")

        # T15-D6 (W43) — the runner is ethernet-only: the wired row's
        # substrate must really say Connected (the UI reads this state).
        # Two marker-bounded calls (run 3's single-chain parse lost the
        # table to the shell-integration prefixes); the NM table rides
        # the log verbatim so a missing NIC vs an unmanaged device vs a
        # hung connection is distinguishable.
        try:
            tbl = serial.run("echo NM-T-START; nmcli -t device status 2>&1 "
                             "| head -8; echo NM-T-END", settle=8)
            m = re.search(r"NM-T-START\r?\n(.*?)\r?\nNM-T-END", tbl, re.S)
            table = (m.group(1) if m else tbl).strip()
            log("w43 NM table: " + table.replace("\n", " | ")[:400])
            out = serial.run(
                "nmcli -t -f TYPE,STATE device status 2>/dev/null | "
                "grep -c '^ethernet:connected'; echo W-OK", settle=4)
            count = out.split("W-OK")[0].strip()
            wired_ok = count == "1"
            log("w43 wired state: "
                + ("ethernet:connected PASS" if wired_ok
                   else f"FAIL (count={count!r})"))
        except Exception as e:
            log(f"w43 wired probe failed: {e}")

        # T15-D2 (W42) — the default browser role: xdg-settings must name
        # the Aegis entry (the Drivers pane's Open CUPS and every web link
        # ride this role).
        try:
            out = serial.run("xdg-settings get default-web-browser 2>&1; "
                             "echo B-OK", settle=3)
            seg = out.split("B-OK")[0].strip().lower()
            browser_default_ok = "aegis" in seg
            log("w42 default browser: " + (seg if seg else "(empty)"))
        except Exception as e:
            log(f"w42 default-browser probe failed: {e}")

    # T11 — the four M3 apps, launched over the same DBus surface and
    # captured the same way as Files/Terminal/Settings. Each open_app call
    # carries its own diff-vs-home assert; a window that never paints
    # fails the release below through the opens dict.
    if open_app("04c-music", "aegis-music", wait_s=25, click_idx=5):
        opens["music"] = True
        q.key("alt", "f4"); time.sleep(5)
    if open_app("04d-calculator", "aegis-calculator", wait_s=25, click_idx=6):
        opens["calculator"] = True
        q.key("alt", "f4"); time.sleep(5)
    if open_app("04e-editor", "aegis-editor", wait_s=25, click_idx=7):
        opens["editor"] = True
        q.key("alt", "f4"); time.sleep(5)
    if open_app("04f-monitor", "aegis-monitor", wait_s=25, click_idx=8):
        opens["monitor"] = True
        q.key("alt", "f4"); time.sleep(5)

    # T13 W24 — the three TIER B debs must LAUNCH, not just install ("installs
    # but doesn't launch must go red in CI, not be discovered in a VM").
    # open_app's diff-vs-home check IS the W25 window-mapped proof (the
    # process existing says nothing — a crashed electron process is
    # exactly what this catches). The dock clicks ride the guest-resolved
    # map (browser 2, os 3, corex 4); the W25 wrapper guards the electron
    # launches, and the W24 launch logs land in
    # ~/.local/state/aegis/launch/ for the diag dump.
    if open_app("04g-browser", "aegis-browser-stable", wait_s=30,
                click_idx=2, launch_cmd="desktop"):
        opens["browser"] = True
        q.key("alt", "f4"); time.sleep(5)
    if open_app("04h-os", "os-private-chat", wait_s=30,
                click_idx=3, launch_cmd="desktop"):
        opens["os"] = True
        q.key("alt", "f4"); time.sleep(5)
    if open_app("04i-corex", "corex-terminal", wait_s=45,
                click_idx=4, launch_cmd="desktop"):
        opens["corex"] = True
        q.key("alt", "f4"); time.sleep(5)

    # T14 — the Store: the apt-backed app store opens with the curated
    # catalog rendered (the diff gate proves the window). T15-D3 (W38) —
    # the window rides the AppWindow anatomy now: the three traffic
    # lights must exist in its titlebar (the user's exact report: no
    # lights = cannot close) and the RED light must close the window —
    # "cannot close" is a red CI verdict, not a user report.
    if open_app("04k-store", "aegis-store", wait_s=25, click_idx=9):
        opens["store"] = True
        try:
            st = window_hairline(f"{OUT}/04k-store.png")
            if st:
                top, x0, run_len = st
                tl = traffic_lights_triple(f"{OUT}/04k-store.png", top, x0)
                w38_lights_ok = tl is not None
                log(f"w38 store lights: "
                    + (f"found at {tl}" if tl
                       else "MISSING — the anatomy regressed"))
                if tl:
                    red_x, red_y = tl[0]
                    q.click(red_x, red_y, W, H)
                    time.sleep(3)
                    q.shot("04k2-store-closed")
                    stc = dump_window_state()
                    closed = (stc is None
                              or "aegis-store" not in (stc.get("ids") or []))
                    d2 = diff_px(thumb(f"{OUT}/04k2-store-closed.png"), home)
                    w38_close_ok = closed and d2 < 6
                    log(f"w38 store close: payload-closed={closed} "
                        f"diff-vs-home={d2:.1f}")
            else:
                log("w38 store lights: no window hairline found")
        except Exception as e:
            log(f"w38 store probe failed: {e}")
        if not w38_close_ok:
            q.key("alt", "f4"); time.sleep(5)

    # T13 W26 — the Trash tile must open Files AT the trash view (it used
    # to open Home because aegis-files took no path argument). The dock
    # click launches aegis-files --path trash:///; the capture is the
    # evidence and the diff gate proves the window opened.
    trash_idx = tile_index.get("aegis-files --path trash:///", 11)
    q.mouse_abs(W // 2, int(H * NEUTRAL_Y), W, H)
    time.sleep(0.8)
    q.click(*tiles[trash_idx], W, H)
    time.sleep(8)
    q.shot("04j-trash")
    d = diff_px(thumb(f"{OUT}/04j-trash.png"), home)
    log(f"04j-trash: diff-vs-home={d:.1f} (Trash slot click, "
        f"tile index {trash_idx})")

    # T13 D24 (W35) — Meta+S toggles the control center through the same
    # aegis-shortcuts script; toggled OFF again (the CC has no Escape
    # path — the toggle IS the close), then the panel-click capture below
    # stays the pointer-path evidence.
    try:
        q.key("meta_l", "s")
        time.sleep(2.5)
        q.shot("05c-cc-shortcut")
        d = diff_px(thumb(f"{OUT}/05c-cc-shortcut.png"), home)
        log(f"05c-cc-shortcut: diff-vs-home={d:.1f} (Meta+S)")
        q.key("meta_l", "s")
        time.sleep(1.5)
    except Exception as e:
        log(f"cc shortcut capture failed: {e}")

    q.click(W - 19, 14, W, H)            # panel CC glyph (the cluster's
                                         # last item: spans W-28..W-10;
                                         # W-60 lands in the CLOCK's hit
                                         # area since T15-D10 — the first
                                         # run opened the calendar here)
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

    # T13 D26 (W37) — the dead-control verdict for the CC dark tile:
    # click the tile center (grid geometry: sheet 348 wide anchored
    # top-right margins 16, header 30, tiles 152x64 with 12 gaps — the
    # Dark Mode tile is row 2 col 2, center (1172, 234); cross-checked
    # against the measured DND knob x 1206-1222 from the v0.6.20
    # capture — and PROVEN live on the v0.6.52 capture: the sheet
    # re-rendered light and the tile went unchecked, so the CLICK is
    # good; the v0.6.52 failure was the kdeglobals WRITE, which
    # setDarkMode now performs as a deterministic QSaveFile rewrite
    # (util.cpp T13 D29) and mirrors into a theme state file. The
    # verdict is the state file (the pattern every other gate uses)
    # PLUS the kdeglobals token polled up to three times over serial.
    dark_flipped = False
    theme_light = False
    if serial is not None:
        try:
            serial.run("rm -f ~/.local/state/aegis-shell/aegis/theme; "
                       "echo THEME-CLEAN", settle=2)
            before = serial.run("grep ColorScheme "
                                "~/.config/kdeglobals 2>/dev/null | head -1; "
                                "echo TOKEN-END", settle=2)
            q.click(1172, 234, W, H)
            time.sleep(2.5)
            q.shot("05c-dark-toggled")
            state_out = serial.run(
                "cat ~/.local/state/aegis-shell/aegis/theme 2>/dev/null; "
                "echo THEME-END", settle=2)
            theme_light = "light" in state_out

            def _tok(s):
                m = re.search(r"ColorScheme=(Aegis\w+)", s)
                return m.group(1) if m else ""

            after = ""
            for _ in range(3):
                after = serial.run("grep ColorScheme "
                                   "~/.config/kdeglobals 2>/dev/null | head -1; "
                                   "echo TOKEN-END", settle=2)
                if _tok(after) != _tok(before) and _tok(after):
                    break
                time.sleep(1.5)
            tb, ta = _tok(before), _tok(after)
            dark_flipped = bool(tb) and bool(ta) and tb != ta
            log(f"dark tile verdict: {tb or 'none'} -> {ta or 'none'} "
                + f"(state file: {'light' if theme_light else 'absent'}) "
                + ("PASS" if dark_flipped and theme_light
                   else "PASS on state file only" if theme_light
                   else "FAIL"))
            q.click(1172, 234, W, H)
            time.sleep(1.5)
        except Exception as e:
            log(f"dark tile probe failed: {e}")

    # T15-D10 (W47) — the calendar popover: click the panel clock, the
    # glass sheet must appear (diff-vs-home), clicking the clock again
    # closes it. The CC sheet is toggled off first (one sheet at a time).
    calendar_ok = False
    drm_clean = None       # None = check never ran (serial lost)
    try:
        q.key("meta_l", "s")            # CC off (toggle — the CC has no
        time.sleep(1.5)                 # Escape path)
        # the DND block reassigned `home` to the CC-open frame — take a
        # clean desktop reference here
        q.shot("05e-home-ref")
        cal_ref = thumb(f"{OUT}/05e-home-ref.png")
        # region-scoped verdict: the 300x340 sheet is ~10% of the frame —
        # a whole-frame thumb diff dilutes it under the threshold (the
        # second run measured 1.5 on a WORKING popover). Diff the sheet
        # region only (anchored right, margin 84: x W-384..W-84, y 40..380).
        def cal_region(png):
            im = Image.open(png).convert("RGB")
            Wd, Hd = im.size
            box = im.crop((Wd - 384, 40, Wd - 84, 380))
            px = list(box.getdata())
            n = len(px)
            return tuple(sum(c[i] for c in px) / n for i in range(3))

        q.click(W - 108, 14, W, H)      # the panel clock
        time.sleep(2.5)
        q.shot("05d-calendar")
        cal_open_delta = max(abs(a - b) for a, b in
                             zip(cal_region(f"{OUT}/05d-calendar.png"),
                                 cal_region(f"{OUT}/05e-home-ref.png")))
        log(f"05d-calendar: sheet-region delta={cal_open_delta:.1f}")
        calendar_ok = cal_open_delta > 2.0
        q.click(W - 108, 14, W, H)      # toggle closed
        time.sleep(1.5)
        q.shot("05d2-calendar-closed")
        cal_closed_delta = max(abs(a - b) for a, b in
                               zip(cal_region(f"{OUT}/05d2-calendar-closed.png"),
                                   cal_region(f"{OUT}/05e-home-ref.png")))
        log(f"05d2-calendar-closed: sheet-region delta={cal_closed_delta:.1f}")
        calendar_ok = calendar_ok and cal_closed_delta < 2.0
    except Exception as e:
        log(f"calendar probe failed: {e}")

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
            "journalctl -b --no-pager 2>/dev/null | grep -ai plymouth | head -12; echo GPU-PROBE", settle=6)
        log("gpu/plymouth probe: " + out.strip().replace("\n", " | ")[700:])
        # T15-D1 (W41) — the journal must carry NO plymouthd DRM-master /
        # headless signature on the release-blocking variant either (the
        # review §0 rule: assert on BOTH variants).
        try:
            out2 = serial.run(
                "journalctl -b --no-pager 2>/dev/null | grep -ai plymouth "
                "| grep -aicE 'could not take drm master|headless|no drm'; "
                "echo DRM-CNT", settle=6)
            seg = out2.split("DRM-CNT")[0].strip()
            drm_clean = seg == "0" or seg == ""
            log("virtio journal DRM-master check: "
                + ("clean" if drm_clean else f"FAILURE LINES ({seg})"))
        except Exception as e:
            drm_clean = None
            log(f"virtio DRM-master check failed: {e}")
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
    # T13 W24 — the three Tier B debs joined the gate; T14 — the Store.
    failures = []
    for app in ("files", "terminal", "settings", "music", "calculator",
                "editor", "monitor", "store", "browser", "os", "corex"):
        if not opens.get(app):
            failures.append(f"{app} window never opened (screen unchanged)")
    for name, text in probes.items():
        if probe_failed(text):
            failures.append(f"QML probe ({name}) reported a load error")

    # T12 D7 — the W23 test gaps: config drift, greeter, kind tints,
    # monitor cards, magnification clearance. "A probe that cannot fail
    # is not a probe" — the v0.6.20 lesson.
    for f in config_assert("serial-diag.txt"):
        failures.append("config drift: " + f)
    for f in sddm_theme_assert("serial-diag.txt"):
        failures.append(f)
    # greeter_assert stays UNWIRED — the live ISO autologins and the
    # greeter never renders between splash and session (see its
    # docstring and the T12 D7 notes in docs/TASKS.md).
    try:
        tint = tint_assert(f"{OUT}/02-files.png")
        log(f"tint assert: {tint} px at #FA2D48 in 02-files")
        if tint < 300:
            failures.append(f"Files PDF tint missing ({tint} px at "
                            "#FA2D48, need >= 300 — broken build measures "
                            "237 without the glyph, fixed 395) — W16 "
                            "regressed")
    except Exception as e:
        failures.append(f"tint assert crashed: {e}")
    try:
        mon = monitor_card_assert(f"{OUT}/04f-monitor.png")
        log(f"monitor assert: {mon} accent px in 04f-monitor")
        if mon < 25:
            failures.append(f"Monitor cards empty ({mon} accent px, "
                            "need >= 25) — W17 regressed")
    except Exception as e:
        failures.append(f"monitor assert crashed: {e}")
    try:
        home_i, files_i = island_autohide_assert(f"{OUT}/01-home.png",
                                                 f"{OUT}/02-files.png")
        log(f"island assert: home {home_i} px (visible), "
            f"files {files_i} px (should be hidden)")
        if home_i < 15:
            failures.append(f"island missing on the idle home "
                            f"({home_i} px) — the idle capsule itself broke")
        if files_i > 8:
            failures.append(
                f"island did not hide with a window open ({files_i} px "
                "in 02-files) — the W20 chain broke (script load, DBus "
                "path, Util slot or the QML binding)")
    except Exception as e:
        failures.append(f"island assert crashed: {e}")
    try:
        rest, mag = magnify_clearance_assert(f"{OUT}/01-home.png",
                                             f"{OUT}/01b-dock-magnify.png")
        if rest is None or mag is None:
            log("magnify assert: clearance not measurable — skipped")
        else:
            log(f"magnify assert: rest clearance {rest} px, "
                f"magnified {mag} px")
            if mag < rest + 8:
                failures.append(
                    f"dock end-tile clearance did not grow with the field "
                    f"(rest {rest}, mag {mag}) — V1 regressed")
    except Exception as e:
        failures.append(f"magnify assert crashed: {e}")

    # T13 D20/D24/D26 — the W27 restore, the XKB typing probe, the
    # presentation toggle and the dark tile each carry a file-based or
    # state-based verdict; a miss is a failed release like every other
    # assert (a probe that cannot fail is not a probe).
    if not w27_minimized:
        failures.append("W27: after Meta+M the Files window still shows in "
                        "the tracking payload (ids must lose it, allIds "
                        "must keep it, active must empty) — the pinned "
                        "Window Minimize or the payload contract broke")
    if not w27_restored:
        failures.append("W27: the dock Files click did not bring the "
                        "minimized window back active — activateOrLaunch "
                        "broke (kwinrc request transport or the script "
                        "poll)")
    # T15 verdicts — every W38-W47 fix rides a red-able probe (W23 rule)
    if not w38_lights_ok:
        failures.append("W38: the Store titlebar carries no traffic-light "
                        "triple — the AppWindow anatomy regressed (the "
                        "cannot-close report is back)")
    if not w38_close_ok:
        failures.append("W38: the Store red light click did not close the "
                        "window (payload or pixels unchanged)")
    if not w44_files_ok:
        failures.append("W44: the Files CSD right-edge drag grew the window "
                        "by < 100 px — the 8 px resize strips are not real "
                        "targets")
    if not w44_terminal_ok:
        failures.append("W44: the Konsole right-edge drag grew the window "
                        "by < 100 px — the decorated (aurorae) resize path "
                        "is broken; flip kwinrc to BorderSize=Tiny per the "
                        "review ruling")
    if not w39_rotate_ok:
        failures.append("W39: the rotate-wallpapers toggle click wrote no "
                        "tokens.conf key — the switch is dead or the knob "
                        "scan missed")
    if not w39_dim_ok:
        failures.append("W39: the focus-dim toggle click wrote no "
                        "governor.conf wallpaperDim key — the override "
                        "chain is broken")
    if not w39_effects_ok:
        failures.append("W39: the effects-row toggle click wrote no "
                        "governor.conf blurLive key — Governor.setEffect "
                        "is not reachable from Settings")
    if not wired_ok:
        failures.append("W43: the runner has no ethernet:connected state — "
                        "the wired-first UI has nothing to represent")
    if not browser_default_ok:
        failures.append("W42: xdg-settings get default-web-browser does "
                        "not name an Aegis entry — the build-time role "
                        "stamp did not land")
    if not calendar_ok:
        failures.append("W47: the clock click did not open the calendar "
                        "popover (or the second click did not close it)")
    if drm_clean is False:
        failures.append("W41: the virtio journal carries plymouthd "
                        "DRM-master/headless lines — the renderer is "
                        "failing on the release-blocking path too")
    if not xkb_ok:
        failures.append("W35: typed keystrokes never produced "
                        "/tmp/aegis-xkb-ok — the keyboard chain (harness "
                        "channel, XKB layout, focus) is broken")
    if not presentation_on:
        failures.append("W30.1: the presentation toggle click did not "
                        "write the state file — the toggle is dead or the "
                        "click point drifted")
    if not dark_flipped or not theme_light:
        failures.append("W37: the dark tile verdict failed — "
                        + ("state file missing (the shell never applied "
                           "the toggle)" if not theme_light else
                           "kdeglobals ColorScheme did not flip (the "
                           "config write is still broken)")
                        + " — see the dark tile verdict line")

    if failures:
        for f in failures:
            log("ASSERT FAILED: " + f)
        log("capture complete (FAILED release)")
        q._cmd("quit")
        sys.exit(1)

    log("capture complete")
    q._cmd("quit")

if __name__ == "__main__":
    if "--vmware-boot-check" in sys.argv:
        vmware_boot_check()
    else:
        main()
