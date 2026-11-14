#!/usr/bin/env python3
"""Compare AWDL TLVs in the phone's frames and our master indication template.

Prints types and lengths, and the names inside Bonjour-style TLVs only as a list of
service types. Output can still identify devices, so don't publish it.
"""
import plistlib
import re
import subprocess


def walk(data, offset=0):
    while offset + 3 <= len(data):
        kind = data[offset]
        length = int.from_bytes(data[offset + 1:offset + 3], "little")
        if offset + 3 + length > len(data):
            yield kind, length, None
            return
        yield kind, length, data[offset + 3:offset + 3 + length]
        offset += 3 + length


def describe(name, data, offset):
    if not data:
        print(f"{name}: none")
        return
    print(f"{name}: {len(data)} bytes")
    print("  TLV type:length " + " ".join(f"{k}:{n}{'' if v is not None else '(cut)'}" for k, n, v in walk(data, offset)))
    found = sorted({m.decode() for m in re.findall(rb"_[a-zA-Z0-9-]{2,30}", data)})
    print("  service-like labels: " + (" ".join(found) or "none"))
    # AWDL compresses common names: c0 07 stands for _airdrop._tcp.local, so a text
    # search alone misses it. PTR is DNS type 0x0c.
    print(f"  compressed _airdrop PTR records: {data.count(bytes((0xc0, 0x07, 0x0c)))}")


def main():
    root = plistlib.loads(subprocess.run(["ioreg", "-a", "-l", "-w0", "-d0", "-p", "IOService"], capture_output=True).stdout)
    raw = subprocess.run(["ioreg", "-a", "-l", "-w0", "-r", "-c", "ItlAWDLInterface", "-d0"], capture_output=True).stdout
    interface = plistlib.loads(raw) if raw else {}
    interface = interface[0] if isinstance(interface, list) and interface else interface
    describe("largest peer MIF", root.get("ITLAWDLSampleLargestMIF"), 40)
    describe("largest peer PSF", root.get("ITLAWDLSampleLargestPSF"), 40)
    describe("our MI template", interface.get("ItlwmAWDLMiSample"), 0)
    counts = root.get("ITLAWDLPeerTLVCounts")
    if counts:
        items = [(i, int.from_bytes(counts[i * 4:i * 4 + 4], "little")) for i in range(256)]
        print("peer TLV counts: " + " ".join(f"{i}:{c}" for i, c in items if c))
    print(f"peers naming us: {root.get('ITLAWDLHeardActionMentions')}")


if __name__ == "__main__":
    main()
