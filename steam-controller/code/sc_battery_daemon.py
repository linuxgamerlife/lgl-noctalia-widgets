#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 jahrekza
# Copyright (C) 2026 Jarek

"""
Steam Controller 2 battery daemon for the Noctalia plugin.

Reads raw HID reports from /dev/hidraw*, takes the battery percentage (byte[2])
and charging flag (byte[1]: 1 = on battery, 2 = charging) from every 0x43
report, and takes live buttons, sticks, triggers and touchpads from the Triton
0x42/0x45/0x47 state reports. Writes / prints a JSON state object.

Modes:
  (default)   keep the state file fresh
  --stream    also print one compact JSON object per line (used by battery.luau)
  --buzz      rumble the controller (output report 0x80) and exit

Only the Python 3 standard library is needed.
"""
import fcntl
import json
import os
import select
import signal
import struct
import subprocess
import sys
import time
from collections import deque
from datetime import datetime

SC_VID = 0x28DE
INTERNAL_PUCK_PID = 0x1305                 # receiver built into the Steam Machine
RECEIVER_PIDS = (0x1304, INTERNAL_PUCK_PID)  # standalone puck, Steam Machine
SC_PIDS = RECEIVER_PIDS + (0x1302, 0x1303)   # + controller on USB-C, Bluetooth LE
HIDIOCGRAWINFO = 0x80084803
HIDIOCSFEATURE_64 = (3 << 30) | (64 << 16) | (ord("H") << 8) | 0x06
HIDIOCGFEATURE_65 = (3 << 30) | (65 << 16) | (ord("H") << 8) | 0x07

SIGNAL_WINDOW = 6       # 0x7b readings averaged for the signal strength (~2-3 s)
SIGNAL_STALE = 10       # s without a reading -> no signal value
DOCK_POLL = 3           # s between "is the pad on the dock?" queries
SILENCE_DISCONNECT = 2  # s without reports -> pad is off
WRITE_INTERVAL = 5      # s between state heartbeats
INPUT_POLL_HZ = 30      # live-visualisation update rate
INPUT_POLL_INTERVAL = 1.0 / INPUT_POLL_HZ
INPUT_STICK_DEADZONE = 1200
INPUT_TRIGGER_DEADZONE = 400
RUNTIME_DIR = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
try:
    os.makedirs(RUNTIME_DIR, exist_ok=True)
except OSError:
    RUNTIME_DIR = "/tmp"
STATE_FILE = os.path.join(RUNTIME_DIR, "noctalia-sc-battery.json")
LOCK_FILE = os.path.join(RUNTIME_DIR, "noctalia-sc-battery.lock")
DAEMON_VERSION = "2.1.0"

# Triton (Steam Controller 2) input report IDs and button bits, from SDL's
# SDL_hidapi_steam_triton.c / controller_structs.h.
TRITON_STATE_REPORTS = (0x42, 0x45, 0x47)
TRITON_A = 1 << 0
TRITON_B = 1 << 1
TRITON_X = 1 << 2
TRITON_Y = 1 << 3
TRITON_QAM = 1 << 4
TRITON_R3 = 1 << 5
TRITON_VIEW = 1 << 6
TRITON_R4 = 1 << 7
TRITON_R5 = 1 << 8
TRITON_R = 1 << 9
TRITON_DPAD_DOWN = 1 << 10
TRITON_DPAD_RIGHT = 1 << 11
TRITON_DPAD_LEFT = 1 << 12
TRITON_DPAD_UP = 1 << 13
TRITON_MENU = 1 << 14
TRITON_L3 = 1 << 15
TRITON_STEAM = 1 << 16
TRITON_L4 = 1 << 17
TRITON_L5 = 1 << 18
TRITON_L = 1 << 19
TRITON_RIGHT_JOYSTICK_TOUCH = 1 << 20
TRITON_RIGHT_TOUCHPAD_TOUCH = 1 << 21
TRITON_RIGHT_TOUCHPAD_CLICK = 1 << 22
TRITON_RIGHT_TRIGGER_CLICK = 1 << 23
TRITON_LEFT_JOYSTICK_TOUCH = 1 << 24
TRITON_LEFT_TOUCHPAD_TOUCH = 1 << 25
TRITON_LEFT_TOUCHPAD_CLICK = 1 << 26
TRITON_LEFT_TRIGGER_CLICK = 1 << 27
TRITON_RIGHT_GRIP_TOUCH = 1 << 28
TRITON_LEFT_GRIP_TOUCH = 1 << 29

