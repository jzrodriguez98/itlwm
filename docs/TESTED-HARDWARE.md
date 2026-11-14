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
| ForbiddenItlwm | 0.1.0-beta1, 0.2.0-beta1, 0.4.0-beta1's changes in development builds, and 0.5.0-test1 (Tahoe) |
| BTLEAdvFixup | 0.8.0, 0.8.2's changes in a development build, 0.9.0 and 0.9.1 (Tahoe) |
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
| Sonoma | 14.8.9 (23J631) | Test builds from 0.5.0-test1. Wi-Fi side verified offline from Apple's Kernel Debug Kit, BTLEAdvFixup's patterns from Apple's installer. Not tested on hardware yet |
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
| Intel AX210 (AMD Ryzen 7 5800H laptop) | macOS Sequoia 15.8.1, with 0.5.1-test1: AirDrop works both ways; Mac → iPhone slower (issue #22) |
| Intel AX210 (Xiaomi Mi Notebook Pro) | macOS 26.7.2, with 0.5.0-test1: AirDrop works both ways, listener on 149 at 80 MHz in China (issue #18) |
| Intel AX201 (Tiger Lake-H, Dell G15) | macOS 26.7.3, with 0.5.0-test1: AirDrop works both ways; on channel 6 in Japan (issue #23) |
| Intel AX201 (Tiger Lake, dynabook G83) | macOS Sequoia 15.8.3, with 0.5.3-test1: AirDrop works both ways, also with an iPad, and iPad → Mac AirPlay works. On a network without 149, Mac → iPad works only without `-itlawdlcoexmulti` (issue #29) |
| Intel AX210 (Dell Precision 5540) | macOS 26.7.3, with 0.5.3-test1: Mac → iPhone works; iPhone → Mac stalls on large photos and videos (issue #26, open) |
| Intel AX411 class (AX1690i) | macOS 26.7.2, with 0.4.1-beta1: AirDrop works both ways, on channel 6 (issue #15) |

The project hasn't verified these reports. The platforms, and which features were tried, vary between them.

## Not tested

- Other Intel cards, and other laptops with an AX211, beyond the user reports above
- Other macOS builds, and 26.7.2 and 26.7.3 on the project's own hackintosh
- **macOS Sequoia on the project's own hackintosh.** The Sequoia build was verified offline from the 15.8 and 15.8.3 Kernel Debug Kits, and in the user reports so far (above) Wi-Fi works. with 0.5.1-test1 users report AirDrop working both ways on 15.8.2 (#7) and 15.6 (#19)
- **macOS Sonoma (test build).** Verified offline from the 14.8.9 Kernel Debug Kit; nobody has booted it yet
- iPads, other iPhones, other Macs
- Sleep and wake during a transfer, and long-term stability
