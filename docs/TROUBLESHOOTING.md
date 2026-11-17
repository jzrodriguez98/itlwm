# Troubleshooting

Start with `bash tools/compat/check_compat.sh`. Then read the driver's own state:

```bash
ioreg -l -w0 | grep -E '"ItlwmAWDL(InterfaceBuild|BuildCheck)"|"ITLAWDLCoex(Added|Channel|OwnWidth|CountryLearned|CountryNotices|PeerSyncFrames|PeerPresentEntries|TxOK|TxSubmitErrors)"'
```

| Key | Healthy value |
| --- | --- |
| `ItlwmAWDLInterfaceBuild` | `forbidden-0.6.0-beta.1`, `forbidden-0.6.0-beta.1-sequoia` or `forbidden-0.6.0-beta.1-sonoma` |
| `ItlwmAWDLBuildCheck` | `verified` (`expected: …` on a 15.8.x kernel that wasn't checked offline). Anything starting with `blocked` means AirDrop is off on this macOS build: see below |
| `ITLAWDLCoexAdded` | Yes: the AirDrop listener exists |
| `ITLAWDLCoexChannel`, `ITLAWDLCoexOwnWidth` | 149 and 80. From 0.6.0, 44 and 80 (or 20) where your iPhone uses 44 |
| `ITLAWDLCoexCountryLearned` | Yes |
| `ITLAWDLCoexCountryNotices` | A small number. It climbs fast if the firmware keeps restarting |
| `ITLAWDLCoexPeerSyncFrames` | Rises while an Apple device with AirDrop open is nearby |
| `ITLAWDLCoexPeerPresentEntries` | How many of the iPhone's 16 time slots it spends on the listener's channel |
| `ITLAWDLCoexTxSubmitErrors` | 0 |

The driver's log doesn't reach the unified log, so its state is only in the I/O Registry, and it's lost at reboot.

## `ItlwmAWDLBuildCheck` says blocked

The driver only starts AirDrop on macOS builds whose Wi-Fi stack was checked: Tahoe 26.7.1 to 26.7.3, Sequoia 15.8 to 15.8.3 (15.8.1 and 15.8.2 run checked kernels; any other 15.8.x kernel starts as "expected"), and Sonoma 14.8.9.
- **Nothing at all, and no ForbiddenItlwm keys:** check that you used the kexts for your macOS version. A ForbiddenItlwm built for another macOS version refuses to start, and logs `this kext is for macOS …`.
- **`blocked: unverified macOS build`:** your build isn't on the list yet. Normal Wi-Fi still works. Please open an issue with your build (`sw_vers -buildVersion`) so it can be checked. `-itlawdlanybuild` forces AirDrop on anyway, at the risk of a kernel panic.
- **`blocked: IO80211AWDLProtocol table differs`:** the Wi-Fi stack isn't the one the driver was checked against. If you applied OpenCore Legacy Patcher's "Modern Wireless" root patches, revert them. Otherwise Apple changed the part of its Wi-Fi stack the driver plugs into. Starting AirDrop would likely panic, so no flag overrides this. Please report your build.

## The listener is on channel 6, or `CountryLearned` is No

Apple devices use channel 149 or 44 for AirDrop on 5 GHz, and each picks one by its own country rules (Japan, Germany and Russia, for example, use 44). From 0.6.0 the listener follows the iPhone: once it has heard the iPhone, it moves to the channel the iPhone uses (`ITLAWDLCoexPeer5GHz` shows which: 44, 149, or 1 for neither). Before it has heard one, it starts on 149.

The firmware opens channel 149 only after a nearby network tells it the country.
- Make sure some 5 GHz network that advertises a country is in range. Switching on an iPhone's Personal Hotspot nearby, without joining it, has worked.
- Wait a minute after it appears.
- Some countries don't allow channels 149 to 161, or allow them only at 20 or 40 MHz. Up to 0.5.4 AirDrop stayed on channel 6 there; from 0.6.0 it uses 44 if the iPhone does and the firmware allows it. The checker warns about known ones.
- **Channels 149 to 161 marked passive** (China, for example): from 0.5.0, once the hackintosh hears a Wi-Fi network's beacon on one of these channels, the listener may use it (Linux does this only before the country is known; here it also counts after, see HOW-IT-WORKS). `ITLAWDLCoexBeaconHints` shows which channels were heard (bits 0 to 3 = 149, 153, 157, 161). A router on 149 at 80 MHz covers all four. The same applies to 36 to 48 for channel 44 (bits 8 to 11). From 0.6.0 such a channel can also be used while the Mac's own Wi-Fi is connected on a channel in the same group (36–48, 52–64, 100–144 or 149–165), if the firmware marks it for that (Linux's rule for Wi-Fi Direct interfaces): `ITLAWDLCoexIrConcurrent` lists the channels, `ITLAWDLCoexIrConcurrentUsed` counts the uses. With neither, AirDrop stays on 6.
- The driver never overrides the country's rules, and `itlwm_cc` doesn't help.

## The iPhone doesn't list the Mac

- **Bluetooth:** it must be on, with BTLEAdvFixup for your macOS version loaded, `-btleadv` set and IntelBTPatcher disabled. AirDrop finds devices over Bluetooth LE first. BTLEAdvFixup's patterns only match specific builds (26.7.1 and, from 0.8.1, 26.7.3 and 26.7.2, with 26.7.2's own pattern for one site from 0.9.1, on Tahoe; 15.8, 15.8.2 and 15.8.3 on Sequoia; from 0.9.0, 14.8.9 on Sonoma): `check_compat.sh` shows whether they match yours. To check it's running: `ioreg -l -w0 -d1 | grep '"BTLEAdv'` should show `BTLEAdvHookRouted` = 1. On Sequoia, BTLEAdvFixup before 0.8.3 never started.
- **AirDrop settings:** with Contacts Only, the two devices must share an Apple Account or know each other as contacts. Try Everyone for 10 Minutes to rule this out.
- **Is the iPhone heard?** Read `ITLAWDLCoexPeerSyncFrames` twice, a few seconds apart, with the iPhone's share sheet open. If it rises, the radios hear each other.
- **Unlock the iPhone and keep the share sheet open** for 10 to 15 seconds.
- **The iPhone itself can get stuck.** During testing there was a period when the iPhone listed no Mac on any build, including builds that had worked earlier that day, while the Mac could still see and send to the iPhone. Several restarts didn't fix it. **Reset Network Settings on the iPhone did.** A factory reset also helped, but only for a while. If the Mac's counters look healthy, look at the iPhone before the driver. Try these in order:
  1. Restart the iPhone.
  2. Settings → General → Transfer or Reset iPhone → Reset → Reset Network Settings. This forgets saved Wi-Fi networks.
  3. As a last resort, back up the iPhone and factory reset it. Afterwards the iPhone is a new device to AirDrop: Contacts Only won't match until it's signed in to its Apple Account again and has synced, so use Everyone for 10 Minutes meanwhile. Finder may list it twice for a while.

## Sequoia: the devices list each other, but transfers stay on "Waiting"

Fixed in 0.5.1-test1 ([#7](https://github.com/retropineaple/ForbiddenItlwm/issues/7), [#13](https://github.com/retropineaple/ForbiddenItlwm/issues/13), found in [#19](https://github.com/retropineaple/ForbiddenItlwm/issues/19)). Up to 0.5.0 the driver created its AirDrop packet pools in a mode that Sequoia's kernel refuses for a network interface, so `awdl0` was never created: `ifconfig awdl0` said the interface doesn't exist, and `ItlwmAWDLSyncProbeStage` stayed `snapshot-not-ready`. Update to 0.5.1-test1 or later. Then `ifconfig awdl0` should show the interface, and `ItlwmAWDLPoolType` should be 1. Confirmed working on 15.8.1 (#13, #22), 15.8.2 (#7), 15.8.3 (#16) and 15.6 (#19).

**Which keys show it works:** `ifconfig awdl0` lists the interface, `ItlwmAWDLClientEvents` has an `open` and a `prepare-bsd` but no `close`, `ItlwmAWDLSyncProbeStage` is `frame-built`, and `ITLAWDLCoexTxSubmitted` and `ItlwmAWDLDataDelivered` rise. Up to 0.5.1, three keys looked like failures even when it worked: `ItlwmAWDLTransportReady` (always No), `ITLAWDLCoexLastBuildResult` (kept the error from before macOS sent its template) and `ItlwmAWDLDataCopyAttempts`/`Success` (only count an optional probe). Ignore them.

## The first iPhone → Mac send is slow to connect, or sits on "Waiting"

This is the main known problem. The time goes into the iPhone finding the Mac's AirDrop service before any data moves, and it's worst when both devices have been idle. Cancelling and sending again usually connects quickly. Mac → iPhone isn't affected.

**Both directions stay on "Waiting"?** Check that the Mac is connected to a Wi-Fi network. The AirDrop listener runs beside the Wi-Fi connection, so with Wi-Fi on but no network joined, AirDrop can't connect (a known limitation; a real Mac doesn't need a network).

## Transfers are slower than expected

- **Check the iPhone's Wi-Fi first.** AirDrop gets the share of the iPhone's radio time that its own Wi-Fi leaves over. If the iPhone isn't on Wi-Fi, or is on channel 149, it gets 15 of 16 slots (about 22 MB/s). On a quiet network on another channel it gets 11 (about 15 MB/s), on a busy one 7 (about 6 MB/s). `ITLAWDLCoexPeerPresentEntries` shows the current number.
- **Check the channel:** on 6, everything is very slow. The listener can drop to 6 for a while when the firmware briefly loses the country (`ITLAWDLCoexCountryLearned` No).
- **Mac → iPhone much slower than iPhone → Mac:** on some setups (#22, #24) the iPhone never accepted block ack (`ITLAWDLCoexBaTxStateName` stays `asking`), so every frame went out singly. It happened when the Mac's own Wi-Fi was on the same channel as the AirDrop listener. From 0.6.0 the fix from [PR #47](https://github.com/retropineaple/ForbiddenItlwm/pull/47) is on by default (`ITLAWDLCoexSameChannelProbe*` keys). If it's still slow, please report it with the measure output. **Workaround:** put your router (or the Mac's network) on another channel, such as 36–48, or 100 and up where allowed. Not 153–161: at 80 MHz they share the listener's block on 149 (#26).
- **Check pf and QUIC (Tahoe especially):** run `sysctl net.filter_state net.link.generic.system.enable_netagent`. If it prints `pf` and `0`, macOS has turned off its user-space network path and AirDrop's QUIC runs without pacing; `sharingd` then logs `quic_time_delta start time X is after end time Y` hundreds of times per transfer. On Tahoe the usual cause is OpenCore's `Kernel > Quirks > PowerTimeoutKernelPanic`: it rewrites the kernel string `com.apple` to `not.apple`, pf's anchor check shares that string on kernel 25.6, and the stock `/etc/pf.conf` then counts as custom rules. The quirk is there to stop a kernel panic when a driver is slow to change power state: if your hackintosh boots and sleeps fine without it, set it to false and reboot; the check should then print an empty `net.filter_state` and `1`. Your own pf rules or firewall apps that load anchors cause the same thing. Section 7 of `check_compat.sh` does this check. Full analysis: [ax210-airdrop-awdl-hackintosh: skywalk-pf-quic.md](https://github.com/kevineduardo/ax210-airdrop-awdl-hackintosh/blob/main/docs/reference/skywalk-pf-quic.md).
- **Measure it:** `bash tools/compat/airdrop_measure.sh` prints the speed and connect times macOS logs for each transfer.
- **The very first send after boot** is often slower while rate control settles.

## Networks are missing from the Wi-Fi list

**Check for OpenCore Legacy Patcher root patches first,** not only the Wi-Fi ones: on one machine OCLP's audio patch alone left the list empty, with every scan failing, until OCLP's patches were removed (#20).

**If the list stays empty after macOS dropped the connection** (for example when you switch or log out of an account) and only turning Wi-Fi off and on brings it back: fixed in 0.6.0-beta.1. A background scan interrupted by the disconnect left a flag set, and the driver then refused every scan macOS asked for; `ItlwmScanStats` shows it as a third `busy` number that keeps rising (`busy=0/0/112/0`). From 0.6.0-beta.1 the driver also tells your router it's leaving, so the next join works on the first try.

From 0.6.0 the driver counts what happens to macOS's scan requests (#20, #24, #45). After the list has looked wrong for a while, run `ioreg -l -w0 | grep -E '"ItlwmScan(Stats|StatsSTA|Last)"'` and post the output with your report. It holds counts only, no network names. On Sonoma, `ItlwmScanStats` exists from 0.6.0-beta.1 (0.6.0-alpha.1 had no counters there).

## A new Bluetooth LE mouse or keyboard won't pair

Fixed in BTLEAdvFixup 0.9.1 (from 0.5.4-beta.2, #27). Earlier versions, with IntelBTPatcher disabled, let a new LE mouse or keyboard connect but never finish pairing; devices paired before kept working. Update BTLEAdvFixup. If a device still won't pair with 0.9.1, check `ioreg -l -w0 -d 1 | grep -E '"BTLEAdv(PipeHooks|LengthRewrites|LengthFailures)"'` while pairing (`PipeHooks` should be 5, and `LengthRewrites` should go up) and report it.

BTLEAdvFixup 0.9.2 (0.6.0-beta.1) also stops that fix from taking over the controller's event pipe when a pairing round doesn't finish ([PR #61](https://github.com/retropineaple/ForbiddenItlwm/pull/61)): with 0.9.1, that could leave USB devices unresponsive until a cold boot, or panic. `BTLEAdvLengthExpired` and `BTLEAdvLengthAborts` count rounds given up.

## AirPods drop out while playing Apple Music

On one AX211 machine, AirPods Pro 3 went silent and disconnected within seconds of starting Apple Music, then reconnected ([#52](https://github.com/retropineaple/ForbiddenItlwm/issues/52)). The fix there was `-btlfxa2dpcheck`, an option of the BlueToolFixup-FixA2DP fork (not of ForbiddenItlwm), which works alongside BTLEAdvFixup.

## Instant Hotspot, Sidecar or Universal Control don't work

Not supported yet. Instant Hotspot's Bluetooth connection to the iPhone times out (#39, #40): join the hotspot as a normal network instead, with its password, from the Wi-Fi list or with `networksetup -setairportnetwork en0 "<network name>" <password>`. Sidecar and Universal Control need AWDL traffic registration, which the driver doesn't do yet; Sidecar over USB works (#42).

## Bluetooth turns off after some hours, and `bluetoothd` crash reports say `KERN_MEMORY_ERROR`

Seen on Tahoe 26.7.3 ([#62](https://github.com/retropineaple/ForbiddenItlwm/issues/62)). `bluetoothd` crashes with `EXC_BAD_ACCESS (SIGBUS)`, restarts a few times, and Bluetooth then shows as Off. The crash reports name APFS: "compressed data hash mismatch".

BlueToolFixup and BTLEAdvFixup both patch `bluetoothd`'s code in memory, in the copy macOS shares between processes. When memory runs low, macOS drops part of a block of that code and reads it again later, and its integrity check then also covers the page that is still patched, which fails. It follows memory pressure, so it shows up after hours, not at boot.

Until there's a fix: a full power-off (not a restart) brings Bluetooth back. Please add the crash reports to #62, with your RAM size and `memory_pressure | tail -1`.

## Wi-Fi is off or greyed out, and there's no `en0`

The kext can be loaded (`kmutil` lists it) while the driver itself failed to start.
- **0.4.0 and 0.4.1 failed to start on some machines** (#14, #16). Use 0.5.0-test1 or later, or 0.3.x.
- **Check the start result:** `ioreg -l -w0 | grep -E '"ItlwmStart'`. From 0.5.0, a failed start leaves `ItlwmStartResult` = `failed` and the driver's own messages in `ItlwmStartLog`. Attach both to an issue.
- **Leftovers from an older AirportItlwm setup** (the cause in #14): The AirDrop-enabled AirportItlwm build needs macOS's own Wi-Fi stack. Revert OpenCore Legacy Patcher's "Modern Wireless" root patches, and remove from config.plist any `Kernel → Block` entry for `com.apple.iokit.IOSkywalkFamily`, any injected `IOSkywalkFamily.kext` or `IO80211FamilyLegacy.kext`, and any other `AirportItlwm.kext` or `itlwm.kext`.
- **`MinKernel`/`MaxKernel`:** they must match the kext's macOS version (see [INSTALL.md](INSTALL.md)).

## Normal Wi-Fi stopped working

- Remove any flag listed under "Don't use" in [BOOT-FLAGS.md](BOOT-FLAGS.md).
- A fast-rising `ITLAWDLCoexCountryNotices`, with `ITLAWDLCoexAdded` flipping between Yes and No, means the firmware is restarting around the listener. Boot without the `-itlawdl*` flags to confirm the station works on its own, then report it.
- **Wi-Fi keeps dropping and reconnecting while the AirDrop flags are on:** remove `-itlawdlcoexmulti` and keep the rest. The listener then stays on your Wi-Fi network's channel instead of its own, and Wi-Fi stays stable (#16). iPhone → Mac still uses block ack in this setup (about 5 MB/s); Mac → iPhone is slower. `ITLAWDLCoexAddsAfterRestart` rising means the firmware is restarting underneath.
- **Before 0.6.0, removing `-itlawdlcoexmulti` was also the advice where channel 149 isn't available (#29).** From 0.6.0 keep it: the listener follows the iPhone onto 44, and the same-channel fix ([PR #47](https://github.com/retropineaple/ForbiddenItlwm/pull/47)) only works with it (#63).
- Use USB tethering from the iPhone to get online while you test.

## iMessage or other Apple services don't work over Wi-Fi

Check the link quality macOS sees:

```bash
printf 'show State:/Network/Interface/en0/LinkQuality\n' | scutil
```

- **It should be 100 (or 50 or 10 on a weak signal).** ForbiddenItlwm 0.2.0 and later set it on Tahoe, 0.3.0 and later on Sequoia, and the Sonoma build sets it too. With -2 ("off"), Apple Push won't connect over Wi-Fi, and iMessage, FaceTime and other push-based services fail. Older builds and the original AirportItlwm for Tahoe leave it at -2.
- **If iMessage on the Mac only sends as text messages** (relayed through the iPhone) and they fail, re-enable the Mac on the iPhone: Settings → Apps → Messages → Text Message Forwarding. A new SMBIOS ROM makes the Mac a new device to Apple.
- **For iMessage on a hackintosh in general:** use a serial that Apple's coverage check calls invalid. Set ROM to the Wi-Fi card's permanent MAC address (`ifconfig en0 | grep ether`).

## Reporting a bug

Include:
- the output of `bash tools/compat/collect_hw_macos.sh` (read it first; it leaves out addresses and names)
- the `ioreg` lines above, taken right after the problem
- what you did, and the time

Don't post `-itlawdlsamples` output or iPhone sysdiagnoses publicly: they contain device names, addresses and personal data.
