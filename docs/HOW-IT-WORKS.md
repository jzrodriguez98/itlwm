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
- its own PHY context on the 5 GHz channel the iPhone uses for AirDrop, 149 or 44 (from 0.6.0), at 80 MHz when allowed; channel 6 when neither is
- its own firmware station and transmit queue
- the AWDL address

The firmware time-shares the radio between the station's channel and the listener's. So normal Wi-Fi stays connected while AirDrop runs.

The listener is added once the Mac's Wi-Fi connection is up and removed when it disconnects, so AirDrop needs the Mac to be on a Wi-Fi network. From 0.6.0-beta.1 ([PR #12](https://github.com/retropineaple/ForbiddenItlwm/pull/12)) it is added only after the connection is fully set up, and removing it first waits for any setup still in progress.

- **Receive:** the driver picks AWDL action frames and data frames out of what the listener receives. It hands action frames to Apple's peer manager with real RSSI metadata, which the peer manager needs before it accepts a peer. IPv6 data goes into `awdl0`.
- **Transmit:** macOS's sync frames are built from Apple's template and sent every 110 TU. With `-itlawdlsvcmerge` its service records are merged in, and with `-itlawdlawsync` idle frames are timed to the iPhone's windows. `awdl0`'s IPv6 packets go out the listener's queue with AWDL data framing.

### 3. Following the iPhone's schedule

An iPhone doesn't stay on one channel. Its sync frames carry a 16-slot channel sequence, and on each slot it is on our channel, on its own Wi-Fi network's channel, or dozing.
- **Tracking:** `include/AWDLPeerSchedule.hpp` tracks that sequence and its timing. It assumes offset 0 until the iPhone's own frames prove otherwise.
- **The send gate:** frames for the iPhone go out only while it is on our channel. While it is idle, they go only at the start of its availability windows. Before the gate, frames sent while the iPhone was away were lost. The losses made QUIC slow itself down, so Mac → iPhone ran at a fraction of the link speed.
- **Peer pause:** while the iPhone is away, its firmware station queue is paused, so the firmware doesn't burn retries on it.

### 4. Speed: Block Ack and aggregation

With `-itlawdlcoexbatx` the driver negotiates Block Ack with the iPhone and lets the firmware send A-MPDU aggregates at VHT 80 MHz two-stream rates. Receive Block Ack works too. `-itlawdlcaps` advertises the matching capabilities, so the iPhone sends at the same rates.

The `awdl0` transmit pool is 2048 packets. With the 128 used during bring-up, long Mac → iPhone transfers ran the pool dry and stalled, because the flowswitch drops on allocation failure without telling QUIC.

### 5. Bluetooth: IntelBTPatcher (renamed BTLEAdvFixup)

`bluetoothd` only turns on extended LE advertising after chip checks that a third-party controller fails, so on an Intel controller the Mac never advertises AirDrop. BTLEAdvFixup is a small Lilu plugin that, with `-btleadv`:
- patches `bluetoothd`'s pages in memory as they're validated (the way BlueToolFixup does) to take the "supported" path
- keeps APFS's integrity check working on those pages (#62). The patches live in the copy of the file that macOS keeps in memory. `bluetoothd` is stored compressed, and APFS checks it in 16 KB blocks: when macOS drops one page of a block and reads it again, the check also covers the block's pages that are still in memory, patched, and fails, so `bluetoothd` crashed. BTLEAdvFixup keeps each patched page's original bytes (BlueToolFixup's too, since its hook runs around BlueToolFixup's) and hooks APFS's `apfs_vnop_verify`, the function decmpfs calls for this check, to give it a copy with the original bytes. The pages in memory are never changed by the check
- adjusts outgoing HCI commands, such as the random address of each advertising set, and takes over IntelBTPatcher's fix-up before the first scan (IntelBTPatcher must be disabled, since Lilu panics if two plugins hook the same function)
- takes over IntelBTPatcher's fix for new LE HID devices (a mouse, a keyboard) that connect but never finish bonding: the Intel controller never sends LE Data Length Change on Tahoe, so `bluetoothd` waits for it forever ("No database exists"). BTLEAdvFixup hooks the controller's interrupt IN pipe, sends every LE Read Remote Features command twice more, and rewrites the two duplicate completions into the PHY Update Complete and LE Data Length Change events `bluetoothd` is missing. Devices that are already bonded skip discovery and never trigger this.

Its byte patterns are exact bytes from specific `bluetoothd` builds: 25G241's (26.7.1) and 25G342's (26.7.3) for the Tahoe build, 24H241's (15.8.3) for the Sequoia build, which also match 15.8 (24H23) and 15.8.2 (24H232) unchanged, and 23J631's (14.8.9) for the Sonoma build. 26.7.2 (25G332) matches 26.7.3 except at its extendedConnection site, whose bytes get their own, longer pattern: the window covers the instructions on either side, so it identifies that build by itself. Each set is tried on every page, and only matches its own build. The four sites and the edits are the same on every build; only addresses and, on Sequoia, two vtable slots and one struct offset differ. On another build the patterns may not match, and then nothing is changed. `tools/compat/check_compat.sh` reports whether they match a tester's `bluetoothd`.

