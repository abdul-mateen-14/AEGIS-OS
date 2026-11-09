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

def start_qemu(accel):
    cmd = ["qemu-system-x86_64", *accel, "-m", "4096", "-smp", "4",
           "-device", "virtio-vga", "-display", "none",
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
    """Dock tile centers.

    v0.4.0 dock: an always-expanded LIGHT glass tray (white 13% tint) with
    64 px squircle icons — brightness-gap clustering cannot separate icons
    from a light tray, so we detect the tray extent (a long run of columns
    brighter than the wallpaper) and divide it evenly across the known tile
    count from shell/packaging/config.json. The tray must be at REST for
    this to hold — callers park the pointer away from the dock first.
    """
    im = Image.open(png).convert("RGB")
    W, H = im.size
    band_top, band_bot = max(0, H - 100), H - 6
    px = im.load()
    means = []
    for x in range(W):
        vals = [sum(px[x, y]) / 3 for y in range(band_top, band_bot, 2)]
        means.append(sum(vals) / len(vals))

    def tray_run(thresh):
        """longest run of columns above thresh, bridging gaps <= 3 px."""
        best = (0, 0)
        start = None; gap = 0
        for x, m in enumerate(means):
            if m > thresh:
                if start is None:
                    start = x
                gap = 0
                if x - start > best[1] - best[0]:
                    best = (start, x)
            elif start is not None:
                gap += 1
                if gap > 3:
                    if x - gap - start > best[1] - best[0]:
                        best = (start, x - gap)
                    start = None; gap = 0
        if start is not None and W - start > best[1] - best[0]:
            best = (start, W)
        return best

    n = expected_tiles()
    # tray glass raises columns ~15-25 above the wallpaper band
    x0, x1 = tray_run(48)
    if x1 - x0 < 55 * n - 80:
        # fallback: legacy bright-cluster scan (dark tray / sliver frames)
        flags = []
        for x in range(W):
            vals = [sum(px[x, y]) / 3 for y in range(band_top, band_bot, 2)]
            bright = sum(1 for v in vals if v > 130)
            flags.append(means[x] > 44 or bright >= 2)
        clusters = []; start = None
        for x, f in enumerate(flags):
            if f and start is None:
                start = x
            elif not f and start is not None:
                if x - start >= 8:
                    clusters.append((start, x))
                start = None
        if start is not None and W - start >= 8:
            clusters.append((start, W))
        return [((s + e) // 2, (band_top + band_bot) // 2) for s, e in clusters
                if abs((s + e) // 2 - W // 2) < 620]

    pad = Tokens_pad = 12
    pitch = (x1 - x0 - 2 * pad) / n
    y = (band_top + band_bot) // 2
    return [(round(x0 + pad + pitch * (i + 0.5)), y) for i in range(n)]

def wait_desktop(q, proc, timeout=DESKTOP_TIMEOUT):
    """Desktop readiness = the dock tray is visible (>= 6 icon tiles)."""
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
        # The dock rests expanded and the pointer is parked high — no summon
        # needed. If tiles are missing but the wallpaper is clearly up,
        # probe once from the neutral parking spot.
        if tiles < 6 and n >= 2 and sat > 25 and val > 25:
            try:
                W, H = Image.open(png).size
                q.mouse_abs(W // 2, int(H * NEUTRAL_Y), W, H)
                time.sleep(2.5)
                q.shot(f"boot-{n:02d}-hover")
                png = f"{OUT}/boot-{n:02d}-hover.png"
                tiles = len(find_tiles(png))
                sat, val = metrics(png)
            except Exception as e:
                log(f"probe failed: {e}")
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
    W, H = Image.open(f"{OUT}/boot-{n:02d}.png").size
    q.mouse_abs(W // 2, int(H * NEUTRAL_Y), W, H)   # park pointer away from dock
    time.sleep(2.5)
    q.shot("01-home")

    # macOS dock magnification + tooltip: hover a center tile, let the
    # springs settle, then capture the wave and the black label bubble.
    home = thumb(f"{OUT}/01-home.png")
    tiles = find_tiles(f"{OUT}/01-home.png")
    log(f"resolution {W}x{H}; dock tiles: {len(tiles)} at {tiles[:4]}...")
    if len(tiles) < 6:
        log("ERROR: fewer than 6 dock tiles found")
        q.shot("zz-dock")
        sys.exit(2)
    q.mouse_abs(*tiles[len(tiles) // 2], W, H)
    time.sleep(1.4)
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
            log(f"{name}: diff-vs-home={d:.1f}")
            if d > 6:
                return True
            log(f"{name} attempt {attempt + 1}: screen looks unchanged, retrying")
            q.mouse_abs(W // 2, H // 2, W, H)
            time.sleep(2)
        return False

    open_app(0, "02-files")           # Files
    q.key("alt", "f4"); time.sleep(5)
    open_app(1, "03-terminal", wait_s=18)   # Terminal
    q.key("alt", "f4"); time.sleep(5)
    open_app(11, "04-settings", wait_s=30)  # Settings (12 tiles before it,
    q.key("alt", "f4"); time.sleep(5)       # separator yields no cluster)

    q.click(W - 60, 14, W, H)            # panel right cluster -> Control Center
    time.sleep(3)
    q.shot("05-control-center")

    log("capture complete")
    q._cmd("quit")

if __name__ == "__main__":
    main()
