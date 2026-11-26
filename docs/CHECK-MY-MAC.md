# Help add support for your macOS build

If your macOS build isn't supported yet, `tools/check-my-mac.pl` collects what's needed to add it. It checks, on your own
Mac, the parts of Apple's code that the kexts' layouts and patches depend on, and prints a short report to paste in
[discussion #98](https://github.com/retropineaple/ForbiddenItlwm/discussions/98). It replaces sending in system files: nothing is uploaded, copied or changed.

## Run it

1. Download `tools/check-my-mac.pl` from this repository (open the file on GitHub, then **Download raw file**).
2. In Terminal, run it with the system Perl:

   ```sh
   perl ~/Downloads/check-my-mac.pl
   ```

3. Paste the whole output in [discussion #98](https://github.com/retropineaple/ForbiddenItlwm/discussions/98).

It needs nothing extra. Perl, `codesign`, `sw_vers` and `uname` come with every macOS, and you don't need the
Command Line Tools, a Kernel Debug Kit or an installer. It runs in about a second and only reads two system files:

- `/usr/sbin/bluetoothd`
- `/System/Library/KernelCollections/BootKernelExtensions.kc`, where it reads IO80211Family

The report contains your macOS version and build, the kernel version, short hashes of the two files, and the results of
the checks. Where BTLEAdvFixup has no pattern for your build yet, it also shows a few short byte sequences from
bluetoothd. It doesn't contain your user name, Mac name, serial number, network or location.

## What it checks

- **IO80211Family:**
  - how the AirDrop interface reaches its peer manager;
  - the AirDrop packet counters;
  - the layout of the master indication and unicast MI requests;
  - the election RSSI threshold request;
  - the size of the AirDrop protocol table that the driver checks when it starts.
- **bluetoothd:** whether each place BTLEAdvFixup patches matches one of its patterns. A site that doesn't match is
  listed with the candidates found by code shape. That's often enough to add your build, but some sites (such as
  extendedConnection) match many places, and may still need a closer look.
- **IO80211 tables and imports:** the size and a short hash of the names of six IO80211 class tables, and whether every
  kernel function ForbiddenItlwm imports is present on this build.
- **The Apple signature of bluetoothd.** While BTLEAdvFixup is loaded it patches bluetoothd in memory, so the signature
  then reads as invalid. That's expected, and the report says so. BlueToolFixup patches bluetoothd in memory the
  same way, so it reads as invalid with BlueToolFixup alone too. With neither loaded, a broken signature means the
  system files were modified, for example by OpenCore Legacy Patcher, so please mention it if you use it.

`RESULT: everything ... matches this build` means every check the script makes passed. That's good evidence, so
support can usually be added quickly, but it doesn't prove the build behaves the same: the script doesn't check
everything, for example not BTLEAdvFixup's APFS and USB hooks. Anything else lists what differs, which is what's needed to add it. Until a release
adds your build, the driver keeps AirDrop off on it (unless it runs an "expected" Sequoia 15.8.x kernel, or you use
`-itlawdlanybuild`).

## Unsupported macOS versions (Ventura and older)

The script also runs there. With no build to compare against it only reports what it measures, marked `(measured)`,
and checks the imports against the Sonoma build. For a deeper look, add `--details report.txt`: it writes the full
method lists of the IO80211 tables to that file (Apple's class and method names only, nothing about you), which you can
attach to your post in [discussion #98](https://github.com/retropineaple/ForbiddenItlwm/discussions/98). This shows how far a port would be; it doesn't make that version supported.

## For maintainers

- **Check loose copies:**
  ```sh
  perl tools/check-my-mac.pl --kext IO80211Family --bluetoothd bluetoothd --family sequoia
  ```
  Add `--skywalk IOSkywalkFamily` to check the Skywalk imports too.
- **Import lists:** run `python3 tools/gen_check_my_mac.py --imports DIR` after a build, with `DIR/<target>/ForbiddenItlwm.kext`.
- **Safety:** the script stops itself on deep recursion or after 120 s, so a bug can't fill memory and swap.
- **Pattern table:** it is generated from `BTLEAdvFixup/BTLEAdvPatches.hpp`. Run `python3 tools/gen_check_my_mac.py`
  after changing a pattern. `tools/test_awdl.py` fails if the table is stale.
- **Driver values:** the expected values in `%EXPECT` must match `ForbiddenItlwm/AirportItlwmV2.cpp` and
  `AWDLBuildGuard.cpp`.