def single_instance():
    """Take a per-user lock; exit quietly when another daemon is already up."""
    fd = os.open(LOCK_FILE, os.O_RDWR | os.O_CREAT, 0o600)
    deadline = time.time() + 2.0
    while True:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            break
        except OSError:
            # A restart can overlap the previous process for a moment.
            if time.time() >= deadline:
                os.close(fd)
                sys.exit(0)
            time.sleep(0.05)
    os.ftruncate(fd, 0)
    os.write(fd, str(os.getpid()).encode())
    return fd

def release_lock(fd):
    try:
        os.ftruncate(fd, 0)
    except OSError:
        pass
    os.close(fd)

def hid_info(dev):
    """(connection, bluetooth MAC or "") from the hidraw node's sysfs uevent."""
    name, bus, pid, uniq = "", "", 0, ""
    try:
        with open(f"/sys/class/hidraw/{os.path.basename(dev)}/device/uevent") as f:
            for line in f:
                k, _, v = line.strip().partition("=")
                if k == "HID_NAME":
                    name = v
                elif k == "HID_ID":
                    parts = v.split(":")
                    bus = parts[0]
                    pid = int(parts[2], 16) if len(parts) == 3 else 0
                elif k == "HID_UNIQ":
                    uniq = v
    except OSError:
        pass
    if bus == "0005":
        return "bluetooth", uniq
    if pid in RECEIVER_PIDS or "puck" in name.lower():
        return "receiver", ""
    return "usb", ""

def hid_pid(dev):
    """USB/BT product ID of a hidraw node (0 if unknown)."""
    try:
        with open(f"/sys/class/hidraw/{os.path.basename(dev)}/device/uevent") as f:
            for line in f:
                if line.startswith("HID_ID="):
                    return int(line.strip().split(":")[2], 16)
    except (OSError, IndexError, ValueError):
        pass
    return 0

def bluez_battery(address):
    """Live battery % from the BLE Battery Service via BlueZ, or None."""
    if not address:
        return None
    dev = "dev_" + address.upper().replace(":", "_")
    for hci in ("hci0", "hci1", "hci2"):
        try:
            out = subprocess.run(
                ["busctl", "--system", "get-property", "org.bluez",
                 f"/org/bluez/{hci}/{dev}", "org.bluez.Battery1", "Percentage"],
                capture_output=True, text=True, timeout=3).stdout.split()
        except (OSError, subprocess.TimeoutExpired):
            return None
        if len(out) == 2 and out[0] == "y":
            return max(0, min(100, int(out[1])))
    return None

def puck_dock_node():
    """hidraw node of the puck's dock interface: a 28de:1304 node without OUTPUT reports."""
    for i in range(32):
        base = f"/sys/class/hidraw/hidraw{i}/device"
        try:
            with open(base + "/uevent") as f:
                if "28DE:00001304" not in f.read().upper():
                    continue
            with open(base + "/report_descriptor", "rb") as f:
                desc = f.read()
        except OSError:
            continue
        j, has_out = 0, False
        while j < len(desc):
            b = desc[j]
            if b == 0xFE:                      # long item
                j += 3 + (desc[j + 1] if j + 1 < len(desc) else 0)
                continue
            if (b & 0xFC) == 0x90:             # Main item, tag Output
                has_out = True
                break
            j += 1 + (0, 1, 2, 4)[b & 3]
        if not has_out:
            return f"/dev/hidraw{i}"
    return None

def puck_docked():
    """True/False = pad on/off the puck's dock, None = can't tell."""
    dev = puck_dock_node()
    if not dev:
        return None
    try:
        fd = os.open(dev, os.O_RDWR)
    except OSError:
        return None
    try:
        out = bytearray(64)
        out[0], out[1] = 0x02, 0xB4
        fcntl.ioctl(fd, HIDIOCSFEATURE_64, bytes(out))
        time.sleep(0.05)
        buf = bytearray(65)
        buf[0] = 0x02
        fcntl.ioctl(fd, HIDIOCGFEATURE_65, buf, True)
        if buf[1] != 0xB4:                     # answer to someone else's command
            return None
        return buf[3] == 2
    except OSError:
        return None
    finally:
        os.close(fd)

