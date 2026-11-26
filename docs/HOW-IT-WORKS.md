# How ForbiddenItlwm works

AirDrop finds a device over Bluetooth LE, then moves the data over **AWDL** (Apple Wireless Direct Link), a peer-to-peer Wi-Fi link. On a real Mac, Apple's Wi-Fi stack runs most of AWDL itself: elections, timing, service discovery and the data path. It needs a driver that can create an AWDL interface and move its frames on the right channel at the right time.

ForbiddenItlwm makes macOS's native stack (IO80211Family with Skywalk, on Tahoe, Sequoia and Sonoma) believe it has a capable AWDL radio, and does the radio work Intel firmware doesn't do for it. The approach follows FranciumOS-org/AirPort_RTW89, which did this on a Realtek card with the older Wi-Fi stack.

## The pieces

```
           macOS (sharingd, rapportd, mDNSResponder, wifip2pd)
                               │
          IO80211 AWDL peer manager  (Apple's, unchanged)
                               │
   ItlAWDLInterface: awdl0  ── ForbiddenItlwm/AirportItlwmV2.cpp
                               │  9 itlAWDL* calls
   AWDL listener, schedule, ── itlwm/hal_iwx/ItlIwx.cpp
   Block Ack, send gate
                               │
            Intel firmware: station context (normal Wi-Fi)
                          + listener context on 149/80 or 44/80 (AirDrop)
```

### 1. The interface: `awdl0`

- `wifip2pd` asks for an AWDL interface only if the card reports the AWDL capability. `-itlawdliface` sets it.
- `AirportItlwm::createVirtualInterface` then builds `ItlAWDLInterface`, a concrete subclass of Apple's `IO80211VirtualInterface` and `IO80211AWDLProtocol`. Apple's classes are abstract, so the subclass has to match Apple's virtual table slot for slot. `tools/abi/audit_vtable.py` checks all 568 slots against Tahoe 25G241's table, all 563 against Sequoia 24H241's, and all 547 against Sonoma 23J631's. This is why each macOS version needs its own build, and why each build is checked against specific macOS builds.
- Setup creates the Skywalk packet pools and queues and registers `awdl0`.
- Apple's peer manager then pushes its settings and its frame template (the "MI" frame with the Mac's name and services) through `setAWDL_*` calls. The driver keeps copies.

### 2. The radio: a second firmware context

Normal Wi-Fi uses the firmware's station context. ForbiddenItlwm adds a second MAC context, a **listener**, with:
- its own PHY context on the 5 GHz channel the iPhone uses for AirDrop, 149 or 44 (from 0.6.0), at 80 MHz when allowed, else at 20 MHz when the iPhone uses that channel; channel 6 otherwise
- its own firmware station and transmit queue
- the AWDL address

The firmware time-shares the radio between the station's channel and the listener's. So normal Wi-Fi stays connected while AirDrop runs.

The listener is added once the Mac's Wi-Fi connection is up and removed when it disconnects, so AirDrop needs the Mac to be on a Wi-Fi network. From 0.6.0-beta.1 ([PR #12](https://github.com/retropineaple/ForbiddenItlwm/pull/12)) it is added only after the connection is fully set up, and removing it first waits for any setup still in progress.

- **Receive:** the driver picks AWDL action frames and data frames out of what the listener receives. It hands action frames to Apple's peer manager with real RSSI metadata, which the peer manager needs before it accepts a peer. IPv6 data goes into `awdl0`.
- **Transmit:** macOS's sync frames are built from Apple's template and sent every 110 TU. With `-itlawdlsvcmerge` its service records are merged in, and with `-itlawdlawsync` idle frames are timed to the iPhone's windows. `awdl0`'s IPv6 packets go out the listener's queue with AWDL data framing.

### 3. Following the iPhone's schedule

An iPhone doesn't stay on one channel. Its sync frames carry a 16-slot channel sequence, and on each slot it is on the listener's channel, on its own Wi-Fi network's channel, or dozing.
- **Tracking:** `include/AWDLPeerSchedule.hpp` tracks that sequence and its timing. It assumes offset 0 until the iPhone's own frames prove otherwise.
- **The send gate:** frames for the iPhone go out only while it is on the listener's channel. While it is idle, they go only at the start of its availability windows. Before the gate, frames sent while the iPhone was away were lost. The losses made QUIC slow itself down, so Mac → iPhone ran at a fraction of the link speed.
- **Peer pause:** while the iPhone is away, its firmware station queue is paused, so the firmware doesn't burn retries on it.

