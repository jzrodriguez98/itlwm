# Security

ForbiddenItlwm runs inside the macOS kernel and parses Wi-Fi frames that any device in radio range can send. A bug there can crash the Mac or, in the worst case, let a nearby device read or change kernel memory.

## Reporting a problem

Please **don't open a public issue** for a security problem. Use GitHub's private reporting instead: **Security → Report a vulnerability** on this repository. Include:

- the release (`ItlwmAWDLInterfaceBuild` in `ioreg`) and the macOS build (`sw_vers -buildVersion`),
- what triggers it (a frame, a request from macOS, a boot flag) and what happens,
- a crash log or panic report if there is one.

Reports are read and answered as soon as possible. Once a fix is released, the report can be made public with credit, if you want it.

Ordinary bugs (AirDrop not working, slow transfers, Wi-Fi drops) go to the normal [issues](https://github.com/retropineaple/ForbiddenItlwm/issues).

## Supported versions

Only the newest release, including test builds, gets security fixes. Each macOS version has its own kext; all of them are covered.

## Inherited code

Most of the Wi-Fi driver comes from [itlwm](https://github.com/OpenIntelWireless/itlwm) and OpenBSD. A problem found in that code here likely exists in other itlwm-based drivers too; it is reported upstream as well.
