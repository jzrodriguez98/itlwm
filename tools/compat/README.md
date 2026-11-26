# Will AirDrop work on my Intel Wi-Fi card?

These scripts are for testers. None of them changes your system's settings or files, needs extra software, or sends anything anywhere. The two collectors each write one text file, a report that you read first and then share with the project.

| Script | Runs on | What it does |
| --- | --- | --- |
| `check_compat.sh` | macOS | Checks the macOS build, your Intel Wi-Fi and Bluetooth hardware and the kexts you have loaded, and says how likely the driver is to work |
| `collect_hw_macos.sh` | macOS | Writes a hardware report for adding or debugging support |
| `collect_hw_linux.sh` | Linux | Writes a richer hardware report, from a Linux live USB on the same laptop, for cards the driver doesn't support yet |
| `airdrop_measure.sh` | macOS | Measures AirDrop transfer speed and connect times in both directions, from macOS's own AirDrop log |

## 1. Check

```bash
bash check_compat.sh
```

It works before you install anything. If ForbiddenItlwm is already running, it also checks the AirDrop listener's channel and the boot flags.

It also checks channels 149 and 44 and the country:
- **Country code:** the code the Wi-Fi driver reports to macOS. `ZZ` means the firmware hasn't learned a country yet.
- **Channel map:** whether channels 149 to 161 (for 149 at 80 MHz) and 36 to 48 (for 44 at 80 MHz) are in it.
- **Your network:** which channel your Wi-Fi network is on.
- **Nearby networks:** how many nearby networks macOS lists, and how many are on 149 to 165.
- **With the AirDrop build running,** also whether the firmware learned a country this boot, which 5 GHz channel the iPhone uses (once it has been heard), and why the firmware refused the listener's channel if it did.
- **Network stack (section 7):** whether pf has turned off macOS's user-space network path, which can slow AirDrop's QUIC transfers. On Tahoe, OpenCore's PowerTimeoutKernelPanic quirk causes it.

The check prints your country code on screen. Leave it out if you paste the output somewhere public.