### 3b. New in 0.7.0-alpha.1: following macOS's plan (`itlawdlsched=1`, experimental)

This is how 0.7.0-alpha.1 differs from earlier versions. Up to 0.6.0-beta.4, and in 0.7.0-alpha.1 without the flag, the listener is on its channel all the time and the firmware decides when the radio serves it and when it serves the station. The Mac advertises "always on the listener's channel", keeps its own clock, picks the channel from what nearby devices announce, and ignores the plan macOS's peer manager makes. With `itlawdlsched=1` (from 0.7.0-alpha.1; older versions ignore it) the driver acts on that plan, as Apple's drivers do:
- **macOS's plan:** IO80211's peer manager plans 16 slots of 64 TU (about 65 ms) for AirDrop, the Mac's Wi-Fi and channel 6, and hands the sequence to the driver (`setAWDL_*`). The driver keeps the listener on the channel macOS chose, falling back to its own choice if macOS names nothing usable.
- **Airtime on request:** a second firmware context (a P2P Device context in the listener's binding) asks for session protection shortly before each run of AirDrop slots (`itlschedlead`, 12 ms by default) and ends it with the run. Before back-to-back runs it ends the current session early, so the next request goes out with its lead time; the firmware decides the exact start, so this narrows the hand-over gap rather than removing it. This is the firmware's own mechanism for timed airtime; the Intel firmware has no AWDL scheduler.
- **Channel 6:** in the slot every Apple device spends on channel 6, a channel-6 context listens, sends the sync frame and passes group data to `awdl0`. That slot is advertised as the station's, since unicast there couldn't be acknowledged.
- **Advertising and timing:** the sync frames carry the schedule the driver really follows (plus free slots it fills while data flows), go out only inside an AirDrop slot so their timing is fresh, and follow the elected master's clock. The election itself follows IO80211's rules, on the time each frame was on air.
- **What macOS expects from a driver:** availability-window start and end events, peer cache control, the AWDL packet counters macOS reads through its peer manager (in 0.7.0-alpha.1 at offsets checked per macOS build, so only on verified builds; from 0.7.0-alpha.2 through macOS's own `getPeerManager()`, see section 7), the station's traffic counts its scheduler uses to size Wi-Fi time, the announcement (MI) first after it changes, and multicast held to each device's availability windows.
- **Safety:** it starts once AWDL has been on for 3 s, macOS has sent a plan, the listener has settled and the start delay has passed; it stops while macOS has AWDL off; it resumes after the first two firmware restarts in a boot and stops at the third.
- **Cards and shared channels:** in 0.7.0-alpha.1 it runs only on AX210-family cards and stays idle while the Mac's Wi-Fi and the listener share a channel, though the flag still turns off the channel-6 search. From 0.7.0-alpha.2 it also runs on the AX200 family (the 22000 family's firmware has the same session protection; untested there), and on a shared channel it still runs macOS's channel-6 entries, since the radio is already on the shared channel for the rest.
- **Width beside the Mac's Wi-Fi (from 0.7.0-alpha.2):** the listener keeps 80 MHz with the Mac's Wi-Fi in its 80 MHz block on another main channel, and takes its channel inside a 160 MHz Wi-Fi channel, at 80 MHz too (section 6). 80 MHz there needs a scheduler that is switched on, has its firmware context in place and has started a session since the last firmware restart; until then the listener uses 20 MHz there. That is a one-time check: a pause or later failed sessions don't undo it, only the scheduler stopping or a firmware restart. Then the change back to 20 MHz starts without the usual settle and idle waits, but it still drains the listener's queue (up to 2 s) and drops the iPhone's block-ack session, so a running transfer can be cut; leaving a 160 MHz channel follows the normal move rules. Widening to 80 MHz follows the usual rules for a change: the choice has to hold for 60 s, with no AirDrop data for the last 30 s. If the listener can't be on macOS's channel, the scheduler pauses and the listener runs as without the flag.

**Still different from a real Mac:** the driver acknowledges macOS's election parameters without applying them, unicast announcements stay behind the separate `-itlawdlumi` flag, the announcement's timing offset is reported but not used as a per-window send schedule, frames sent to the Mac on channel 6 can't be acknowledged, and AirDrop without a Wi-Fi network isn't done yet. Block Ack with each of several devices (`-itlawdlmultipeer`, from 0.7.0-alpha.2) and a second 5 GHz AirDrop channel (part of `itlawdlsched=1` from 0.7.0-alpha.4) exist as experimental features, but neither has been tested here with more than one real Apple device: the second channel only with a simulated one.

`ITLAWDLSched*` keys show its state; `itlawdlsched=3` adds diagnostics. The code is in `itlwm/hal_iwx/ItlIwx.cpp`, with the election and session rules in `include/AWDLElection.hpp` and `include/AWDLSessionFollow.hpp` (host-tested).

### 4. Speed: Block Ack and aggregation

With `-itlawdlcoexbatx` the driver negotiates Block Ack with the iPhone and lets the firmware send A-MPDU aggregates at VHT 80 MHz two-stream rates. Receive Block Ack works too. `-itlawdlcaps` advertises the matching capabilities, so the iPhone sends at the same rates.

The `awdl0` transmit pool is 2048 packets. With the 128 used during bring-up, long Mac → iPhone transfers ran the pool dry and stalled, because the flowswitch drops on allocation failure without telling QUIC.

### 5. Bluetooth: IntelBTPatcher (renamed BTLEAdvFixup)

`bluetoothd` only turns on extended LE advertising after chip checks that a third-party controller fails, so on an Intel controller the Mac never advertises AirDrop. BTLEAdvFixup is a small Lilu plugin that, with `-btleadv`:
- patches `bluetoothd`'s pages in memory as they're validated (the way BlueToolFixup does) to take the "supported" path
- keeps APFS's integrity check working on those pages (#62). The patches live in the copy of the file that macOS keeps in memory. `bluetoothd` is stored compressed, and APFS checks it in 16 KB blocks: when macOS drops one page of a block and reads it again, the check also covers the block's pages that are still in memory, patched, and fails, so `bluetoothd` crashed. BTLEAdvFixup keeps each patched page's original bytes (BlueToolFixup's too, since its hook runs around BlueToolFixup's) and hooks APFS's `apfs_vnop_verify`, the function decmpfs calls for this check, to give it a copy with the original bytes. The pages in memory are never changed by the check
- adjusts outgoing HCI commands, such as the random address of each advertising set, and takes over IntelBTPatcher's fix-up before the first scan (IntelBTPatcher must be disabled, since Lilu panics if two plugins hook the same function)
- with `-btleadvnodupfilter` (experimental, from 0.7.0-alpha.1 with BTLEAdvFixup 0.9.5), patches `bluetoothd` so it scans without the duplicate filter. Intel controllers filter duplicates by address only, so an iPhone's changed advertisement (asking the Mac for a link) was reported only at the next scan restart, up to about 10 s later
- takes over IntelBTPatcher's fix for new LE HID devices (a mouse, a keyboard) that connect but never finish bonding: the Intel controller never sends LE Data Length Change on Tahoe, so `bluetoothd` waits for it forever ("No database exists"). BTLEAdvFixup hooks the controller's interrupt IN pipe, sends every LE Read Remote Features command twice more, and rewrites the two duplicate completions into the PHY Update Complete and LE Data Length Change events `bluetoothd` is missing. Devices that are already bonded skip discovery and never trigger this.

Its byte patterns are exact bytes from specific `bluetoothd` builds: 25G241's (26.7.1) and 25G342's (26.7.3) for the Tahoe build, 24H241's (15.8.3) for the Sequoia build, which also match 15.8 (24H23), 15.8.1 and 15.8.2 unchanged, plus a 15.7.x set from 0.7.0-alpha.2 (15.7.3, 15.7.8 and 15.7.9), and 23J631's (14.8.9) for the Sonoma build, which 14.8.8 matches too, plus two 14.8.7 sites from 0.7.0-alpha.2. 26.7.2 (25G332) matches 26.7.3 except at its extendedConnection site, whose bytes get their own, longer pattern: the window covers the instructions on either side, so it identifies that build by itself. Each set is tried on every page, and only matches its own build. The four sites and the edits are the same on every build (a fifth, the duplicate filter, is patched only with `-btleadvnodupfilter`); only addresses and, on Sequoia, two vtable slots and one struct offset differ. On another build the patterns may not match, and then nothing is changed. `tools/compat/check_compat.sh` reports whether they match a tester's `bluetoothd`.

The bonding fix was tested on macOS 26.7.2 (25G332) with an Intel Wi-Fi 6 AX200 (PCI 8086:2723, Bluetooth function USB 8087:0029) on a MacBookPro16,4 SMBIOS, running this plugin with IntelBTPatcher disabled: a new Bluetooth LE mouse bonds, and bluetoothd stays stable afterwards. Reports for other Intel cards are welcome.

### 6. Country and channels 149 and 44

Apple's AWDL uses channel 6 on 2.4 GHz and one 5 GHz channel, 149 or 44, which each device picks by its own country rules. From 0.6.0 the listener follows the iPhone: the iPhone's channel sequence (in its sync frames) shows which 5 GHz channel it uses, and the listener takes 44 if the iPhone uses 44, otherwise 149 (`ITLAWDLCoexPeer5GHz`). Slots the iPhone gives to its own Wi-Fi network aren't counted. Before any iPhone is heard, the listener starts on 149.

Intel firmware starts in world mode, where these channels are listen-only. It opens them after it learns the country from a nearby network's beacons, if that country's rules allow it. The driver asks the firmware and follows its answer, with two exceptions where the firmware marks a channel passive (China's 149 to 161, Japan's 36 to 48, for example):
- **Beacon hint** (`ITLAWDLCoexBeaconHints`): the driver treats the channel as usable once it has received a beacon from a Wi-Fi network on it. Linux's cfg80211 has the same mechanism but applies it only while no country is known (and iwlwifi, whose firmware manages the country, doesn't use it). ForbiddenItlwm also applies it after a country is learned, so it is broader than Linux; without that, the listener would stay on channel 6 in China. Hints a new country doesn't allow are cleared. Beacons aren't authenticated, so anything that sends one on the channel counts, as it does for the firmware's own passive-channel rule.
- **Beside a connection** (`ITLAWDLCoexIrConcurrent`): if the firmware marks the channel usable for concurrent operation, the listener may use it while the Mac's own Wi-Fi is connected on a channel in the same group (36–48, 52–64, 100–144, 149–165). This is Linux's relaxed rule for Wi-Fi Direct (P2P) interfaces, which iwlwifi turns on; the AWDL listener is the closest equivalent to such an interface. Without either, the listener uses channel 6, which works but is slow: the iPhone spends few slots there, and 2.4 GHz rates are low.

