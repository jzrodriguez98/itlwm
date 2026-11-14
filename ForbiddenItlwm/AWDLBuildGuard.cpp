//
//  AWDLBuildGuard.cpp
//  ForbiddenItlwm
//
//  Decides once whether AirDrop (AWDL) may start on this macOS build. Two checks must both pass:
//  1. The running kernel is one whose IO80211Family and IOSkywalkFamily were verified (AWDLBuildGuard.hpp).
//  2. Apple's IO80211AWDLProtocol virtual table, which ItlAWDLInterface subclasses slot for slot,
//     still has the expected functions at spread-out anchor slots, its own pure methods where
//     expected, and ends where expected (568 slots on Tahoe, 563 on Sequoia, 547 on Sonoma). This catches a changed
//     table on any build.
//  -itlawdlanybuild skips check 1 (never check 2). When AWDL may not start, the driver behaves like
//  plain AirportItlwm: normal Wi-Fi works and nothing AWDL-related is created or sent.
//

#include <IOKit/IOLib.h>
#include <libkern/version.h>
#include <AWDLBuildGuard.hpp>

#if !defined(ITL_AWDL_NATIVE)
// A target without the AirDrop port: the driver is plain Wi-Fi, and nothing here
// may reference Apple's AWDL classes, which this kext would then need at load time.
bool itlAWDLBuildAllowed() { return false; }
bool itlAWDLBuildVerified() { return false; }
const char *itlAWDLBuildStatus() { return "unavailable: AirDrop isn't ported to this macOS version yet"; }
#else

extern "C" {
extern const uintptr_t itlNativeAWDLProtocolVtable[] __asm__("__ZTV19IO80211AWDLProtocol");
void itlAnchorAWDLProtocolD1() __asm__("__ZN19IO80211AWDLProtocolD1Ev");
void itlAnchorWakeFlags() __asm__("__ZN25IOSkywalkNetworkInterface21getSupportedWakeFlagsEPj");
void itlAnchorInterfaceCCA() __asm__("__ZN23IO80211SkywalkInterface15setInterfaceCCAE18apple80211_channeli");
void itlAnchorStatsDump() __asm__("__ZN23IO80211SkywalkInterface9statsDumpEv");
#if defined(ITL_AWDL_GUARD_SEQUOIA) || defined(ITL_AWDL_GUARD_SONOMA)
void itlAnchorVirtualInit() __asm__("__ZN23IO80211VirtualInterface4initEP17IO80211ControllerP10ether_addrjPKc");
#else
void itlAnchorSyncDPSStats() __asm__("__ZN23IO80211SkywalkInterface12syncDPSStatsEP26apple82011_postMessage_dps");
#endif
void itlAnchorReserved15() __asm__("__ZN23IO80211VirtualInterface34_RESERVEDIO80211VirtualInterface15Ev");
void itlAnchorPureVirtual() __asm__("___cxa_pure_virtual");
}

namespace {
// Slots counted from the address point (the vtable symbol plus two words), as in the 25G241 table
// (Tahoe) and the 24H241 Kernel Debug Kit table (Sequoia).
struct Anchor { unsigned slot; uintptr_t expected; };

int gAllowed = -1;
bool gVerified = false;
const char *gStatus = "not-checked";

bool vtableMatches()
{
    const uintptr_t *slots = itlNativeAWDLProtocolVtable + 2;
    const uintptr_t pure = reinterpret_cast<uintptr_t>(&itlAnchorPureVirtual);
#if defined(ITL_AWDL_GUARD_SONOMA)
    // From 23J631's Kernel Debug Kit: 547 slots, 62 AWDL pure virtuals from 485.
    const Anchor anchors[] = {
        {0, reinterpret_cast<uintptr_t>(&itlAnchorAWDLProtocolD1)},
        {297, reinterpret_cast<uintptr_t>(&itlAnchorWakeFlags)},
        {379, reinterpret_cast<uintptr_t>(&itlAnchorInterfaceCCA)},
        {420, reinterpret_cast<uintptr_t>(&itlAnchorStatsDump)},
        {446, reinterpret_cast<uintptr_t>(&itlAnchorVirtualInit)},
        {484, reinterpret_cast<uintptr_t>(&itlAnchorReserved15)},
        {485, pure},
        {546, pure},
        {547, 0},
    };
#elif defined(ITL_AWDL_GUARD_SEQUOIA)
    const Anchor anchors[] = {
        {0, reinterpret_cast<uintptr_t>(&itlAnchorAWDLProtocolD1)},
        {299, reinterpret_cast<uintptr_t>(&itlAnchorWakeFlags)},
        {380, reinterpret_cast<uintptr_t>(&itlAnchorInterfaceCCA)},
        {415, pure},                                   // setMacAddress, pure in IO80211SkywalkInterface here
        {420, reinterpret_cast<uintptr_t>(&itlAnchorStatsDump)},
        {460, reinterpret_cast<uintptr_t>(&itlAnchorVirtualInit)},
        {499, reinterpret_cast<uintptr_t>(&itlAnchorReserved15)},
        {500, pure},
        {562, pure},
        {563, 0},
    };
#else
    const Anchor anchors[] = {
        {0, reinterpret_cast<uintptr_t>(&itlAnchorAWDLProtocolD1)},
        {300, reinterpret_cast<uintptr_t>(&itlAnchorWakeFlags)},
        {380, reinterpret_cast<uintptr_t>(&itlAnchorInterfaceCCA)},
        {420, reinterpret_cast<uintptr_t>(&itlAnchorStatsDump)},
        {460, reinterpret_cast<uintptr_t>(&itlAnchorSyncDPSStats)},
        {504, reinterpret_cast<uintptr_t>(&itlAnchorReserved15)},
        {505, pure},
        {567, pure},
        {568, 0},
    };
#endif
    for (const auto &a : anchors)
        if (slots[a.slot] != a.expected)
            return false;
    return true;
}
}

bool itlAWDLBuildAllowed()
{
    if (gAllowed >= 0)
        return gAllowed == 1;
    int dummy = 0;
    const bool anyBuild = PE_parse_boot_argn("-itlawdlanybuild", &dummy, sizeof(dummy));
    const ItlAWDL::BuildCheck build = ItlAWDL::checkBuild(version, nullptr);
    if (!vtableMatches()) {
        gStatus = "blocked: IO80211AWDLProtocol table differs";
        gAllowed = 0;
    } else if (build == ItlAWDL::BuildCheck::Verified) {
        gStatus = "verified";
        gAllowed = 1;
        gVerified = true;
#ifdef ITL_AWDL_GUARD_SEQUOIA
    } else if (build == ItlAWDL::BuildCheck::Expected) {
        gStatus = "expected: macOS 15.8.x kernel not checked offline";
        gAllowed = 1;
#endif
    } else if (anyBuild) {
        gStatus = "unverified build, allowed by -itlawdlanybuild";
        gAllowed = 1;
    } else {
        gStatus = "blocked: unverified macOS build";
        gAllowed = 0;
    }
    IOLog("ForbiddenItlwm: AirDrop %s\n", gStatus);
    return gAllowed == 1;
}

// True only for a kernel on the verified list whose table matched. Code that relies on native data
// layouts the vtable anchors don't cover (such as the master indication request) needs this, not
// just itlAWDLBuildAllowed(): an "expected" or -itlawdlanybuild build stays off.
bool itlAWDLBuildVerified()
{
    return itlAWDLBuildAllowed() && gVerified;
}

const char *itlAWDLBuildStatus()
{
    itlAWDLBuildAllowed();
    return gStatus;
}
#endif
