#!/usr/bin/env python3
"""Boot-capture: boots an Aegis OS ISO in QEMU, drives the shell over QMP and
captures screenshots: silent boot timeline, home desktop, Files, Terminal,
Settings and Control Center. Designed for CI runners; also runs locally.

If the desktop does not come up, the script logs into the guest over the
serial console (interactive socket chardev), dumps diagnostics, and attempts
live recovery (start SDDM / isolate graphical.target) before giving up.

Usage: python3 boot-capture.py <iso> [screenshot-dir]
"""
import json, os, shutil, socket, subprocess, sys, time

ISO = sys.argv[1] if len(sys.argv) > 1 else "iso/AegisOS.iso"
OUT = sys.argv[2] if len(sys.argv) > 2 else "screenshots"
SOCK = "/tmp/aegis-qmp.sock"
SERIAL_SOCK = "/tmp/aegis-serial.sock"
ABS_MAX = 0x7FFF          # QMP abs input range for absolute pointer devices
DESKTOP_TIMEOUT = 1200    # KVM boots in ~3 min; TCG needs more

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
               "systemd.show_status=yes")

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

def start_qemu(accel):
    cmd = ["qemu-system-x86_64", *accel, "-m", "4096", "-smp", "4",
           "-vga", "std", "-display", "none",
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
    chains = (["-enable-kvm", "-cpu", "host"],
              ["-accel", "tcg,thread=multi", "-cpu", "max"])
    for accel in chains:
        log(f"trying accelerator: {accel[0]}")
        for p in (SOCK, SERIAL_SOCK):
            if os.path.exists(p):
                os.remove(p)
        proc = start_qemu(accel)
        if proc:
            log(f"accelerator in use: {accel[0]}")
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

    def login(self, user="aegis", passwords=("", "aegis", "live", "root")):
        for _ in range(3):
            self.send("\n"); self._drain(2)
            if b"login:" in self.buf:
                break
        if b"login:" not in self.buf:
            return False
        self.send(user + "\n"); self._drain(2.5)
        for pw in passwords:
            if b"Password" not in self.buf:
                break
            self.send(pw + "\n"); self._drain(3)
        self.send("echo SHELL-OK $(id -un)\n"); self._drain(3)
        return b"SHELL-OK" in self.buf

    def run(self, cmd, settle=3.0):
        self.send(cmd + "\n"); self._drain(settle)
        out = self.buf.decode(errors="replace")
        # keep only the response after the echoed command
        idx = out.rfind(cmd)
        return out[idx + len(cmd):] if idx >= 0 else out

def serial_diagnose(serial):
    diag_cmds = [
        "echo ===TARGET===; systemctl get-default",
        "echo ===FAILED===; systemctl --failed --no-pager | head -15",
        "echo ===DM===; systemctl is-active display-manager sddm; systemctl status display-manager --no-pager 2>&1 | head -12",
        "echo ===GRAPHICAL===; systemctl status graphical.target --no-pager 2>&1 | head -10",
        "echo ===JOURNAL-ERR===; journalctl -b -p 3 --no-pager 2>&1 | tail -40",
        "echo ===SESS===; loginctl list-sessions --no-pager 2>&1; ls /usr/share/wayland-sessions/ 2>&1",
        "echo ===WALLPAPER===; ls -la /usr/share/wallpapers/aegis/ 2>&1; ls /usr/share/sddm/themes/ 2>&1",
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

def serial_recover(serial, q, W=1280, H=800):
    log("attempting live recovery over serial")
    out = serial.run("sudo -n systemctl start display-manager 2>&1 || sudo -n systemctl start sddm 2>&1 || echo RECOVERY-SUDO-FAILED", settle=6)
    log("recovery: " + out.strip().replace("\n", " | ")[:300])
    if "RECOVERY-SUDO-FAILED" in out:
        return False
    # give the greeter/shell up to 5 minutes to appear
    for i in range(15):
        time.sleep(20)
        try:
            q.shot("recover")
            tiles = len(find_tiles(f"{OUT}/recover.png"))
            sat, val = metrics(f"{OUT}/recover.png")
            log(f"recover-{i}: sat={sat:.1f} val={val:.1f} tiles={tiles}")
            if tiles >= 6:
                return True
        except Exception as e:
            log(f"recovery probe failed: {e}")
    return False

# ---------------- choreography ----------------
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

def wait_desktop(q, proc, timeout=DESKTOP_TIMEOUT):
    """Desktop readiness = the dock is visible (>= 6 icon tiles)."""
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
        tiles = 0
        try:
            tiles = len(find_tiles(png))
        except Exception:
            pass
        log(f"boot-{n:02d}: sat={sat:.1f} val={val:.1f} tiles={tiles} t={time.time() - t0:.0f}s")
        if tiles >= 6:
            return n
        n += 1; time.sleep(20)
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
    q.shot("01-home")

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
    q._cmd("quit")

if __name__ == "__main__":
    main()