class DockCache:
    def __init__(self):
        self.value, self.at = None, 0

    def get(self):
        if time.time() - self.at >= DOCK_POLL:
            v = puck_docked()
            self.at = time.time()
            if v is not None:
                self.value = v
        return bool(self.value)

    def reset(self):
        self.at = 0

def find_device():
    """Returns (live hidraw node or None, connection of any silent controller/puck node or "")."""
    present = ""
    for i in range(32):
        dev = f"/dev/hidraw{i}"
        try:
            fd = os.open(dev, os.O_RDONLY | os.O_NONBLOCK)
        except OSError:
            continue
        try:
            buf = bytearray(8)
            fcntl.ioctl(fd, HIDIOCGRAWINFO, buf, True)
            _, vendor, product = struct.unpack("ihh", bytes(buf))
            if vendor & 0xFFFF != SC_VID or product & 0xFFFF not in SC_PIDS:
                continue
            present = present or hid_info(dev)[0]
            if select.select([fd], [], [], 0.15)[0]:
                return dev, present
        except OSError:
            pass
        finally:
            os.close(fd)
    return None, present

def _int_or(value, fallback):
    try:
        return int(value)
    except (TypeError, ValueError):
        return fallback

def neutralize_input(inp):
    """Clamp the Triton axes and hide idle stick jitter from the live view."""
    for key in ("lx", "ly", "rx", "ry"):
        value = max(-32768, min(32767, _int_or(inp.get(key), 0)))
        if abs(value) <= INPUT_STICK_DEADZONE:
            value = 0
        inp[key] = value
    for key in ("l2", "r2"):
        value = max(0, min(32767, _int_or(inp.get(key), 0)))
        if value <= INPUT_TRIGGER_DEADZONE:
            value = 0
        inp[key] = value
    buttons = max(0, min(0x3FFFFFFF, _int_or(inp.get("buttons"), 0)))
    inp["buttons"] = buttons
    for prefix, touch_bit in (
        ("lp", TRITON_LEFT_TOUCHPAD_TOUCH),
        ("rp", TRITON_RIGHT_TOUCHPAD_TOUCH),
    ):
        x = max(-32768, min(32767, _int_or(inp.get(prefix + "x"), 0)))
        y = max(-32768, min(32767, _int_or(inp.get(prefix + "y"), 0)))
        pressure = max(0, min(32767, _int_or(inp.get(prefix + "p"), 0)))
        if not (buttons & touch_bit):
            x = y = pressure = 0
        inp[prefix + "x"] = x
        inp[prefix + "y"] = y
        inp[prefix + "p"] = pressure
    return inp

def neutral_input():
    return neutralize_input({
        "lx": 0, "ly": 0, "rx": 0, "ry": 0,
        "l2": 0, "r2": 0, "buttons": 0,
        "lpx": 0, "lpy": 0, "lpp": 0,
        "rpx": 0, "rpy": 0, "rpp": 0,
    })

def parse_triton_input(data):
    """Parse a Triton 0x42/0x45/0x47 report into the widget's compact form."""
    if not data or len(data) < 46:
        return None
    if data[0] not in TRITON_STATE_REPORTS:
        return None
    payload = data[1:]
    if len(payload) < 45:
        return None
    _seq, buttons, l2, r2, lx, ly, rx, ry = struct.unpack_from(
        "<BIhhhhhh", payload, 0
    )
    # The 0x47 timestamp variant inserts a 2-byte trackpad timestamp before the
    # pad coordinates; the common button/stick/trigger prefix is unchanged.
    pad_offset = 19 if data[0] == 0x47 else 17
    lpx, lpy, lpp, rpx, rpy, rpp = struct.unpack_from("<hhHhhH", payload, pad_offset)
    return neutralize_input({
        "lx": lx, "ly": ly, "rx": rx, "ry": ry,
        "l2": l2, "r2": r2, "buttons": buttons,
        "lpx": lpx, "lpy": lpy, "lpp": lpp,
        "rpx": rpx, "rpy": rpy, "rpp": rpp,
    })

