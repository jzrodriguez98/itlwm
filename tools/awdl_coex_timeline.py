#!/usr/bin/env python3
"""Export the AWDL coexistence queue timeline to CSV."""

import argparse
import csv
from pathlib import Path
import re
import struct
import subprocess
import sys


HEADER = struct.Struct("<II")
ENTRY = struct.Struct("<QQ8I5HBBI")
CAPACITY = 4096
FLAGS = (
    "aggregate_queue_active", "bulk", "paused", "schedule_usable", "schedule_requests_pause",
    "tx_halted", "move_pending", "refill_enabled",
)
COLUMNS = (
    "uptime_us", "last_ba_us", "generation", "listener", "peer_epoch", "ba_reports",
    "acked_frames", "refill_frames", "empty_host_ready", "empty_host_idle", "host_depth",
    "aggregate_depth", "last_ba_host_depth", "last_ba_after_reclaim", "last_ba_after_refill",
    "channel", "refill_kicks",
) + FLAGS


def decode(registry):
    match = re.search(r'"ITLAWDLCoexBaTimeline"\s*=\s*<([0-9a-fA-F]+)>', registry)
    if not match:
        raise ValueError("Timeline missing. Boot iface156 with the coexistence BA trace flag and wait for the listener.")
    blob = bytes.fromhex(match[1])
    if len(blob) < HEADER.size:
        raise ValueError("Truncated timeline header.")
    version, count = HEADER.unpack_from(blob)
    if version != 1:
        raise ValueError(f"Unsupported timeline version {version}.")
    retained = min(count, CAPACITY)
    if len(blob) != HEADER.size + retained * ENTRY.size:
        raise ValueError("Timeline length does not match its header.")
    for index in range(count - retained, count):
        offset = HEADER.size + index % CAPACITY * ENTRY.size
        *fields, flags, channel, refill_kicks = ENTRY.unpack_from(blob, offset)
        yield (*fields, channel, refill_kicks, *(int(bool(flags & (1 << bit))) for bit in range(len(FLAGS))))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("snapshot", nargs="?", type=Path, help="Read a saved ioreg text snapshot instead of live data.")
    args = parser.parse_args()
    try:
        registry = args.snapshot.read_text() if args.snapshot else subprocess.check_output(
            ["/usr/sbin/ioreg", "-lw0", "-d1"], text=True,
        )
        rows = list(decode(registry))
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"{error}\n")
    writer = csv.writer(sys.stdout, lineterminator="\n")
    writer.writerow(COLUMNS)
    writer.writerows(rows)


if __name__ == "__main__":
    main()
