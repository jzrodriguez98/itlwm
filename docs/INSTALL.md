# Installing the AirDrop AirportItlwm build

This beta has been tested on one hackintosh: an HP Envy x360 13-bf with an Intel AX211, on macOS 26.7.1 (25G241), booted with OpenCore 1.0.8, with an iPhone 11. Users report it working on 26.7.2 (25G332) and 26.7.3 (25G342). The Sequoia build (15.8.x) was verified offline. Users report Wi-Fi working on it. AirDrop needs 0.5.1-test1 or later; users confirmed it working on 15.8.1, 15.8.2, 15.8.3 and 15.6. The Sonoma build (14.8.9, test build) was verified offline only. The details are in [TESTED-HARDWARE.md](TESTED-HARDWARE.md). Read the whole page before you start.

## Before you start

- **Check your macOS build:** `sw_vers -buildVersion`.
  - **Tahoe:** `25G241`, `25G332` or `25G342`. Use the Tahoe kexts.
  - **Sequoia:** `24H23` (15.8) and `24H241` (15.8.3) were checked offline, and `24H32` (15.8.1) and `24H232` (15.8.2) run those verified kernels. Use the Sequoia kexts. AirDrop transfers on Sequoia need 0.5.1-test1 or later.
  - **Sonoma (test build):** `23J631` (14.8.9) was checked offline. Use the Sonoma kexts. On other Sonoma 14.4+ builds the Sonoma kext runs as plain Wi-Fi.
  - On any other build the driver keeps AirDrop off and works as plain Wi-Fi.
- **Use the kexts for your macOS version.** AirportItlwm and the Bluetooth plugin are built separately for Tahoe, Sequoia and Sonoma. An AirportItlwm build for the other version refuses to start, and the Bluetooth plugin's patterns will not match.
- **Revert OCLP Wi-Fi root patches.** ForbiddenItlwm uses the Wi-Fi stack that ships with macOS. If you applied OpenCore Legacy Patcher's "Modern Wireless" root patches for an older AirportItlwm, revert them first. Also remove what that setup added to config.plist: a `Kernel → Block` entry for `com.apple.iokit.IOSkywalkFamily`, and injected `IOSkywalkFamily.kext` or `IO80211FamilyLegacy.kext`.
- **Run the checker:** `bash tools/compat/check_compat.sh`. It tells you whether your card and Bluetooth are likely to work.
- **Use a USB stick.** Copy your working EFI folder to a USB stick and make every change there. Your internal EFI stays as it is, so if anything goes wrong you just boot without the stick.
- **Know the rollback:** boot from your internal EFI, or put the original `AirportItlwm.kext` and `config.plist` back on the stick.

## What you need

