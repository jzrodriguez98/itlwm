# Roadmap

What's being worked on, what comes next, and what's planned further out. These are plans, not promises: there are no dates, and priorities change with what testers find. Issue numbers link to the discussion.

## Now

- **Faster Mac → iPhone transfers** ([#22](https://github.com/retropineaple/ForbiddenItlwm/issues/22), [#24](https://github.com/retropineaple/ForbiddenItlwm/issues/24)). On some setups the iPhone never accepts block ack, so the Mac sends one frame at a time: a few MB/s instead of about 20. It seems to depend on whether the Mac and the iPhone are on the same Wi-Fi channel. Neither of 0.5.3's test flags fixed it; the cause is still being investigated.
- **Channel 44 where 149 isn't allowed** ([#17](https://github.com/retropineaple/ForbiddenItlwm/issues/17), [PR #21](https://github.com/retropineaple/ForbiddenItlwm/pull/21)). In Japan and other countries without channel 149, iPhones use channel 44 for AirDrop, but the driver falls back to channel 6, which is slow. A tester's patch moves the listener to 44 at 80 MHz; it needs two safety rules (see the PR) before it can ship.
- **Stable Wi-Fi when the Mac is on 2.4 GHz** ([#16](https://github.com/retropineaple/ForbiddenItlwm/issues/16)). With the listener on its own channel, one AX201 kept dropping its normal Wi-Fi while that was on 2.4 GHz. 0.5.2-test1 has a test flag (`-itlawdlsameband`) for it.

## Next

- **Wi-Fi reconnects without losing AirDrop** ([PR #12](https://github.com/retropineaple/ForbiddenItlwm/pull/12)): restoring the listener cleanly after the Mac's Wi-Fi reconnects or switches networks.
- **Fewer boot flags.** The beta needs a long list of flags. They should become sensible defaults, with flags only for testing.
- **Faster normal Wi-Fi while AirDrop is on.** The Mac's own Wi-Fi loses about 30 to 45% of its speed while AirDrop's listener runs, because the two share the radio. Giving the listener less airtime while nothing is being sent should win most of that back.
- **Wi-Fi 6 by default.** The driver can use Wi-Fi 6 (802.11ax), but only with the boot argument `itlwm_he=1`, which comes from the upstream code and hasn't been tested with AirDrop. The goal is to test it with AirDrop on and turn it on by default.
- **Faster connects.** A cold iPhone → Mac connect takes 3 to 10 s, mostly before any data moves. The target is under 2 s in both directions.
- **More macOS builds:** Sequoia 15.6 ([#19](https://github.com/retropineaple/ForbiddenItlwm/issues/19)) and each new Tahoe or Sequoia update, checked against Apple's Kernel Debug Kit before AirDrop is switched on for it.

## Later

- **Instant Hotspot:** joining the iPhone's hotspot from the Wi-Fi menu without typing the password.
- **Continuity Camera:** using the iPhone as the Mac's webcam.
- **A unified Bluetooth kext that survives macOS updates:** one Bluetooth kext made for ForbiddenItlwm, replacing BTLEAdvFixup, IntelBluetoothFirmware and BlueToolFixup, with patches that keep working across small macOS updates.
- **Sonoma on hardware, more Sonoma builds, and a look at Ventura 13.** Sonoma 14.8.9 has a test build that nobody has run yet. Ventura needs its own study of that version's Wi-Fi stack first, so it isn't certain.
- **Sleep and wake:** not tested so far, since sleep is disabled on the test machine.

## Researching

These also use Apple's peer-to-peer Wi-Fi. None has been tried yet, so whether they're possible isn't known.

- **AirPlay to the hackintosh**
- **Sidecar**
- **Universal Control**

## Not planned

- **iPhone Mirroring:** it very likely needs a T2 chip or Apple silicon, which a hackintosh doesn't have.

## Done recently

- **0.5.4:** laobamac's later fixes to the base driver ([#36](https://github.com/retropineaple/ForbiddenItlwm/pull/36)); block ack without `-itlawdlcoexmulti` ([#16](https://github.com/retropineaple/ForbiddenItlwm/issues/16)); new LE mice and keyboards pair again with BTLEAdvFixup 0.9.1 ([#31](https://github.com/retropineaple/ForbiddenItlwm/pull/31)).
- **0.5.1:** AirDrop works on Sequoia ([#7](https://github.com/retropineaple/ForbiddenItlwm/issues/7), [#13](https://github.com/retropineaple/ForbiddenItlwm/issues/13), [#19](https://github.com/retropineaple/ForbiddenItlwm/issues/19)).
- **0.5.0:** Wi-Fi starts again on machines where 0.4.x didn't ([#14](https://github.com/retropineaple/ForbiddenItlwm/issues/14), [#16](https://github.com/retropineaple/ForbiddenItlwm/issues/16)); channel 149 in China ([#11](https://github.com/retropineaple/ForbiddenItlwm/issues/11)); a Sonoma 14.8.9 test build.
- **0.2.0:** iMessage and other push services over Wi-Fi.

See the [changelog](../CHANGELOG.md) for everything.
