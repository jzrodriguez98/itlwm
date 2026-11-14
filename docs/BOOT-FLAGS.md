# Boot flags

AirDrop is off unless its flags are set, so with none of them ForbiddenItlwm behaves like AirportItlwm. The beta needs a long list of flags. They are the exact set used for every tested result. The Tahoe, Sequoia and Sonoma builds use the same flags. Simpler defaults are planned.

## The tested set

Add all of these to `boot-args`, on one line, separated by spaces:

```
-btleadv -itlawdlcoexprobe -itlawdliface -itlawdlnativeup -itlawdlcoexrx -itlawdlcoextx -itlawdlcoexmulti -itlawdlcoexdata -itlawdlmitx -itlawdlelicit -itlawdlcaps -itlawdlsvcmerge -itlawdlawsync itlawdlintcoal=4 -itlawdlcoexbatx -itlawdlcoexpeerpause -itlawdlcoexbatrace itlawdltxqueue=4096
```

What each one does:

| Flag | Effect |
| --- | --- |
| `-btleadv` | Turns BTLEAdvFixup on, so `bluetoothd` can start Bluetooth LE advertising on the Intel controller. `-btleadvoff` turns it off again |
| `-itlawdlcoexprobe` | Adds a second firmware context, the AWDL listener, beside the normal Wi-Fi station |
| `-itlawdliface` | Tells macOS the card can do AWDL and creates the `awdl0` interface |
| `-itlawdlnativeup` | Accepts the requests that let macOS's AWDL peer manager start |
| `-itlawdlcoexrx` | Hands the AWDL frames the listener hears to macOS |
| `-itlawdlcoextx` | Gives the listener its own firmware station and queue, and sends macOS's AWDL sync frames from it |
| `-itlawdlcoexmulti` | Puts the listener on its own channel (149 at 80 MHz when allowed, else 6). The firmware time-shares the radio between it and the station |
| `-itlawdlcoexdata` | Carries AirDrop's data through the listener, both ways |
| `-itlawdlmitx` | Sends macOS's own AWDL announcement (its name and services) in the sync frames. Only on verified macOS builds: `ItlwmAWDLMiState` says `on`, `off` or `blocked: build not verified` |
| `-itlawdlelicit` | Adds the extra AWDL fields Apple devices expect: election parameters, channel sequence and HT capabilities |
| `-itlawdlcaps` | Reports two spatial streams and VHT to macOS and to peers, so the iPhone uses 80 MHz two-stream rates |
| `-itlawdlsvcmerge` | Merges macOS's service records into the announcement frames, which helps discovery |
| `-itlawdlawsync` | Times idle sync frames to the iPhone's availability windows |
| `itlawdlintcoal=4` | Shorter interrupt coalescing for the listener, for lower latency |
| `-itlawdlcoexbatx` | Outbound Block Ack and firmware aggregation. This is what makes Mac → iPhone fast |
| `-itlawdlcoexpeerpause` | Pauses the iPhone's firmware queue while its schedule has it away, so frames aren't wasted |
| `-itlawdlcoexbatrace` | Records Block Ack events in the I/O Registry for bug reports. Diagnostic only, cheap |
| `itlawdltxqueue=4096` | Size of the driver's own transmit queue for `awdl0` |

## Optional

| Flag | Effect |
| --- | --- |
| `itlawdltxpool=N` | Size of the `awdl0` transmit packet pool, 896 to 8192. Default 2048. Below that, long Mac → iPhone transfers can stall |
| `-itlawdlanybuild` | Starts AirDrop on a macOS build the driver hasn't verified. **Risk of a kernel panic.** Only for testing a new build, from a USB stick. It doesn't override the check of Apple's AWDL function table |
| `itlawdlbtcoex=1` | Firmware Bluetooth coexistence mode 1. Fixed choppy Bluetooth audio during AirDrop on an older test build. Before 0.5.1 it only took effect in the monitor test mode |
| `-itlawdlsamples` | Publishes raw frame samples in the I/O Registry for debugging. **They can hold device names and addresses.** Never share them publicly, and don't leave the flag on |

## Comparison flags

These restore earlier behaviour, for A/B testing only. Leave them off.

| Flag | Effect |
| --- | --- |
| `-itlawdlcoexnogate` | Turns off the send gate, which holds frames for the iPhone while its schedule has it away |
| `-itlawdlcoexcalwait` | Waits for a 300-frame calibration of the iPhone's schedule instead of assuming it straight away |
| `-itlawdlsameband` | Test (0.5.2): while the Mac's Wi-Fi is on 2.4 GHz, keep the listener on channel 6 instead of 149, so the radio doesn't time-share across bands. For setups where Wi-Fi keeps dropping with `-itlawdlcoexmulti` (#16) |
| `-itlawdlbaaskshared` | Test (0.5.3, #24): when the Mac's Wi-Fi is on the listener's own channel, send Block Ack requests without waiting for the iPhone's window. `ITLAWDLCoexBaAsksShared` counts them. From 0.5.4 it also works without `-itlawdlcoexmulti` |
| `-itlawdlhideinfra` | Test (0.5.3, #24): leave the Mac's Wi-Fi network and channel out of AirDrop's sync frames. `ItlwmAWDLSyncInfraStripped` counts the frames changed |
| `-itlawdlnosharedba` | Turns off block ack when the listener shares your Wi-Fi's channel (without `-itlawdlcoexmulti`), as before 0.5.4 |
| `itlawdlpooltype=N` | AirDrop packet pool type: 0 (quantum, Tahoe's default) or 1 (packet, the default on Sequoia and Sonoma from 0.5.1). Sequoia doesn't create `awdl0` with 0 |
| `-itlawdlcoexnoorder` | Lets short frames overtake a paused aggregate queue, as older builds did |
| `-itlawdlcoexbarefill`, `-itlawdlcoexawhold`, `-itlawdlcoexbafilterhyst`, `-itlawdlcoexawsync0` | Older experiments. No gain was measured |

## Don't use

- **`-itlawdlcoexlowlat`** is disabled in this build and ignored. On the AX211 the firmware rejected the low-latency command, and normal Wi-Fi went down with it.
- **The dedicated-mode test flags:** `-itlawdlrx` and the flags that build on it (`-itlawdlqueue`, `-itlawdl6`, `-itlawdloneshot`, `-itlawdlsyncprobe` and the other train and probe flags, `-itlawdlch149`, `itlawdlcc=`). They put the card in monitor mode, so normal Wi-Fi is down. They are kept for development.
- **Country overrides.** Nothing here changes the country's rules, and nothing should. (From 0.5.0 the driver uses channels the firmware marks passive once it has heard a network there, as Linux does; that needs no flag.) `itlwm_cc` only changes the code macOS displays. It doesn't open channel 149.
