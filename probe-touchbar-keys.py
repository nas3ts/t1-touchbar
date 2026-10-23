#!/usr/bin/env python3
"""
Probe the T1 Touch Bar's key events.

Run as root:   sudo python3 probe-touchbar-keys.py

Press each Touch Bar key once.  For the F-keys, HOLD the physical Fn key (bottom-left)
and tap the bar.  Press Ctrl-C when done and paste the output back.
"""
import glob, os, re, struct, sys

# keycode -> name table
NAMES = {}
hdr = "/usr/include/linux/input-event-codes.h"
if os.path.exists(hdr):
    for line in open(hdr):
        m = re.match(r'#define\s+(KEY_\w+)\s+(0x[0-9a-fA-F]+|\d+)', line)
        if m:
            NAMES[int(m.group(2), 0)] = m.group(1)

def find_device():
    for ev in sorted(glob.glob('/sys/class/input/event*'),
                     key=lambda p: int(p.rsplit('event', 1)[1])):
        try:
            name = open(os.path.join(ev, 'device/name')).read().strip()
        except OSError:
            continue
        if 'iBridge Virtual HID' in name:
            return '/dev/input/' + os.path.basename(ev), name
    return None, None

dev, name = find_device()
if not dev:
    sys.exit("Could not find an 'iBridge Virtual HID' input device.")

print(f"Listening on {dev}  ({name})")
print("Press each Touch Bar key once.  Ctrl-C when done.\n")

EV_KEY = 1
FMT = "llHHi"                      # timeval(2x long) + type + code + value
SZ = struct.calcsize(FMT)
seen = []

with open(dev, 'rb', buffering=0) as f:
    try:
        while True:
            data = f.read(SZ)
            if len(data) < SZ:
                break
            _, _, etype, code, value = struct.unpack(FMT, data)
            if etype == EV_KEY and value == 1:      # key press
                kn = NAMES.get(code, f"KEY_?{code}")
                seen.append(code)
                print(f"  code {code:3d}   {kn}")
    except KeyboardInterrupt:
        pass

print("\nSummary of distinct keys pressed:")
uniq = sorted(set(seen))
for c in uniq:
    print(f"  {c:3d}  {NAMES.get(c, 'KEY_?')}")
