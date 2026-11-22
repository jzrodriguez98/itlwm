#!/bin/bash
# AirDrop on Intel Wi-Fi: compatibility check for testers.
#
# Read-only. It changes nothing, needs no sudo and sends nothing anywhere. It reads the macOS build,
# the Intel Wi-Fi and Bluetooth hardware IDs, which kexts are loaded and, if AirportItlwm
# is already running, a few of its status keys. Then it says how likely the driver is
# to work on this machine, based on the support table in tools/compat/README.md (2026-11-10 study).
#
# Usage: bash check_compat.sh
#
# The verdict is an estimate. The project tests the AX211 (firmware so-a0-gf-a0-68) on macOS 26.7.1
# (25G241); 26.7.2 (25G332) and 26.7.3 (25G342) were verified offline. On Sequoia, 15.8 (24H23) and 15.8.3
# (24H241) were verified offline for the separate Sequoia kexts; 15.8.1 (24H32) and 15.8.2 (24H232) run
# verified kernels. Users report AirDrop working with the AX201, AX200, AX210 and AX411 class (see
# docs/TESTED-HARDWARE.md). Everything else is predicted from the firmware's capabilities and the code.

set -u
export LC_ALL=C

if [ -t 1 ]; then
    RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; BLU=$'\033[36m'; BLD=$'\033[1m'; RST=$'\033[0m'
else
    RED=; GRN=; YEL=; BLU=; BLD=; RST=
fi
pass() { printf '  %s[ OK ]%s %s\n' "$GRN" "$RST" "$*"; }
warn() { printf '  %s[WARN]%s %s\n' "$YEL" "$RST" "$*"; }
fail() { printf '  %s[FAIL]%s %s\n' "$RED" "$RST" "$*"; }
info() { printf '  %s[info]%s %s\n' "$BLU" "$RST" "$*"; }
head1() { printf '\n%s%s%s\n' "$BLD" "$*" "$RST"; }

TESTED_VERSION="26.7.1"
TESTED_BUILD="25G241"
BLOCKERS=0     # Things that stop it working at all, whatever the card.
CARD_TIER=""   # tested, likely, needs-fixes, port, unsupported, unknown

if [ "$(uname -s)" != "Darwin" ]; then
    echo "This check runs on macOS. On Linux, use collect_hw_linux.sh to collect hardware details instead."
    exit 2
fi

echo "${BLD}AirDrop on Intel Wi-Fi: compatibility check${RST}"
echo "Read-only: nothing on this Mac is changed."

# ---------------------------------------------------------------- macOS
head1 "1. macOS"
OS_VER=$(sw_vers -productVersion 2>/dev/null)
OS_BUILD=$(sw_vers -buildVersion 2>/dev/null)
ARCH=$(uname -m)
info "macOS $OS_VER ($OS_BUILD), $ARCH"
if [ "$ARCH" != "x86_64" ]; then
    fail "Needs an Intel (x86_64) hackintosh."
    BLOCKERS=$((BLOCKERS + 1))
fi
OS_MAJOR=${OS_VER%%.*}
# Builds the driver allows AirDrop on (AirportItlwm/AWDLBuildGuard.cpp): 25G241 tested on
# hardware, 25G332 and 25G342 verified offline from Apple's Kernel Debug Kits.
OFFLINE_BUILDS="25G332 25G342"
if [ "$OS_BUILD" = "$TESTED_BUILD" ]; then
    pass "Same build as the tested one ($TESTED_VERSION, $TESTED_BUILD)."
elif [ -n "$OS_BUILD" ] && echo " $OFFLINE_BUILDS " | grep -q " $OS_BUILD "; then
    pass "macOS $OS_VER ($OS_BUILD): supported. Its Wi-Fi stack was checked against $TESTED_BUILD and is the same where"
    pass "the driver depends on it. See the bluetoothd pattern check below for the Bluetooth side. Please report your result."
elif [ "${OS_MAJOR:-0}" = "15" ]; then
    # The Sequoia kexts (AirportItlwm and BTLEAdvFixup for Sequoia), not the Tahoe ones.
    SEQ_VERIFIED="24H23 24H32 24H232 24H241"   # 24H32 (15.8.1) and 24H232 (15.8.2) run verified kernels
    OS_MINOR=$(echo "$OS_VER" | cut -d. -f2)
    if echo " $SEQ_VERIFIED " | grep -q " $OS_BUILD "; then
        pass "macOS $OS_VER ($OS_BUILD): supported by the Sequoia kexts. Users report AirDrop working on 15.8.1 to 15.8.3"
        pass "with 0.5.1-test1 or later. Use the Sequoia AirportItlwm and IntelBTPatcher bundle built by this branch."
    elif [ "${OS_MINOR:-0}" = "8" ]; then
        warn "macOS $OS_VER ($OS_BUILD): expected to work with the Sequoia kexts (same 15.8 kernel family), but this build"
        warn "wasn't checked offline. The driver still checks Apple's Wi-Fi tables at boot. Please report your result."
    else
        fail "On Sequoia, AirDrop needs macOS 15.8 or newer (this is $OS_VER). Normal Wi-Fi may still work with the Sequoia kext."
        BLOCKERS=$((BLOCKERS + 1))
    fi
elif [ "${OS_MAJOR:-0}" = "14" ]; then
    # The Sonoma kexts (in development): only 14.8.9 was checked offline.
    if [ "$OS_BUILD" = "23J631" ]; then
        pass "macOS $OS_VER ($OS_BUILD): supported by the Sonoma kexts. Their Wi-Fi stack was checked offline, but Sonoma"
        pass "isn't confirmed working on hardware yet, so please report your result. Use the Sonoma AirportItlwm and IntelBTPatcher bundle built by this branch."
    else
        warn "macOS $OS_VER ($OS_BUILD): only Sonoma 14.8.9 (23J631) is checked. On this build the Sonoma kext keeps AirDrop off"
        warn "(normal Wi-Fi may still work). Updating to 14.8.9 is the way to get AirDrop on Sonoma."
    fi
