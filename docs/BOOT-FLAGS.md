# Boot flags

The Tahoe, Sequoia and Sonoma builds use the same flags, except that WPA3 (`-itlwmwpa3`) and Wi-Fi 6 (`itlwm_he=1`) work only in the Tahoe and Sequoia builds. Which ones you need depends on the version you install: 0.7.0-alpha.2 turns AirDrop's tested set on by itself, while 0.7.0-alpha.1 and earlier need the whole set in `boot-args`.

## From 0.7.0-alpha.2

**AirDrop's Wi-Fi flags are on by default.** The tested set below (everything in it except `-btleadv`) is what the driver does without any flags, including `itlawdlintcoal=4` and `itlawdltxqueue=4096`. Only BTLEAdvFixup still needs its flag, so add this to `boot-args`:

```
-btleadv
```

- **Updating from an older release?** You don't have to change `boot-args`. Every flag of the old tested set is still read and changes nothing, so a leftover set works exactly like the defaults. A value you set yourself, such as `itlawdltxqueue=2048`, still wins.
- **From 0.7.0-alpha.4, Block Ack refill is part of the set** (`-itlawdlcoexbarefill`): after each Block Ack from the iPhone, the next frames go to the firmware straight away instead of at the driver's next pass. In tests here (AX211, Tahoe 26.7.1, 105 MB files, iPhone on 149), a development build with refill added took Mac → iPhone sends from 18.4 to 24.8 MB/s on average; the 0.7.0-alpha.4 code averaged about 27 MB/s, up to 33 MB/s. `-itlawdlnocoexbarefill` turns it off.
- **The experimental flags** (`itlawdlsched=1`, `-btleadvnodupfilter`, see [Experimental](#experimental)) are still off unless you add them.
- **To turn AirDrop off** and keep normal Wi-Fi, add `-itlawdloff`. It wins over every other AirDrop flag, old ones and the experimental ones included, and the driver then behaves like AirportItlwm. `ItlwmAWDLBuildCheck` says "off: -itlawdloff". It doesn't touch BTLEAdvFixup: with `-btleadv` still set, the Mac and the iPhone can still list each other over Bluetooth, but transfers fail. Leave out `-btleadv` too to turn AirDrop off completely.
- **To turn one flag of the set off,** add its name with `no` after `-itlawdl`: `-itlawdlnocoexmulti` turns `-itlawdlcoexmulti` off, for example. That wins over the flag itself. For troubleshooting only.
- **To go back to the old rule,** add `-itlawdlnodefaults`: then only the flags that are set count, and with none of them ForbiddenItlwm behaves like AirportItlwm. `ItlwmAWDLDefaults` in the I/O Registry says which rule is in use.
- **Before a macOS update,** boot without `-btleadv` and `-btleadvnodupfilter` as before (BTLEAdvFixup's own advice). The Wi-Fi defaults don't need to be turned off for an update.

## Up to 0.7.0-alpha.1: the tested set

AirDrop is off unless its flags are set, so with none of them ForbiddenItlwm 0.7.0-alpha.1 or earlier behaves like AirportItlwm. The tested set below is the one the project's results use, unless a result names other flags. From 0.7.0-alpha.2 these are the defaults (see above).

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
| `-itlawdlcoexmulti` | Puts the listener on its own channel: the one the iPhone uses for AirDrop (149, or 44 from 0.6.0), at 80 MHz when allowed, else at 20 MHz when the iPhone uses that channel, else 6. The firmware time-shares the radio between it and the station |
| `-itlawdlcoexdata` | Carries AirDrop's data through the listener, both ways |
| `-itlawdlmitx` | Sends macOS's own AWDL announcement (its name and services) in the sync frames. Only where both the kernel and the macOS build are on the verified list, or with `-itlawdlanybuild` on an unverified build (see Optional). `ItlwmAWDLMiState` says `on`, `off` or `blocked: build not verified` |
| `-itlawdlelicit` | Adds the extra AWDL fields Apple devices expect: election parameters, channel sequence and HT capabilities |
| `-itlawdlcaps` | Reports VHT and the card's spatial streams to macOS and to peers, so the iPhone uses 80 MHz rates. Two streams on two-antenna cards; from 0.6.0-beta.3, one on one-antenna cards such as the 9461, 9462 and AX101 (#87). `ItlwmCardStreams` shows what the driver found |
| `-itlawdlsvcmerge` | Merges macOS's service records into the announcement frames, which helps discovery |
| `-itlawdlawsync` | Times idle sync frames to the iPhone's availability windows |
| `itlawdlintcoal=4` | Shorter interrupt coalescing for the listener, for lower latency |
| `-itlawdlcoexbatx` | Outbound Block Ack and firmware aggregation. This is what makes Mac → iPhone fast |
| `-itlawdlcoexpeerpause` | Pauses the iPhone's firmware queue while its schedule has it away, so frames aren't wasted |
| `-itlawdlcoexbatrace` | Records Block Ack events in the I/O Registry for bug reports. Diagnostic only, cheap |
| `itlawdltxqueue=4096` | Size of the driver's own transmit queue for `awdl0` |

## Experimental

**Each flag below says which version added it;** older versions ignore it. They're off by default. Without them the driver uses its tested set, which is the default from 0.7.0-alpha.2 and changes between releases (from 0.7.0-alpha.4 it includes Block Ack refill, for example), so it doesn't behave exactly like any one older release. Add them on top of the tested set to try them, and say in your report that you did.

**What the scheduler needs.** Check `ioreg -l -w0 | grep '"ITLAWDLSchedSp"'`: it says whether the scheduler is running, and if not, why.
- **The card:** in 0.7.0-alpha.1, AX210-family cards only: the AX210, the AX211, the AX411 (AX1690i), and Intel CNVi cards on Alder Lake and newer boards. From 0.7.0-alpha.2, also the AX200 family: the AX200 and cards on Ice, Comet or Tiger Lake boards (AX201, AX101, 9560 class), whose firmware has the same session feature. The scheduler hasn't been tested on those cards yet, so please report your results. In 0.7.0-alpha.1 the flag still turns off the channel-6 search on them, so leave it off there with that release.
- **When the Mac's Wi-Fi and AirDrop share a channel** (for example a router on 149): in 0.7.0-alpha.1 the scheduler stays idle, doesn't visit channel 6, and the flag has still turned off the channel-6 search, so a device the Mac hasn't heard yet can take longer to find. From 0.7.0-alpha.2 it still makes macOS's channel-6 visits there; the radio is already on the shared channel for the rest, so only channel 6 needs a session, and the Mac advertises the shared channel as before. `ITLAWDLSchedSp` then says "shared channel: channel 6 only".
- **Your router's channel and width.** From 0.7.0-alpha.2 AirDrop keeps 80 MHz with your router in its 80 MHz block on another main channel, or at 160 MHz over AirDrop's channel ([#26](https://github.com/retropineaple/ForbiddenItlwm/issues/26), [#101](https://github.com/retropineaple/ForbiddenItlwm/issues/101)). It starts at 20 MHz there, and `ITLAWDLSchedSp` says "overlap waits for a session in this generation" until the scheduler has started a session. Then it moves to 80 MHz by the usual rules for a change: the choice has to hold for 60 s, with no AirDrop data for the last 30 s (the two run at the same time, and a transfer delays it). `ITLAWDLCoexOwnWidth` shows the width in use. If AirDrop can't use the channel macOS picked, the scheduler pauses ("paused: macOS wants 44, listener on 149") and AirDrop works as in 0.6.0-beta.4.
- **A few seconds to start.** It waits until AirDrop has been on for 3 s, macOS has sent its plan, the listener has settled, and the start delay has passed. macOS itself sometimes turns AirDrop on late, so `itlschedstartdelay=0` doesn't make it start at once.
- **Few firmware restarts.** It resumes after the first two firmware restarts in a boot and stops at the third ("stopped: too many firmware restarts") until the next boot.

| Flag | Effect |
| --- | --- |
| `itlawdlsched=1` | From 0.7.0-alpha.1: the AirDrop scheduler. The driver follows macOS's AirDrop plan, channel and clock, much as a real Mac does, and covers the channel-6 slot itself ([HOW-IT-WORKS](HOW-IT-WORKS.md#3b-new-in-070-alpha1-following-macoss-plan-itlawdlsched1-experimental)). On the project's hackintosh it fixes the failed first send after the iPhone was idle. It turns off the channel-6 search (`-itlawdlnosearch6`), which it no longer needs, even on a card where the scheduler can't run (see above). From 0.7.0-alpha.2 it also keeps AirDrop at 80 MHz beside a router in the same 80 MHz block or at 160 MHz (see above; `-itlschedoldoverlap` turns that off) |
| `itlawdlsched=3` | The scheduler plus its diagnostics: more I/O Registry keys under `ITLAWDLSched*`, firmware crash records in `ITLFwCrashRecords` (from 0.7.0-alpha.3 also the full raw tables in `ITLFwCrashRaw`), counts of AirDrop frames lost before reaching macOS, and `-itlawdlpmdebug`. For bug reports |
| `itlschedlead=N` | With the scheduler: how early, in µs, the driver asks the firmware for each of macOS's slots (1000 to 20000, default 12000) |
| `itlschedstartdelay=N` | With the scheduler: the minimum seconds it waits after AirDrop starts (0 to 60, default 3). It also waits for the conditions above, so 0 doesn't mean at once |
| `-itlawdlmultipeer` | From 0.7.0-alpha.2, untested with more than one Apple device: every Apple device that asks to send to the Mac with Block Ack gets its own firmware station and receive sessions (one per free station the firmware has, up to 12; 11 on an AX211), instead of being refused while another device holds the driver's one station ([#81](https://github.com/retropineaple/ForbiddenItlwm/issues/81), [#45](https://github.com/retropineaple/ForbiddenItlwm/issues/45)). So several devices can send to the Mac at full speed. Sending from the Mac is aggregated to each of them too: a device the Mac sends a lot to gets its own aggregation queue and Block Ack agreement, and its frames keep their order. Each device's own schedule, from its sync frames, pauses its queue while it is away from the channel and makes frames sent singly wait for its availability window, as for the first device. A device that has exchanged nothing for about a minute gives its station back. `ITLAWDLCoexPeers` shows each slot. If you try it with two or more Apple devices, please report how it went |
| `-itlawdlamsdurx` | From 0.7.0-alpha.3: when an Apple device asks to pack several packets into one frame (A-MSDU) for its transfer to the Mac, the driver agrees, as a real Mac's receiver can. The card unpacks such frames itself. Tested with one iPhone, which asked every time; no clear speed change yet. `ITLAWDLAmsduRx` shows requests, answers and packed pieces received. The Mac packs its own frames only with `-itlawdlamsdutx` (below). Please report your iPhone → Mac speed with and without it |
| `-itlawdlamsdutx` | From 0.7.0-alpha.4: the Mac packs two packets into one frame (A-MSDU) when it sends to an Apple device that agreed to it, and the firmware turns it on for that device. Packing only happens when two frames for the same device are waiting; otherwise frames go one at a time as before. Tested here with one iPhone: hundreds of thousands of packed frames with no firmware crash, but no clear speed change, since frames already go out in groups (A-MPDU). `ITLAWDLAmsduTx` shows what happened |
| `-itlschednosecond` | From 0.7.0-alpha.4, `itlawdlsched=1` also covers a second 5 GHz AirDrop channel, as a real Mac's radio does ([#45](https://github.com/retropineaple/ForbiddenItlwm/issues/45)): when macOS's plan names one beside the main channel (for example 44, for a nearby device that can't use 149), the listener switches there in those slots and back, sends to the devices that are there, tells other devices it's there, and answers their Block Ack requests. Frames for devices on the main channel wait during those slots. With only devices on 149 nearby, macOS's plan has no second channel and nothing changes. This flag turns it off and keeps the listener on the main channel, as in alpha.3. `ITLAWDLSchedSecond` shows the switches. Tested here only with a simulated second channel (see `itlsimsecond` below), not yet with a real device on 44. The test flags `-itlschedsecond`, `-itlschedsecondtx` and `-itlschedsecondsync` from the development builds are still read and turn their parts on without the scheduler set |
| `-btleadvnodupfilter` | From 0.7.0-alpha.1 (BTLEAdvFixup 0.9.5): BTLEAdvFixup turns off `bluetoothd`'s scan duplicate filter, so the Mac notices at once when the iPhone asks for a link, instead of up to about 10 s later |

## Optional

| Flag | Effect |
| --- | --- |
| `-itlwmwpa3` | Tahoe and Sequoia builds only. Opt-in WPA3-Personal (SAE/H2E, PMF) on iwx. Without it WPA2 behaviour. Mixed WPA2/WPA3 networks whose AP doesn't offer H2E still join as WPA2; WPA3-only APs without H2E (hunting-and-pecking only) can't be joined. With the flag, WPA2 networks that offer protected management frames use them too. The Sonoma build has no SAE join: there, mixed WPA2/WPA3 networks join as WPA2 and WPA3-only networks can't be joined |
| `itlawdltxpool=N` | Size of the `awdl0` transmit packet pool, 896 to 8192. Default 2048. Below that, long Mac → iPhone transfers can stall |
| `-itlawdlpeerhandoff` | From 0.7.0-alpha.2 ([PR #50](https://github.com/retropineaple/ForbiddenItlwm/pull/50)): when another Apple device asks for a Block Ack session while the device that holds the driver's one receive session has gone idle, the driver hands the session over once the idle device's queues have drained. Helps when a nearby Mac or iPad keeps an iPhone waiting ([#81](https://github.com/retropineaple/ForbiddenItlwm/issues/81)). Off by default; `ITLAWDLCoexPeerHandoff*` show what it did. Please report your result |
| `-itlawdloff` | From 0.7.0-alpha.2: turns AirDrop off, whatever other flags are set; normal Wi-Fi works as with AirportItlwm. `ItlwmAWDLBuildCheck` reads "off: -itlawdloff". Useful to tell a Wi-Fi problem from an AirDrop one |
| `-itlawdlanybuild` | Starts AirDrop on a macOS build the driver hasn't verified. **Risk of a kernel panic.** Only for testing a new build, from a USB stick. From 0.6.0-beta.2 it also turns on the announcement (`-itlawdlmitx`), so other devices can list the Mac and AirDrop can really be tested; before, it stayed off there and nothing was listed. `ItlwmAWDLMiState` then reads "on (unverified build, -itlawdlanybuild)". From 0.7.0-alpha.2 it makes any build the list doesn't cover work like a verified one, including a listed kernel on an unlisted build and an "expected" Sequoia kernel: the announcement copy and the AirDrop packet counters both run, each behind a runtime check (the announcement's pointer and contents; the counters only once macOS's `getPeerManager()` returns a real `IO80211AWDLPeerManager`). The scheduler runs as on a verified build. It doesn't override the check of Apple's AWDL function table, and it doesn't affect BTLEAdvFixup, whose patterns must match the build's `bluetoothd` |
| `itlawdlbtcoex=N` | Forces firmware Bluetooth coexistence mode N (0 off, 1 NW, 2 BT, 3 Wi-Fi). From 0.6.0-beta.4, mode 1 (NW, with SYNC2SCO, HIGH_BAND_RET and MPLUT when the firmware has it, as Linux) is the default; it once fixed choppy Bluetooth audio during AirDrop as `itlawdlbtcoex=1`. Other modes are sent without modules. `ITLAWDLBtCoexMode` and `ITLAWDLBtCoexModules` show what was sent |
| `itlwm_scanout=N` | Longer off-channel visits for full scans while connected, N from 120 to 480 TU. By default each visit is capped at 120 TU, which fits one passive (DFS) channel before the 120 TU back home, so a full 5 GHz scan while connected can take 8–14 s and the Wi-Fi menu and Settings panel wait on it. 240–360 brought it to about 4.7 s on an AX210; 480 was slower. The 120 TU home time, low-latency scans and scans while not connected are unchanged. `ItlwmScanMaxOutTU` shows the value in use (#64) |
| `itlwm_lqmint=N` | Posts a link-quality update only when the signal moves by 3 dB or more, or after N seconds (1 to 60). By default it's every 2 s plus every 8th beacon, which makes macOS announce a signal change about 1.7 times a second. macOS takes the link's signal only from these updates, so check that `printf 'show State:/Network/Interface/en0/LinkQuality\n' \| scutil` (your Wi-Fi interface) stays at 100 and that iMessage works. `ItlwmLqmMinIntervalSec` and `ItlwmWCLLqmSuppressed` show the setting and the updates held back (#64) |
| `-itllog` | From 0.6.0: keeps the driver's own log and publishes it as `ITLAWDLLog`, so a failed wake or a firmware restart can be read back afterwards. It's hex: `ioreg -l -w0 \| grep '"ITLAWDLLog"' \| sed 's/.*<//; s/>.*//' \| xxd -r -p`. **It can hold network names and addresses**: check it before posting. While it is set, any app on this Mac can read the log. From 0.6.0-beta.1 the driver no longer writes network names or EAPOL handshakes into it, and Wi-Fi addresses (MAC, BSSID) appear only as their last two bytes. Turn it off once you have what you need |
| `-itlawdlsamples` | Publishes raw frame samples in the I/O Registry for debugging. **They can hold device names and addresses.** Never share them publicly, and don't leave the flag on |

## Comparison flags

These restore earlier behaviour, for A/B testing only. Leave them off.

| Flag | Effect |
| --- | --- |
| `-itlawdlnodefaults` | From 0.7.0-alpha.2: the tested set isn't on by default any more, only the flags that are set count, as up to 0.7.0-alpha.1. With no AirDrop flags the driver then behaves like AirportItlwm |
| `-itlawdlcoexnogate` | Turns off the send gate, which holds frames for the iPhone while its schedule has it away |
| `-itlawdlcoexcalwait` | Waits for a 300-frame calibration of the iPhone's schedule instead of assuming it straight away |
| `-itlawdlsameband` | Test (0.5.2): while the Mac's Wi-Fi is on 2.4 GHz, keep the listener on channel 6 instead of 149, so the radio doesn't time-share across bands. For setups where Wi-Fi keeps dropping with `-itlawdlcoexmulti` (#16) |
| `-itlawdlsta44` | Test: while the Mac's own Wi-Fi is on channel 44 and the other device is seen on 44 too, keep the listener on 44 (at 80 MHz when allowed) instead of following the other device's 149 slots. For setups where the listener moves between 44 and 149 every few seconds (#68): the router on 44, and the other device on the same network. Confirmed with a MacBook Air M1 on an AX200; not tested with iPhones |
| `-itlawdlnosamechprobe` | Turns off the same-channel fix for Mac → iPhone block ack ([PR #47](https://github.com/retropineaple/ForbiddenItlwm/pull/47)), on by default from 0.6.0. The old opt-in flag `-itlawdlcoexsamechprobe` is still accepted and changes nothing |
| `-itlawdlfilterbysession` | Keeps the listener's promiscuous receive off only during a receive block-ack session, as before 0.6.0 (PR #57). From 0.6.0 it stays off while the iPhone's firmware station exists, which fixed stalled sends after the iPhone was idle. From 0.6.0-beta.3 that applies only with `-itlawdlcoexmulti`; without it (the listener sharing the station's channel) the old rule is used, since the new one stopped Mac → iPhone there (#63), so this flag is then only needed with `-itlawdlcoexmulti` |
| `-itlawdlnosearch6` | Turns off the search on channel 6: while no device's schedule has been heard, the listener spends 15 s of every minute on 6 to find a device that uses only 44 (#35). From 0.6.0-beta.3. `itlawdlsched=1` sets it |
| `-itlawdlnoirconcurrent` | Doesn't use passive channels next to the Mac's own Wi-Fi (0.6.0's rule, taken from Linux's rule for Wi-Fi Direct interfaces) |
| `-itlawdloverlap80` | Ignores the Mac's Wi-Fi channel when choosing the listener's width, as before 0.6.0: 80 MHz even in the same 80 MHz block on another main channel (#26) or inside a 160 MHz channel (PR #21), with or without the scheduler |
| `-itlschedoldoverlap` | From 0.7.0-alpha.2, with `itlawdlsched=1`: keeps the old rules beside your router (20 MHz in the same 80 MHz block, AirDrop's channel avoided inside a 160 MHz channel) instead of 80 MHz. It overrides `-itlsched80` (same block) and `-itlsched160` (inside 160 MHz), which turn the new behaviour on one part at a time and are both part of `itlawdlsched=1` |
| `-itlawdlnosharedba` | Turns off block ack when the listener shares your Wi-Fi's channel (without `-itlawdlcoexmulti`), as before 0.5.4 |
| `itlawdlpooltype=N` | AirDrop packet pool type: 0 (quantum, Tahoe's default) or 1 (packet, the default on Sequoia and Sonoma from 0.5.1). Sequoia doesn't create `awdl0` with 0 |
| `-itlawdlcoexnoorder` | Lets short frames overtake a paused aggregate queue, as older builds did |
| `-itlawdlcoexawhold`, `-itlawdlcoexbafilterhyst`, `-itlawdlcoexawsync0` | Older experiments. No gain was measured |
| `-itlawdlnocoexbarefill` | Turns off Block Ack refill (on by default from 0.7.0-alpha.4), so frames reach the firmware only at the driver's next pass, as before |

## Diagnostics and upstream flags

Not needed for AirDrop. Listed so you know what they do if you find them in a guide.

| Flag | Effect |
| --- | --- |
| `-itlmccprobe` | Records what the laptop's ACPI methods report about the Wi-Fi country, in the I/O Registry. Diagnostic only |
| `-itlawdlpmdebug` | Asks macOS's AWDL peer manager for its debug flags. Diagnostic only. `itlawdlsched=3` sets it |
| `-itlawdldatacopy` | Publishes `ItlwmAWDLDataCopyAttempts`/`Success`, a receive-copy probe from the bring-up. Diagnostic only |
| `-itlawdlairtime` | From 0.7.0-alpha.4: measures where the time goes while the Mac sends to the iPhone (Mac not on AirDrop's channel, iPhone away, nothing to send, held back, frames waiting with the firmware's queue empty, queued) and publishes it as `ITLAWDLAirtime`. Diagnostic only; changes nothing about sending |
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
