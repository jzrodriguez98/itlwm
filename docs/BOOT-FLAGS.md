# Boot flags

AirDrop is off unless its flags are set, so with none of them ForbiddenItlwm behaves like AirportItlwm. The beta needs a long list of flags. They are the exact set used for every tested result. The Tahoe, Sequoia and Sonoma builds use the same flags. Simpler defaults are planned.

## The tested set

Add all of these to `boot-args`, on one line, separated by spaces:

```
-btleadv -itlawdlcoexprobe -itlawdliface -itlawdlnativeup -itlawdlcoexrx -itlawdlcoextx -itlawdlcoexmulti -itlawdlcoexdata -itlawdlmitx -itlawdlelicit -itlawdlcaps -itlawdlsvcmerge -itlawdlawsync itlawdlintcoal=4 -itlawdlcoexbatx -itlawdlcoexpeerpause -itlawdlcoexbatrace itlawdltxqueue=4096
```

What each one does:

| Flag | Effect |
| --- | --- |
| `-btleadv` | Turns this branch's IntelBTPatcher (renamed BTLEAdvFixup) on, so `bluetoothd` can start Bluetooth LE advertising on the Intel controller. `-btleadvoff` turns it off again |
| `-itlawdlcoexprobe` | Adds a second firmware context, the AWDL listener, beside the normal Wi-Fi station |
| `-itlawdliface` | Tells macOS the card can do AWDL and creates the `awdl0` interface |
| `-itlawdlnativeup` | Accepts the requests that let macOS's AWDL peer manager start |
| `-itlawdlcoexrx` | Hands the AWDL frames the listener hears to macOS |
| `-itlawdlcoextx` | Gives the listener its own firmware station and queue, and sends macOS's AWDL sync frames from it |
| `-itlawdlcoexmulti` | Puts the listener on its own channel: the one the iPhone uses for AirDrop (149, or 44 from 0.6.0), at 80 MHz when allowed, else 6. The firmware time-shares the radio between it and the station |
| `-itlawdlcoexdata` | Carries AirDrop's data through the listener, both ways |
| `-itlawdlmitx` | Sends macOS's own AWDL announcement (its name and services) in the sync frames. Only on verified macOS builds: `ItlwmAWDLMiState` says `on`, `off` or `blocked: build not verified` |
| `-itlawdlelicit` | Adds the extra AWDL fields Apple devices expect: election parameters, channel sequence and HT capabilities |
| `-itlawdlcaps` | Reports VHT and the card's spatial streams to macOS and to peers, so the iPhone uses 80 MHz rates. Two streams on two-antenna cards; from 0.6.0-beta.3, one on one-antenna cards such as the 9461, 9462 and AX101 (#87). `ItlwmCardStreams` shows what the driver found |
| `-itlawdlsvcmerge` | Merges macOS's service records into the announcement frames, which helps discovery |
| `-itlawdlawsync` | Times idle sync frames to the iPhone's availability windows |
| `itlawdlintcoal=4` | Shorter interrupt coalescing for the listener, for lower latency |
| `-itlawdlcoexbatx` | Outbound Block Ack and firmware aggregation. This is what makes Mac → iPhone fast |
| `-itlawdlcoexpeerpause` | Pauses the iPhone's firmware queue while its schedule has it away, so frames aren't wasted |
| `-itlawdlcoexbatrace` | Records Block Ack events in the I/O Registry for bug reports. Diagnostic only, cheap |
| `itlawdltxqueue=4096` | Size of the driver's own transmit queue for `awdl0` |

## Optional