elif [ "${OS_MAJOR:-0}" = "26" ]; then
    warn "macOS 26 but build $OS_BUILD isn't verified yet. The driver keeps AirDrop off on it (normal Wi-Fi still works),"
    warn "unless you add -itlawdlanybuild, which risks a kernel panic. Please report this build so it can be checked."
    BLOCKERS=$((BLOCKERS + 1))
else
    fail "AirDrop is only built for macOS 26 (Tahoe), 15.8 (Sequoia) and 14.8.9 (Sonoma). Tested on $TESTED_VERSION ($TESTED_BUILD)."
    BLOCKERS=$((BLOCKERS + 1))
fi

# ---------------------------------------------------------------- Wi-Fi card
head1 "2. Intel Wi-Fi card"
# One line per PCI network controller: vendor device subvendor subdevice revision ioname model
# (ioreg -r prints each match as a block. Its children, such as the Wi-Fi driver that publishes
# IOModel, the firmware name, are indented inside it, and so is a card behind a PCI bridge.)
le16() { # "<f0510000>" -> 51f0
    local h=${1#<}; h=${h%>}
    printf '%s%s' "${h:2:2}" "${h:0:2}"
}
PCI_LINES=$(ioreg -r -c IOPCIDevice -l -w0 2>/dev/null | awk '
    function flush() { if (cls ~ /^<..8002/) print ven, dev, sven, sdev, rev, nm, (model == "" ? "-" : model); }
    # A device behind a PCI bridge (a discrete M.2 card behind a root port) is printed inside the
    # entry of the bridge, indented, so a new device starts at any IOPCIDevice line, at any depth.
    /^[ |]*\+-o .*<class IOPCIDevice,/ { if (started) flush(); started=1; ven=dev=sven=sdev=rev=cls=nm=model=""; s=$0; sub(/^[ |]*\+-o /, "", s); split(s, a, " "); nm=a[1]; next }
    /"class-code" = /      && cls == ""  { cls=$NF }
    /"vendor-id" = /       && ven == ""  { ven=$NF }
    /"device-id" = /       && dev == ""  { dev=$NF }
    /"subsystem-vendor-id" = / && sven == "" { sven=$NF }
    /"subsystem-id" = /    && sdev == "" { sdev=$NF }
    /"revision-id" = /     && rev == ""  { rev=$NF }
    /"IOModel" = "iwl/     && model == "" { model=$NF; gsub(/"/, "", model) }
    END { if (started) flush() }')

FOUND_INTEL=0
WIFI_DEV=""; WIFI_FW=""
while read -r ven dev sven sdev rev nm model; do
    [ -z "${ven:-}" ] && continue
    v=$(le16 "$ven"); d=$(le16 "$dev"); sv=$(le16 "$sven"); sd=$(le16 "$sdev"); r=$(le16 "$rev")
    if [ "$v" != "8086" ]; then
        info "Network controller $v:$d at $nm is not Intel; this driver doesn't cover it."
        continue
    fi
    FOUND_INTEL=1; WIFI_DEV=$d; WIFI_FW=$model
    info "Intel Wi-Fi at $nm: device 0x$d, subsystem $sv:$sd, revision 0x$r"
done <<EOF
$PCI_LINES
EOF

lower() { printf '%s' "$1" | tr 'A-F' 'a-f'; }
classify_device() { # family from the PCI device ID alone
    case "$(lower "$1")" in
        2723) echo "ax200";;
        02f0|06f0|34f0|3df0|4df0|43f0|a0f0) echo "qu";;
        2720) echo "qnj";;
        2725) echo "ax210-family-discrete";;
        7a70|7af0|51f0|51f1|54f0|7f70) echo "so-cnvi";;
        2726) echo "snj";;
        2729|7e40) echo "ma";;
        08b1|08b2|08b3|08b4|095a|095b|3165|3166|24f3|24f4|24f5|24f6|24fb|24fd|2526|9df0|a370|31dc|30dc|271c|271b|42a4) echo "iwm";;
        42*|00[0-9a-f][0-9a-f]|08[89a][0-9a-f]|0082|0083|0084|0085|0087|0089|008a|008b|0090|0091|0892|0893|0894|0895|0896|0897|08ae|08af|088e|088f|0890|0891|0887|0888) echo "iwn";;
        272b|a840) echo "wifi7";;
        *) echo "unknown";;
    esac
}
describe_firmware() { # the firmware the Wi-Fi driver loaded says which radio is on the card
    case "$1" in
        iwlwifi-so-a0-gf-a0-*)  CARD_TIER=tested;      TEXT="AX211. The tested card.";;
        iwlwifi-ty-a0-gf-a0-*)  CARD_TIER=reported;    TEXT="AX210. Users report AirDrop working (Tahoe 26.7.2 and 26.7.3, Sequoia 15.8.1).";;
        iwlwifi-so-a0-gf4-a0-*) CARD_TIER=reported;    TEXT="AX411 class (AX1690i). Users report AirDrop working on Tahoe 26.7.2. Its firmware can run two radios at once (CDB), which the driver doesn't use.";;
        iwlwifi-so-a0-hr-b0-*)  CARD_TIER=likely;      TEXT="Wi-Fi 6 HR radio (AX201/AX203 class) on an Alder Lake or newer platform. Same family as AX211. Users report an AX201 working on Tahoe 26.7.1.";;
        iwlwifi-so-a0-jf-b0-*)  CARD_TIER=likely;      TEXT="Wi-Fi 5 JF radio (9560/9462/9461 class) on an Alder Lake or newer platform. Same family; untested. 9461/9462 have one antenna.";;
        iwlwifi-cc-a0-*)        CARD_TIER=reported;    TEXT="AX200. Older family (22000). Users report AirDrop working on Sequoia 15.6.";;
        iwlwifi-Qu*-hr-*)       CARD_TIER=reported;    TEXT="Wi-Fi 6 HR radio (AX201, or the one-antenna AX101) on Ice, Comet or Tiger Lake. Users report the AX201 working on Tahoe 26.7.1 and 26.7.3 and on Sequoia 15.8.1 to 15.8.3. The AX101 is untested.";;
        iwlwifi-Qu*-jf-*)       CARD_TIER=needs-fixes; TEXT="Wi-Fi 5 JF radio (9560, or one-antenna 9461/9462) on Ice or Comet Lake. Older family (22000), untested.";;
        iwlwifi-SoSnj-*|iwlwifi-ma-*|iwlwifi-QuQnj-*)
                                CARD_TIER=unsupported; TEXT="Needs firmware ($1) that this driver doesn't bundle, so even normal Wi-Fi won't start.";;
        *)                      CARD_TIER=unknown;     TEXT="Firmware $1 isn't in the support table.";;
    esac
}

