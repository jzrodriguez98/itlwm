#!/usr/bin/env python3
"""Report the -itlawdlpeertrain result from the I/O Registry after a test boot.

Prints TLV types and lengths, never TLV contents other than the election
parameters, because AWDL service and ARPA TLVs can carry device names.
"""
import plistlib
import subprocess


def tlvs(frame):
    # 24-byte header, then category, OUI, type, version, subtype, reserved and
    # two 32-bit timestamps: TLVs begin at offset 40. Same layout as the builder.
    offset = 40
    while offset + 3 <= len(frame):
        kind = frame[offset]
        length = int.from_bytes(frame[offset + 1:offset + 3], "little")
        if offset + 3 + length > len(frame):
            break  # Samples are capped at 1024 bytes, so the tail may be cut.
        yield kind, frame[offset + 3:offset + 3 + length]
        offset += 3 + length


def describe(name, frame):
    print(f"{name}: {len(frame)} bytes, source ..:{frame[14]:02x}:{frame[15]:02x}, subtype {frame[30]}")
    print("  TLV type:length " + " ".join(f"{k}:{len(v)}" for k, v in tlvs(frame)))
    for kind, value in tlvs(frame):
        if kind == 5 and len(value) >= 19:
            # Layout from seemoo-lab/owl; unverified against this macOS build.
            print(f"  election: distance {value[3]}, master ..:{value[9]:02x}:{value[10]:02x}, "
                  f"master metric {int.from_bytes(value[11:15], 'little')}, "
                  f"self metric {int.from_bytes(value[15:19], 'little')}")


def interface_properties():
    raw = subprocess.run(["ioreg", "-a", "-l", "-w0", "-r", "-c", "ItlAWDLInterface", "-d0"], capture_output=True).stdout
    if not raw:
        return {}
    found = plistlib.loads(raw)
    return found[0] if isinstance(found, list) and found else {}


def describe_output(frame):
    # Headers only. No addresses are printed.
    if len(frame) < 14:
        return f"{len(frame)} bytes"
    kind = int.from_bytes(frame[12:14], "big")
    text = f"{len(frame)} bytes sampled, ethertype {kind:#06x}"
    if kind == 0x86dd and len(frame) >= 54:
        text += f", IPv6 next header {frame[20]}"
        if frame[20] == 17 and len(frame) >= 58:
            text += f", UDP port {int.from_bytes(frame[56:58], 'big')}"
        if frame[20] == 58:
            text += f", ICMPv6 type {frame[54]}"
    return text


