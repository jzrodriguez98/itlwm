# Contributing

Pull requests are welcome. This page explains how to make one that can be reviewed and merged quickly. ForbiddenItlwm runs in the macOS kernel and talks to Wi-Fi firmware, so every change is read line by line and checked with the host tests and builds, and tested on the project's hackintosh where that's possible. What couldn't be tested (other cards, Sequoia and Sonoma on hardware, several Apple devices at once) is said in the release notes. Small, focused pull requests get through that much faster than big ones.

## Before you start

- **Look for an issue first.** If one exists, say there that you're working on it. If not, open one that describes the problem, your hardware and your macOS build. For anything larger than a small fix, agree on the approach in the issue before writing much code.
- **Base your branch on `next-release`.** That's where the next release is put together. `main` only moves when a release is published.

## One topic per pull request

This is the most important rule.

- **A pull request fixes one problem or adds one feature.** If you find a second bug along the way, open a second pull request (or an issue) for it. Smaller pull requests are reviewed and merged sooner.
- **No drive-by changes.** Leave out reformatting, renaming, moving code and comment rewrites in code your change doesn't need. They hide the real change in the diff.
- **If a change depends on another,** open the first one on its own and say in the second which one it needs. Splitting a large piece of work into steps that each work on their own is fine and welcome.

## What to leave out

- **Version numbers, release notes and release builds.** The maintainer bumps versions, writes the CHANGELOG and builds the release packages. Describe your change in the pull request instead.
- **Built kexts, zips and other binaries.** Only source goes into the repository.
- **CI and repository settings.** If you think the project needs CI or a change to how the repository is set up, open an issue about it first.
- **Private information.** No names, email addresses, home folder paths, serial numbers, Wi-Fi network names, MAC addresses or locations in code, comments, tests, logs or screenshots.
- **Proprietary code.** Don't paste code or disassembly from Apple, Intel or other closed binaries. Describe what you found in your own words, with the build and address, instead.

## How changes are expected to behave

- **New behaviour goes behind a boot flag, off by default,** unless it fixes a clear bug. A flag lets testers compare with and without it, and lets anyone turn it off if it misbehaves on their setup. Use the existing naming (`-itlawdl…` for AirDrop, `-itlwm…` for Wi-Fi) and document the flag in [docs/BOOT-FLAGS.md](docs/BOOT-FLAGS.md).
- **Without your flag, nothing changes.** Please check that the driver behaves exactly as before when your flag isn't set.
- **Fixes must work for everyone,** not just your card, country, router or iPhone. Don't hard-code a channel, a country or a device. The firmware's regulatory decision is final: never work around it.
- **Behave like a real Mac.** The aim is for macOS's own AirDrop and Wi-Fi software to work unchanged. Prefer doing what Apple's drivers do over patching macOS.
- **Keep all three macOS builds building.** Tahoe, Sequoia and Sonoma share the code. If your change only applies to one, keep it from breaking the others.

## Checks to run

Run these before you open the pull request, and say in it that they passed:

```
python3 tools/test_awdl.py
python3 tools/build.py --target tahoe
python3 tools/build.py --target sequoia
python3 tools/build.py --target sonoma
```

For BTLEAdvFixup changes, also build it with `tools/build_btleadv.py` for the three targets. If you change a class the macOS frameworks call into, run `tools/abi/audit_vtable.py` on each build. New logic that can be tested without hardware (parsers, state machines, calculations) should get a host test in `tests/`, added to `tools/test_awdl.py`.

## The pull request description

Please include:

- **What problem it solves,** with a link to the issue.
- **What changed and why,** briefly. Point out anything a reviewer should look at closely.
- **How you tested it:** card (PCI ID), macOS build (`sw_vers -buildVersion`), the boot flags you used, and the results. For AirDrop, transfer speeds in both directions with `tools/compat/airdrop_measure.sh` are the most useful numbers. Say what you couldn't test.
- **Driver counters** where they help, read with a filtered `ioreg -l -w0 | grep …` command. Please don't attach full sysdiagnoses or raw logs.

If you used an AI assistant, say so and check the result yourself on hardware before asking for review. It's fine to use one; it isn't fine to submit code you haven't read or tested.

## Review

- Expect questions and requested changes. The maintainer may push small fixes to your branch, or merge your commits together with fixes, keeping your authorship.
- A pull request may be split, or parts of it taken, if it covers more than one topic.
- Please keep the discussion in the pull request, so the reasoning stays on record.

## Bugs and questions

Ordinary bugs go to [issues](https://github.com/retropineaple/ForbiddenItlwm/issues). Security problems go through private reporting, as described in [SECURITY.md](SECURITY.md).

By contributing, you agree that your contribution is licensed under the licence of the part you change: GPL-2.0 for the Wi-Fi driver ([LICENSE](LICENSE)) and GPL-3.0-only for BTLEAdvFixup ([BTLEAdvFixup/LICENSE](BTLEAdvFixup/LICENSE)).
