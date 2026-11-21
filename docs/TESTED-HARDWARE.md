# Where it was tested

Every result the project measured comes from this one setup. Reports from other users are listed separately under [User reports](#user-reports). Anything else is untested.

## The hackintosh

| | |
| --- | --- |
| Laptop | HP Envy x360 13-bf (2022, convertible) |
| CPU | Intel Core i7-1250U (12th gen, Alder Lake-U, 2 P-cores + 8 E-cores, 12 threads) |
| Memory | 16 GB |
| Graphics | Intel Iris Xe (internal 2880 × 1800 OLED) |
| Wi-Fi | Intel AX211 (Wi-Fi 6E, CNVi, PCI device 8086:51F0), firmware `iwlwifi-so-a0-gf-a0-68` |
| Bluetooth | Intel AX211 Bluetooth on USB, 8087:0033 (Bluetooth 5.3), firmware loaded by IntelBluetoothFirmware |
| macOS | macOS Tahoe 26.7.1 (25G241). 26.7.2 (25G332) and 26.7.3 (25G342) verified offline, and reported working by users. Sequoia 15.8.x not tested on this machine |
| SMBIOS | MacBookPro16,2 |
| Bootloader | OpenCore 1.0.8 (release build) |

Kexts used with ForbiddenItlwm:

| Kext | Version |
| --- | --- |
| ForbiddenItlwm | 0.1.0-beta1, 0.2.0-beta1, 0.4.0-beta1's changes in development builds, 0.5.0-test1, 0.6.0-alpha.1's changes in a development build, 0.6.0-beta.1 and 0.6.0-beta.2 (Tahoe, listener on 149) |
| BTLEAdvFixup | 0.8.0, 0.8.2's changes in a development build, 0.9.0, 0.9.1, 0.9.2 and 0.9.3 (Tahoe) |
| Lilu | 1.7.2 |
| IntelBluetoothFirmware | 2.5.1 |
| BlueToolFixup | 2.7.3 |
| IntelBTPatcher | Disabled |

The laptop also loads kexts for its own hardware (graphics, audio, touchscreen, input, battery). They aren't part of ForbiddenItlwm. The laptop's complete OpenCore EFI, with ForbiddenItlwm in it, and its setup guide are published at [retropineaple/whateverxe-hp-envy-x360](https://github.com/retropineaple/whateverxe-hp-envy-x360).

## The iPhone

| | |
| --- | --- |
| Model | iPhone 11 |
| iOS | iOS 27.2 (24B119) |
| Wi-Fi and Bluetooth | Built in (Wi-Fi 6, Bluetooth 5.0) |
| AirDrop setting | Contacts Only on both devices for most tests, Everyone for 10 Minutes for some |

## Conditions

- **The hackintosh's Wi-Fi:** connected to a normal 5 GHz network on channel 36 at 80 MHz for the coexistence results. AirDrop ran on channel 149 at 80 MHz beside it.
- **The country:** the firmware learned it from nearby networks.
- **The iPhone's Wi-Fi:** tested in three states, which change the speed (see the README):
  - not associated
  - associated on channel 149
  - associated on channel 36
- **Transfers:** mostly 100 MB files, plus iPhone sysdiagnose files of up to about 500 MB, in both directions.
- **When:** November 2026.

## macOS builds

Which macOS builds AirDrop starts on, and what is known about each. Each macOS version has its own kexts.

| macOS | Build | Status |
| --- | --- | --- |
| Tahoe | 26.7.1 (25G241) | Tested on hardware |
| Tahoe | 26.7.3 (25G342) | Reported working by a user (AX210). Wi-Fi side verified offline from Apple's Kernel Debug Kit, BTLEAdvFixup's patterns from Apple's installer |
| Tahoe | 26.7.2 (25G332) | Reported working by a user (AX210). Wi-Fi side verified offline from Apple's Kernel Debug Kit. BTLEAdvFixup's patterns are the same bytes as 26.7.3's |
| Sequoia | 15.8 (24H23) | Verified offline from Apple's Kernel Debug Kit. AirDrop needs 0.5.1-test1 or later; not yet confirmed by a user on this build |
| Sequoia | 15.8.1 (24H32) | Runs a verified kernel, so the build check passes. **AirDrop works both ways with 0.5.1-test1**, reported by users (AX201, AX210; [#13](https://github.com/retropineaple/ForbiddenItlwm/issues/13), [#22](https://github.com/retropineaple/ForbiddenItlwm/issues/22)) |
| Sequoia | 15.8.2 (24H232) | Same kernel as 15.8.3, so the build check passes. BTLEAdvFixup's patterns match. **AirDrop works both ways with 0.5.1-test1**, reported by a user (AX201, [issue #7](https://github.com/retropineaple/ForbiddenItlwm/issues/7)). Earlier versions didn't send |
| Sequoia | 15.8.3 (24H241) | Wi-Fi side verified offline from Apple's Kernel Debug Kit, BTLEAdvFixup's patterns from Apple's installer. **AirDrop works both ways with 0.5.1-test1**, reported by a user (AX201, [#16](https://github.com/retropineaple/ForbiddenItlwm/issues/16)) |
| Sonoma | 14.8.9 (23J631) | Test builds from 0.5.0-test1. Wi-Fi side verified offline from Apple's Kernel Debug Kit, BTLEAdvFixup's patterns from Apple's installer. First hardware report (0.5.4-beta.2, AX210, [#55](https://github.com/retropineaple/ForbiddenItlwm/issues/55)): the build check passes and the listener starts on 149, but macOS doesn't ask for `awdl0` (`ItlwmAWDLCreateRequests` 0). Fixed in 0.6.0-beta.3 ([PR #77](https://github.com/retropineaple/ForbiddenItlwm/pull/77)): one user reports AirDrop working both ways on an AX200 |
| Sonoma | Other 14.4 to 14.8.x builds | The Sonoma kext runs as plain Wi-Fi; AirDrop stays off |
| Any other build | | AirDrop stays off and normal Wi-Fi works |

The driver checks the build itself when it starts. On a build it doesn't know, it keeps AirDrop off instead of risking a kernel panic. BTLEAdvFixup's patterns are exact bytes from specific `bluetoothd` builds (26.7.1, and 26.7.2 and 26.7.3, which share theirs, on Tahoe; 15.8, 15.8.2 and 15.8.3 on Sequoia; 14.8.9 on Sonoma). On other builds, `tools/compat/check_compat.sh` shows whether they still match.

## User reports

Users on Reddit and GitHub have reported:

| Card | Reported on |
| --- | --- |
| Intel AX201 | macOS 26.7.1 |
| Intel AX211, on other machines than the test laptop | macOS 26.7.1 |
| Intel AX210 (desktop, Intel NUC8) | macOS 26.7.2, with 0.3.1-test1 (issue #8) |
| Intel AX210 | macOS 26.7.3, with 0.3.1-test1 (issue #5) |
| Intel AX201 | macOS Sequoia 15.8.2, with 0.3.0-beta1 and 0.4.1-beta1: Wi-Fi works; with 0.4.1 each device lists the other, but transfers don't work; with 0.5.0, `awdl0` is still never created; **with 0.5.1-test1, AirDrop works both ways** (issue #7) |
| Intel AX201 | macOS Sequoia 15.8, with 0.4.1-beta1: Wi-Fi works; the iPhone lists the Mac, but transfers don't work (issue #13, fixed in 0.5.1) |
| Intel AX201 (CNVi) | macOS Sequoia 15.8.3, with 0.3.0-beta1: Wi-Fi works, AirDrop transfers don't (fixed in 0.5.1). 0.4.x didn't start (issue #16, fixed in 0.5.0) |
| Intel AX210 (AMD Ryzen 7 5700X desktop) | macOS 26.7.3, with 0.5.0-test1: Wi-Fi and AirDrop work, listener on 149 at 80 MHz (issue #14) |
| Intel AX200 (AMD Ryzen 5 5600H laptop) | macOS Sequoia 15.6, with 0.4.1-beta1 plus local fixes, including the 0.5.1 pool-type fix: AirDrop works both ways on 149 at 80 MHz (issue #19) |
| Intel AX201 (Comet Lake-H, HP) | macOS Sequoia 15.8.3, with 0.5.1-test1: AirDrop works both ways (issue #16) |
| Intel AX201 (Comet Lake-H, MSI) | macOS Sequoia 15.8.1, with 0.5.1: AirDrop works both ways (issue #13) |
| Intel AX210 (AMD Ryzen 7 5800H laptop) | macOS Sequoia 15.8.1, with 0.5.1-test1: AirDrop works both ways; Mac → iPhone slower (issue #22). With 0.5.3-test1: AirDrop and Handoff work, AirPlay from it to a Mac mini works, Sidecar works over USB but not over Wi-Fi (issue #42) |
| Intel AX210 (Xiaomi Mi Notebook Pro) | macOS 26.7.2, with 0.5.0-test1: AirDrop works both ways, listener on 149 at 80 MHz in China (issue #18) |
| Intel AX201 (Tiger Lake-H, Dell G15) | macOS 26.7.3, with 0.5.0-test1: AirDrop works both ways; on channel 6 in Japan (issue #23) |
| Intel AX201 (Tiger Lake, dynabook G83) | macOS Sequoia 15.8.3, with 0.5.3-test1: AirDrop works both ways, also with an iPad, and iPad → Mac AirPlay works. On a network without 149, Mac → iPad works only without `-itlawdlcoexmulti` (issue #29) |
| Intel AX210 (Dell Precision 5540) | macOS 26.7.3, with 0.5.3-test1: Mac → iPhone works; iPhone → Mac stalls on large photos and videos (issue #26, open) |
| Intel AX411 class (AX1690i) | macOS 26.7.2, with 0.4.1-beta1: AirDrop works both ways, on channel 6 (issue #15) |
| Intel AX211 (Lenovo ThinkPad E16 Gen 3, Raptor Lake, PCI 8086:51F1) | macOS 26.7.1, with 0.3.1-test1: AirDrop works both ways (issue #6, which found the frame padding fixed in that build) |
| Intel AX210 (Lenovo ThinkPad E14 Gen 5, AMD) | macOS 26.7.3, with 0.5.3-test1: the driver runs and the checks pass; AirDrop untested, no Apple device at hand (issue #43) |
| Intel AX210 | macOS 26.7.2, with 0.5.4-beta.2: AirDrop works both ways; Sidecar and Universal Control fail (issue #56, same cause as #42) |
| Intel AX200 (MacBookPro16,4 SMBIOS) | macOS 26.7.2, with BTLEAdvFixup 0.9.1: a new Bluetooth LE mouse pairs and stays connected (PR #31) |
| Intel AX210 (discrete, VT-d) | macOS 26.7.3: five nights of scheduled sleep with the full AirDrop flag set. Four woke normally, with Wi-Fi rejoining 6–10 s after the wake; on one the driver stayed unavailable until Wi-Fi was turned off and on (issue #38, open) |
| Intel AX200 | macOS 26.7.3, with a local build of 0.6.0-beta.1: AirDrop with a MacBook Air M1 works both ways, listener on 44 at 20 MHz, the hackintosh's Wi-Fi on 36 at 80 MHz ([PR #74](https://github.com/retropineaple/ForbiddenItlwm/pull/74)) |
| Intel AX211 | macOS 26.7.3, with the same-channel fix (PR #47): Mac → iPhone 27–33 MB/s instead of 3–4 MB/s (PR #47) |
| Intel AX210 (desktop, Intel NUC8i7HVK) | macOS 26.7.3, with the same-channel fix (PR #47): 19–26 MiB/s with the iPhone's network on 149 (issue #24) |
| Intel AX201 | macOS 26.7.3, with 0.6.0-alpha.1 in Japan: listener on channel 44 at 80 MHz, Mac → iPhone 26 MB/s, iPhone → Mac 27.6 MB/s (issues #17, #21) |
| Intel AX201 (Lenovo AIO, Tiger Lake) | macOS Sequoia 15.8.2, with 0.6.0-alpha.1 in China: iPhone → Mac about 40 MB/s, Mac → iPhone 27–31 MB/s, block ack agreed (issue #24). With 0.5.4-beta.2: Handoff works, but its badge shows an old device name; Instant Hotspot doesn't (issue #40) |
| Intel AX201 | macOS Sequoia 15.8.1, with 0.6.0-alpha.1, Mac's Wi-Fi and the listener both on 149: Mac → iPhone 28–30 MB/s, iPhone → Mac 36 MB/s, block ack agreed (issue #24) |
| Intel AX211 (Dell XPS) | macOS 26.7.3, with 0.6.0-alpha.1 in the UK, router on 44: iPhone → Mac works on 44 (it didn't on 0.5.4); Mac → iPhone stalls (issues #17, #63, open) |
| Intel AX201 (CNVi, Alder Lake or newer) | macOS 26.7.3: AirDrop with two iPads works both ways (iPad → Mac 24.5 MB/s on 0.6.0-beta.2); with an iPhone 17 Pro it fails, also on 0.6.0-beta.2 (issue #45, open) |
| Intel AX210 | Sonoma 14.8.9, with 0.5.4-beta.2: the listener starts, but `awdl0` isn't created (issue #55) |
| Intel AX200 | Sonoma 14.8.9, with the fix for #55 ([PR #77](https://github.com/retropineaple/ForbiddenItlwm/pull/77), in 0.6.0-beta.3): `awdl0` is created, AirDrop works both ways at 5–7 MB/s, listener on 149 at 20 MHz |
| Intel AX201 (MSI, Tiger Lake) | macOS 26.7.1, with 0.5.4-beta.2: transfers fail. With 0.6.0-beta.2 and the full tested set, router on 44 at 80 MHz: AirDrop works both ways, iPhone → Mac 16 MB/s, Mac → iPhone 12.9 MB/s (issue #53) |
| Intel AX210 (AMD Ryzen 9 7945HX) | macOS 26.7.2, with 0.5.4-beta.2: AirDrop finds nothing; the iPhone sends no data to the Mac (issue #46, open) |
| Intel AX211 (desktop) | macOS Sequoia: Wi-Fi and Bluetooth work, AirDrop and Handoff don't (issue #35, open) |
| Intel AX210 (desktop, PCIe adapter) | macOS Sequoia 15.8.3, with 0.6.0-beta.2: AirDrop both ways and Universal Clipboard with a Mac and with an iPad. An iPhone 17 waits while the Mac is awake, because the Mac holds block ack (issue #81, open) |
| Intel AX201 (Comet Lake) | macOS 26.7.3 build 25G416 (beta), with 0.6.0-beta.2 and `-itlawdlanybuild`: AirDrop works both ways, iPhone → Mac 9.7 MB/s. With `itlwm_he=1`, Wi-Fi drops as soon as an AirDrop starts (issue #83, open) |
| Intel Wireless-AC 9461 (CNVi, Ice Lake) | macOS 26.7.3, with 0.6.0-beta.2: Wi-Fi works, and the AirDrop listener runs on 149 and hears an Apple device; transfers not reported yet (issue #87, open) |

The project hasn't verified these reports. The platforms, and which features were tried, vary between them.

## Not tested

- Other Intel cards, and other laptops with an AX211, beyond the user reports above
- Other macOS builds, and 26.7.2 and 26.7.3 on the project's own hackintosh
- **macOS Sequoia on the project's own hackintosh.** The Sequoia build was verified offline from the 15.8 and 15.8.3 Kernel Debug Kits, and in the user reports so far (above) Wi-Fi works. With 0.5.1-test1 users report AirDrop working both ways on 15.8.2 (#7) and 15.6 (#19), and with 0.6.0-alpha.1 on 15.8.2 at up to 40 MB/s (#24)
- **macOS Sonoma (test build).** Verified offline from the 14.8.9 Kernel Debug Kit. One user booted it (#55): Wi-Fi and the listener start, but `awdl0` wasn't created; with the fix in 0.6.0-beta.3, another user reports AirDrop working (PR #77)
- iPads, other iPhones, other Macs (users report iPads working, #29 and #45, and AirPlay to a Mac mini, #42; AirDrop with a Mac as the other device is reported working by three users: on the stock 0.6.0-beta.2 (#81), on a local build of 0.6.0-beta.1 (PR #74) and on a modified build (PR #44), #33)
- Sleep and wake (one user report: four of five nights fine, #38), sleep during a transfer, and long-term stability