if [ "$FOUND_INTEL" = 0 ]; then
    fail "No Intel Wi-Fi card found on PCI. This driver is only for Intel cards."
    CARD_TIER=unsupported
else
    FAMILY=$(classify_device "$WIFI_DEV")
    if [ -n "$WIFI_FW" ] && [ "$WIFI_FW" != "-" ]; then
        info "Wi-Fi driver loaded firmware: $WIFI_FW"
        describe_firmware "$WIFI_FW"
        case "$CARD_TIER" in
            tested|reported) pass "$TEXT";;
            likely) warn "$TEXT";;
            needs-fixes) warn "$TEXT";;
            *) fail "$TEXT";;
        esac
    else
        case "$FAMILY" in
            ax200)  CARD_TIER=reported; pass "AX200 (by device ID). Users report AirDrop working on Sequoia 15.6.";;
            qu)     CARD_TIER=likely; warn "Ice/Comet/Tiger Lake CNVi card (AX201, AX101 or 9560/9461/9462 class). Users report the AX201 working; the others are untested."
                    info "Load AirportItlwm (or AirportItlwm) and run this again to tell which radio it is.";;
            qnj)    CARD_TIER=unsupported; fail "Discrete 22000 card whose firmware (QuQnj) isn't bundled.";;
            ax210-family-discrete) CARD_TIER=reported; pass "AX210 (by device ID). Users report AirDrop working (Tahoe 26.7.2 and 26.7.3, Sequoia 15.8.1).";;
            so-cnvi) CARD_TIER=likely; warn "Alder Lake or newer CNVi slot. It could hold an AX211 (tested), AX201/AX203 or 9560-class radio."
                     info "Load AirportItlwm (or AirportItlwm) and run this again to tell which radio it is.";;
            snj)    CARD_TIER=unsupported; fail "Device 0x2726 needs SoSnj firmware, which isn't bundled.";;
            ma)     CARD_TIER=unsupported; fail "Meteor Lake class CNVi (0x$WIFI_DEV) needs 'ma' firmware, which isn't bundled. Normal Wi-Fi won't start either.";;
            iwm)    CARD_TIER=port; fail "Older card (7000/8000/9000 series on the iwm driver part). It has no AirDrop code, and its firmware has no"
                    fail "rate control of its own. Supporting it is a large port, not a fix.";;
            iwn)    CARD_TIER=unsupported; fail "Pre-2013 card (no 80 MHz, no multi-role firmware). Not practical to support.";;
            wifi7)  CARD_TIER=unsupported; fail "Wi-Fi 7 card (BE200/BE201/BE202 class). itlwm doesn't support these at all yet.";;
            *)      CARD_TIER=unknown; fail "Device 0x$WIFI_DEV isn't in the driver's table. Please run collect_hw_macos.sh and share the report.";;
        esac
    fi
fi

# ---------------------------------------------------------------- Wi-Fi driver
head1 "3. Wi-Fi driver"
KEXTS=$(kmutil showloaded --list-only 2>/dev/null | awk '{print $6, $7}')
kext_version() { printf '%s\n' "$KEXTS" | awk -v id="$1" '$1 == id { gsub(/[()]/, "", $2); print $2; exit }'; }
AIRPORT=$(kext_version com.zxystd.AirportItlwm)
ITLWM=$(kext_version com.zxystd.itlwm)
if [ -n "$AIRPORT" ]; then
    pass "AirportItlwm $AIRPORT is loaded."
elif [ -n "$ITLWM" ]; then
    fail "itlwm $ITLWM is loaded. This AirDrop build uses AirportItlwm (the native Wi-Fi variant), not itlwm with HeliPort."
else
    warn "No Intel Wi-Fi driver is loaded. The card check above used PCI IDs only."
fi
MARKER=$(ioreg -l -w0 2>/dev/null | sed -n 's/.*"ItlwmAWDLInterfaceBuild" = "\([^"]*\)".*/\1/p' | head -1)
if [ -n "$MARKER" ]; then
    pass "The AirDrop build is running: $MARKER."
else
    info "AirportItlwm's AirDrop interface isn't running (no ItlwmAWDLInterfaceBuild key). That's expected before installing it."
fi