class State:
    def __init__(self, stream=False):
        self.battery_pct = -1
        self.connected = False
        self.charging = False
        self.provisional = True
        self.last_seen = ""
        self.connection = ""
        self.address = ""
        self.docked = False
        self.internal = False
        self.signal = None
        self.input = neutral_input()
        self.stream = stream
        self._last_stream_write = 0
        self._last_stream_dump = None
        self._last_file_write = 0
        self._last_file_dump = None
        self.load()

    def load(self):
        """Preserve the last known percentage across daemon restarts."""
        try:
            with open(STATE_FILE) as f:
                d = json.load(f)
            self.battery_pct = int(d.get("battery_pct", -1))
        except (OSError, ValueError, TypeError):
            pass

    def payload(self):
        return {
            "battery_pct": self.battery_pct,
            "connected": self.connected,
            "charging": self.charging,
            "provisional": self.provisional,
            "last_seen": self.last_seen,
            "connection": self.connection,
            "address": self.address,
            "docked": self.docked,
            "internal": self.internal,
            "signal_dbm": self.signal,
            "input": self.input,
            "daemon_version": DAEMON_VERSION,
            "updated_at": datetime.now().isoformat(timespec="seconds"),
            "ts": int(time.time()),
        }

    def write(self, force=False, persist=True):
        now = time.time()
        d = self.payload()
        inp = d["input"]
        key = (
            d["battery_pct"], d["connected"], d["charging"], d["provisional"],
            d["connection"], d["docked"], d["internal"], d["signal_dbm"],
            inp.get("lx"), inp.get("ly"), inp.get("rx"), inp.get("ry"),
            inp.get("l2"), inp.get("r2"), inp.get("buttons"),
            inp.get("lpx"), inp.get("lpy"), inp.get("lpp"),
            inp.get("rpx"), inp.get("rpy"), inp.get("rpp"),
        )

        if self.stream and (
            force
            or key != self._last_stream_dump
            or now - self._last_stream_write >= WRITE_INTERVAL
        ):
            print(json.dumps(d, separators=(",", ":")), flush=True)
            self._last_stream_dump = key
            self._last_stream_write = now

        if persist and (
            force
            or key != self._last_file_dump
            or now - self._last_file_write >= WRITE_INTERVAL
        ):
            self._last_file_dump = key
            self._last_file_write = now
            # Keep a copy on disk for debugging and for tools that prefer polling.
            try:
                tmp = STATE_FILE + ".tmp"
                with open(tmp, "w") as f:
                    json.dump(d, f)
                os.replace(tmp, STATE_FILE)
            except OSError:
                pass