| Flag | Effect |
| --- | --- |
| `itlawdltxpool=N` | Size of the `awdl0` transmit packet pool, 896 to 8192. Default 2048. Below that, long Mac → iPhone transfers can stall |
| `-itlawdlanybuild` | Starts AirDrop on a macOS build the driver hasn't verified. **Risk of a kernel panic.** Only for testing a new build, from a USB stick. From 0.6.0-beta.2 it also turns on the announcement (`-itlawdlmitx`), so other devices can list the Mac and AirDrop can really be tested; before, it stayed off there and nothing was listed. `ItlwmAWDLMiState` then reads "on (unverified build, -itlawdlanybuild)". It doesn't override the check of Apple's AWDL function table |
| `itlawdlbtcoex=N` | Forces firmware Bluetooth coexistence mode N (0 off, 1 NW, 2 BT, 3 Wi-Fi). From 0.6.0-beta.4, mode 1 (NW, with SYNC2SCO, HIGH_BAND_RET and MPLUT when the firmware has it, as Linux) is the default; it once fixed choppy Bluetooth audio during AirDrop as `itlawdlbtcoex=1`. Other modes are sent without modules. `ITLAWDLBtCoexMode` and `ITLAWDLBtCoexModules` show what was sent |
| `itlwm_scanout=N` | Longer off-channel visits for full scans while connected, N from 120 to 480 TU. By default each visit is capped at 120 TU, which fits one passive (DFS) channel before the 120 TU back home, so a full 5 GHz scan while connected can take 8–14 s and the Wi-Fi menu and Settings panel wait on it. 240–360 brought it to about 4.7 s on an AX210; 480 was slower. The 120 TU home time, low-latency scans and scans while not connected are unchanged. `ItlwmScanMaxOutTU` shows the value in use (#64) |
| `itlwm_lqmint=N` | Posts a link-quality update only when the signal moves by 3 dB or more, or after N seconds (1 to 60). By default it's every 2 s plus every 8th beacon, which makes macOS announce a signal change about 1.7 times a second. macOS takes the link's signal only from these updates, so check that `printf 'show State:/Network/Interface/en0/LinkQuality\n' \| scutil` (your Wi-Fi interface) stays at 100 and that iMessage works. `ItlwmLqmMinIntervalSec` and `ItlwmWCLLqmSuppressed` show the setting and the updates held back (#64) |
| `-itllog` | From 0.6.0: keeps the driver's own log and publishes it as `ITLAWDLLog`, so a failed wake or a firmware restart can be read back afterwards. It's hex: `ioreg -l -w0 \| grep '"ITLAWDLLog"' \| sed 's/.*<//; s/>.*//' \| xxd -r -p`. **It can hold network names and addresses**: check it before posting. While it is set, any app on this Mac can read the log. From 0.6.0-beta.1 the driver no longer writes network names or EAPOL handshakes into it, and Wi-Fi addresses (MAC, BSSID) appear only as their last two bytes. Turn it off once you have what you need |
| `-itlawdlsamples` | Publishes raw frame samples in the I/O Registry for debugging. **They can hold device names and addresses.** Never share them publicly, and don't leave the flag on |

## Comparison flags

These restore earlier behaviour, for A/B testing only. Leave them off.

| Flag | Effect |
| --- | --- |
| `-itlawdlcoexnogate` | Turns off the send gate, which holds frames for the iPhone while its schedule has it away |
| `-itlawdlcoexcalwait` | Waits for a 300-frame calibration of the iPhone's schedule instead of assuming it straight away |
| `-itlawdlsameband` | Test (0.5.2): while the Mac's Wi-Fi is on 2.4 GHz, keep the listener on channel 6 instead of 149, so the radio doesn't time-share across bands. For setups where Wi-Fi keeps dropping with `-itlawdlcoexmulti` (#16) |
| `-itlawdlsta44` | Test: while the Mac's own Wi-Fi is on channel 44 and the other device is seen on 44 too, keep the listener on 44 (at 80 MHz when allowed) instead of following the other device's 149 slots. For setups where the listener moves between 44 and 149 every few seconds (#68): the router on 44, and the other device on the same network. Confirmed with a MacBook Air M1 on an AX200; not tested with iPhones |
| `-itlawdlnosamechprobe` | Turns off the same-channel fix for Mac → iPhone block ack ([PR #47](https://github.com/retropineaple/ForbiddenItlwm/pull/47)), on by default from 0.6.0. The old opt-in flag `-itlawdlcoexsamechprobe` is still accepted and changes nothing |
| `-itlawdlfilterbysession` | Keeps the listener's promiscuous receive off only during a receive block-ack session, as before 0.6.0 (PR #57). From 0.6.0 it stays off while the iPhone's firmware station exists, which fixed stalled sends after the iPhone was idle. From the next release that applies only with `-itlawdlcoexmulti`; without it (the listener sharing the station's channel) the old rule is used, since the new one stopped Mac → iPhone there (#63), so this flag is then only needed with `-itlawdlcoexmulti` |
| `-itlawdlnosearch6` | Turns off the search on channel 6: while no device's schedule has been heard, the listener spends 15 s of every minute on 6 to find a device that uses only 44 (#35). From the next release |
| `-itlawdlnoirconcurrent` | Doesn't use passive channels next to the Mac's own Wi-Fi (0.6.0's rule, taken from Linux's rule for Wi-Fi Direct interfaces) |
| `-itlawdloverlap80` | Uses 80 MHz on the listener's channel even when the Mac's Wi-Fi uses the same 80 MHz block with another main channel, as before 0.6.0 (#26) |
| `-itlawdlnosharedba` | Turns off block ack when the listener shares your Wi-Fi's channel (without `-itlawdlcoexmulti`), as before 0.5.4 |
| `itlawdlpooltype=N` | AirDrop packet pool type: 0 (quantum, Tahoe's default) or 1 (packet, the default on Sequoia and Sonoma from 0.5.1). Sequoia doesn't create `awdl0` with 0 |
| `-itlawdlcoexnoorder` | Lets short frames overtake a paused aggregate queue, as older builds did |
| `-itlawdlcoexbarefill`, `-itlawdlcoexawhold`, `-itlawdlcoexbafilterhyst`, `-itlawdlcoexawsync0` | Older experiments. No gain was measured |

## Diagnostics and upstream flags

Not needed for AirDrop. Listed so you know what they do if you find them in a guide.

| Flag | Effect |
| --- | --- |
| `-itlmccprobe` | Records what the laptop's ACPI methods report about the Wi-Fi country, in the I/O Registry. Diagnostic only |
| `-itlawdlpmdebug` | Asks macOS's AWDL peer manager for its debug flags. Diagnostic only |
| `-itlawdldatacopy` | Publishes `ItlwmAWDLDataCopyAttempts`/`Success`, a receive-copy probe from the bring-up. Diagnostic only |
| `-itlawdlpoolprobe` | Probes the `awdl0` packet pools once at start and publishes the result. Diagnostic only |
| `-btlenoscan` | The renamed IntelBTPatcher plugin: advertising fixes only, without the scanning changes. For comparison |
| `-btleadvdbg`, `-btleadvbeta` | Lilu's standard debug and beta switches for this branch's IntelBTPatcher plugin |
| `itlwm_he=1` | Wi-Fi 6 (802.11ax), from the upstream driver. Not tested here. One tester ran all their AirDrop tests with it without problems (#58); on another's AX201, Wi-Fi dropped as soon as an AirDrop started (#83), with a router using 160 MHz. Fixed in 0.6.0-beta.4; not tested here yet |
| `-novht`, `-noht40` | Upstream: no 802.11ac, or no 40 MHz on the Mac's own Wi-Fi |

## Don't use

- **`-itlawdlbaaskshared`** and **`-itlawdlhideinfra`** (0.5.3 test flags) were removed in 0.6.0 and are ignored. Neither helped.
- **`-itlawdlpeercctest`** (dedicated mode only): passes the country a nearby device states in its AWDL frames to the firmware. That device isn't authenticated, so this lets anyone nearby choose the radio's country rules. Development only.
- **`-itlawdlcoexlowlat`** is disabled in this build and ignored. On the AX211 the firmware rejected the low-latency command, and normal Wi-Fi went down with it.
- **The dedicated-mode test flags:** `-itlawdlrx` and the flags that build on it (`-itlawdlqueue`, `-itlawdl6`, `-itlawdloneshot`, `-itlawdlsyncprobe` and the other train and probe flags, `-itlawdlch149`, `itlawdlcc=`). They put the card in monitor mode, so normal Wi-Fi is down. They are kept for development.
- **Country overrides.** Nothing here changes the country's rules, and nothing should. (From 0.5.0 the driver uses channels the firmware marks passive once it has heard a network there; Linux does this only before a country is known. That needs no flag.) `itlwm_cc` only changes the code macOS displays. It doesn't open channel 149.