# ---------------------------------------------------------------- Bluetooth
head1 "4. Bluetooth"
BT_IDS=$(ioreg -p IOUSB -l -w0 2>/dev/null | awk '
    /"idVendor" = / { ven=$NF }
    /"idProduct" = / { prod=$NF }
    /^[ |]*\+-o / { if (ven == 32903 && prod != "") printf "%04x\n", prod; ven=""; prod="" }
    END { if (ven == 32903 && prod != "") printf "%04x\n", prod }' | sort -u)
BT_OK=0
if [ -z "$BT_IDS" ]; then
    fail "No Intel Bluetooth controller on USB. AirDrop finds devices over Bluetooth LE first, so it can't work without one."
    BLOCKERS=$((BLOCKERS + 1))
else
    for p in $BT_IDS; do
        case "$p" in
            0033) pass "Intel Bluetooth 8087:$p (AX211 class, Bluetooth 5). Same as the tested machine."; BT_OK=1;;
            0032) pass "Intel Bluetooth 8087:$p (AX210 class, Bluetooth 5)."; BT_OK=1;;
            0029) pass "Intel Bluetooth 8087:$p (AX200 class, Bluetooth 5)."; BT_OK=1;;
            0026) pass "Intel Bluetooth 8087:$p (AX201 class, Bluetooth 5)."; BT_OK=1;;
            0025) pass "Intel Bluetooth 8087:$p (9260 class, Bluetooth 5)."; BT_OK=1;;
            0aaa) pass "Intel Bluetooth 8087:$p (9560/9462/9461 class, Bluetooth 5)."; BT_OK=1;;
            0a2b|0a2a|07dc|07da|0aa7)
                  warn "Intel Bluetooth 8087:$p is Bluetooth 4.x. The LE advertising fix in this branch's IntelBTPatcher bundle relies on Bluetooth 5 extended advertising."; BT_OK=1;;
            0035|0036|0037)
                  warn "Intel Bluetooth 8087:$p (Wi-Fi 7 generation). Not known to work with IntelBluetoothFirmware."; BT_OK=1;;
            *)    info "Intel USB device 8087:$p (not a known Bluetooth controller ID)." ;;
        esac
    done
fi
IBTFW=$(kext_version com.zxystd.IntelBluetoothFirmware)
BTFIX=$(kext_version as.acidanthera.BlueToolFixup)
BTLEADV=$(kext_version org.forbiddenitlwm.IntelBTPatcher)
[ -z "$BTLEADV" ] && BTLEADV=$(kext_version org.forbiddenitlwm.BTLEAdvFixup)
[ -z "$BTLEADV" ] && BTLEADV=$(kext_version org.itlwmawdl.BTLEAdvFixup)
IBTPATCH=$(kext_version com.zxystd.IntelBTPatcher)
LILU=$(kext_version as.vit9696.Lilu)
# IntelBTUnified (laguillo) combines IntelBluetoothFirmware, IntelBTPatcher and BlueToolFixup. Its bundle ID
# depends on how it was built (local.IntelBTUnified by default), so it's matched by name.
IBTUNI=$(printf '%s\n' "$KEXTS" | awk '$1 ~ /IntelBTUnified$/ { gsub(/[()]/, "", $2); print $2; exit }')
if [ -n "$IBTUNI" ]; then
    info "IntelBTUnified $IBTUNI is loaded. It replaces IntelBluetoothFirmware, IntelBTPatcher and BlueToolFixup."
    warn "IntelBTUnified includes the original IntelBTPatcher USB hook, which this branch's IntelBTPatcher bundle also uses with -btleadv; Lilu panics when two plugins hook the same function. For AirDrop, use IntelBluetoothFirmware, BlueToolFixup and this branch's IntelBTPatcher bundle only."
else
    [ -n "$IBTFW" ] && pass "IntelBluetoothFirmware $IBTFW is loaded." || warn "IntelBluetoothFirmware isn't loaded."
    [ -n "$BTFIX" ] && pass "BlueToolFixup $BTFIX is loaded." || warn "BlueToolFixup isn't loaded (needed for third-party Bluetooth on recent macOS)."