def run(stream=False):
    st = State(stream=stream)
    st.write(force=True)
    silent_since = None
    bt_polled = 0
    dock = DockCache()
    charge_flag = None
    bt_battery = False
    rssi = deque(maxlen=SIGNAL_WINDOW)
    rssi_at = 0

    while True:
        dev, present = find_device()
        if not dev:
            # Silent puck: ask it whether the pad is on the dock (charging) or off.
            st.connected = False
            st.internal = False
            st.signal = None
            st.docked = present == "receiver" and dock.get()
            if present == "receiver":
                st.charging = st.docked
                st.connection = "receiver" if st.docked else ""
            else:
                st.charging = present == "usb"
                st.connection = present
            st.address = ""
            st.provisional = True    # battery_pct is now the last known value
            st.input = neutral_input()
            st.write()
            time.sleep(1)
            continue

        try:
            fd = os.open(dev, os.O_RDONLY)
            st.connection, st.address = hid_info(dev)
            st.internal = hid_pid(dev) == INTERNAL_PUCK_PID
            bt_polled = 0
            dock.reset()
            charge_flag = None
            bt_battery = False      # BlueZ answered: it wins over 0x43 on Bluetooth
            rssi.clear()
            st.signal = None
            silent_since = None
            last_input_publish = 0.0
            last_persist = time.time()
        except OSError:
            time.sleep(1)
            continue

        try:
            while True:
                r, _, _ = select.select([fd], [], [], 1.0)
                if not r:
                    silent_since = silent_since or time.time()
                    gap = time.time() - silent_since
                    if gap >= SILENCE_DISCONNECT:
                        # Pad went quiet: rescan, so a switch to cable/Bluetooth is noticed too
                        break
                    continue

                data = os.read(fd, 64)
                # Over Bluetooth the pad exposes a real Battery Service: use it, live.
                if st.connection == "bluetooth" and time.time() - bt_polled >= 30:
                    bt_polled = time.time()
                    pct = bluez_battery(st.address)
                    bt_battery = pct is not None
                    if bt_battery:
                        st.battery_pct = pct
                        st.provisional = False
                silent_since = None
                st.connected = True
                # The dock charges the pad whatever link it uses (puck radio or Bluetooth)
                st.docked = st.connection != "usb" and dock.get()
                if data and data[0] == 0x43 and len(data) >= 2 and data[1] in (1, 2):
                    charge_flag = data[1] == 2   # dock, or a USB-C cable/charger in any mode
                if charge_flag is not None:
                    st.charging = charge_flag or st.docked
                else:
                    st.charging = st.docked or st.connection == "usb"
                st.last_seen = datetime.now().strftime("%H:%M")

                # 0x7b byte[9] = signal strength between pad and receiver, signed dBm.
                # 0 = no reading. Not sent over Bluetooth.
                if data and data[0] == 0x7B and len(data) >= 10 and data[9]:
                    dbm = data[9] - 256 if data[9] > 127 else data[9]
                    if -110 <= dbm <= -5:
                        rssi.append(dbm)
                        rssi_at = time.time()
                if rssi and time.time() - rssi_at < SIGNAL_STALE:
                    st.signal = round(sum(rssi) / len(rssi))
                else:
                    st.signal = None

                # byte[2] is the live battery %.
                if data and data[0] == 0x43 and len(data) >= 3 and data[2] <= 100 and not bt_battery:
                    st.battery_pct = data[2]
                    st.provisional = False

                inp = parse_triton_input(data)
                if inp is not None:
                    st.input = inp

                now = time.time()
                if now - last_input_publish >= INPUT_POLL_INTERVAL:
                    last_input_publish = now
                    st.write(persist=False)
                if now - last_persist >= 1.5:
                    last_persist = now
                    st.write()
        except OSError:
            st.connected = False
            st.charging = False
            st.docked = False
            st.signal = None
            st.provisional = True
            st.input = neutral_input()
            st.write()
        finally:
            try:
                os.close(fd)
            except OSError:
                pass
        time.sleep(1)

# Rumble (output report 0x80, layout from SDL's SDL_hidapi_steam_triton.c):
# report id, type, intensity u16, left speed u16, left gain s8, right speed u16,
# right gain s8. The pad stops on its own after ~50 ms, so it is resent every 40 ms.
RUMBLE = struct.Struct("<BBHHbHb")
# Easter egg: a scream-shaped buzz (speed, seconds) -- quick rise, hold, fade
BUZZ_PATTERN = [(30000, 0.08), (55000, 0.12), (65535, 0.45), (45000, 0.15), (25000, 0.15)]

def buzz():
    """Rumble whichever controller node is live (puck slot, Bluetooth or USB)."""
    dev, _ = find_device()
    if not dev:
        return 1
    try:
        fd = os.open(dev, os.O_WRONLY)
    except OSError:
        return 1
    try:
        for speed, secs in BUZZ_PATTERN:
            end = time.time() + secs
            while time.time() < end:
                os.write(fd, RUMBLE.pack(0x80, 0, 0, speed, 0, speed, 0))
                time.sleep(0.04)
        os.write(fd, RUMBLE.pack(0x80, 0, 0, 0, 0, 0, 0))
    except OSError:
        return 1
    finally:
        os.close(fd)
    return 0

def main():
    if "--buzz" in sys.argv[1:]:
        return buzz()
    stream = "--stream" in sys.argv[1:]
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    signal.signal(signal.SIGINT, lambda *_: sys.exit(0))
    lock = single_instance()
    try:
        run(stream=stream)
    except (KeyboardInterrupt, BrokenPipeError):
        pass
    finally:
        release_lock(lock)
    return 0

if __name__ == "__main__":
    sys.exit(main())