def main():
    raw = subprocess.run(["ioreg", "-a", "-l", "-w0", "-d0", "-p", "IOService"],
                         capture_output=True, check=True).stdout
    root = plistlib.loads(raw)
    value = lambda key: root.get(key, 0)
    if "ITLAWDLHeardActionMentions" not in root:
        print("No heard-us counters. This boot is not running the iface29 build with -itlawdlrx.")
        return
    print(f"train frames submitted      {value('ITLAWDLTrainSubmitted')} of 1536")
    print(f"own frames heard back       {value('ITLAWDLHeardSelfEchoes')}")
    print(f"peer frames addressed to us {value('ITLAWDLHeardActionToUs')}")
    print(f"peer frames naming us       {value('ITLAWDLHeardActionMentions')}")
    print(f"data multicast / to us / other / mDNS  {value('ITLAWDLHeardDataMulticast')} / "
          f"{value('ITLAWDLHeardDataToUs')} / {value('ITLAWDLHeardDataToOther')} / {value('ITLAWDLHeardDataMDNS')}")
    if "ITLAWDLAirAckToAWDL" in root:
        print()
        print("unicast probe               acked  failed  no-ACK retries  last failure")
        for name, key in (("peer, AWDL source", "PeerAWDL"), ("peer, hardware source", "PeerHardware"),
                          ("absent, AWDL source", "ControlAWDL"), ("absent, hardware source", "ControlHardware"),
                          ("neighbor solicit to peer", "PeerNeighbor"), ("echo request to peer", "PeerEcho"),
                          ("solicit from foreign addr", "PeerForeign")):
            print(f"{name:27} {value('ITLAWDLAck' + key + 'OK'):5}  {value('ITLAWDLAck' + key + 'Fail'):6}  "
                  f"{value('ITLAWDLAck' + key + 'Retries'):14}  0x{value('ITLAWDLAck' + key + 'LastFailure'):02x}")
    if "ITLAWDLAirAckToAWDL" in root:
        print()
        if "ITLAWDLMacContextResult" in root:
            state = "failed" if value("ITLAWDLMacContextResult") else "accepted"
            print(f"MAC context address change  {state}, firmware generation {value('ITLAWDLMacContextGeneration')}")
        print(f"raw ACK frames seen         to AWDL {value('ITLAWDLAirAckToAWDL')}, to hardware {value('ITLAWDLAirAckToHardware')}")
        print(f"unicast addressed to us     {value('ITLAWDLAirUnicastToUs')}, retried {value('ITLAWDLAirUnicastToUsRetried')}")
        print(f"to foreign address          {value('ITLAWDLAirUnicastToForeign')} frames, {value('ITLAWDLAirUnicastToForeignRetried')} retried, "
              f"{value('ITLAWDLAirAckToForeign')} raw ACKs")
        if "ITLAWDLAirTypesToUs" in root:
            raw = root["ITLAWDLAirTypesToUs"]
            names = {0x02: "data", 0x12: "null", 0x22: "qos data", 0x32: "qos null", 0x34: "action", 0x14: "probe resp", 0x10: "probe req"}
            found = []
            for i in range(0, len(raw) // 4):
                count = int.from_bytes(raw[i * 4:i * 4 + 4], "little")
                if count:
                    found.append(f"{names.get(i, hex(i << 2))} {count}")
            print("frame types to us           " + (", ".join(found) or "none"))
        if "ITLAWDLHeardEchoReply" in root:
            print(f"replies from peers          echo {value('ITLAWDLHeardEchoReply')}, neighbor advert {value('ITLAWDLHeardNeighborAdvert')}, "
                  f"neighbor solicit {value('ITLAWDLHeardNeighborSolicit')}")
        if "ITLAWDLAckPeers" in root:
            print("per peer                    " + str(root["ITLAWDLAckPeers"]))
    print()
    for key, label in (("ITLAWDLSampleTX", "our frame"), ("ITLAWDLSamplePSF", "peer PSF"),
                       ("ITLAWDLSampleMIF", "peer MIF"), ("ITLAWDLSampleMention", "frame naming us")):
        if key in root:
            describe(label, root[key])
    print()
    if "ITLAWDLAirAckToAWDL" in root:
        for source, label in (("AWDL", "AWDL address"), ("Hardware", "hardware address")):
            peer, peer_fail = value(f"ITLAWDLAckPeer{source}OK"), value(f"ITLAWDLAckPeer{source}Fail")
            control, control_fail = value(f"ITLAWDLAckControl{source}OK"), value(f"ITLAWDLAckControl{source}Fail")
            if not peer and not peer_fail:
                continue  # This source wasn't probed in this mode.
            if control:
                print(f"ACK, {label}: the absent control also succeeded, so status doesn't show ACKs here.")
            elif not control_fail:
                print(f"ACK, {label}: the control hasn't run, so nothing can be concluded.")
            elif peer:
                print(f"ACK, {label}: PROVEN. A peer's radio ACKed {peer} frames and the control never did.")
            else:
                print(f"ACK, {label}: no peer ACK in {peer_fail} tries. The control failed as it should. Either "
                      "peers don't hear us, weren't on channel 6, or firmware missed the ACK.")
        print()
        foreign, foreign_retried = value("ITLAWDLAirUnicastToForeign"), value("ITLAWDLAirUnicastToForeignRetried")
        if "ITLAWDLAckPeerForeignOK" in root and foreign:
            if foreign_retried * 2 > foreign:
                print(f"ACK CONTROL: {foreign_retried} of {foreign} replies to the foreign address were retries, so the retry bit does show missing ACKs.")
            else:
                print(f"ACK CONTROL: only {foreign_retried} of {foreign} replies to the foreign address were retries, so the retry reading is unproven.")
        elif "ITLAWDLAckPeerForeignOK" in root:
            print("ACK CONTROL: no replies to the foreign address, so it tells us nothing.")
        interface = interface_properties()
        if interface:
            print(f"DELIVERY: {interface.get('ItlwmAWDLDataDelivered', 0)} frames into awdl0, {interface.get('ItlwmAWDLDataDeliverFailed', 0)} refused, "
                  f"last error {hex(interface.get('ItlwmAWDLDataDeliverLastError', 0) & 0xffffffff)}")
            print(f"macOS output: {interface.get('ItlwmAWDLTxCallbacks', 0)} transmit callbacks, {interface.get('ItlwmAWDLTxPacketsOffered', 0)} packets offered, "
                  f"{interface.get('ItlwmAWDLRxSupplyCallbacks', 0)} receive supply callbacks")
            for key, label in (("ItlwmAWDLQueueStateAtRegistration", "at registration"), ("ItlwmAWDLQueueStateAfterEnable", "after enable"),
                               ("ItlwmAWDLQueueStateRefused", "when refused")):
                if key in interface:
                    print(f"queues {label} (enabled, ring ready): {interface[key]}")
            if "ITLAWDLSampleActionToUs" in root:
                action = root["ITLAWDLSampleActionToUs"]
                print(f"action frame to us: {len(action)} bytes, category {action[24]}, action {action[25]}")
            if interface.get("ItlwmAWDLNativeUp"):
                print(f"native requests: sync enabled {interface.get('ItlwmAWDLSyncEnabledRequested', 'never')}, sync state {interface.get('ItlwmAWDLSyncStateRequested', 'never')}")
            if "ItlwmAWDLMiLength" in interface:
                print(f"MI template: {interface['ItlwmAWDLMiLength']} bytes, {interface.get('ItlwmAWDLMiUpdates')} updates, "
                      f"{interface.get('ItlwmAWDLMiRejected', 0)} rejected, build failed {interface.get('ItlwmAWDLMiBuildFailed', False)}")
            if "ItlwmAWDLOobRequests" in interface:
                print(f"OOB requests: {interface['ItlwmAWDLOobRequests']}, first {interface.get('ItlwmAWDLOobFirstName')}, "
                      f"{interface.get('ItlwmAWDLOobFirstLength')} data bytes; recorded, not sent")
            if "ITLAWDLTxMulticastSent" in root:
                print(f"sent over the air: {value('ITLAWDLTxMulticastSent')} multicast, {value('ITLAWDLTxUnicastSent')} unicast "
                      f"({value('ITLAWDLTxUnicastOK')} ACKed, {value('ITLAWDLTxUnicastFail')} not, last failure {value('ITLAWDLTxLastFailure'):#x})")
                print(f"native packets: {interface.get('ItlwmAWDLTxAccepted', 0)} accepted, {interface.get('ItlwmAWDLTxCompleted', 0)} completed, "
                      f"{interface.get('ItlwmAWDLTxDropped', 0)} not sent, complete error {interface.get('ItlwmAWDLTxCompleteLastError', 0) & 0xffffffff:#x}")
                if "ITLAWDLPeerLinkLocal" in root:
                    ip = root["ITLAWDLPeerLinkLocal"]
                    words = [ip[i:i + 2].hex().lstrip("0") or "0" for i in range(8, 16, 2)]
                    print("try: ping6 -c 5 fe80::" + ":".join(words) + "%awdl0")
            if "ItlwmAWDLTxSample" in interface:
                print("first output frame: " + describe_output(interface["ItlwmAWDLTxSample"]))
        print(subprocess.run(["netstat", "-I", "awdl0"], capture_output=True, text=True).stdout.strip().splitlines()[-1])
        print()
        to_us, retried = value("ITLAWDLAirUnicastToUs"), value("ITLAWDLAirUnicastToUsRetried")
        if "ITLAWDLAckPeerNeighborOK" in root:
            if not to_us:
                print("SEND ACK: untested. No peer addressed us, so it may be ignoring us at the AWDL level.")
            elif retried * 2 > to_us:
                print(f"SEND ACK: likely not working. {retried} of {to_us} frames to us were retries.")
            else:
                print(f"SEND ACK: looks like it works. Only {retried} of {to_us} frames to us were retries.")
            print()
        # The ACK lines above are the stronger test; the checks below can't contradict them.
        return
    named = value("ITLAWDLHeardActionMentions") or value("ITLAWDLHeardActionToUs") or value("ITLAWDLHeardDataToUs")
    if named:
        print("VERDICT: a peer reacted to us, so our frames are reaching it over the air.")
    elif not value("ITLAWDLTrainSubmitted"):
        print("VERDICT: no frames sent. No peer was audible on channel 6 during the test.")
    else:
        print("VERDICT: inconclusive. Frames were sent and no peer named us. Peers only name a")
        print("station they accept or elect, so compare the election metrics above before")
        print("concluding that they cannot hear us.")


if __name__ == "__main__":
    main()