fi
[ -n "$LILU" ] && pass "Lilu $LILU is loaded." || warn "Lilu isn't loaded (BTLEAdvFixup is a Lilu plugin)."
if [ -n "$BTLEADV" ]; then pass "AirDrop IntelBTPatcher bundle $BTLEADV is loaded."; else info "The AirDrop IntelBTPatcher bundle isn't loaded. It's part of the AirDrop package."; fi
[ -n "$IBTPATCH" ] && [ -n "$BTLEADV" ] && warn "The original IntelBTPatcher and this fork's renamed IntelBTPatcher bundle are both loaded. They hook the same USB requests; keep only this fork's bundle enabled."
# The IntelBTPatcher bundle patches four places in bluetoothd. Its patterns are exact bytes from macOS 26.7.1
# (25G241) and 26.7.3 (25G342) for the Tahoe build, and from 15.8.3 (24H241) for the Sequoia build (also matching 15.8 and 15.8.2), so
# they only match a bluetoothd of one of those builds. This reads /usr/sbin/bluetoothd
# (read-only) and counts each site in its original form and, when the IntelBTPatcher bundle is already running and
# the page cache returns the patched page, in its patched form. Generated from
# BTLEAdvFixup/BTLEAdvPatches.hpp; keep the two in step.
BTD=/usr/sbin/bluetoothd
if [ -r "$BTD" ] && command -v perl >/dev/null 2>&1; then
    BT_SET=tahoe; [ "${OS_MAJOR:-0}" = "15" ] && BT_SET=sequoia; [ "${OS_MAJOR:-0}" = "14" ] && BT_SET=sonoma
    BT_PATTERNS=$(BT_SET=$BT_SET perl -0777 -ne '
        sub n { my $hex = shift; my $re = join "", map { "\\x$_" } ($hex =~ /(..)/g); my $c = () = /$re/sg; return $c; }
        my (@advertising, @scanning, @randomAddress, @extendedConnection);
        if ($ENV{BT_SET} eq "sonoma") {
            @advertising = (n("84c00f8434010000e88e7cfaff488b084889c7ff91000700004189c6"), n("84c0909090909090e88e7cfaff488b084889c7b801000000904189c6"));
            @scanning = (n("84c00f8434010000e8207ffaff488b084889c7ff91700700004189c6"), n("84c0909090909090e8207ffaff488b084889c7b801000000904189c6"));
            @randomAddress = (n("83b8c402000003772331ffe8fca4d6ff"), n("83b8c402000003772390909090909090"));
            @extendedConnection = (n("0fb6bd6effffffe8c8bfd7ff"), n("bf010000009090e8c8bfd7ff"));
        } elsif ($ENV{BT_SET} eq "sequoia") {
            @advertising = (n("84c00f8438010000e8104cf9ff488b084889c7ff91c00700004189c6"), n("84c0909090909090e8104cf9ff488b084889c7b801000000904189c6"));
            @scanning = (n("84c00f8438010000e8ba4ef9ff488b084889c7ff91480800004189c6"), n("84c0909090909090e8ba4ef9ff488b084889c7b801000000904189c6"));
            @randomAddress = (n("83b8f8020000037723" . "31ffe859abd2ff"), n("83b8f802000003772390909090909090"));
            @extendedConnection = (n("0fb6bd5effffffe800cfd3ff"), n("bf010000009090e800cfd3ff"));
        } else {
            # Tahoe: the 26.7.1 and 26.7.3 sets. Only one set can match a given bluetoothd.
            @advertising = (n("84c00f8438010000e80878f8ff488b084889c7ff91180900004189c6") + n("84c00f8438010000e81878f8ff488b084889c7ff91180900004189c6"),
                            n("84c0909090909090e80878f8ff488b084889c7b801000000904189c6") + n("84c0909090909090e81878f8ff488b084889c7b801000000904189c6"));
            @scanning = (n("84c00f8438010000e8b27af8ff488b084889c7ff91a80900004189c6") + n("84c00f8438010000e8c27af8ff488b084889c7ff91a80900004189c6"),
                         n("84c0909090909090e8b27af8ff488b084889c7b801000000904189c6") + n("84c0909090909090e8c27af8ff488b084889c7b801000000904189c6"));
            @randomAddress = (n("83b83403000003772a31ffe83e6bceff") + n("83b83403000003772a31ffe81e6cceff"),
                              n("83b83403000003772a90909090909090"));   # same patched bytes on both builds: count once
            @extendedConnection = (n("0fb6bd5effffffe8cb9dcfff") + n("0fb6bd5effffffe8ab9ecfff"),
                                   n("bf010000009090e8cb9dcfff") + n("bf010000009090e8ab9ecfff"));
        }
        for my $p (["advertising", @advertising], ["scanning", @scanning], ["randomAddress", @randomAddress], ["extendedConnection", @extendedConnection]) {
            my ($name, $orig, $patched) = @$p;
            printf "%s=%d(%s) ", $name, $orig + $patched, $patched ? "patched" : "original";
        }' "$BTD" 2>/dev/null)
    BT_MATCH_OK=1
    for kv in $BT_PATTERNS; do v=${kv#*=}; [ "${v%%(*}" = 1 ] || BT_MATCH_OK=0; done
    if [ -z "$BT_PATTERNS" ]; then
        info "Couldn't read bluetoothd to check the IntelBTPatcher bundle's patterns."
    elif [ "$BT_MATCH_OK" = 1 ]; then
        pass "IntelBTPatcher bundle patterns each match this macOS's bluetoothd once ($BT_PATTERNS)."
    else
        warn "IntelBTPatcher bundle patterns don't all match this bluetoothd ($BT_PATTERNS). Each should be 1."
        warn "Without them the Mac can't advertise AirDrop over Bluetooth, so iPhones won't list it. Please report this build."
    fi
fi
BT_STATE=$(system_profiler SPBluetoothDataType 2>/dev/null | awk -F': ' '/^ *State:/ { print $2; exit }')
[ -n "$BT_STATE" ] && info "Bluetooth state: $BT_STATE"

# ---------------------------------------------------------------- channels 149 and 44, and country
head1 "5. Channels 149 and 44, and country"
# The fast mode puts the AirDrop listener on the iPhone's 5 GHz AWDL channel at 80 MHz: 149 (needs 149 to
# 161 in the firmware's channel map and allowed to transmit) or, from 0.6.0, 44 where the iPhone uses 44
# (needs 36 to 48). Intel firmware starts in world mode (country ZZ), where those channels are listen-only,
# and opens them only after it learns the country from a nearby network's beacons. The driver accepts the
# firmware's decision and never overrides it.
SP=$(system_profiler SPAirPortDataType 2>/dev/null)
CC=$(printf '%s\n' "$SP" | awk -F': ' '/^ *Country Code:/ { print $2; exit }')
SUPPORTED=$(printf '%s\n' "$SP" | awk -F': ' '/^ *Supported Channels:/ { print $2; exit }')
CUR_CH=$(printf '%s\n' "$SP" | awk '/Current Network Information:/ { on=1 } /Other Local Wi-Fi Networks:/ { on=0 }
    on && /^ *Channel:/ { sub(/^ *Channel: */, ""); print; exit }')
NEARBY=$(printf '%s\n' "$SP" | awk '/Other Local Wi-Fi Networks:/ { on=1; next } on && /^ *Channel:/ { sub(/^ *Channel: */, ""); print }')
# Countries whose rules, in the Linux wireless regulatory database (wireless-regdb db.txt, read
# 2026-11-10), have no Wi-Fi rule covering channels 149 to 161, or allow them only at 20 or 40 MHz.
# Intel firmware applies its own built-in tables, which follow the same laws but can be stricter, so a
# country missing from these lists can still have 149 closed by the firmware.
NO_149=" AF AI AN AW AZ BL BT BY DZ EG ET FO GE GF GI GL GP IM IR JP KH LS MA MF MQ MR MW PF PM RE SA SM SR TD TN TR UZ VA VC WF WS YE YT ZW "
NARROW_149=" CF KE GU KP SV "
CC_OVERRIDE=$(sysctl -n kern.bootargs 2>/dev/null | tr ' ' '\n' | sed -n 's/^itlwm_cc=//p' | head -1)

if [ -n "$CC_OVERRIDE" ]; then
    warn "Boot argument itlwm_cc=$CC_OVERRIDE is set. It only changes the code macOS shows; the firmware's channel map"
    warn "is unchanged, and this project doesn't use overrides. Remove it so the check reads the firmware's own code."
fi
if [ -z "$SP" ]; then
    warn "macOS returned no Wi-Fi details (is Wi-Fi on?)."
elif [ -z "$CC" ] || [ "$CC" = "ZZ" ] || [ "$CC" = "00" ]; then
    # Without a country, the driver still uses 149 or 44 once it has heard a router beaconing there (or the
    # station is connected in the same band), so the listener's own channel decides, when the build runs.
    LISTEN_CH=""
    [ -n "$MARKER" ] && LISTEN_CH=$(ioreg -l -w0 2>/dev/null | sed -n 's/.*"ITLAWDLCoexChannel" = \([0-9]*\).*/\1/p' | head -1)
    if [ "$LISTEN_CH" = "149" ] || [ "$LISTEN_CH" = "44" ]; then
        info "Country code: ${CC:-none}. The firmware hasn't learned a country, but the listener is on channel $LISTEN_CH:"
        info "routers heard on that channel (or your Wi-Fi in the same band) let the driver use it anyway."
        CH149_STATE=no-country-open
    else
        warn "Country code: ${CC:-none}. The firmware hasn't learned a country, so channels 149 and 44 are listen-only for now."
        warn "AirDrop will use channel 6 (very slow) until a nearby network advertises the country, or until routers"
        warn "are heard on 149 or 44."
        CH149_STATE=no-country
    fi
else
    pass "Country code: $CC. The firmware (or macOS's location, when the firmware has none) reports a country."
    CH149_STATE=country
    case "$NO_149" in
        *" $CC "*)
            warn "In $CC the radio rules don't allow Wi-Fi on channels 149 to 161 (Linux regulatory database)."
            warn "iPhones use channel 44 there. From 0.6.0 the listener follows them to 44 if the firmware allows it;"
            warn "up to 0.5.4, and where 44 isn't allowed either, AirDrop uses channel 6 (very slow)."
            CH149_STATE=law;;
    esac
    case "$NARROW_149" in
        *" $CC "*)
            warn "In $CC the rules allow channels 149 to 161 only at 20 or 40 MHz. The fast mode needs 80 MHz,"
            warn "so the driver is expected to use channel 44 (from 0.6.0, if the iPhone uses it) or 6 here."
            CH149_STATE=law;;
    esac
fi
if [ -n "$SUPPORTED" ]; then
    MISSING_CH=""
    for c in 149 153 157 161; do
        case ", $SUPPORTED," in *", $c (5GHz)"*|*", $c (5 GHz)"*) ;; *) MISSING_CH="$MISSING_CH $c";; esac
    done
    MISSING_44=""
    for c in 36 40 44 48; do
        case ", $SUPPORTED," in *", $c (5GHz)"*|*", $c (5 GHz)"*) ;; *) MISSING_44="$MISSING_44 $c";; esac
    done
    if [ -z "$MISSING_CH" ]; then
        pass "Channels 149, 153, 157 and 161 are in the channel map (needed for 149 at 80 MHz)."
    else
        warn "Missing from the channel map:$MISSING_CH. 149 at 80 MHz isn't possible here."
    fi
    if [ -z "$MISSING_44" ]; then
        pass "Channels 36, 40, 44 and 48 are in the channel map (needed for 44 at 80 MHz, from 0.6.0)."
    else
        warn "Missing from the channel map:$MISSING_44. 44 at 80 MHz isn't possible here."
    fi
    if [ -n "$MISSING_CH" ] && [ -n "$MISSING_44" ]; then
        fail "Neither 149 nor 44 at 80 MHz is possible here; AirDrop would stay on channel 6."
        CH149_STATE=not-in-map
    fi
    case ", $SUPPORTED," in *", 6 (2GHz)"*|*", 6 (2.4GHz)"*) ;; *) warn "Channel 6 isn't in the channel map either, so the listener has no channel at all.";; esac
