#!/usr/bin/env python3
"""Show which channel the AirDrop driver is on. Read-only, and needs no sudo.

  python3 tools/awdl_channel.py          one reading
  python3 tools/awdl_channel.py --watch  a new line whenever something changes
"""
import re
import subprocess
import sys
import time

COUNTERS = {
    "ITLAWDLBackgroundScans": "scans",
    "ITLAWDLMovesUp": "moves up",
    "ITLAWDLMovesDown": "moves down",
    "ITLAWDLLastMoveMs": "last move ms",
    "ITLAWDLCountryNotices": "notices",
    "ITLAWDLCountryAnswers": "answers",
    "ITLAWDLTxWindow": "window",
}


def read_registry():
    return subprocess.run(["/usr/sbin/ioreg", "-lw0"], capture_output=True, text=True, errors="replace").stdout


def number(text, key):
    match = re.search(r'"%s" = (\d+)' % key, text)
    return int(match.group(1)) if match else None


def summary(text):
    channel = number(text, "ITLAWDLFixedChannel")
    if channel is None:
        return "The AirDrop driver isn't running in test mode, or hasn't reported yet."
    band = "5 GHz" if channel > 14 else "2.4 GHz"
    speed = "fast" if channel > 14 else "slower"
    parts = ["Channel %d (%s, %s)" % (channel, band, speed)]
    answered = number(text, "ITLAWDLCountryLastAnswered")
    if answered and 32 < answered >> 8 < 127 and 32 < answered & 255 < 127:
        parts.append("country " + chr(answered >> 8) + chr(answered & 255))
    for key, label in COUNTERS.items():
        value = number(text, key)
        if value is not None:
            parts.append("%s %d" % (label, value))
    return " | ".join(parts)


def main():
    if "--watch" not in sys.argv[1:]:
        print(summary(read_registry()))
        return
    print("Watching. Press Ctrl-C to stop.")
    last = None
    try:
        while True:
            line = summary(read_registry())
            if line != last:
                print(time.strftime("%H:%M:%S"), line, flush=True)
                last = line
            time.sleep(5)
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
