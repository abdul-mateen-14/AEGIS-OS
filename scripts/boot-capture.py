#!/usr/bin/env python3
"""Boot-capture: boots an Aegis OS ISO in QEMU, drives the shell over QMP and
captures screenshots: silent boot timeline, home desktop, Files, Terminal,
Settings and Control Center. Designed for CI runners; also runs locally.

Usage: python3 boot-capture.py <iso> [screenshot-dir]
"""
import json, os, shutil, socket, subprocess, sys, time

ISO = sys.argv[1] if len(sys.argv) > 1 else "iso/AegisOS.iso"
OUT = sys.argv[2] if len(sys.argv) > 2 else "screenshots"
SOCK = "/tmp/aegis-qmp.sock"
ABS_MAX = 0x7FFF          # QMP abs input range for absolute pointer devices
DESKTOP_TIMEOUT = 1500    # seconds to wait for the desktop (TCG fallback needs it)

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
def start_qemu():
    accel = (["-enable-kvm", "-cpu", "host"] if os.path.exists("/dev/kvm")
             else ["-accel", "tcg,thread=multi", "-cpu", "max"])
    log(f"accelerator: {accel[0]}")
    cmd = ["qemu-system-x86_64", *accel, "-m", "3072", "-smp", "2",
           "-vga", "std", "-display", "none",
           "-device", "qemu-xhci", "-device", "usb-tablet",
           "-nic", "none", "-cdrom", ISO, "-boot", "d", "-no-reboot",
           "-qmp", f"unix:{SOCK},server,nowait",
           "-serial", "file:/tmp/aegis-serial.log"]
    log("qemu: " + " ".join(cmd))
    return subprocess.Popen(cmd, stdout=open("/tmp/aegis-qemu.log", "w"),
                            stderr=subprocess.STDOUT)

# ---------------- choreography ----------------
def wait_desktop(q, timeout=DESKTOP_TIMEOUT):
    n = 0; t0 = time.time()
    while time.time() - t0 < timeout:
        try:
            q.shot(f"boot-{n:02d}")
        except Exception as e:
            log(f"shot failed: {e}"); time.sleep(10); continue
        sat, val = metrics(f"{OUT}/boot-{n:02d}.png")
        log(f"boot-{n:02d}: sat={sat:.1f} val={val:.1f} t={time.time() - t0:.0f}s")
        if sat > 25 and val > 30:
            if n and metrics(f"{OUT}/boot-{n-1:02d}.png")[0] > 25:
                return n
        n += 1; time.sleep(15)
    return -1

def find_tiles(png):
    """Dock tile centers: bright icon clusters in the bottom strip."""
    im = Image.open(png).convert("RGB"); W, H = im.size
    top = max(0, H - 180); px = im.load()
    cols = []
    for x in range(W):
        cols.append(sum(1 for y in range(top, H, 2) if sum(px[x, y]) / 3 > 170))
    clusters = []; start = None
    for x, c in enumerate(cols):
        if c >= 4 and start is None:
            start = x
        elif c < 4 and start is not None:
            if x - start >= 20:
                clusters.append((start, x))
            start = None
    if start is not None and W - start >= 20:
        clusters.append((start, W))
    tiles = []
    for s, e in clusters:
        ys = [y for x in range(s, e) for y in range(top, H, 2)
              if sum(px[x, y]) / 3 > 170]
        if ys:
            tiles.append(((s + e) // 2, sum(ys) // len(ys)))
    return tiles

def main():
    os.makedirs(OUT, exist_ok=True)
    if os.path.exists(SOCK):
        os.remove(SOCK)
    proc = start_qemu()
    q = QMP(SOCK)
    log("QMP connected")
    n = wait_desktop(q)
    if n < 0:
        log("DESKTOP NEVER APPEARED")
        q.shot("zz-final")
        shutil.copy("/tmp/aegis-serial.log", "serial.log")
        sys.exit(1)
    log(f"desktop up at boot-{n:02d}")
    time.sleep(10)                       # settle desktop animations
    q.shot("01-home")
    shutil.copy("/tmp/aegis-serial.log", "serial.log")

    home = thumb(f"{OUT}/01-home.png")
    tiles = find_tiles(f"{OUT}/01-home.png")
    W, H = Image.open(f"{OUT}/01-home.png").size
    log(f"resolution {W}x{H}; dock tiles: {tiles}")
    if len(tiles) < 6:
        log("ERROR: fewer than 6 dock tiles found")
        q.shot("zz-dock")
        sys.exit(2)

    def open_app(idx, name, wait_s=25):
        for attempt in range(2):
            q.click(*tiles[idx], W, H)
            time.sleep(wait_s)
            q.shot(name)
            d = diff_px(thumb(f"{OUT}/{name}.png"), home)
            log(f"{name}: diff-vs-home={d:.1f}")
            if d > 6:
                return True
            log(f"{name} attempt {attempt + 1}: screen looks unchanged, retrying")
            q.mouse_abs(W // 2, H // 2, W, H)
            time.sleep(2)
        return False

    open_app(0, "02-files")
    q.key("alt", "f4"); time.sleep(5)
    open_app(1, "03-terminal", wait_s=18)
    q.key("alt", "f4"); time.sleep(5)
    open_app(5, "04-settings", wait_s=30)
    q.key("alt", "f4"); time.sleep(5)

    q.click(W - 60, 14, W, H)            # panel right cluster -> Control Center
    time.sleep(3)
    q.shot("05-control-center")

    log("capture complete")
    shutil.copy("/tmp/aegis-serial.log", "serial.log")
    q._cmd("quit")

if __name__ == "__main__":
    main()