fi
[ -n "$CUR_CH" ] && info "Your Wi-Fi network is on channel $CUR_CH."
if [ -n "$NEARBY" ]; then
    N_ALL=$(printf '%s\n' "$NEARBY" | grep -c .)
    N_5=$(printf '%s\n' "$NEARBY" | grep -c '5GHz')
    N_U3=$(printf '%s\n' "$NEARBY" | awk '{ c=$1+0 } c >= 149 && c <= 165 { n++ } END { print n+0 }')
    info "Nearby networks macOS lists: $N_ALL ($N_5 on 5 GHz, $N_U3 on channels 149 to 165)."
    if [ "$N_U3" -gt 0 ]; then
        info "Networks on 149 to 165 nearby suggest those channels are legal where you are."
    fi
else
    info "macOS listed no other nearby networks (it can hide them without Location Services)."
fi
info "Channels 149 and 44 also depend on the country's radio laws. Even after it learns the country, the firmware"
info "decides, and in some countries (Japan and Turkey, for example) Wi-Fi isn't allowed on 149 to 161 at all."
case "${CH149_STATE:-}" in
    no-country)
        info "What helps: be near networks that advertise their country (most home and office routers do)."
        info "In the project's tests an iPhone's Personal Hotspot, switched on nearby (not joined), also taught the firmware.";;
