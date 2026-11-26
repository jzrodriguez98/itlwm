# Troubleshooting

Start with `bash tools/compat/check_compat.sh`. Then read the driver's own state:

```bash
ioreg -l -w0 | grep -E '"ItlwmAWDL(InterfaceBuild|BuildCheck)"|"ITLAWDLCoex(Added|Channel|OwnWidth|CountryLearned|CountryNotices|PeerSyncFrames|PeerPresentEntries|TxOK|TxSubmitErrors)"'
```

| Key | Healthy value |
| --- | --- |
| `ItlwmAWDLInterfaceBuild` | `forbidden-` and the version you installed, for example `forbidden-0.7.0-alpha.4` (`-sequoia` or `-sonoma` added on those builds) |
| `ItlwmAWDLBuildCheck` | `verified` (`expected: …` on a 15.8.x kernel that wasn't checked offline). Anything starting with `blocked` means AirDrop is off on this macOS build: see below |
| `ITLAWDLCoexAdded` | Yes: the AirDrop listener exists |
| `ITLAWDLCoexChannel`, `ITLAWDLCoexOwnWidth` | 149 and 80. From 0.6.0, 44 and 80 where your iPhone uses 44. 20 when your router is in the same 80 MHz block on another main channel; from 0.7.0-alpha.2 80 there too with `itlawdlsched=1`, once the scheduler runs |
| `ITLAWDLCoexCountryLearned` | Yes |
| `ITLAWDLCoexCountryNotices` | A small number. It climbs fast if the firmware keeps restarting |
| `ITLAWDLCoexPeerSyncFrames` | Rises while an Apple device with AirDrop open is nearby |
| `ITLAWDLCoexPeerPresentEntries` | How many of the iPhone's 16 time slots it spends on the listener's channel |
| `ITLAWDLCoexTxSubmitErrors` | 0 |

The driver's log doesn't reach the unified log, so its state is only in the I/O Registry, and it's lost at reboot.

## `ItlwmAWDLBuildCheck` says blocked

The driver only starts AirDrop on macOS builds whose Wi-Fi stack was checked: Tahoe 26.7.1 to 26.7.3, Sequoia 15.8 to 15.8.3, and Sonoma 14.8.9. Up to 0.7.0-alpha.1, 15.8.1 and 15.8.2 start AirDrop but without the announcement copy, since only 15.8 and 15.8.3 are on the list; any other 15.8.x kernel starts as "expected". 0.7.0-alpha.2 adds 26.7 (25G229), 26.7.2's other build (25G330), 15.8.1, 15.8.2 (both builds), 15.7.3, 15.7.4, 15.7.8, 15.7.9, 14.8.3, 14.8.4, 14.8.7 and 14.8.8, all checked offline from Apple's Kernel Debug Kits or installers. 0.7.0-alpha.3 adds the 26.7.4 beta 25G422, from a user's `check-my-mac.pl` report.
- **Nothing at all, and no ForbiddenItlwm keys:** check that you used the kexts for your macOS version. A ForbiddenItlwm built for another macOS version refuses to start, and logs `this kext is for macOS …`.
- **`blocked: unverified macOS build`:** your build isn't on the list yet. Normal Wi-Fi still works. Please open an issue with your build (`sw_vers -buildVersion`) so it can be checked. `-itlawdlanybuild` forces AirDrop on anyway, announcement included from 0.6.0-beta.2, and from 0.7.0-alpha.2 the packet counters too, so the build works like a verified one. It's at the risk of a kernel panic, so use it only from a USB stick. Bluetooth still needs BTLEAdvFixup's patterns to match the build: `perl tools/check-my-mac.pl` shows whether they do.
- **`blocked: IO80211AWDLProtocol table differs`:** the Wi-Fi stack isn't the one the driver was checked against. If you applied OpenCore Legacy Patcher's "Modern Wireless" root patches, revert them. Otherwise Apple changed the part of its Wi-Fi stack the driver plugs into. Starting AirDrop would likely panic, so no flag overrides this. Please report your build.

## The listener is on channel 6, or `CountryLearned` is No

Apple devices use channel 149 or 44 for AirDrop on 5 GHz, and each picks one by its own country rules (Japan, Germany and Russia, for example, use 44). From 0.6.0 the listener follows the iPhone: once it has heard the iPhone, it moves to the channel the iPhone uses (`ITLAWDLCoexPeer5GHz` shows which: 44, 149, or 1 for neither). Before it has heard one, it starts on 149.

**It moves to 6 for about 15 s every minute:** that's the search for a device it hasn't heard yet (from 0.6.0-beta.3, #35). A listener on 149 never hears a phone that uses only 44, so while no device's schedule has been heard it waits on 6, where every Apple device spends a slot, then follows the device it finds. `ITLAWDLCoexSearch6` shows a search in progress and `ITLAWDLCoexSearch6Dwells` counts them; it stops as soon as a device is heard. `-itlawdlnosearch6` turns it off, and the experimental `itlawdlsched=1` does too: the driver then visits channel 6 in its own slot instead.

The firmware opens channel 149 only after a nearby network tells it the country.
- Make sure some 5 GHz network that advertises a country is in range. Switching on an iPhone's Personal Hotspot nearby, without joining it, has worked.
- Wait a minute after it appears.
- Some countries don't allow channels 149 to 161, or allow them only at 20 or 40 MHz. Up to 0.5.4 AirDrop stayed on channel 6 there; from 0.6.0 it uses 44 if the iPhone does and the firmware allows it. The checker warns about known ones.
- **Channels 149 to 161 marked passive** (China, for example): from 0.5.0, once the hackintosh hears a Wi-Fi network's beacon on one of these channels, the listener may use it (Linux does this only before the country is known; here it also counts after, see HOW-IT-WORKS). `ITLAWDLCoexBeaconHints` shows which channels were heard (bits 0 to 3 = 149, 153, 157, 161). A router on 149 at 80 MHz covers all four. The same applies to 36 to 48 for channel 44 (bits 8 to 11). From 0.6.0 such a channel can also be used while the Mac's own Wi-Fi is connected on a channel in the same group (36–48, 52–64, 100–144 or 149–165), if the firmware marks it for that (Linux's rule for Wi-Fi Direct interfaces): `ITLAWDLCoexIrConcurrent` lists the channels, `ITLAWDLCoexIrConcurrentUsed` counts the uses. With neither, AirDrop stays on 6.
- The driver never overrides the country's rules, and `itlwm_cc` doesn't help.

## The listener moves between 44 and 149

`ITLAWDLCoexMoves` and `ITLAWDLCoexPeer5GHzChanges` keep rising, `ITLAWDLCoexChannel` alternates between 44 and 149, and `ITLAWDLCoexBaTxStateName` falls back to `asking` or `off` after each move ([#68](https://github.com/retropineaple/ForbiddenItlwm/issues/68)). Transfers are slow or never finish.

Seen with the router on channel 44 and the other device on the same network. That device's channel sequence then has 44 in most slots, its Wi-Fi slots included, and 149 in a few AWDL slots, for example `<2c2c952c2c2c2c2c06952c9595952c2c>`. The listener follows it to 149; when a later sequence leaves 149 out, it comes back to 44.

- **From 0.6.0-beta.2** the listener moves between two 5 GHz channels only once the same choice has held for 60 s and no AirDrop data has flowed for 30 s, so it no longer moves every few seconds or during a transfer. `ITLAWDLCoexMovesSettleDropped` counts the choices that changed before they settled.
- **Test flag:** add `-itlawdlsta44`. While the Mac's own Wi-Fi is on 44 and the other device is seen on 44 too, the listener then stays on 44 and shares the station's channel. `ITLAWDLCoexStation44` shows Yes, and `ITLAWDLCoexMoves` should stay at 0. Confirmed with a MacBook Air M1 on an AX200 (27 MB/s to the hackintosh, 20 MB/s from it); not tested with iPhones, so please report your result.
- **Without the flag:** move the router off 44. On 100 and up the listener keeps 44 at 80 MHz to itself, but the radio then time-shares between the two channels.

## The iPhone doesn't list the Mac

- **Boot flags:** check that the whole tested set from [BOOT-FLAGS.md](BOOT-FLAGS.md) is set, not part of it. Without `-itlawdlmitx` the driver, the listener, `awdl0` and Bluetooth all look healthy and `ITLAWDLCoexPeerSyncFrames` rises, but `ItlwmAWDLMiState` is `off`, `ItlwmAWDLSyncMIBuilt` stays 0 and `ITLAWDLCoexDataRx` stays 0: the other device hears the Mac but never learns it offers AirDrop. `check_compat.sh` checks the whole set and `ItlwmAWDLMiState`.
- **The Mac's Wi-Fi on a radar (DFS) channel, 52–144:** without `-itlawdlcoexmulti` the listener shares that channel, where no Apple device looks for AirDrop, so nothing is found (#63). Keep `-itlawdlcoexmulti`, as in the tested set.
- **Bluetooth:** it must be on, with this branch's `IntelBTPatcher.kext` for your macOS version loaded and `-btleadv` set. The original IntelBTPatcher implementation must be disabled. AirDrop finds devices over Bluetooth LE first. BTLEAdvFixup's patterns only match specific builds (26.7.1 and, from 0.8.1, 26.7.3 and 26.7.2, with 26.7.2's own pattern for one site from 0.9.1, on Tahoe; 15.8, 15.8.2 and 15.8.3 on Sequoia; from 0.9.0, 14.8.9 on Sonoma): `check_compat.sh` shows whether they match yours. To check it's running: `ioreg -l -w0 -d1 | grep '"BTLEAdv'` should show `BTLEAdvHookRouted` = 1. On Sequoia, BTLEAdvFixup before 0.8.3 never started.
- **SMBIOS serial number** ([#46](https://github.com/retropineaple/ForbiddenItlwm/issues/46)): with an empty PlatformInfo → Generic, macOS uses the motherboard maker's serial, Apple's identity service never registers the Mac, and AirDrop drops the devices it finds: nothing is listed on either side, though every check here passes. `rapportd` then logs `Failed to get self IDS Correlation Identifier`. Generate SystemSerialNumber and MLB with `macserial` for your SMBIOS model, set ROM to the Wi-Fi card's MAC address (see the iMessage section below), and reboot.
- **AirDrop settings:** with Contacts Only, the two devices must share an Apple Account or know each other as contacts. Try Everyone for 10 Minutes to rule this out.
- **Is the iPhone heard?** Read `ITLAWDLCoexPeerSyncFrames` twice, a few seconds apart, with the iPhone's share sheet open. If it rises, the radios hear each other.
- **Unlock the iPhone and keep the share sheet open** for 10 to 15 seconds.
- **The iPhone can lose track of the Mac as one of your own devices.** In testing, after a day of many reboots, the iPhone stopped listing the Mac on every build, including builds that had worked earlier that day, while the Mac could still see and send to the iPhone. Texts sent from the Mac (relayed through the iPhone) failed at the same time, and the iPhone's Settings → Apps → Messages → Text Message Forwarding showed "sign in with your Apple Account on other devices" with no switch for the Mac. **Turning iMessage off and on on the iPhone fixed both** (Settings → Apps → Messages → iMessage). The Mac then showed "Device Added to Your Account", and about two minutes later the iPhone listed the Mac again and texts from the Mac went through. Reset Network Settings did not help with this one.
- **The iPhone itself can get stuck.** During testing there was a period when the iPhone listed no Mac on any build, including builds that had worked earlier that day, while the Mac could still see and send to the iPhone. Several restarts didn't fix it. **Reset Network Settings on the iPhone did.** A factory reset also helped, but only for a while. If the Mac's counters look healthy, look at the iPhone before the driver. Try these in order:
  1. Restart the iPhone.
  2. Turn iMessage off and on on the iPhone (see above), and wait two minutes.
  3. Settings → General → Transfer or Reset iPhone → Reset → Reset Network Settings. This forgets saved Wi-Fi networks.
  4. As a last resort, back up the iPhone and factory reset it. Afterwards the iPhone is a new device to AirDrop: Contacts Only won't match until it's signed in to its Apple Account again and has synced, so use Everyone for 10 Minutes meanwhile. Finder may list it twice for a while.

## Sequoia: the devices list each other, but transfers stay on "Waiting"

Fixed in 0.5.1-test1 ([#7](https://github.com/retropineaple/ForbiddenItlwm/issues/7), [#13](https://github.com/retropineaple/ForbiddenItlwm/issues/13), found in [#19](https://github.com/retropineaple/ForbiddenItlwm/issues/19)). Up to 0.5.0 the driver created its AirDrop packet pools in a mode that Sequoia's kernel refuses for a network interface, so `awdl0` was never created: `ifconfig awdl0` said the interface doesn't exist, and `ItlwmAWDLSyncProbeStage` stayed `snapshot-not-ready`. Update to 0.5.1-test1 or later. Then `ifconfig awdl0` should show the interface, and `ItlwmAWDLPoolType` should be 1. Confirmed working on 15.8.1 (#13, #22), 15.8.2 (#7), 15.8.3 (#16) and 15.6 (#19).

**Which keys show it works:** `ifconfig awdl0` lists the interface, `ItlwmAWDLClientEvents` has an `open` and a `prepare-bsd` but no `close`, `ItlwmAWDLSyncProbeStage` is `frame-built`, and `ITLAWDLCoexTxSubmitted` and `ItlwmAWDLDataDelivered` rise. Up to 0.5.1, three keys looked like failures even when it worked: `ItlwmAWDLTransportReady` (always No), `ITLAWDLCoexLastBuildResult` (kept the error from before macOS sent its template) and `ItlwmAWDLDataCopyAttempts`/`Success` (only count an optional probe). Ignore them.

## The first iPhone → Mac send is slow to connect, or sits on "Waiting"

**Try 0.7.0-alpha.1's experimental flags.** Add `itlawdlsched=1 -btleadvnodupfilter` to the tested set ([BOOT-FLAGS](BOOT-FLAGS.md#experimental)); they work only from 0.7.0-alpha.1, and in 0.7.0-alpha.1 the scheduler runs on AX210-family cards only (0.7.0-alpha.2 adds the AX200 family). On the project's hackintosh (AX211) connects take about 1 to 2 s, the first send no longer fails, even after the iPhone sat idle for a long time, and Mac → iPhone sends no longer sit on "Waiting". The Mac's announcement now reaches the iPhone first, and with `-btleadvnodupfilter` the Mac notices at once when the iPhone asks for a link over Bluetooth. Please report your result and your card, with `ioreg -l -w0 | grep '"ITLAWDLSched'`.

**Up to 0.6.0-beta.4, or without the flags,** this is the main known problem. The time goes into the iPhone finding the Mac's AirDrop service before any data moves, and it's worst when both devices have been idle. Cancelling and sending again usually connects quickly. Mac → iPhone can sit on "Waiting" too, less often.


**Both directions stay on "Waiting"?** Check that the Mac is connected to a Wi-Fi network. The AirDrop listener runs beside the Wi-Fi connection, so with Wi-Fi on but no network joined, AirDrop can't connect (a known limitation; a real Mac doesn't need a network).

## Transfers are slower than expected

- **Check the iPhone's Wi-Fi first.** AirDrop gets the share of the iPhone's radio time that its own Wi-Fi leaves over. If the iPhone isn't on Wi-Fi, or is on channel 149, it gets 15 of 16 slots (about 22 MB/s). On a quiet network on another channel it gets 11 (about 15 MB/s), on a busy one 7 (about 6 MB/s). `ITLAWDLCoexPeerPresentEntries` shows the current number.
- **Check the channel:** on 6, everything is very slow. The listener can drop to 6 for a while when the firmware briefly loses the country (`ITLAWDLCoexCountryLearned` No).
- **Mac → iPhone much slower than iPhone → Mac:** on some setups (#22, #24) the iPhone never accepted block ack (`ITLAWDLCoexBaTxStateName` stays `asking`), so every frame went out singly. It happened when the Mac's own Wi-Fi was on the same channel as the AirDrop listener. From 0.6.0 the fix from [PR #47](https://github.com/retropineaple/ForbiddenItlwm/pull/47) is on by default (`ITLAWDLCoexSameChannelProbe*` keys). If it's still slow, please report it with the measure output. **Workaround:** put your router (or the Mac's network) on another channel, such as 36–48, or 100 and up where allowed. Not 153–161: at 80 MHz they share the listener's block on 149, so it drops to 20 MHz (#26); from 0.7.0-alpha.2, with `itlawdlsched=1`, it keeps 80 MHz there.
- **Check pf and QUIC (Tahoe especially):** run `sysctl net.filter_state net.link.generic.system.enable_netagent`. If it prints `pf` and `0`, macOS has turned off its user-space network path and AirDrop's QUIC runs without pacing; `sharingd` then logs `quic_time_delta start time X is after end time Y` hundreds of times per transfer. On Tahoe the usual cause is OpenCore's `Kernel > Quirks > PowerTimeoutKernelPanic`: it rewrites the kernel string `com.apple` to `not.apple`, pf's anchor check shares that string on kernel 25.6, and the stock `/etc/pf.conf` then counts as custom rules. The quirk is there to stop a kernel panic when a driver is slow to change power state: if your hackintosh boots and sleeps fine without it, set it to false and reboot; the check should then print an empty `net.filter_state` and `1`. Your own pf rules or firewall apps that load anchors cause the same thing. Section 7 of `check_compat.sh` does this check. Full analysis: [ax210-airdrop-awdl-hackintosh: skywalk-pf-quic.md](https://github.com/kevineduardo/ax210-airdrop-awdl-hackintosh/blob/main/docs/reference/skywalk-pf-quic.md).
- **Measure it:** `bash tools/compat/airdrop_measure.sh` prints the speed and connect times macOS logs for each transfer.
- **The very first send after boot** is often slower while rate control settles.

## Networks are missing from the Wi-Fi list

**Check for OpenCore Legacy Patcher root patches first,** not only the Wi-Fi ones: on one machine OCLP's audio patch alone left the list empty, with every scan failing, until OCLP's patches were removed (#20).

**If the list stays empty after macOS dropped the connection** (for example when you switch or log out of an account) and only turning Wi-Fi off and on brings it back: fixed in 0.6.0-beta.1. A background scan interrupted by the disconnect left a flag set, and the driver then refused every scan macOS asked for; `ItlwmScanStats` shows it as a third `busy` number that keeps rising (`busy=0/0/112/0`). From 0.6.0-beta.1 the driver also tells your router it's leaving, so the next join works on the first try.

From 0.6.0 the driver counts what happens to macOS's scan requests (#20, #24, #45). After the list has looked wrong for a while, run `ioreg -l -w0 | grep -E '"ItlwmScan(Stats|StatsSTA|Last)"'` and post the output with your report. It holds counts only, no network names. On Sonoma, `ItlwmScanStats` exists from 0.6.0-beta.1 (0.6.0-alpha.1 had no counters there).

## The Wi-Fi menu or the Wi-Fi settings are slow

In a busy area, with many networks in range, the Wi-Fi menu and System Settings → Wi-Fi can take seconds to minutes to refresh ([#64](https://github.com/retropineaple/ForbiddenItlwm/issues/64)).

- **Remove old remembered networks** in System Settings → Wi-Fi → Advanced. For every network it lists, macOS checks the whole remembered list; one user went from 148 remembered networks to 24, and the check from 1.7–4.6 s per row to 0.15 s. This is macOS, not the driver, and helped the most.
- **Faster scans while connected:** the opt-in boot flag `itlwm_scanout=360` lets each off-channel visit cover several passive channels (BOOT-FLAGS). On an AX210 full scans went from 8–14 s to about 4.7 s.

## A new Bluetooth LE mouse or keyboard won't pair

Fixed in the BTLEAdvFixup implementation version 0.9.1 (from 0.5.4-beta.2, #27). Earlier versions, with IntelBTPatcher disabled, let a new LE mouse or keyboard connect but never finish pairing; devices paired before kept working. Update this branch's IntelBTPatcher bundle (the BTLEAdvFixup implementation). If a device still won't pair with 0.9.1, check `ioreg -l -w0 -d 1 | grep -E '"BTLEAdv(PipeHooks|LengthRewrites|LengthFailures)"'` while pairing (`PipeHooks` should be 5, and `LengthRewrites` should go up) and report it.

BTLEAdvFixup 0.9.2 (0.6.0-beta.1) also stops that fix from taking over the controller's event pipe when a pairing round doesn't finish ([PR #61](https://github.com/retropineaple/ForbiddenItlwm/pull/61)): with 0.9.1, that could leave USB devices unresponsive until a cold boot, or panic. `BTLEAdvLengthExpired` and `BTLEAdvLengthAborts` count rounds given up.

**With BTLEAdvFixup 0.9.2 new LE mice and keyboards don't pair again** ([#71](https://github.com/retropineaple/ForbiddenItlwm/issues/71)): a security fix in it switched the data-length fix off completely, and no `BTLEAdvLength*` key ever appears. Use 0.9.3 (0.6.0-beta.2). `BTLEAdvEventPipes` should then be 1 or more.

## AirPods drop out while playing Apple Music

On one AX211 machine, AirPods Pro 3 went silent and disconnected within seconds of starting Apple Music, then reconnected ([#52](https://github.com/retropineaple/ForbiddenItlwm/issues/52)). The fix there was `-btlfxa2dpcheck`, an option of the BlueToolFixup-FixA2DP fork (not of ForbiddenItlwm), which works alongside BTLEAdvFixup.

## One device works, but an iPhone stays on "Waiting"

The driver keeps block ack with one Apple device at a time, and keeps it for as long as that device has exchanged data in the last ten minutes. Another Mac or an iPad nearby can hold it, and the iPhone's requests are then dropped (#81). To check, run this while an iPhone send fails:
```
ioreg -l -w0 | grep -E '"ITLAWDLCoex(BaPeerAdded|BaOtherPeer|BaRequests)"'
```
A high `ITLAWDLCoexBaOtherPeer` means another device holds it. Put that device to sleep, or turn its Wi-Fi off, for about ten minutes, then try the iPhone again. From 0.7.0-alpha.2 you can instead try `-itlawdlpeerhandoff` ([PR #50](https://github.com/retropineaple/ForbiddenItlwm/pull/50), opt-in): it hands the session to the iPhone once the other device is idle. `ITLAWDLCoexPeerHandoffRetired` counts the handovers; please report whether it helped. Or try the experimental `-itlawdlmultipeer` (from 0.7.0-alpha.2): each device gets its own block ack, so neither waits for the other. `ioreg -l -w0 | grep '"ITLAWDLCoexPeers"'` shows one entry per device; please report it with how the transfers went. Known issue: with `-itlawdlmultipeer`, Block Ack to a second device sometimes never starts, so the Mac sends to it frame by frame ([#103](https://github.com/retropineaple/ForbiddenItlwm/issues/103)).

The two devices can also use different AirDrop channels, for example the iPhone 44 and an iPad 149 (`ITLAWDLCoexPeer5GHz` shows the last device heard). The listener is on one 5 GHz channel at a time, so the device on the other channel reaches the Mac only in its few slots there ([#45](https://github.com/retropineaple/ForbiddenItlwm/issues/45)). From 0.7.0-alpha.4, `itlawdlsched=1` follows both: when macOS's plan names a second channel, the listener visits it in those slots, and `ITLAWDLSchedSecond` shows the visits. This is experimental and was tested here only with a simulated second channel. It can only use a channel the card's firmware lets the Mac send on.

## Universal Clipboard or Handoff from the Mac stops working

Close any AirDrop window in Finder and any AirDrop share sheet. The Intel Bluetooth controller has one legacy advertising set, and while AirDrop is browsing, macOS gives it to AirDrop instead of the clipboard (#65). To check, `/usr/bin/log show --last 5m --predicate 'process == "bluetoothd" AND eventMessage CONTAINS "current advertisers"'` should list type 12 while you copy.

## Instant Hotspot, Sidecar or Universal Control don't work

Not supported yet. Instant Hotspot's Bluetooth connection to the iPhone times out (#39, #40): join the hotspot as a normal network instead, with its password, from the Wi-Fi list or with `networksetup -setairportnetwork en0 "<network name>" <password>`. If that fails too, turn the Mac's Bluetooth off for the join and back on afterwards: while it's on, macOS can still send the join down the Instant Hotspot path (#39). Sidecar and Universal Control need AWDL traffic registration, which the driver doesn't do yet; Sidecar over USB works (#42).

## Bluetooth turns off after some hours, and `bluetoothd` crash reports say `KERN_MEMORY_ERROR`

Seen on Tahoe 26.7.1 and 26.7.3 ([#62](https://github.com/retropineaple/ForbiddenItlwm/issues/62)), also without ForbiddenItlwm. `bluetoothd` crashes with `EXC_BAD_ACCESS (SIGBUS)`, restarts a few times, and Bluetooth then shows as Off. The crash reports name APFS: "compressed data hash mismatch".

BlueToolFixup and BTLEAdvFixup both patch `bluetoothd`'s code in memory, in the copy macOS shares between processes. When memory runs low, macOS drops part of a block of that code and reads it again later, and its integrity check then also covers the page that is still patched, which fails. It follows memory pressure, so it shows up after hours, not at boot.

Fixed in 0.6.0-beta.4 (BTLEAdvFixup source version 0.9.4), with `-btleadv` and this branch's renamed `IntelBTPatcher.kext` after `BlueToolFixup.kext` in `Kernel` → `Add` (the order in [INSTALL.md](INSTALL.md)). The renamed plugin then gives APFS's check the original bytes of the patched pages, BlueToolFixup's too. Check:

```bash
ioreg -l -w0 | grep -E '"BTLEAdv(VerifyHook|PatchedPages|VerifyRescues|VerifyRescueFailures)"'
```

`BTLEAdvVerifyHook` should be 1. `BTLEAdvPatchedPages` counts the patched pages it knows: on 26.7.1 it's 6 once Bluetooth has been used, four from BlueToolFixup and two from BTLEAdvFixup. If it stays at 2 or less, the renamed plugin loads before BlueToolFixup and can't see BlueToolFixup's patches: move it after. `BTLEAdvVerifyRescues` counts reloads that would have crashed `bluetoothd`.

Without the renamed plugin (BlueToolFixup alone, with any Bluetooth card), a full power-off (not a restart) still brings Bluetooth back.

## Wi-Fi is off or greyed out, and there's no `en0`

The kext can be loaded (`kmutil` lists it) while the driver itself failed to start.
- **0.4.0 and 0.4.1 failed to start on some machines** (#14, #16). Use 0.5.0-test1 or later, or 0.3.x.
- **Check the start result:** `ioreg -l -w0 | grep -E '"ItlwmStart'`. From 0.5.0, a failed start leaves `ItlwmStartResult` = `failed` and the driver's own messages in `ItlwmStartLog`. Attach both to an issue.
- **Leftovers from an older AirportItlwm setup** (the cause in #14): ForbiddenItlwm needs macOS's own Wi-Fi stack. Revert OpenCore Legacy Patcher's "Modern Wireless" root patches, and remove from config.plist any `Kernel → Block` entry for `com.apple.iokit.IOSkywalkFamily`, any injected `IOSkywalkFamily.kext` or `IO80211FamilyLegacy.kext`, and any other `AirportItlwm.kext` or `itlwm.kext`.
- **`MinKernel`/`MaxKernel`:** they must match the kext's macOS version (see [INSTALL.md](INSTALL.md)).

## Normal Wi-Fi stopped working

**Is it AirDrop or the Wi-Fi driver?** From 0.7.0-alpha.2, add `-itlawdloff` and reboot: AirDrop is then off and the driver works as plain Wi-Fi (with `-btleadv` still set, devices may still list each other over Bluetooth, but transfers fail). If the problem stays, it isn't AirDrop's. Normal Wi-Fi is also faster then, since the radio no longer time-shares with AirDrop's listener.

- Remove any flag listed under "Don't use" in [BOOT-FLAGS.md](BOOT-FLAGS.md).
- A fast-rising `ITLAWDLCoexCountryNotices`, with `ITLAWDLCoexAdded` flipping between Yes and No, means the firmware is restarting around the listener. Boot without the `-itlawdl*` flags (from 0.7.0-alpha.2, with `-itlawdloff`) to confirm the station works on its own, then report it.
- **Wi-Fi keeps dropping and reconnecting while the AirDrop flags are on:** remove `-itlawdlcoexmulti` and keep the rest (from 0.7.0-alpha.2, where it's a default, add `-itlawdlnocoexmulti` instead). The listener then stays on your Wi-Fi network's channel instead of its own, and Wi-Fi stays stable (#16). iPhone → Mac still uses block ack in this setup (about 5 MB/s); Mac → iPhone is slower. `ITLAWDLCoexAddsAfterRestart` rising means the firmware is restarting underneath.
- **Before 0.6.0, removing `-itlawdlcoexmulti` was also the advice where channel 149 isn't available (#29).** From 0.6.0 keep it: the listener follows the iPhone onto 44, and the same-channel fix ([PR #47](https://github.com/retropineaple/ForbiddenItlwm/pull/47)) only works with it (#63).
- Use USB tethering from the iPhone to get online while you test.

## iMessage or other Apple services don't work over Wi-Fi

Check the link quality macOS sees:

```bash
printf 'show State:/Network/Interface/en0/LinkQuality\n' | scutil
```

- **It should be 100 (or 50 or 10 on a weak signal).** ForbiddenItlwm 0.2.0 and later set it on Tahoe, 0.3.0 and later on Sequoia, and the Sonoma build sets it too. With -2 ("off"), Apple Push won't connect over Wi-Fi, and iMessage, FaceTime and other push-based services fail. Older builds and the original AirportItlwm for Tahoe leave it at -2.
- **If iMessage on the Mac only sends as text messages** (relayed through the iPhone) and they fail, re-enable the Mac on the iPhone: Settings → Apps → Messages → Text Message Forwarding. A new SMBIOS ROM makes the Mac a new device to Apple. If that screen has no switch for the Mac and says to sign in on other devices, turn iMessage off and on on the iPhone and wait about two minutes (see "The iPhone doesn't list the Mac").
- **For iMessage on a hackintosh in general:** use a serial that Apple's coverage check calls invalid. Set ROM to the Wi-Fi card's own MAC address, which `networksetup -getmacaddress Wi-Fi` shows. `ifconfig` shows the address in use, which can differ (a private Wi-Fi address, for example).

## Reporting a bug

Include:
- the output of `bash tools/compat/collect_hw_macos.sh` (read it first; it leaves out addresses and names)
- the `ioreg` lines above, taken right after the problem
- what you did, and the time

Don't post `-itlawdlsamples` output or iPhone sysdiagnoses publicly: they contain device names, addresses and personal data.
