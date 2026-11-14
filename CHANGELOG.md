# Changelog

## 0.5.4-beta.2

- **BTLEAdvFixup 0.9.1: new Bluetooth LE mice and keyboards pair again ([#27](https://github.com/retropineaple/ForbiddenItlwm/issues/27), [#31](https://github.com/retropineaple/ForbiddenItlwm/pull/31), thanks to CreateRan).** With IntelBTPatcher disabled, a new LE mouse or keyboard connected but never finished pairing, because BTLEAdvFixup didn't include IntelBTPatcher's fix for it. It does now, including lshbluesky's LE Data Length Change fix for Tahoe. Devices that were already paired weren't affected.
- **BTLEAdvFixup 0.9.1 also patches a second spot in macOS 26.7.2's `bluetoothd`** (25G332), whose bytes differ from 26.7.3's there.
- The Wi-Fi driver is the same code as 0.5.4-beta.1; only its build name changed.
- **Tested on the project's hackintosh** (Tahoe 26.7.1): BTLEAdvFixup 0.9.1 loads with all its hooks, Bluetooth and paired devices work, AirDrop at about 20 MB/s both ways. The pairing fix itself was tested by CreateRan on 26.7.2 with an AX200 (a new LE mouse pairs and stays connected).

## 0.5.4-beta.1

The first release with the new names: **beta** means everything in it was tested on the project's hackintosh. (Up to 0.5.3, `-test1` was used for what is now called alpha.)

- **laobamac's later fixes to the base driver ([#36](https://github.com/retropineaple/ForbiddenItlwm/pull/36), thanks to alikaylan).** The 21 commits laobamac made to itlwm/AirportItlwm after ForbiddenItlwm started, merged with their authorship kept. They mostly affect normal Wi-Fi:
  - transmit queues and TX completion handling, rate-control locking (laobamac #22), and queue checks for newer firmware;
  - joins: link authorization before RUN (laobamac #21), "fast lane" QoS requests, no VHT on 2.4 GHz, a clean fallback from invalid 160 MHz channels, and the last piece of the WPA2/WPA3 transition fix (mingww64);
  - scanning: macOS's scan timing, and passive channels no longer cut short during a scan while connected;
  - VT-d: only the bytes the card wrote are copied, and an unplugged card is detected properly;
  - macOS integration: native channel information, traffic counters and link quality for iMessage and other iServices.
- **Block ack without `-itlawdlcoexmulti` ([#16](https://github.com/retropineaple/ForbiddenItlwm/issues/16)).** When the AirDrop listener shares your Wi-Fi's channel (without `-itlawdlcoexmulti`, or when its own channel isn't available), the driver now answers the iPhone's block-ack requests. iPhone → Mac goes from about 1 MB/s to about 5 MB/s there. Mac → iPhone is still sent frame by frame in that setup, because the iPhone doesn't answer our request on that channel (#24). `-itlawdlnosharedba` turns it off, for comparison. `-itlawdlbaaskshared` now works there too.
- **Block-ack requests pause while AirDrop is idle.** After 30 s without data, the driver stops asking the iPhone for block ack, instead of asking for up to 10 minutes after a transfer. The next transfer starts asking again straight away. `ITLAWDLCoexBaTxIdleHolds` counts the pauses.
- **Tools:** `airdrop_measure.sh` shows the listener's width when it shares your Wi-Fi's channel. `check_compat.sh` recognises IntelBTUnified and warns that it can't be used with BTLEAdvFixup ([#32](https://github.com/retropineaple/ForbiddenItlwm/issues/32)).
- **Tested on the project's hackintosh** (Tahoe 26.7.1, AX211): Wi-Fi works, AirDrop at 17–24 MB/s iPhone → Mac and 21–26 MB/s Mac → iPhone. The Sequoia and Sonoma builds are built and checked offline, as before.
- BTLEAdvFixup is unchanged (0.9.0).

## 0.5.3-test1 (test build)

Two test flags for slow Mac → iPhone transfers (#22, #24). When the Mac's own Wi-Fi is on the same channel as the AirDrop listener (usually 149), the iPhone never accepts block ack, so frames go out one at a time. On any other channel it accepts within a second. These flags test two explanations; neither is on by default:

- **`-itlawdlbaaskshared`:** in that case, send the block-ack request without waiting for the iPhone's window. The driver's window check held back thousands of requests there. `ITLAWDLCoexBaAsksShared` counts the requests sent this way.
- **`-itlawdlhideinfra`:** leave the Mac's Wi-Fi network and channel out of AirDrop's sync frames (the infrastructure fields of the Data Path State TLV, as described by seemoo-lab/owl). The iPhone then sees a Mac that isn't on Wi-Fi. `ItlwmAWDLSyncInfraStripped` counts the frames changed.

Workaround until one of them becomes the default: put your router (or the Mac's network) on a channel other than the listener's, for example 36–48 or 157.

## 0.5.2-test1 (test build)

- **Channel 149 no longer lost to a passing world-mode country.** The card's firmware can briefly report its world code and then the same country again. The driver cleared its channel-149 beacon hints each time, so in China and Japan the listener fell back to channel 6 until it heard a network again (#21). The hints are now cleared only when a different country is learned.
- **New diagnostics for the open reports:**
  - `ITLAWDLCoexPeerSequence`: the iPhone's 16-slot channel schedule, while normal Wi-Fi is on (#21, #24). `…Frames` and `…Updates` count them.
  - `ITLAWDLCoexAddsAfterRemove` and `ITLAWDLCoexAddsAfterRestart`: why the listener was added again, after Wi-Fi reconnected or after a firmware restart, plus `ITLAWDLCoexFirmwareGeneration` (#16).
  - `ITLAWDLCoexCountryUnusableAnswers` and `ITLAWDLCoexHintClears`: how often the firmware's country drops to its world code, and how often hints are cleared.
- **`-itlawdlsameband` (test flag, #16):** while the Mac's Wi-Fi is on 2.4 GHz, keep the listener on channel 6 instead of time-sharing the radio across bands. Off by default until testers confirm it helps.
- **`tools/compat/airdrop_measure.sh`:** measures AirDrop speed and connect times in both directions from macOS's own AirDrop log, without a sysdiagnose.
- **`check_compat.sh`** knows 15.8.1 runs a verified kernel, and lists the AX201, AX200, AX210 and AX411 class as reported working.
- **Clearer diagnostic keys (#7).** `ITLAWDLCoexLastBuildResult` now resets after a successful frame build instead of keeping the error from before macOS sent its template. `ItlwmAWDLTransportReady` is gone: nothing ever set it, so it read No while AirDrop worked. `ItlwmAWDLDataCopyAttempts`/`Success` are only published with the `-itlawdldatacopy` probe.

## 0.5.1-test1 (test build)

- **Sequoia: AirDrop transfers fixed (#7, #13, #16).** The driver created its AirDrop packet pools as "quantum" pools. Sequoia's kernel refuses those for a network interface, so `awdl0` was never created. Devices could see each other, but transfers stayed on "Waiting". The pools are now ordinary packet pools, as Apple's own drivers use. Found by liszsw241 in #19, who confirmed AirDrop both ways on 15.6 with this change. The 0.5.0 diagnostics on 15.8.1 and 15.8.2 point to the same failure. Not yet confirmed on 15.8.x itself.
  - The Sonoma build gets the same change: Sonoma's kernel treats these pools the same way. Tahoe is unchanged.
  - New key `ItlwmAWDLPoolType` (1 on Sequoia and Sonoma, 0 on Tahoe). `itlawdlpooltype=0`, `1` or `2` overrides it, for testing only.
- **`itlawdlbtcoex` now works beside normal Wi-Fi (#19).** It was only read in the old monitor test mode.
- BTLEAdvFixup is unchanged (0.9.0).

## 0.5.0-test1 (test build)

- **macOS Sonoma 14.8.9, as its own kexts.** A third pair of kexts, for Sonoma, beside Tahoe and Sequoia.
  - Built with `tools/build.py --target sonoma` and `tools/build_btleadv.py --target sonoma`.
  - Verified offline against Apple's Kernel Debug Kit for 14.8.9 (23J631): every virtual slot of the AirDrop interface (547 of 547), the Wi-Fi classes' tables, every kernel import, and the data layouts the AirDrop code reads.
  - **AirDrop starts only on 14.8.9.** It's the only Sonoma installer Apple still offers, and the only build checked. On other Sonoma 14.4+ builds the kext is plain Wi-Fi.
  - **iMessage and push over Wi-Fi:** the link-quality fix from 0.2.0 now works on Sonoma too. Upstream's Sonoma release notes say iMessage doesn't work there out of the box.
  - **BTLEAdvFixup 0.9.0** has a Sonoma build, with `bluetoothd` patterns from Apple's 14.8.9 installer.
  - **Not tested on any hardware yet,** not even plain Wi-Fi. Testers wanted.
- **Tested on the project's hackintosh (Tahoe 26.7.1, AX211):** the Tahoe build starts, and Wi-Fi, Bluetooth and AirDrop both ways work as before. The Sequoia and Sonoma builds and the fix for #14 and #16 still need testers.
- **Sonoma uses older driver code for joining networks.** Those parts are fixed for this release: the key handler no longer writes Wi-Fi keys to the log, and it checks every length and index.
- **Sequoia Bluetooth patterns checked on more builds.** BTLEAdvFixup's Sequoia patterns, taken from 15.8.3, also match `bluetoothd` from Apple's 15.8 and 15.8.2 installers, unchanged. 15.8.1 wasn't checked.
- **`check_compat.sh`** recognises Sonoma 14.8.9 and checks its Bluetooth patterns.
- **Fixed: Wi-Fi didn't start on some machines with 0.4.0 and 0.4.1 (#14, #16).** 0.4.0 read the card's MSI settings from the wrong place, so on some machines the driver stopped right after starting and Wi-Fi stayed off or greyed out. 0.3.x wasn't affected.
- **Channel 149 where the firmware marks it passive (#11, #15).** In some countries (China, for example) the card's firmware marks channels 149 to 161 as passive, so the AirDrop listener fell back to channel 6 at 20 MHz. Now, as on Linux, once the hackintosh has heard a Wi-Fi network's beacon on those channels, the listener can use 149 at 80 MHz. These hints are cleared when the country changes.
  - New keys: `ITLAWDLCoexBeaconHints`, and `ITLAWDLCoexBaTxStateName`, which names the block-ack state (`asking` isn't `agreed`).
- **Firmware messages are length-checked on every card family.** Before reading a message from the card's firmware, the driver checks it fits: AX200 and newer, the 7000 to 9000 series, and the older 1000 to 6000 series. The build also adds a stack protector and zero-fills local variables.
- **Diagnostics for open reports:**
  - **#7 and #13 (no `awdl0` on Sequoia):** the AirDrop interface records who opens and closes it in `ItlwmAWDLClientEvents`. On Sequoia it also records when `awdl0` is created and removed.
  - **#14 and #16 (Wi-Fi doesn't start):** if the driver fails to start, its messages stay on the Wi-Fi card's PCI entry as `ItlwmStartLog`, with `ItlwmStartResult`. Before, they were lost.
- **Docs:** the OpenCore entries an old OCLP Wi-Fi setup leaves behind (#14) are now in the README requirements; troubleshooting for a driver that doesn't start, for Sequoia transfers that stay on "Waiting", and for leftovers from older AirportItlwm setups; current user reports.

## 0.4.1-beta1

- **Sequoia: BTLEAdvFixup now actually starts.** Every earlier Sequoia build of BTLEAdvFixup told Lilu it was for Tahoe, and Lilu disables a plugin on any other macOS. So on Sequoia it never ran: `bluetoothd` wasn't patched, the IntelBTPatcher replacement wasn't active, and iPhones couldn't find the hackintosh over Bluetooth. BTLEAdvFixup 0.8.3 declares the macOS version it's built for. Sequoia users should update BTLEAdvFixup; the Tahoe build behaves as before.
- **Nothing else changed.** ForbiddenItlwm is rebuilt from the same code with the new version number.

## 0.4.0-beta1

Everything from the 0.3.1-test1 test build (below), plus:

- **Security fixes.** A review of the driver found these, and they're fixed:
  - **Wi-Fi password handshake (WPA/WPA2):** a length check in the handshake code could be fooled by a malformed message, letting a malicious access point, or anyone who knows the network's password, corrupt kernel memory. This code comes from itlwm and OpenBSD.
  - **An old join function** copied network name and key lengths without checking them. Normal joins don't use it, but it now refuses anything that doesn't fit.
  - **The AirDrop announcement copy (`-itlawdlmitx`)** now only runs on macOS builds whose data layout was verified, so it stays off with `-itlawdlanybuild` and on unverified Sequoia versions (`ItlwmAWDLMiState` shows which). It only keeps data that looks like a real announcement. With `-itlawdlsamples`, a kernel address is no longer published in the I/O Registry.
  - **Memory and shutdown:** two memory leaks on rejected Wi-Fi frames, packets not handed back when the AirDrop interface stops, power callbacks that could run after the driver stopped, a use-after-free after a failed start, and a once-a-second health check (the watchdog) that ran without the driver's lock.
  - **One card only:** a second supported Intel Wi-Fi card is now left alone instead of corrupting the first one's state.
- **WPA2/WPA3 networks rejoin after a reboot.** Networks offering WPA2, PSK-SHA256 and WPA3 together were shown to macOS as WPA3, which the driver can't complete, so auto-join failed and macOS gave up on the whole network. They're now shown as WPA2, as with the original AirportItlwm, and the driver no longer picks PSK-SHA256 without protected management frames. Thanks to lucassaureliano (issue #9), alikaylan (issue #5) and mingww64, whose PR #1 carries the same fix.
- **BTLEAdvFixup 0.8.2:** its state is locked between threads; commands it adds time out after a second and are retried if they fail; it only acts on Intel Bluetooth controllers; and a removed advertising set no longer keeps its old random address. Its patterns also cover 26.7.2, whose `bluetoothd` matches 26.7.3's (thanks to ZEQ-Avidia, issue #8).
- **`check_compat.sh`:** no longer counts one Bluetooth pattern twice, which made it warn on 26.7.3 (issues #5, #8), and the listener check uses a more portable `grep`.
- **Removing BTLEAdvFixup before a macOS update:** an incremental update can fail while `bluetoothd` is patched (issue #8). Boot once without `-btleadv` before updating.
- **Tested** on the project's hackintosh (AX211, 26.7.1): WPA2 and open networks, AirDrop both ways, Bluetooth devices, Wi-Fi off and on, and restarts. Sleep wasn't tested.

## 0.3.1-test1 (test build)

- **AirDrop on setups that pad AWDL frames.** On some machines every AirDrop frame from the iPhone arrived with zero bytes after its last field, so the driver rejected all of them and transfers stayed on "Waiting". Seen on an AX211 (8086:51F1) in a ThinkPad E16 Gen 3 with an iPhone 16 Pro. The driver now cuts that padding, and only that: nothing but trailing zero bytes is removed, and only when the frame is otherwise invalid and parses without them. `ITLAWDLCoexZeroPadTrimmed` counts the frames fixed. Diagnosis and approach by keenerdavid18 (issue #6). Not tested on that hardware with this exact build yet.
- **BTLEAdvFixup 0.8.1 (Tahoe): macOS 26.7.3 support.** The Tahoe build now also carries `bluetoothd` patterns for 26.7.3 (25G342), taken from Apple's installer and verified offline. They're the same four patches as on 26.7.1. Not tested on hardware yet. Thanks to the issue #5 report, and to mingww64, whose PR #2 independently found three of the four sites.
- **`check_compat.sh`** finds discrete Wi-Fi cards behind a PCI root port (most desktops and M.2 slots). It used to report "No Intel Wi-Fi card found" for them. Thanks to alikaylan (issue #5) for the diagnosis. It also checks the 26.7.3 Bluetooth patterns.

## 0.3.0-beta1

- **macOS Sequoia 15.8.x support, as separate kexts.** Each macOS version now has its own ForbiddenItlwm and BTLEAdvFixup. Releases have Tahoe zips and Sequoia zips: use the ones for your macOS.
  - Built with `tools/build.py --target sequoia` and `tools/build_btleadv.py --target sequoia`.
  - Verified offline from Apple's Kernel Debug Kits for 15.8 (24H23) and 15.8.3 (24H241): every virtual table slot of the AirDrop interface (563 of 563) and every kernel import. 15.8.1 and 15.8.2 are expected to work: AirDrop starts there as "expected" if Apple's Wi-Fi tables still match at boot.
  - BTLEAdvFixup's Sequoia patterns are exact bytes from 15.8.3's `bluetoothd`. On 15.8 to 15.8.2 they may not match, and then iPhones may not list the Mac. `check_compat.sh` tells you.
  - It uses the Wi-Fi stack that ships with Sequoia, like laobamac's native Sequoia AirportItlwm. Revert OpenCore Legacy Patcher's "Modern Wireless" root patches first if you applied them.
  - **Not tested on any hardware yet.** Testers wanted.
- **Each kext refuses the wrong macOS.** The Tahoe ForbiddenItlwm now refuses to start outside macOS 26, and the Sequoia one outside 15.2 or newer Sequoia, instead of risking a kernel panic.
- **iMessage and push over Wi-Fi on Sequoia:** the 0.2.0 link-quality fix applies to the Sequoia build too.
- **Tahoe:** apart from the version check, the Tahoe kexts behave as in 0.2.0-beta1. The Tahoe build of BTLEAdvFixup is unchanged (0.8.0).
- **Tools:** the ABI audit takes `--target sequoia`, the BTLEAdvFixup pattern test takes `--target` and `--binary`, and `check_compat.sh` recognises Sequoia.

## 0.2.0-beta1

- **More Tahoe builds:** AirDrop now also starts on macOS 26.7.2 (25G332) and 26.7.3 (25G342). Both were verified offline from Apple's Kernel Debug Kits:
  - IOSkywalkFamily is identical to 26.7.1.
  - IO80211Family's AirDrop-related code is instruction for instruction the same as 26.7.1.
  - All virtual table slots and all kernel imports match.

  Neither has been tested on hardware yet. BTLEAdvFixup's `bluetoothd` patterns are still exact bytes from 26.7.1, so on these builds the Mac may not advertise AirDrop over Bluetooth, and iPhones may not list it. `check_compat.sh` tells you. Reports welcome.
- **Build check:** the driver now refuses to start AirDrop on a macOS build it doesn't know, and on a build where Apple's AWDL function table has changed. On those builds it works as plain Wi-Fi instead of risking a kernel panic. The result is shown in `ItlwmAWDLBuildCheck`. `-itlawdlanybuild` overrides the build list, but not the table check.
- **iMessage, push and other Apple services work over Wi-Fi.** The Tahoe driver never set the Wi-Fi interface's link quality, so macOS rated Wi-Fi "off" (LinkQuality -2), and Apple Push wouldn't connect over it. That broke iMessage and anything else that needs push. It also kept AirDrop between your own devices (same Apple Account) from working properly. The driver now reports link quality from the signal strength (good, poor or bad), and also gives the signal strength to macOS's Wi-Fi stack. This came from the original AirportItlwm for Tahoe.
- **Tester check:** `check_compat.sh` now recognises the supported builds and checks BTLEAdvFixup's patterns against the tester's own `bluetoothd`. BTLEAdvFixup itself is unchanged at 0.8.0.
- **Source layout:** the source folder `AirportItlwm/` is now `ForbiddenItlwm/`. The kext is byte-identical to before apart from the changes above.
- **Troubleshooting:** when the iPhone can't see the Mac but the Mac can see the iPhone, Reset Network Settings on the iPhone fixed it in testing. If iMessage on the Mac only sends as text messages, re-enable the Mac under the iPhone's Text Message Forwarding.

## 0.1.0-beta1

First public beta.

- AirDrop between an Intel Wi-Fi Mac and an iPhone, both ways, while normal Wi-Fi stays connected.
- Tested on an Intel AX211 with macOS 26.7.1 (25G241). About 22 MB/s each way when the iPhone's schedule allows it.
- Based on AirportItlwm 2.4.1 for macOS Tahoe.
- The AirDrop-enabled build keeps the product name `AirportItlwm.kext` and bundle identifier `com.zxystd.AirportItlwm`.
- BTLEAdvFixup 0.8.0, bundle identifier `org.forbiddenitlwm.BTLEAdvFixup`.
- `-itlawdlcoexlowlat` is disabled because it broke Wi-Fi on the AX211.

Known issues: cold iPhone → Mac connects take 3 to 10 s and occasionally fail. One macOS build only. See the README.