esac

# ---------------------------------------------------------------- AirDrop runtime
head1 "6. AirDrop listener (only while the AirDrop build runs)"
if [ -n "$MARKER" ]; then
    REG=$(ioreg -l -w0 2>/dev/null | grep -oE '"ITLAWDLCoex(Channel|OwnWidth|CountryLearned|CountryNotices|CountryAnswers|CountryFailures|RefusedReason|MultiState|Added|Gate|AssumeZero|Peer5GHz)" = [^,}]*' | sort -u)
    get() { printf '%s\n' "$REG" | sed -n "s/^\"ITLAWDLCoex$1\" = //p" | head -1 | tr -d '"'; }
    CH=$(get Channel); W=$(get OwnWidth); CL=$(get CountryLearned); ADDED=$(get Added); P5=$(get Peer5GHz)
    if [ -z "$ADDED" ]; then
        warn "No listener status yet. Join a Wi-Fi network and wait a minute, then run this again."
    elif { [ "$CH" = "149" ] || [ "$CH" = "44" ]; } && [ "$W" = "80" ]; then
        pass "Listener on channel $CH at 80 MHz (country learned: ${CL:-?}). This is the fast mode."
    elif [ "$CH" = "149" ] || [ "$CH" = "44" ]; then
        info "Listener on channel $CH at ${W:-?} MHz (country learned: ${CL:-?})."
    elif [ "$CH" = "6" ]; then
        warn "Listener on channel 6 at 20 MHz. The firmware hasn't opened channel 149 or 44 yet, usually because no"
        warn "nearby network has told it the country. AirDrop is very slow or fails on channel 6."
    else
        info "Listener channel ${CH:-?}, width ${W:-?}, state $(get MultiState)."
    fi
    if [ -n "$ADDED" ]; then
        case "$P5" in
            44|149) info "Your iPhone uses channel $P5 for AirDrop (from its last sync frames).";;
            1) info "Your iPhone's latest schedule names neither 149 nor 44.";;
        esac
        NOTICES=$(get CountryNotices); ANSWERS=$(get CountryAnswers)
        if [ "$CL" = "Yes" ] && [ "$CH" != "149" ] && [ "$CH" != "44" ]; then
            warn "The firmware learned a country this boot but still keeps the listener off channels 149 and 44. Its"
            warn "rules for this country don't allow AirDrop there, and the driver accepts that."
        elif [ "$CL" = "Yes" ]; then
            pass "The firmware learned a country this boot ($NOTICES notices, $ANSWERS answered)."
        elif [ "${NOTICES:-0}" -gt 0 ] 2>/dev/null; then
            warn "The firmware sent $NOTICES country notices but hasn't settled on a country yet."
        else
            warn "The firmware hasn't reported any country this boot."
        fi
        RR=$(get RefusedReason)
        if [ -n "$RR" ] && [ "$RR" != "0" ]; then
            WHY=""
            [ $((RR & 2)) -ne 0 ] && WHY="$WHY listen-only (passive),"
            [ $((RR & 4)) -ne 0 ] && WHY="$WHY radar (DFS),"
            [ $((RR & 8)) -ne 0 ] && WHY="$WHY no ad hoc,"
            [ $((RR & 16)) -ne 0 ] && WHY="$WHY not active,"
            warn "The firmware refused the listener's channel last time it was checked:${WHY%,}."
        fi
    fi
    ARGS=$(sysctl -n kern.bootargs 2>/dev/null)
    # The tested set from docs/BOOT-FLAGS.md; keep the two in step. Flags without a value must match
    # whole words; the two with a value (itlawdlintcoal=, itlawdltxqueue=) match by name.
    MISSING=""
    for f in -btleadv -itlawdlcoexprobe -itlawdliface -itlawdlnativeup -itlawdlcoexrx -itlawdlcoextx -itlawdlcoexmulti \
             -itlawdlcoexdata -itlawdlmitx -itlawdlelicit -itlawdlcaps -itlawdlsvcmerge -itlawdlawsync \
             -itlawdlcoexbatx -itlawdlcoexpeerpause -itlawdlcoexbatrace; do
        case " $ARGS " in *" $f "*) ;; *) MISSING="$MISSING $f";; esac
    done
    for f in itlawdlintcoal itlawdltxqueue; do
        case " $ARGS" in *" $f="*) ;; *) MISSING="$MISSING $f=";; esac
    done
    if [ -z "$MISSING" ]; then
        pass "All AirDrop boot flags of the tested set are set."
    else
        warn "Missing AirDrop boot flags:$MISSING"
        warn "Use the whole tested set from docs/BOOT-FLAGS.md: a partial set can pass every other check here and still not work."
        FLAGS_MISSING=1
    fi
    # Without the announcement (-itlawdlmitx) the sync frames carry no name or services, so other devices
    # hear this Mac but never learn it offers AirDrop: nothing is listed and no AirDrop data arrives.
    MI_STATE=$(ioreg -l -w0 2>/dev/null | sed -n 's/.*"ItlwmAWDLMiState" = "\([^"]*\)".*/\1/p' | head -1)
    case "$MI_STATE" in
        on) pass "The AirDrop announcement is on (ItlwmAWDLMiState = on).";;
        on*) warn "The AirDrop announcement is on, on a build the driver hasn't verified: ItlwmAWDLMiState = $MI_STATE.";;
        "") ;;
        off) case " $ARGS " in
                 *" -itlawdlmitx "*) warn "The AirDrop announcement is off (ItlwmAWDLMiState = off) although -itlawdlmitx is set.";;
                 *) fail "The AirDrop announcement is off (ItlwmAWDLMiState = off) because -itlawdlmitx isn't set. Other devices"
                    fail "can't discover this Mac: the radios hear each other, but no AirDrop data arrives (ITLAWDLCoexDataRx stays 0).";;
             esac
             MI_OFF=1;;
        blocked*)
            # Not a flag problem: on a build the driver hasn't verified, the announcement stays off (section 1).
            warn "The AirDrop announcement is blocked: ItlwmAWDLMiState = $MI_STATE."
            warn "The driver only sends it on verified macOS builds (or with -itlawdlanybuild, at the risk of a panic),"
            warn "so other devices won't list this Mac.";;
        *)  warn "The AirDrop announcement isn't running: ItlwmAWDLMiState = $MI_STATE."; MI_OFF=1;;
    esac
