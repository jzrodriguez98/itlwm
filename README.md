<p align="center"><img src="docs/images/icon-512.png" alt="ForbiddenItlwm logo" width="180"></p>

<h1 align="center">ForbiddenItlwm</h1>

<p align="center"><em>Because AirDrop was never supposed to work on Intel Wi-Fi.</em></p>

**AirDrop for Intel Wi-Fi cards on macOS.** ForbiddenItlwm is a fork of AirportItlwm that adds AWDL, the peer-to-peer Wi-Fi link AirDrop runs on. Apple's own Wi-Fi stack does the rest. Normal Wi-Fi stays connected while AirDrop works.

> **New alpha: [0.7.0-alpha.4](https://github.com/retropineaple/ForbiddenItlwm/releases/tag/v0.7.0-alpha.4).** The last alpha of 0.7.0: faster Mac → iPhone transfers by default, hidden networks and 802.1X fixes (PR #107), a fix for one-antenna cards (#97) and for `bluetoothd` being killed after long uptimes (BTLEAdvFixup 0.9.8, #62). Experimental: a second 5 GHz AirDrop channel with `itlawdlsched=1` (#45) and packed frames when the Mac sends (`-itlawdlamsdutx`). AirDrop still needs only `-btleadv` in `boot-args`; the experimental parts stay off unless you add their [boot flags](docs/BOOT-FLAGS.md#experimental). See the [CHANGELOG](CHANGELOG.md).

> **Public beta: [0.6.0-beta.4](https://github.com/retropineaple/ForbiddenItlwm/releases/tag/v0.6.0-beta.4).** Works on macOS Tahoe 26.7.x and Sequoia 15.8.x, with a Sonoma 14.8.9 test build. Each macOS version has its own kexts. Fixes come out often: before reporting a problem, update to the newest release (**Watch → Custom → Releases** to be notified).

## ⚠️ Read this first

> [!WARNING]
> **Use it at your own risk.** ForbiddenItlwm is experimental beta software that runs inside the macOS kernel. A bug can cause kernel panics, bootloops, lost Wi-Fi or Bluetooth, failed transfers, or a hackintosh that won't boot from that EFI. It comes with no warranty of any kind, and I am not liable for any damage or data loss.

> [!IMPORTANT]
> **This project was built with the use of AI.** Most of the driver code, the reverse-engineering and the test tools were written with the help of AI (Claude). I am not a professional kernel developer. I closely monitored and directed the work, researched and reviewed it, and ran every hardware test on my own hardware, but AI written code can still contain mistakes that testing on a few machines won't catch. If you'd rather not run AI-assisted kernel code, please don't install it.

- Test from a USB stick with a copy of your EFI, never your only working one.
- Run the [compatibility checker](#will-it-work-on-my-hackintosh) first.
- **Before you update macOS, boot once without `-btleadv` and `-btleadvnodupfilter`.** Otherwise an incremental update can fail.

## What works

On the project's test machine (AX211, macOS 26.7.1, iPhone 11), with normal 5 GHz Wi-Fi connected the whole time:

| | Result |
| --- | --- |
| Mac → iPhone | Works, connects in 1 to 4 s. About 22 MB/s up to 0.7.0-alpha.3; with 0.7.0-alpha.4, 25 to 27 MB/s on average and up to 33 MB/s (105 MB files, iPhone on 149) |
| iPhone → Mac | Works. About 20 MB/s. A cold connect takes 3 to 10 s up to 0.6.0-beta.4; with 0.7.0-alpha.1's experimental flags it takes about 1 to 2 s |
| Handoff, Universal Clipboard | Work |
| iMessage and push over Wi-Fi | Work |

Speed depends on the iPhone's own Wi-Fi: full speed when it's off Wi-Fi or on channel 149, less when it's busy on another channel. Users with other machines report similar results; see [where it was tested](docs/TESTED-HARDWARE.md).

Users also report **AirPlay** working over this driver, from an iPad to the hackintosh ([#29](https://github.com/retropineaple/ForbiddenItlwm/issues/29), [#42](https://github.com/retropineaple/ForbiddenItlwm/issues/42)) and from the hackintosh to another Mac ([#42](https://github.com/retropineaple/ForbiddenItlwm/issues/42)), and AirDrop with iPads. Neither was tested on the project's machine.

## Supported macOS and cards

| macOS | Builds | AirDrop |
| --- | --- | --- |
| Tahoe | 26.7.1, 26.7.2, 26.7.3; 26.7 from 0.7.0-alpha.2; 26.7.4 beta (25G422) from 0.7.0-alpha.3 | Works (tested on 26.7.1, users on 26.7.2 and 26.7.3). 0.7.0-alpha.2 adds 26.7 (25G229, the same Wi-Fi stack and kernel as 26.7.1) and 26.7.2's other build (25G330), checked offline. 0.7.0-alpha.3 adds the 26.7.4 beta 25G422 from a user's check-my-mac report; the final 26.7.4 may be another build |
| Sequoia | 15.8, 15.8.1, 15.8.2, 15.8.3; 15.7.3, 15.7.4, 15.7.8, 15.7.9 from 0.7.0-alpha.2 | Works from 0.5.1-test1 (users on 15.8.1 to 15.8.3). Up to 0.7.0-alpha.1, 15.8.1 and 15.8.2 weren't on the list, so the announcement copy stays off there (from 0.6.0-beta.1) and other devices may not list the Mac. 0.7.0-alpha.2 adds them, checked offline (15.8.1 runs 15.8's Wi-Fi stack, 15.8.2 15.8.3's), and 15.7.3, 15.7.4, 15.7.8 and 15.7.9 (the same AirDrop code as 15.8, and new BTLEAdvFixup patterns for 15.7.3, 15.7.8 and 15.7.9) |
| Sonoma | 14.8.9; 14.8.3, 14.8.4, 14.8.7, 14.8.8 from 0.7.0-alpha.2 | Test build. From 0.6.0-beta.3 macOS creates `awdl0`, and one user reports AirDrop working both ways on an AX200 at 5–7 MB/s ([PR #77](https://github.com/retropineaple/ForbiddenItlwm/pull/77), [#55](https://github.com/retropineaple/ForbiddenItlwm/issues/55)). Not tested here. 0.7.0-alpha.2 adds 14.8.3, 14.8.4, 14.8.7 and 14.8.8, checked offline, with new BTLEAdvFixup patterns for 14.8.7 |

On another build of a supported macOS version the driver keeps AirDrop off and works as plain Wi-Fi, apart from "expected" Sequoia 15.8.x kernels (AirDrop starts without the announcement copy) and with `-itlawdlanybuild`. On another macOS version the kext doesn't start: use the build for your version. BTLEAdvFixup's Bluetooth patterns for 15.7.4, 14.8.3 and 14.8.4 haven't been checked yet (no bluetoothd from those builds). [docs/TESTED-HARDWARE.md](docs/TESTED-HARDWARE.md) has every build and report.

**Cards:** Intel Wi-Fi 6 and 6E cards. The project tests the AX211; users report the AX201, AX210, AX200 and an AX1690i working. Older 7000, 8000 and 9000-series cards (such as the 7265, the 9260, and the 9560 on 8th and 9th-gen Intel boards) run on a part of the driver without AirDrop code, so they get normal Wi-Fi only ([#37](https://github.com/retropineaple/ForbiddenItlwm/issues/37)). The 9560, 9461 and 9462 on 10th-gen (Ice Lake, Comet Lake) and newer boards run on the newer part, which has the AirDrop code; one is being tested ([#87](https://github.com/retropineaple/ForbiddenItlwm/issues/87)). On one AX101 the firmware kept restarting with AirDrop on ([#97](https://github.com/retropineaple/ForbiddenItlwm/issues/97)); 0.7.0-alpha.4 has a candidate fix, waiting for confirmation on an AX101. `check_compat.sh` tells which part your card uses.

**No OCLP Wi-Fi patches.** ForbiddenItlwm needs macOS's own Wi-Fi stack. If you used OpenCore Legacy Patcher's "Modern Wireless" root patch for an older AirportItlwm, revert it, and also remove what it added to `config.plist` (see [INSTALL](docs/INSTALL.md#before-you-start)). Left in place, they stop Wi-Fi from starting.

## Will it work on my hackintosh?

```bash
bash tools/compat/check_compat.sh
```

Read-only: it changes nothing and sends nothing anywhere. More in [tools/compat](tools/compat/README.md).

**Channels 149 and 44, and your country.** AirDrop is fast on 5 GHz at 80 MHz. Apple devices use channel 149 or 44 for it, each by its own country rules (in Japan, Germany and Russia, for example, iPhones use 44).
- **The card has to learn your country first,** from a nearby Wi-Fi network that advertises it (most routers do; an iPhone's Personal Hotspot switched on nearby also works). Until then it falls back to channel 6.
- **From 0.6.0-alpha.1 the listener follows your iPhone** onto 44 when the iPhone uses 44 ([#17](https://github.com/retropineaple/ForbiddenItlwm/issues/17), [PR #21](https://github.com/retropineaple/ForbiddenItlwm/pull/21)). Up to 0.5.4 it stayed on 149 or fell back to channel 6, which works but is slow.
- **From 0.7.0-alpha.1, with `itlawdlsched=1`,** the listener uses the AirDrop channel macOS itself picks with Apple's rules, instead of guessing from what nearby devices announce, and visits channel 6 in the slot Apple devices use it. If macOS names no usable channel, it falls back to the old choice.
- **Some countries have no channel 149** (Turkey, Egypt and Saudi Arabia, for example), and some allow 149 or 44 only at 20 or 40 MHz. Where neither is usable at 80 MHz, AirDrop uses 149 or 44 at 20 MHz if your iPhone uses that channel (with `itlawdlsched=1`, if macOS picked it), and otherwise channel 6.
- **Your router in AirDrop's 80 MHz block on another main channel** (153–161 at 80 MHz with AirDrop on 149, or 36, 40 or 48 with 44), **or at 160 MHz over AirDrop's channel:** up to 0.7.0-alpha.1 AirDrop drops to 20 MHz there, or avoids that channel ([#26](https://github.com/retropineaple/ForbiddenItlwm/issues/26), [#101](https://github.com/retropineaple/ForbiddenItlwm/issues/101)). From 0.7.0-alpha.2, with `itlawdlsched=1`, it stays at 80 MHz there, as on a real Mac. On the project's AX211 that was tested for reception and Wi-Fi speed, the 160 MHz case with a simulated 160 MHz link; no AirDrop transfer has been tested in these layouts yet.
- **Where the card marks a channel passive** (China's 149, Japan's 44), AirDrop uses it once it has heard a Wi-Fi network there, or from 0.6.0 while your Mac's own Wi-Fi is connected nearby in the same channel group.

The checker shows your country and whether channels 149 and 44 are open; [TROUBLESHOOTING](docs/TROUBLESHOOTING.md#the-listener-is-on-channel-6-or-countrylearned-is-no) explains the rest.

**Your macOS build isn't supported yet?** Run `perl tools/check-my-mac.pl` and paste its output in [discussion #98](https://github.com/retropineaple/ForbiddenItlwm/discussions/98). It reads the Apple code the kexts rely on, on your Mac, and reports what's needed to add support for your build, so you don't have to send in system files. It sends nothing itself. More in [CHECK-MY-MAC](docs/CHECK-MY-MAC.md).

## Install

See **[docs/INSTALL.md](docs/INSTALL.md)**. In short: on a USB stick with a copy of your EFI, replace `AirportItlwm.kext` with this branch's matching `AirportItlwm.kext`, add this branch's `IntelBTPatcher.kext`, add the [boot flags](docs/BOOT-FLAGS.md), and boot from the stick. Keep the original IntelBTPatcher implementation disabled.

## After installing: what to test

Boot from the USB stick, join your Wi-Fi network, wait a minute, then check:

1. **The driver runs:** `bash tools/compat/check_compat.sh` shows the AirDrop build running and your card and Bluetooth as OK.
2. **Wi-Fi works:** browse, and try a speed test.
3. **Bluetooth works:** it's on, and `ioreg -l -w0 -d1 | grep '"BTLEAdvHookRouted'` shows 1.
4. **AirDrop's channel:** `ioreg -l -w0 | grep '"ITLAWDLCoexChannel"'` shows 149, or 44 where your iPhone uses 44 (6 means slow; see above).
5. **AirDrop both ways:** send a large file from the Mac to the iPhone, and one from the iPhone to the Mac. Run `bash tools/compat/airdrop_measure.sh` while you do, to see the speed and connect time.
6. **iMessage:** send and receive an iMessage on the Mac. If it fails, `printf 'show State:/Network/Interface/en0/LinkQuality\n' | scutil` should show 100 (or 50 or 10 on a weak signal); see [TROUBLESHOOTING](docs/TROUBLESHOOTING.md#imessage-or-other-apple-services-dont-work-over-wi-fi).

Please report what you find, working or not, in a [GitHub issue](https://github.com/retropineaple/ForbiddenItlwm/issues), with your card, macOS build and the checker's output.

**Security problems** (anything that could let a nearby device or another program crash the Mac or read memory): please don't open a public issue. See [SECURITY.md](SECURITY.md).

## Known limitations

- **Mac → iPhone can still be slower than iPhone → Mac** on some setups ([#24](https://github.com/retropineaple/ForbiddenItlwm/issues/24), [#63](https://github.com/retropineaple/ForbiddenItlwm/issues/63)). 0.6.0's same-channel fix ([PR #47](https://github.com/retropineaple/ForbiddenItlwm/pull/47)) solved the main case (#22).
- **Slow connects, mostly iPhone → Mac, and a failed first send after the iPhone was idle** (sending again works). 0.7.0-alpha.1's experimental flags (`itlawdlsched=1 -btleadvnodupfilter`, see [BOOT-FLAGS](docs/BOOT-FLAGS.md#experimental)) address the causes found on the project's hackintosh (AX211): connects take about 1 to 2 s, the first send no longer fails, even after the iPhone sat idle for a long time, and Mac → iPhone no longer sits on "Waiting". Reports from other machines are needed. In 0.7.0-alpha.1 the scheduler runs on AX210-family cards only; 0.7.0-alpha.2 adds the AX200 family.
- **Normal Wi-Fi loses some speed while AirDrop's listener runs** (they share the radio).
- **Boot flags:** up to 0.7.0-alpha.1 a long list; from 0.7.0-alpha.2 only `-btleadv` (the rest are defaults). Sleep untested on the project's hackintosh (one user reports four of five nights fine; 0.6.0-beta.4 fixes the failed wake they caught, [#38](https://github.com/retropineaple/ForbiddenItlwm/issues/38)), tested with iPhones (users report iPads working, and AirDrop with a Mac as the other device, [#33](https://github.com/retropineaple/ForbiddenItlwm/issues/33), [#81](https://github.com/retropineaple/ForbiddenItlwm/issues/81)).
- **Not working yet:**
  - **Instant Hotspot,** joining the iPhone's hotspot from the Wi-Fi menu: its Bluetooth connection to the iPhone times out ([#39](https://github.com/retropineaple/ForbiddenItlwm/issues/39), [#40](https://github.com/retropineaple/ForbiddenItlwm/issues/40)). Join the hotspot as a normal network, with its password, instead.
  - **Sidecar and Universal Control over Wi-Fi:** the driver doesn't support the traffic registration they need ([#42](https://github.com/retropineaple/ForbiddenItlwm/issues/42)). Sidecar over USB works.
  - **Internet Sharing over Wi-Fi:** the card can't act as an access point ([#28](https://github.com/retropineaple/ForbiddenItlwm/issues/28)). Sharing over Bluetooth or USB works.
- **One Apple device at a time for fast transfers.** The driver keeps block ack with one device, as long as that device has exchanged data in the last ten minutes. A second Apple device nearby (another Mac, an iPad) can then keep an iPhone waiting ([#81](https://github.com/retropineaple/ForbiddenItlwm/issues/81)). From 0.7.0-alpha.2 the opt-in `-itlawdlpeerhandoff` hands it over once that device is idle, and the experimental `-itlawdlmultipeer` keeps block ack with each device instead, as a real Mac does (untested here with more than one Apple device; on one tester's setup Block Ack to the second device sometimes never starts, [#103](https://github.com/retropineaple/ForbiddenItlwm/issues/103)). See TROUBLESHOOTING.
- **AirDrop needs the Mac to be connected to a Wi-Fi network.** The AirDrop listener runs beside your Wi-Fi connection: with Wi-Fi on but no network joined, transfers stay on "Waiting". A real Mac doesn't need a network for this.
- **WPA3:** opt-in with `-itlwmwpa3` (SAE/H2E, PMF), in the Tahoe and Sequoia builds. Without it, and in the Sonoma build, WPA3-only networks are refused.
- **The Sonoma kext's Wi-Fi code** takes paths of its own (join, scan, keys, teardown) that the Tahoe and Sequoia kexts don't use. They had their first security review for 0.6.0; one user runs it on 14.8.9 (#77), and it hasn't been tested here.

What's planned: [ROADMAP](docs/ROADMAP.md).

## Documentation

| Document | What's in it |
| --- | --- |
| [INSTALL](docs/INSTALL.md) | Building, OpenCore setup, first boot, uninstalling |
| [BOOT-FLAGS](docs/BOOT-FLAGS.md) | The flags the beta needs, and the experimental ones |
| [TROUBLESHOOTING](docs/TROUBLESHOOTING.md) | When the iPhone can't see the Mac, it's slow, or Wi-Fi breaks |
| [TESTED-HARDWARE](docs/TESTED-HARDWARE.md) | Every tested and reported machine, card and macOS build |
| [ROADMAP](docs/ROADMAP.md) | What's being worked on and what's planned |
| [HOW-IT-WORKS](docs/HOW-IT-WORKS.md) | How the driver gives macOS an AWDL radio |
| [CHECK-MY-MAC](docs/CHECK-MY-MAC.md) | Sending in data so an unsupported macOS build can be added |
| [tools/compat](tools/compat/README.md) | Compatibility checker, transfer measurement, hardware reports |
| [CHANGELOG](CHANGELOG.md) | Releases |
| [CONTRIBUTING](CONTRIBUTING.md) | How to make a pull request that can be reviewed and merged |

## Credits

ForbiddenItlwm builds on a lot of other people's work:

- **[itlwm / AirportItlwm](https://github.com/OpenIntelWireless/itlwm)** by zxystd and the OpenIntelWireless contributors: the Intel Wi-Fi driver this is built on.
- **laobamac**, for AirportItlwm on macOS Tahoe and Sequoia (version 2.4.1), the exact code this fork starts from, including the native Sequoia Wi-Fi support the Sequoia build is based on.
- **kgp-macPro/AirportItlwm-Tahoe**, named in the base code's notes as the basis of its DMA design.
- **[OpenBSD](https://www.openbsd.org)** for net80211 and the iwx, iwm and iwn drivers.
- **[Linux iwlwifi](https://wireless.wiki.kernel.org/en/users/drivers/iwlwifi)** and **Intel**, for the firmware and as a reference. No code was copied.
- **[FranciumOS-org/AirPort_RTW89](https://github.com/FranciumOS-org/AirPort_RTW89)** (GPL-2.0): it showed the approach and was used to cross-check the wire format.
- **[seemoo-lab/owl](https://github.com/seemoo-lab/owl)** and the Open Wireless Link research, used to cross-check AWDL frame formats and timing. No code was copied.
- **[Acidanthera](https://github.com/acidanthera)**, for Lilu, MacKernelSDK and BlueToolFixup. BTLEAdvFixup's page hook follows BlueToolFixup.
- **[IntelBluetoothFirmware / IntelBTPatcher](https://github.com/OpenIntelWireless/IntelBluetoothFirmware)** (GPL-3.0): BTLEAdvFixup's HCI hook follows IntelBTPatcher.
- Apple's XNU sources were read as a reference.

ForbiddenItlwm isn't affiliated with or endorsed by Apple or Intel. AirDrop is a trademark of Apple Inc.

## License

- **The Wi-Fi driver:** GPL-2.0, see [LICENSE](LICENSE). Files from OpenBSD keep their own ISC and BSD notices.
- **BTLEAdvFixup:** GPL-3.0-only, see [BTLEAdvFixup/LICENSE](BTLEAdvFixup/LICENSE).
- **Intel firmware** in `itlwm/firmware`: Intel's redistribution licence, see [iwlwifi-firmware-license](iwlwifi-firmware-license).
