#!/usr/bin/env python3
"""Print a read-only snapshot of the AWDL radio probe counters."""
import json
import re
import struct
import subprocess

PREFIX = "ITLAWDLRadio"
FIELDS = (
    "Requests", "RequestErrors", "UnexpectedLengths", "Reports", "ReportUS",
    "LastCommandLength", "LastNotificationLength", "Temperature", "RxTime", "TxTime", "OnTime",
)


def main():
    registry = subprocess.check_output(["/usr/sbin/ioreg", "-l", "-w0"], text=True)
    properties = dict(re.findall(r'"(ITLAWDL\w+)" = (\d+|<[0-9a-f]+>)', registry))
    if PREFIX + "Requests" not in properties:
        raise SystemExit("Radio probe unavailable. Boot with -itlawdlradioprobe on a supported build.")

    snapshot = {name: int(properties[PREFIX + name])
                for name in FIELDS if PREFIX + name in properties}
    if snapshot.get("Temperature", 0) >= 1 << 31:
        snapshot["Temperature"] -= 1 << 32
    for name in ("FixedChannel", "BaFilterOff", "TxWindow", "Tx80Requested", "Tx80Completed",
                 "Tx80Reported", "Tx80Acked", "Tx80Disabled"):
        key = "ITLAWDL" + name
        if key in properties:
            snapshot[name] = int(properties[key])
    for name in ("Beacons", "OtherData"):
        payload = properties.get(PREFIX + name)
        if payload:
            counts = struct.unpack("<256I", bytes.fromhex(payload[1:-1]))
            snapshot[name] = {channel: count for channel, count in enumerate(counts) if count}
    print(json.dumps(snapshot, indent=2))


if __name__ == "__main__":
    main()
