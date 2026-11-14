# Troubleshooting

Start with `bash tools/compat/check_compat.sh`. Then read the driver's own state:

```bash
ioreg -l -w0 | grep -E '"ItlwmAWDL(InterfaceBuild|BuildCheck)"|"ITLAWDLCoex(Added|Channel|OwnWidth|CountryLearned|CountryNotices|PeerSyncFrames|PeerPresentEntries|TxOK|TxSubmitErrors)"'
```

| Key | Healthy value |
| --- | --- |
| `ItlwmAWDLInterfaceBuild` | `forbidden-0.5.4-beta.2`, `forbidden-0.5.4-beta.2-sequoia` or `forbidden-0.5.4-beta.2-sonoma` |
| `ItlwmAWDLBuildCheck` | `verified` (`expected: …` on a 15.8.x kernel that wasn't checked offline). Anything starting with `blocked` means AirDrop is off on this macOS build: see below |
| `ITLAWDLCoexAdded` | Yes: the AirDrop listener exists |
| `ITLAWDLCoexChannel`, `ITLAWDLCoexOwnWidth` | 149 and 80 |
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

The firmware opens channel 149 only after a nearby network tells it the country.
- Make sure some 5 GHz network that advertises a country is in range. Switching on an iPhone's Personal Hotspot nearby, without joining it, has worked.
- Wait a minute after it appears.
- Some countries don't allow channels 149 to 161, or allow them only at 20 or 40 MHz. There AirDrop stays on channel 6. The checker warns about known ones.
- **Channels 149 to 161 marked passive** (China, for example): from 0.5.0, once the hackintosh hears a Wi-Fi network's beacon on one of these channels, the listener may use it, as on Linux. `ITLAWDLCoexBeaconHints` shows which channels were heard (bits 0 to 3 = 149, 153, 157, 161). A router on 149 at 80 MHz covers all four. With no network on them nearby, AirDrop stays on 6.
- The driver never overrides the country's rules, and `itlwm_cc` doesn't help.

## The iPhone doesn't list the Mac

- **Bluetooth:** it must be on, with BTLEAdvFixup for your macOS version loaded, `-btleadv` set and IntelBTPatcher disabled. AirDrop finds devices over Bluetooth LE first. BTLEAdvFixup's patterns only match specific builds (26.7.1 and, from 0.8.1, 26.7.3 on Tahoe; 15.8, 15.8.2 and 15.8.3 on Sequoia; from 0.9.0, 14.8.9 on Sonoma): `check_compat.sh` shows whether they match yours. To check it's running: `ioreg -l -w0 -d1 | grep '"BTLEAdv'` should show `BTLEAdvHookRouted` = 1. On Sequoia, BTLEAdvFixup before 0.8.3 never started.
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

## Transfers are slower than expected

- **Check the iPhone's Wi-Fi first.** AirDrop gets the share of the iPhone's radio time that its own Wi-Fi leaves over. If the iPhone isn't on Wi-Fi, or is on channel 149, it gets 15 of 16 slots (about 22 MB/s). On a quiet network on another channel it gets 11 (about 15 MB/s), on a busy one 7 (about 6 MB/s). `ITLAWDLCoexPeerPresentEntries` shows the current number.
- **Check the channel:** on 6, everything is very slow. The listener can drop to 6 for a while when the firmware briefly loses the country (`ITLAWDLCoexCountryLearned` No).
- **Mac → iPhone much slower than iPhone → Mac:** a known open problem on some setups (#22, #24): the iPhone never accepts block ack (`ITLAWDLCoexBaTxStateName` stays `asking`), so every frame goes out singly. It happens when the Mac's own Wi-Fi is on the same channel as the AirDrop listener (usually 149) (#24). **Workaround:** put your router (or the Mac's network) on another channel, such as 36–48 or 157; AirDrop stays on 149 and block ack then forms within a second. Neither of 0.5.3's test flags (`-itlawdlbaaskshared`, `-itlawdlhideinfra`) fixed it; the cause is still being investigated.
- **Measure it:** `bash tools/compat/airdrop_measure.sh` prints the speed and connect times macOS logs for each transfer.
- **The very first send after boot** is often slower while rate control settles.

## A new Bluetooth LE mouse or keyboard won't pair

Fixed in BTLEAdvFixup 0.9.1 (from 0.5.4-beta.2, #27). Earlier versions, with IntelBTPatcher disabled, let a new LE mouse or keyboard connect but never finish pairing; devices paired before kept working. Update BTLEAdvFixup. If a device still won't pair with 0.9.1, check `ioreg -l -w0 -d 1 | grep -E '"BTLEAdv(PipeHooks|LengthRewrites|LengthFailures)"'` while pairing (`PipeHooks` should be 5, and `LengthRewrites` should go up) and report it.

## Wi-Fi is off or greyed out, and there's no `en0`

The kext can be loaded (`kmutil` lists it) while the driver itself failed to start.
- **0.4.0 and 0.4.1 failed to start on some machines** (#14, #16). Use 0.5.0-test1 or later, or 0.3.x.
- **Check the start result:** `ioreg -l -w0 | grep -E '"ItlwmStart'`. From 0.5.0, a failed start leaves `ItlwmStartResult` = `failed` and the driver's own messages in `ItlwmStartLog`. Attach both to an issue.
- **Leftovers from an older AirportItlwm setup** (the cause in #14): ForbiddenItlwm needs macOS's own Wi-Fi stack. Revert OpenCore Legacy Patcher's "Modern Wireless" root patches, and remove from config.plist any `Kernel → Block` entry for `com.apple.iokit.IOSkywalkFamily`, any injected `IOSkywalkFamily.kext` or `IO80211FamilyLegacy.kext`, and any other `AirportItlwm.kext` or `itlwm.kext`.
- **`MinKernel`/`MaxKernel`:** they must match the kext's macOS version (see [INSTALL.md](INSTALL.md)).

## Normal Wi-Fi stopped working

- Remove any flag listed under "Don't use" in [BOOT-FLAGS.md](BOOT-FLAGS.md).
- A fast-rising `ITLAWDLCoexCountryNotices`, with `ITLAWDLCoexAdded` flipping between Yes and No, means the firmware is restarting around the listener. Boot without the `-itlawdl*` flags to confirm the station works on its own, then report it.
- **Wi-Fi keeps dropping and reconnecting while the AirDrop flags are on, or channel 149 isn't available on your network:** remove `-itlawdlcoexmulti` and keep the rest. The listener then stays on your Wi-Fi network's channel instead of its own. Wi-Fi stays stable (#16), and AirDrop works where 149 can't be used (#29). From 0.5.4, iPhone → Mac still uses block ack in this setup (about 5 MB/s); Mac → iPhone is slower. `ITLAWDLCoexAddsAfterRestart` rising means the firmware is restarting underneath.
- Use USB tethering from the iPhone to get online while you test.

## iMessage or other Apple services don't work over Wi-Fi

Check the link quality macOS sees:

```bash
printf 'show State:/Network/Interface/en0/LinkQuality\n' | scutil
```

- **It should be 100 (or 50 or 10 on a weak signal).** ForbiddenItlwm 0.2.0 and later set it on Tahoe, and 0.3.0 and later on Sequoia. With -2 ("off"), Apple Push won't connect over Wi-Fi, and iMessage, FaceTime and other push-based services fail. Older builds and the original AirportItlwm for Tahoe leave it at -2.
- **If iMessage on the Mac only sends as text messages** (relayed through the iPhone) and they fail, re-enable the Mac on the iPhone: Settings → Apps → Messages → Text Message Forwarding. A new SMBIOS ROM makes the Mac a new device to Apple.
- **For iMessage on a Hackintosh in general:** use a serial that Apple's coverage check calls invalid. Set ROM to the Wi-Fi card's permanent MAC address (`ifconfig en0 | grep ether`).

## Reporting a bug

Include:
- the output of `bash tools/compat/collect_hw_macos.sh` (read it first; it leaves out addresses and names)
- the `ioreg` lines above, taken right after the problem
- what you did, and the time

Don't post `-itlawdlsamples` output or iPhone sysdiagnoses publicly: they contain device names, addresses and personal data.