The bonding fix was tested on macOS 26.7.2 (25G332) with an Intel Wi-Fi 6 AX200 (PCI 8086:2723, Bluetooth function USB 8087:0029) on a MacBookPro16,4 SMBIOS, running this plugin with IntelBTPatcher disabled: a new Bluetooth LE mouse bonds, and bluetoothd stays stable afterwards. Reports for other Intel cards are welcome.

### 6. Country and channels 149 and 44

Apple's AWDL uses channel 6 on 2.4 GHz and one 5 GHz channel, 149 or 44, which each device picks by its own country rules. From 0.6.0 the listener follows the iPhone: the iPhone's channel sequence (in its sync frames) shows which 5 GHz channel it uses, and the listener takes 44 if the iPhone uses 44, otherwise 149 (`ITLAWDLCoexPeer5GHz`). Slots the iPhone gives to its own Wi-Fi network aren't counted. Before any iPhone is heard, the listener starts on 149.

Intel firmware starts in world mode, where these channels are listen-only. It opens them after it learns the country from a nearby network's beacons, if that country's rules allow it. The driver asks the firmware and follows its answer, with two exceptions where the firmware marks a channel passive (China's 149 to 161, Japan's 36 to 48, for example):
- **Beacon hint** (`ITLAWDLCoexBeaconHints`): the driver treats the channel as usable once it has received a beacon from a Wi-Fi network on it. Linux's cfg80211 has the same mechanism but applies it only while no country is known (and iwlwifi, whose firmware manages the country, doesn't use it). ForbiddenItlwm also applies it after a country is learned, so it is broader than Linux; without that, the listener would stay on channel 6 in China. Hints a new country doesn't allow are cleared. Beacons aren't authenticated, so anything that sends one on the channel counts, as it does for the firmware's own passive-channel rule.
- **Beside a connection** (`ITLAWDLCoexIrConcurrent`): if the firmware marks the channel usable for concurrent operation, the listener may use it while the Mac's own Wi-Fi is connected on a channel in the same group (36–48, 52–64, 100–144, 149–165). This is Linux's relaxed rule for Wi-Fi Direct (P2P) interfaces, which iwlwifi turns on; the AWDL listener is the closest equivalent to such an interface. Without either, the listener uses channel 6, which works but is slow: the iPhone spends few slots there, and 2.4 GHz rates are low.

### 7. Which macOS builds AirDrop starts on

Each macOS version has its own build (`tools/build.py --target tahoe|sequoia|sonoma`), with that version's IO80211 class declarations, and refuses to start on any other macOS version. `ForbiddenItlwm/AWDLBuildGuard.cpp` then decides once, at startup, and only lets AirDrop start when both of these hold:
- **The kernel is one whose Wi-Fi stack was verified.** Tahoe: 26.7.1 on hardware, and 26.7.2 and 26.7.3 offline (users have since reported both working). Sequoia: 15.8 and 15.8.3 offline (15.8.1 and 15.8.2 run those kernels), and other 15.8.x kernels as "expected". Sonoma: 14.8.9 offline, with no "expected" range. For 26.7.2 and 26.7.3, the Kernel Debug Kits showed the following matching 26.7.1:
  - IOSkywalkFamily is identical.
  - IO80211Family's AWDL, interface, buffer and registration code is instruction for instruction the same.
  - All 568, 505 and 461 slots of the three virtual tables match.
  - Every kernel symbol the driver imports exists.
- **Apple's `IO80211AWDLProtocol` table, read at runtime,** has the expected functions at anchor slots spread across it, its own pure methods where expected, and ends where expected (568 slots on Tahoe, 563 on Sequoia, 547 on Sonoma). This catches a changed table on any build.

When either fails, the driver behaves like plain AirportItlwm. `-itlawdlanybuild` skips the first check, never the second. The result is published as `ItlwmAWDLBuildCheck`. Copying macOS's AirDrop announcement (`-itlawdlmitx`) reads a data layout the table check doesn't cover, so it needs a verified build: from 0.6.0-beta.1 both the kernel and the macOS build must be on the list (one kernel can ship with more than one IO80211Family). It stays off on "expected" kernels, on an unlisted build with a listed kernel, and with `-itlawdlanybuild`.

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
  - about 15 of 16 slots on our channel (about 22 MB/s) when it isn't associated or is associated on 149
  - about 11 (15 MB/s) on a quiet network on another channel
  - about 7 (6 MB/s) on a busy one
- **Cold iPhone → Mac connects** spend their time in AWDL service discovery, before any data connection:
  - The iPhone and Mac exchange service records in action frames.
  - While the iPhone is idle it sits on our channel in only a few slots, and the Mac's radio is often on the station's channel then.
  - The current reading is that the firmware's time-sharing favours the station while the listener is idle. Improving this is the main open work.

## Things worth knowing

These each took one or more test boots to learn.

- **AWDL services travel in TLV type 2 in MI frames,** not as ordinary mDNS on the air. Names are compressed (`c0 07` is `_airdrop._tcp.local`), so a text search misses them.
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
| `include/AWDL*.hpp` | Frame parsing and building, data framing, peer schedule, regulatory rules. Mostly host-testable |
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

Everything else (`itl80211`, `itlwm/hal_iwm`, `itlwm/hal_iwn`, `include/HAL`) is AirportItlwm's normal Wi-Fi driver.
