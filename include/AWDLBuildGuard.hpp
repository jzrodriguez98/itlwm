#pragma once
// Which macOS builds AirDrop (AWDL) may run on. The AWDL interface subclasses Apple's IO80211 classes
// and relies on their virtual tables and on a few native data layouts, so it may only start on a
// build where those were verified. Elsewhere the driver behaves like plain AirportItlwm: normal
// Wi-Fi works and nothing AWDL-related starts. -itlawdlanybuild overrides this, for testers who
// accept the risk of a kernel panic.
//
// Each macOS version has its own kext and its own list.
// Tahoe: 25G241 on hardware; 25G332 and 25G342 offline, from Apple's Kernel Debug Kits
// (IOSkywalkFamily identical, IO80211Family's AWDL, interface, buffer and registration code
// instruction-identical, all virtual table slots and all kernel imports matching).
// Sequoia: 24H23 (15.8) and 24H241 (15.8.3) offline, from their Kernel Debug Kits (identical
// IO80211Family virtual tables; the AWDL subclass audited against them). Other 15.8.x kernels
// (xnu-11417.140.69.71x) are allowed as "expected": the runtime vtable check still has to pass.
// Sonoma: 23J631 (14.8.9) offline, from its Kernel Debug Kit. No other build yet.
#include <stddef.h>
#include <string.h>

namespace ItlAWDL {

struct VerifiedBuild {
    const char *osBuild;   // kern.osversion
    const char *kernel;    // the xnu build tag inside the kernel's version string
};

#if defined(__MAC_14_4) && __IO80211_TARGET == __MAC_14_4
#define ITL_AWDL_GUARD_SONOMA 1
constexpr VerifiedBuild kVerifiedBuilds[] = {
    {"23J631", "xnu-10063.141.1.713.39~1/RELEASE_X86_64"},   // macOS 14.8.9
};
#elif defined(__MAC_15_2) && __IO80211_TARGET == __MAC_15_2
#define ITL_AWDL_GUARD_SEQUOIA 1
constexpr VerifiedBuild kVerifiedBuilds[] = {
    {"24H23",  "xnu-11417.140.69.712.69~1/RELEASE_X86_64"},   // macOS 15.8
    {"24H241", "xnu-11417.140.69.713.47~2/RELEASE_X86_64"},   // macOS 15.8.3
};
// 15.8.1 (24H32), 15.8.2 (24H232) and later 15.8.x updates: same kernel train, not checked offline.
constexpr const char *kExpectedKernelPrefix = "xnu-11417.140.69.71";
constexpr const char *kExpectedKernelSuffix = "/RELEASE_X86_64";
#else
constexpr VerifiedBuild kVerifiedBuilds[] = {
    {"25G241", "xnu-12377.161.15.700.19~2/RELEASE_X86_64"},   // macOS 26.7.1
    {"25G332", "xnu-12377.161.15.701.48~2/RELEASE_X86_64"},   // macOS 26.7.2
    {"25G342", "xnu-12377.161.15.701.48~2/RELEASE_X86_64"},   // macOS 26.7.3
};
#endif

enum class BuildCheck { Verified, UnknownBuild, UnknownKernel, Expected };

inline bool containsText(const char *haystack, const char *needle) {
    if (!haystack || !needle || !*needle) return false;
    const size_t n = strlen(needle);
    for (const char *p = haystack; *p; ++p)
        if (!strncmp(p, needle, n)) return true;
    return false;
}

// kernelVersion is the kernel's `version` string, which is always set. osBuild is `osversion`,
// which may still be empty early in boot; then the kernel alone decides. Both must match when set.
inline BuildCheck checkBuild(const char *kernelVersion, const char *osBuild) {
    bool kernelKnown = false;
    for (const auto &b : kVerifiedBuilds)
        if (containsText(kernelVersion, b.kernel)) kernelKnown = true;
#ifdef ITL_AWDL_GUARD_SEQUOIA
    if (!kernelKnown && containsText(kernelVersion, kExpectedKernelPrefix) && containsText(kernelVersion, kExpectedKernelSuffix))
        return BuildCheck::Expected;
#endif
    if (!kernelKnown) return BuildCheck::UnknownKernel;
    if (!osBuild || !*osBuild) return BuildCheck::Verified;
    for (const auto &b : kVerifiedBuilds)
        if (!strcmp(osBuild, b.osBuild) && containsText(kernelVersion, b.kernel)) return BuildCheck::Verified;
    return BuildCheck::UnknownBuild;
}

inline const char *buildCheckName(BuildCheck c) {
    switch (c) {
        case BuildCheck::Verified: return "verified";
        case BuildCheck::UnknownBuild: return "unknown-build";
        case BuildCheck::UnknownKernel: return "unknown-kernel";
        case BuildCheck::Expected: return "expected";   // Sequoia only
    }
    return "unknown";
}

}