| Kext | Where from | Notes |
| --- | --- | --- |
| `AirportItlwm.kext` | This branch, Tahoe or Sequoia build | AirDrop-enabled AirportItlwm product |
| `IntelBTPatcher.kext` | This branch, Tahoe or Sequoia build | This fork's renamed BTLEAdvFixup implementation; bundle ID `org.forbiddenitlwm.IntelBTPatcher`. Keep `BlueToolFixup.kext` too |
| `Lilu.kext` | [acidanthera/Lilu](https://github.com/acidanthera/Lilu) | Tested with 1.7.2 |
| `IntelBluetoothFirmware.kext` | [OpenIntelWireless/IntelBluetoothFirmware](https://github.com/OpenIntelWireless/IntelBluetoothFirmware) | Tested with 2.5.1 |
| `BlueToolFixup.kext` | [acidanthera/BrcmPatchRAM](https://github.com/acidanthera/BrcmPatchRAM) | Tested with 2.7.3 |

**Important naming note:** This branch outputs its Bluetooth plugin as `IntelBTPatcher.kext`, but it is the upstream BTLEAdvFixup 0.9.4 implementation, not the original IntelBTPatcher code. Its bundle ID is `org.forbiddenitlwm.IntelBTPatcher` to distinguish it. Remove/disable the original IntelBTPatcher kext (`com.zxystd.IntelBTPatcher`) and do not load IntelBTUnified, which includes that same hook; Lilu cannot safely load both implementations. Keep IntelBluetoothFirmware and BlueToolFixup enabled.

## Building

You need the Xcode Command Line Tools (`xcode-select --install`). Full Xcode isn't needed. The build was tested with Python 3 on the Intel hackintosh it was developed on.

1. Put MacKernelSDK in the repository folder. Commit `3f75008` is the one tested:

   ```bash
   git clone https://github.com/acidanthera/MacKernelSDK
   ```

2. Build the Wi-Fi driver for your macOS version. For Tahoe:

   ```bash
   python3 tools/build.py --out build
   ```

   For Sequoia:

   ```bash
   python3 tools/build.py --target sequoia --out build-sequoia
   ```

   For Sonoma:

   ```bash
   python3 tools/build.py --target sonoma --out build-sonoma
   ```

   The result is `AirportItlwm.kext` in the output folder. The first build also generates `include/FwBinary.cpp` from the firmware in `itlwm/firmware`.

3. Build the renamed IntelBTPatcher bundle from the BTLEAdvFixup source. It needs the Lilu SDK, which comes with Lilu's **DEBUG** release. Make a folder holding `MacKernelSDK` and the DEBUG `Lilu.kext`, then:

   ```bash
   python3 tools/build_btleadv.py --out build/btleadv --tree /path/to/that/folder
   ```

   For Sequoia, add `--target sequoia`, and for Sonoma `--target sonoma`, each with its own output folder. The result is `IntelBTPatcher.kext` in the output folder.

4. Optional, for developers: run the offline tests and the ABI audit. The audit checks every virtual slot of the AWDL interface against its macOS version's own table. It must report 568 of 568 for Tahoe, 563 of 563 for Sequoia with `--target sequoia --build build-sequoia`, and 547 of 547 for Sonoma with `--target sonoma --build build-sonoma`:

   ```bash
   python3 tools/test_awdl.py
   ```

   ```bash
   python3 tools/abi/audit_vtable.py --lifecycle-overrides
   ```

## OpenCore setup

All of this goes on the **USB stick's** EFI.

1. **Kexts:** in `EFI/OC/Kexts`, replace `AirportItlwm.kext` with this branch's build and add this branch's `IntelBTPatcher.kext`. Remove the original IntelBTPatcher binary first.

2. **`Kernel` → `Add`:** keep this order, so each kext comes after what it depends on.

   | Order | BundlePath | ExecutablePath | Notes |
   | --- | --- | --- | --- |
   | 1 | `Lilu.kext` | `Contents/MacOS/Lilu` | |
   | 2 | `IntelBluetoothFirmware.kext` | `Contents/MacOS/IntelBluetoothFirmware` | |
   | 3 | `BlueToolFixup.kext` | `Contents/MacOS/BlueToolFixup` | `MinKernel` 21.0.0 |
   | 4 | `IntelBTPatcher.kext` | `Contents/MacOS/IntelBTPatcher` | `MinKernel` 21.0.0. After BlueToolFixup, so it can undo BlueToolFixup's patches for APFS's check too (#62) |
   | 5 | `AirportItlwm.kext` | `Contents/MacOS/AirportItlwm` | Use the existing AirportItlwm entry |

   **Recommended:** limit `AirportItlwm.kext` and `IntelBTPatcher.kext` to their macOS version with `MinKernel` and `MaxKernel`, so a stick moved to another macOS doesn't load the wrong build:

   | Build | `MinKernel` | `MaxKernel` |
   | --- | --- | --- |
   | Tahoe | 25.0.0 | 25.99.99 |
   | Sequoia | 24.0.0 | 24.99.99 |
   | Sonoma | 23.4.0 | 23.99.99 |

   Make sure the original IntelBTPatcher entry is removed and that exactly one `AirportItlwm.kext` and this branch's `IntelBTPatcher.kext` are enabled. Keep the fork-built IntelBTPatcher bundle after BlueToolFixup.

3. **Boot arguments:** add the flags from [BOOT-FLAGS.md](BOOT-FLAGS.md) to `boot-args` under `NVRAM` → `Add` → `7C436110-AB2A-4BBB-A880-FE41995C9F82`. Keep your existing arguments. Because OpenCore only writes NVRAM keys listed under `Delete`, check that `boot-args` is listed there for the same GUID.

4. **Validate:** `plutil -lint config.plist`, and `ocvalidate` if you have it.

## First boot

1. Boot from the USB stick.
2. Join your normal Wi-Fi network as usual.
3. Wait a minute, then check that the driver and its AirDrop listener are running. If Wi-Fi is off or greyed out, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md#wi-fi-is-off-or-greyed-out-and-theres-no-en0).

   ```bash
   ioreg -l -w0 | grep -E '"ItlwmAWDL(InterfaceBuild|BuildCheck)"|"ITLAWDLCoex(Added|Channel|CountryLearned)"'
   ```

   You should see `forbidden-0.6.0-beta.4` (`forbidden-0.6.0-beta.4-sequoia` on Sequoia, `forbidden-0.6.0-beta.4-sonoma` on Sonoma), `BuildCheck` `verified`, `Added` Yes, `Channel` 149 (or 44 where your iPhone uses 44, for example in Japan) and `CountryLearned` Yes. `Channel` 6 means the firmware hasn't opened 149 or 44: see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

4. Or run `bash tools/compat/check_compat.sh` again. It now also reads the listener's state.
5. Turn on AirDrop on both devices. Contacts Only works when the iPhone and the Mac share an Apple Account or know each other as contacts. Otherwise use Everyone for 10 Minutes.
6. Send a file each way.

## Before a macOS update

Boot once without `-btleadv` (or with this branch's IntelBTPatcher disabled), then update. While this branch's IntelBTPatcher is active, `bluetoothd`'s patched pages are what the system reads, and an incremental update that checks the file can fail. If the update still fails, disable BlueToolFixup and this branch's IntelBTPatcher too for the update (#78): BlueToolFixup patches `bluetoothd` the same way, whatever the flags. Then check that the new build is supported before turning `-btleadv` back on: see [the macOS builds](TESTED-HARDWARE.md#macos-builds).

## Uninstalling

On the stick (or your EFI, if you moved it there):
1. Remove the test `AirportItlwm.kext` and `IntelBTPatcher.kext`, and their `Kernel` → `Add` entries.
2. Put `AirportItlwm.kext` back.
3. Remove the `-itlawdl*`, `itlawdl*` and `-btleadv` boot flags.
4. Reboot.

The driver writes nothing to disk. IntelBTPatcher (the renamed BTLEAdvFixup implementation) patches `bluetoothd` in memory only.