else
    info "Skipped: the AirDrop build isn't running."
fi

# ---------------------------------------------------------------- network stack
head1 "7. Network stack (QUIC for AirDrop)"
# When pf holds rules macOS doesn't recognise, the kernel turns off the flowswitch transport agent
# (net.link.generic.system.enable_netagent = 0). Network.framework then falls back from Skywalk
# channel flows to plain sockets, QUIC's pacer stops working, and AirDrop's QUIC transfers degrade
# (sharingd logs "quic_time_delta start time X is after end time Y" many times per transfer).
# On Tahoe (kernel 25.6) OpenCore's PowerTimeoutKernelPanic quirk causes this by itself: it rewrites
# the kernel string "com.apple" to "not.apple", and pf's anchor check uses the same string, so the
# stock /etc/pf.conf (anchor "com.apple/*") counts as custom rules.
FILTER_STATE=$(sysctl -n net.filter_state 2>/dev/null)
NETAGENT=$(sysctl -n net.link.generic.system.enable_netagent 2>/dev/null)
NET_STACK=""
if [ -z "$NETAGENT" ]; then
    info "Couldn't read net.link.generic.system.enable_netagent on this macOS."
elif [ "$NETAGENT" = "0" ] && printf '%s' "$FILTER_STATE" | grep -q pf; then
    NET_STACK=pf
    warn "pf is marked incompatible (net.filter_state = $FILTER_STATE), so macOS turned off its user-space"
    warn "network path (enable_netagent = 0). QUIC, which AirDrop uses, loses its pacing and transfers can be slower."
    if [ "${OS_MAJOR:-0}" -ge 26 ] 2>/dev/null; then
        warn "Most likely cause on Tahoe: OpenCore Kernel > Quirks > PowerTimeoutKernelPanic. If your hackintosh"
        warn "doesn't need it (it stops a panic when a driver is slow to change power state), set it to false and reboot."
    fi
    info "Other causes: your own pf rules or a firewall app that loads pf anchors."
elif [ "$NETAGENT" = "0" ]; then
    warn "macOS's user-space network path is off (enable_netagent = 0, net.filter_state = '${FILTER_STATE}')."
else
    pass "pf state is normal and the user-space network path is on (enable_netagent = $NETAGENT)."
fi

# ---------------------------------------------------------------- verdict
head1 "Verdict"
case "$CARD_TIER" in
    tested)      CARD_TEXT="Your card is the tested one (AX211).";;
    reported)    CARD_TEXT="Users report AirDrop working with your card. Results vary between machines; please report yours.";;
    likely)      CARD_TEXT="Your card is a close relative of the tested AX211 and should work as is, but nobody has reported it yet.";;
    needs-fixes) CARD_TEXT="Your card is in the older Wi-Fi 6 family. It will probably need small driver fixes; your test results would help.";;
    port)        CARD_TEXT="Your card would need a large port of the driver. Not supported.";;
    unsupported) CARD_TEXT="Your card isn't supported.";;
    *)           CARD_TEXT="Your card couldn't be identified.";;
esac
echo "  $CARD_TEXT"
case "${CH149_STATE:-}" in
    no-country) echo "  ${YEL}No country yet, so AirDrop will be on channel 6 (very slow) until the firmware learns one.${RST}";;
    law)        echo "  ${YEL}This country's rules don't allow 149 at 80 MHz. From 0.6.0 AirDrop uses channel 44 if your iPhone does and the firmware allows it; otherwise channel 6 (very slow).${RST}";;
    not-in-map) echo "  ${YEL}Neither 149 nor 44 at 80 MHz is in the channel map here, so AirDrop can only use channel 6 (very slow).${RST}";;
esac
if [ "$NET_STACK" = pf ]; then
    echo "  ${YEL}pf has turned off macOS's user-space network path (section 7): AirDrop works, but transfers can be slower.${RST}"
fi
if [ -n "${FLAGS_MISSING:-}" ] || [ -n "${MI_OFF:-}" ]; then
    echo "  ${YEL}The AirDrop boot flags are incomplete (section 6). Set the whole tested set from docs/BOOT-FLAGS.md before testing.${RST}"
fi
if [ "$BLOCKERS" -gt 0 ]; then
    echo "  ${RED}$BLOCKERS blocker(s) above stop it working on this Mac regardless of the card.${RST}"
fi
case "$CARD_TIER" in
    tested|reported|likely|needs-fixes)
        if [ "$BLOCKERS" -eq 0 ]; then echo "  ${GRN}Worth testing.${RST} Use a separate USB with a backed-up EFI."; fi;;
esac
echo
echo "  To help add support, run collect_hw_macos.sh and share the report it writes."
echo "  It leaves out serial numbers, MAC addresses, network names and paired devices; read it before sharing."
