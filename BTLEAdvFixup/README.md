# BTLEAdvFixup

A Lilu plugin that lets macOS start Bluetooth LE advertising, which AirDrop needs, on an Intel Bluetooth controller.

- **Turn it on** with the boot flag `-btleadv`, and off with `-btleadvoff`. Without the flag it does nothing.
- **What it changes:** it patches `/usr/sbin/bluetoothd` in memory as its pages are validated, so `bluetoothd` takes its "extended advertising supported" path. It also adjusts some outgoing HCI commands, such as the random address of each advertising set, and does IntelBTPatcher's fix-up before the first scan. Nothing on disk changes.
- **One build per macOS version:** the Tahoe build's patterns match macOS 26.7.1 (25G241) and, from 0.8.1, 26.7.3 (25G342) and 26.7.2 (25G332), which shares 26.7.3's bytes (from 0.9.1, 26.7.2 also gets its own pattern for one extended-connection site where its bytes differ), the Sequoia build's (`tools/build_btleadv.py --target sequoia`) match 15.8.3 (24H241) and, checked for 0.9.0, 15.8 (24H23) and 15.8.2 (24H232), and the Sonoma build's (`--target sonoma`, from 0.9.0) match 14.8.9 (23J631). From 0.8.3 each build tells Lilu its own macOS version; before that, Lilu never started the Sequoia build. On another build they don't match, and nothing is patched.
- **Before a macOS update, boot without `-btleadv`.** While the kext is active, reading `bluetoothd` returns the patched pages, and an incremental update that checks the file can fail.
- **Disable IntelBTPatcher.** Both hook the same function, and Lilu panics if two plugins do. BTLEAdvFixup takes over IntelBTPatcher's jobs: the fix-up before the first scan, and, from 0.9.1, the fix that lets new LE mice and keyboards finish pairing.

Build it with `tools/build_btleadv.py`, as described in [docs/INSTALL.md](../docs/INSTALL.md).

## License

GPL-3.0-only. The HCI hook follows IntelBTPatcher (OpenIntelWireless/IntelBluetoothFirmware, GPL-3.0), and the page hook follows BlueToolFixup (acidanthera/BrcmPatchRAM). The full text is in [LICENSE](LICENSE).