**Channel 149 also depends on the country's radio laws.** Apple devices use 44 where they can't (or don't) use 149, and from 0.6.0 the listener follows them there. Learning the country isn't always enough: the firmware still decides from its rules for that country.
- **Not allowed at all:** in the Linux wireless regulatory database (read 2026-11-10), 44 of its 183 country entries have no Wi-Fi rule for channels 149 to 161, for example Japan, Turkey, Egypt and Saudi Arabia.
- **Only narrow:** a few countries (Kenya, the Central African Republic, Guam, El Salvador, North Korea) allow those channels only at 20 or 40 MHz. The fast mode needs 80 MHz.
- **What happens there:** iPhones use channel 44, and from 0.6.0 so does the listener, if the firmware allows 44. Up to 0.5.4 AirDrop stayed on channel 6, which is very slow.
- **The check:** when it sees one of these country codes, it says so.

Intel firmware uses its own built-in tables, not that database. They follow the same laws but can be stricter, so the firmware may also keep 149 closed in a country the database allows. When the AirDrop build is running, the check reports whether the firmware actually opened 149 after learning the country.

What the verdict means:

| Verdict | Cards | Meaning |
| --- | --- | --- |
| Tested | AX211 | The card this was developed on |
| Reported working | AX210, AX411 class (AX1690i), AX201 on Ice, Comet or Tiger Lake, AX200 | Users report AirDrop working (see [docs/TESTED-HARDWARE.md](../../docs/TESTED-HARDWARE.md#user-reports)) |
| Close relative | AX201/AX203, AX101 or 9560-class radios on Alder Lake and newer | Same family and firmware generation as the AX211. One AX201 there works with iPads, but not yet with an iPhone ([#45](https://github.com/retropineaple/ForbiddenItlwm/issues/45)); on one AX101 the firmware keeps restarting with AirDrop on ([#97](https://github.com/retropineaple/ForbiddenItlwm/issues/97)) |
| Older family | AX101, and 9560/9461/9462 on Ice, Comet or Tiger Lake | Older code paths. On a 9461 the listener runs and hears an Apple device, but no transfer is reported yet ([#87](https://github.com/retropineaple/ForbiddenItlwm/issues/87)). One-antenna cards (AX101, 9461, 9462) need more work |
| Large port | 7260, 7265, 3160, 3165, 3168, 8260, 8265, 9260, and the 9560/9461/9462 on Coffee and Cannon Lake | Not supported |
| Unsupported | Pre-2013 cards, Wi-Fi 7 (BE200, BE201), Meteor Lake CNVi | Not supported |

Two things stop it working whatever the card:
- **The macOS build.** With the Tahoe kexts, AirDrop starts on macOS 26.7.1 (25G241), 26.7.2 (25G332) and 26.7.3 (25G342). With the Sequoia kexts, on 15.8 (24H23) and 15.8.3 (24H241), and on 15.8.1, 15.8.2 and other 15.8.x builds without the announcement copy. With the Sonoma kexts (test build), on 14.8.9 (23J631). From 0.7.0-alpha.2 also on 26.7 (25G229), 25G330, 15.8.1 (24H32) and 15.8.2 (24H230, 24H232) with the announcement copy, 15.7.3 (24G419), 15.7.4 (24G517), 15.7.8 (24G824), 15.7.9 (24G830), 14.8.3 (23J220), 14.8.4 (23J319), 14.8.7 (23J520) and 14.8.8 (23J620), and from 0.7.0-alpha.3 on the 26.7.4 beta (25G422), from a user's report (the final 26.7.4 isn't covered). On other builds the driver keeps AirDrop off and works as plain Wi-Fi. The check also tests whether BTLEAdvFixup's patterns for your macOS version (taken from 26.7.1, 26.7.3 and 26.7.2's own site, 15.8.3 or 14.8.9; 26.7.3's set covers the rest of 26.7.2, and the Sequoia set also matches 15.8 and 15.8.2) match your `bluetoothd`.
- **Bluetooth.** AirDrop finds devices over Bluetooth LE first, so it needs a working Intel Bluetooth controller.

A good card can still be slow. The firmware opens channel 149 or 44, the fast mode, only after a nearby network tells it which country it is in. Until then the driver falls back to channel 6, which is very slow. Most home and office routers advertise their country. In the project's tests, an iPhone's Personal Hotspot switched on nearby (without joining it) also taught the firmware. Where the firmware marks 149 to 161 passive (China, for example), 0.5.0 uses them once it has heard a network's beacon there. Otherwise the driver follows the firmware's choice, and setting `itlwm_cc` doesn't help: it only changes the code macOS displays.

**User reports:** users have reported AirDrop working with the AX201 (Tahoe 26.7.1 and 26.7.3, Sequoia 15.8.1 to 15.8.3, and on channel 44 in Japan), AX211s in other machines (26.7.1, 26.7.3), the AX210 (26.7.2, 26.7.3, Sequoia 15.8.1), an AX1690i (26.7.2) and the AX200 (Sequoia 15.6). The project hasn't verified these reports. See [docs/TESTED-HARDWARE.md](../../docs/TESTED-HARDWARE.md#user-reports).

On a CNVi laptop (Alder Lake and newer) the PCI ID alone can't tell an AX211 from an AX201 or a 9560. Load the AirDrop-enabled AirportItlwm build and run the check again: the firmware it loads names the radio.

## 2. Measure

```bash
bash airdrop_measure.sh
```

Leave it running, then send and receive files with AirDrop. For each transfer it prints the direction, the size, the speed macOS measured, and the connect times; press Ctrl-C to stop. `bash airdrop_measure.sh --last 2h` reads transfers you already did, and `--csv results.csv` also saves one line per transfer.

- **Mac → iPhone:** macOS's own timings for the connection (HELLO) and the request (ASK, which includes the iPhone accepting), and the total time.
- **iPhone → Mac:** the time from the first connection the iPhone opens to its request, and from the request to the end of the data. The moment you tap the Mac on the iPhone isn't visible on the Mac, so the time before that first connection isn't counted.
- With ForbiddenItlwm's AirDrop build running, it also prints the listener's channel, the block-ack state and how many of the iPhone's 16 time slots it spends on that channel.

It prints and saves only sizes, speeds and timings: no file names, device names or addresses.

## 3. Collect

On macOS:

```bash
bash collect_hw_macos.sh
```

The report is saved on your **Desktop** as `airdrop-compat-macos-<date>-<time>.txt`. To save it somewhere else, name a folder: `bash collect_hw_macos.sh ~/Downloads`. The script prints the full path when it starts and when it finishes, with commands to show the file in Finder or open it.

For a card that isn't supported yet, also boot a recent Linux live USB on the same laptop and run:

```bash
sudo bash collect_hw_linux.sh
```

The report is saved in the folder you run it from as `airdrop-compat-linux-<date>-<time>.txt`, unless you name another folder. The script prints the full path. On a live USB, copy the file to a USB stick or cloud folder before shutting down, or it will be lost.

Linux's driver reports the card's exact name, radio, firmware version and firmware API. `iw list` shows the bands, channel widths, antennas and how many channels the card can serve at once. That is what adding a card to the macOS driver needs. Install `iw` first if your distribution doesn't include it.

### What the reports contain

- **System:** macOS or Linux version, the SMBIOS model identifier (the Mac model the hackintosh is set up as), the laptop or motherboard maker and model, CPU name.
- **Wi-Fi card:** PCI IDs, the firmware the driver loaded, the driver's version and properties.
- **Bluetooth:** the Intel controller's USB IDs and the controller summary.
- **Loaded kexts:** the names and versions of third-party kexts.
- **Boot flags:** only the AirDrop and Bluetooth ones, the experimental ones included.
- **Wi-Fi interface:** supported channels, plus the current channel and width.
- **Channel 149 and country:** whether the firmware has learned a country (the code itself only with `--include-country`), and the channels of nearby networks, without their names. On Linux, the state of channels 149 to 165.
- **AirDrop driver:** its status counters, if its build is running.

### What they leave out

- serial numbers and hardware UUIDs
- MAC and Bluetooth addresses
- network names, and paired or nearby devices
- your user name, home folder and host name
- the Wi-Fi country code, unless you add `--include-country`

Anything shaped like a MAC address or UUID is replaced. Read the file before sharing anyway, especially:
- **Kext names:** some kexts carry their author's name in their identifier.
- **Supported channels:** the list hints at your region.