**Width beside the Mac's Wi-Fi.** On a real Mac the Wi-Fi's width doesn't set AirDrop's: its driver picks a channel and width the chip supports for each AirDrop slot, and the radio retunes for each slot. Up to 0.7.0-alpha.1, two cases differ here:
- **The Mac's Wi-Fi in the listener's 80 MHz block on another main channel** (157/80 beside 149, 36/80 beside 44): the listener uses 20 MHz (`ITLAWDLCoexOverlap` 1). With both at 80 MHz, one user's iPhone never saw the Mac ([#26](https://github.com/retropineaple/ForbiddenItlwm/issues/26)), while the firmware shared the radio by its own quota. With the listener at 20 MHz that wasn't seen. Why isn't known: a 20 MHz listener on 149 is still inside the Wi-Fi's 149–161 block, but it gives the firmware a different channel to manage.
- **The Mac's Wi-Fi at 160 MHz over the listener's channel** (40/160 covers 36–64, so 44): the listener avoids that channel (`ITLAWDLCoexOverlap` 2), after an AX201's Wi-Fi dropped during transfers with the listener inside (PR #21). With the scheduler in 0.7.0-alpha.1 this left macOS's channel unused ([#101](https://github.com/retropineaple/ForbiddenItlwm/issues/101)).

From 0.7.0-alpha.2, with `itlawdlsched=1`, both use 80 MHz, because the scheduler asks the firmware for each AirDrop slot instead of leaving it to the quota (section 3b). On the project's AX211 a listener on 44/80 beside Wi-Fi on 36/80 received on its own channel, with Wi-Fi at normal speed; the 160 MHz case was tested only with a simulated 160 MHz link. An 80+80 router link isn't modelled: the driver joins such a network at 20 MHz on its main channel, and a 20 MHz Wi-Fi link never narrows the listener, even inside its block.

### 7. Which macOS builds AirDrop starts on

Each macOS version has its own build (`tools/build.py --target tahoe|sequoia|sonoma`), with that version's IO80211 class declarations, and refuses to start on any other macOS version. `ForbiddenItlwm/AWDLBuildGuard.cpp` then decides once, at startup, and only lets AirDrop start when both of these hold:
- **The kernel is one whose Wi-Fi stack was verified.** Tahoe: 26.7.1 on hardware, and 26.7.2 and 26.7.3 offline (users have since reported both working). Sequoia: 15.8 and 15.8.3 offline (15.8.1 runs 15.8's kernel, 15.8.2 15.8.3's), and other 15.8.x kernels as "expected". Sonoma: 14.8.9 offline, with no "expected" range. From 0.7.0-alpha.2 also 26.7 (25G229) and 25G330, 15.8.1, both 15.8.2 builds, 15.7.3, 15.7.4, 15.7.8 and 15.7.9, and 14.8.3, 14.8.4, 14.8.7 and 14.8.8: their Kernel Debug Kits (or, for 15.7.8, 14.8.7 and 14.8.8, their installers' kernel collections) show the same six IO80211 tables, the same AirDrop, interface and buffer code (the 15.7.x builds and 26.7 differ in NAN code only), matching IOSkywalkFamily tables and every import present. From 0.7.0-alpha.3 also the 26.7.4 beta (25G422), from a user's `check-my-mac.pl` report instead of a Kernel Debug Kit: its IO80211Family code differs from 26.7.1's, but the six tables' sizes and names, the AWDL layouts the driver checks and every import match. The final 26.7.4 isn't covered. For 26.7.2 and 26.7.3, the Kernel Debug Kits showed the following matching 26.7.1:
  - IOSkywalkFamily is identical.
  - IO80211Family's AWDL, interface, buffer and registration code is instruction for instruction the same.
  - All 568, 505 and 461 slots of the three virtual tables match.
  - Every kernel symbol the driver imports exists.
- **Apple's `IO80211AWDLProtocol` table, read at runtime,** has the expected functions at anchor slots spread across it, its own pure methods where expected, and ends where expected (568 slots on Tahoe, 563 on Sequoia, 547 on Sonoma). This catches a changed table on any build.

When either fails, the driver behaves like plain AirportItlwm. `-itlawdlanybuild` skips the first check, never the second. The result is published as `ItlwmAWDLBuildCheck`. Two parts read data layouts the table check doesn't cover: copying macOS's AirDrop announcement (`-itlawdlmitx`), and, from 0.7.0-alpha.1, updating macOS's AirDrop packet counters. They need a verified pair: from 0.6.0-beta.1 both the kernel and the macOS build must be on the list (one kernel can ship with more than one IO80211Family). So:
- **Verified pair** (26.7.1, 26.7.2, 26.7.3, 15.8, 15.8.3, 14.8.9; from 0.7.0-alpha.2 also the builds above, and from 0.7.0-alpha.3 25G422): both run.
- **Allowed but not a verified pair:** an "expected" Sequoia kernel, or a listed kernel with an unlisted build (up to 0.7.0-alpha.1, 15.8.1 and 15.8.2, which run 15.8's and 15.8.3's kernels). AirDrop starts, but both stay off, and other devices may not list the Mac without the announcement. 0.7.0-alpha.2 puts 15.8.1 and 15.8.2 on the list.
- **`-itlawdlanybuild`:** from 0.6.0-beta.2 the announcement copy runs on an unknown kernel, with its pointer range-checked and the copy validated, at the risk the flag already carries. From 0.7.0-alpha.2 the flag covers every build the list doesn't verify as a pair (unknown, "expected" or listed kernel), and the packet counters run too, so the build works like a verified one. The counters reach the peer manager through macOS's own `IO80211SkywalkInterface::getPeerManager()` on every build, and write only if the object it returns has `IO80211AWDLPeerManager`'s vtable; otherwise they turn off and `ITLAWDLDataStats` says why.

**Sequoia differs from Tahoe in a few places the driver depends on.** The 15.8 and 15.8.3 Kernel Debug Kits (identical tables) showed:
- the same 63 AWDL protocol methods in the same order, with about ten base-class methods added or removed before them, and objects 16 bytes smaller
- `setMacAddress` pure in `IO80211SkywalkInterface` instead of `IO80211VirtualInterface`
- `IO80211Buffer` without virtual methods: the driver calls its exported functions directly on Sequoia
- the same Skywalk packet, queue and registration layouts, the same RX metadata layout (RSSI at offset 0x2c) and the same out-of-band request layout

**Sonoma 14.8.9 (test build) is the first target without WCL.** Its Wi-Fi stack is the older IO80211FamilyV2, as in upstream's Sonoma 14.4+ kext. The 23J631 Kernel Debug Kit showed:
- 62 AWDL protocol methods (no `setAWDL_CONFIG`), 547 slots in all, and the same object sizes as Sequoia
- an mbuf input and output path beside the Skywalk one, and no `setMacAddress` pure virtual
- the management frame pool on the virtual interface (`IO80211VirtualInterface::getMgmtFramePool`) rather than the controller
- the controller creates `awdl0` from slot 0xe00 (0xdd8 on Tahoe and Sequoia)
- the same Skywalk packet, pool, queue and registration layouts as Sequoia, the same RX metadata (RSSI at 0x2c) and the same out-of-band request layout
- joins go through the older handlers (`setASSOCIATE`, `setCIPHER_KEY`), which this release hardens

### 8. Link quality, and why it matters beyond AirDrop

macOS publishes each interface's link-quality metric as `State:/Network/Interface/en0/LinkQuality`. Apple Push (`apsd`) won't connect over an interface rated "off" (-2), and iMessage, FaceTime and the account-device lookups that AirDrop between your own devices relies on all need push.
- **The original problem:** the pre-Skywalk driver set the metric at link-up. On Tahoe that call was commented out, and `IO80211SkywalkInterface::setLQM` is an empty stub, so en0 stayed "off" forever. Sequoia's IO80211Family has the same stub, so the Sequoia build reports the metric too, and so does the Sonoma build, from its 1-second watchdog.
- **What ForbiddenItlwm does:** every 2 seconds while connected, it calls `IOSkywalkNetworkInterface::reportLinkQuality` (which sets the kernel's metric) from the signal strength: 100 at -70 dBm or stronger, 50 at -80 dBm or stronger, 10 below. It reports "off" when the link drops and, from 0.6.0-beta.1, when the driver stops.
- **It also tells WCL the signal (Tahoe only):** the signal strength goes into WCL's link-quality update (byte 0 valid, the RSSI at offset 4), which Apple's `handleLqmUpdate` reads. From 0.6.0-beta.1 ([PR #1](https://github.com/retropineaple/ForbiddenItlwm/pull/1)) the update also carries the noise floor and signal-to-noise (offsets 0x0b to 0x10) when the firmware has measured noise; some cards' firmware doesn't report it in normal Wi-Fi (the project's AX211 doesn't), and then those fields stay empty. That structure's layout is only known for Tahoe: checked on 26.7.2 and 26.7.3 for the noise fields.

## Why speed and connect time vary

- **Speed follows the iPhone's own Wi-Fi.** Its channel sequence gives AirDrop the slots its station doesn't need:
  - about 15 of 16 slots on the listener's channel (about 22 MB/s) when it isn't associated or is associated on 149
  - about 11 (15 MB/s) on a quiet network on another channel
  - about 7 (6 MB/s) on a busy one
- **Cold iPhone → Mac connects** spend their time in AWDL service discovery, before any data connection:
  - The iPhone and Mac exchange service records in action frames.
  - While the iPhone is idle it sits on the listener's channel in only a few slots, and the Mac's radio is often on the station's channel then.
  - Up to 0.6.0-beta.4 the firmware's time-sharing favoured the station while the listener was idle, and the Mac's Bluetooth saw the iPhone's link request only at the next scan restart, so cold connects took 3 to 10 s. With 0.7.0-alpha.1's experimental flags the scheduler (3b) gives the listener its slots on request and `-btleadvnodupfilter` removes the Bluetooth wait: on the project's hackintosh connects take about 1 to 2 s and the first send after the iPhone was idle no longer fails, even after long idle periods.

## Things worth knowing

These each took one or more test boots to learn.

- **AWDL services travel two ways:** as service-response records (TLV type 2) in MI frames, and as ordinary multicast mDNS over `awdl0`. Both matter for discovery, and which reaches the iPhone first decided the failed first send. In the TLVs, names are compressed (`c0 07` is `_airdrop._tcp.local`), so a text search misses them.
- **Peer creation needs real RSSI** in the frame metadata. With 0 there, the peer manager never adds the peer.
- **`awdl0` is receive-restricted.** Ordinary sockets can't receive on it, so `nc` and similar tools time out even when replies arrive. Judge connectivity with a packet capture.
- **Use `/usr/bin/log`.** In zsh, `log` is a built-in, so a bare `log show` prints nothing useful. `sharingd`, `rapportd`, `mDNSResponder` and `wifip2pd` logs show what AirDrop is doing.
- **The firmware gives a listener context group data only in promiscuous mode,** whatever the multicast filter says.
- **Cross-band retunes on a live binding crash the firmware.** Band changes are refused.
- **Firmware TX status depends on the frame:** for broadcasts it only means the frame left the queue.
- **ACKs must match the MAC context's address.** The listener carries the AWDL address so the firmware credits the peer's ACKs.
- **`LOW_LATENCY_CMD` fails on the AX211's firmware** and takes Wi-Fi down with it, so it is disabled.

## Source layout

| Path | Contents |
| --- | --- |
| `ForbiddenItlwm/AirportItlwmV2.cpp` | The macOS side: interface setup, Skywalk queues and pools, sync frame bridge, data in and out of `awdl0` |
| `ForbiddenItlwm/AirportAWDLInterface.hpp`, `AWDLInactiveProtocol.hpp`, `AWDLRequestedValue.hpp` | `ItlAWDLInterface` and its stored settings |
| `itlwm/hal_iwx/ItlIwx.cpp` | The radio side: the listener context, country handling, receive and transmit, Block Ack, the send gate |
| `include/AWDL*.hpp` | Frame parsing and building, data framing, peer schedule, election and session rules, regulatory rules. Mostly host-testable |
| `include/Airport/macOS26/` | Tahoe's native class declarations, for 25G241 |
| `include/Airport/macOS15/` | Sequoia's native class declarations, for 15.8 (24H23, 24H241) |
| `include/Airport/macOS14/`, `include/Airport/*.h` | Sonoma's AWDL declarations (generated from 23J631), and the non-WCL base classes it builds on |
| `BTLEAdvFixup/` | The Bluetooth LE advertising plugin |
| `tests/`, `tools/test_awdl.py` | Offline tests, many of them on real driver functions extracted into mocks |
| `tools/build.py`, `tools/sources.txt` | Command Line Tools build of `AirportItlwm.kext` |
| `tools/build_btleadv.py` | Build of `IntelBTPatcher.kext` from `BTLEAdvFixup/` sources |
| `tools/abi/` | The virtual table audit against 25G241 (Tahoe), 24H241 (Sequoia) and 23J631 (Sonoma) |
| `ForbiddenItlwm/AWDLBuildGuard.cpp`, `include/AWDLBuildGuard.hpp` | The macOS build check |
| `tools/awdl_*.py` | Readers for the driver's registry diagnostics |
| `tools/compat/` | Tester scripts |
| `tools/check-my-mac.pl`, `tools/gen_check_my_mac.py` | Collects, on a user's Mac, what's needed to support a new macOS build; the generator of its tables ([CHECK-MY-MAC](CHECK-MY-MAC.md)) |

Everything else (`itl80211`, `itlwm/hal_iwm`, `itlwm/hal_iwn`, `include/HAL`) is AirportItlwm's normal Wi-Fi driver.
