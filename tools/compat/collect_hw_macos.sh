#!/bin/bash
# AirDrop on Intel Wi-Fi: hardware report for adding support (macOS).
#
# Read-only. It changes nothing, needs no sudo and sends nothing anywhere. It writes one text file
# in the current folder (or the folder you name) for you to read and then share with the project.
#
# Usage: bash collect_hw_macos.sh [output-folder] [--include-country]
# The report is saved on your Desktop unless you name another folder. The script prints its full path.
#
# What it collects: macOS build, SMBIOS model identifier (the Mac model the hackintosh is set up as) and CPU name, the PCI IDs and driver properties
# of the Intel Wi-Fi card, the Intel Bluetooth controller's USB IDs and controller summary, which
# third-party kexts are loaded, AirDrop-related boot flags, the Wi-Fi interface's supported channels
# and current channel/width, and the AirDrop driver's status counters if its build is running.
#
# What it leaves out: serial numbers, hardware UUIDs, MAC and Bluetooth addresses, network names,
# paired or nearby devices, your user name and home folder, and (unless --include-country) the Wi-Fi
# country code. It also replaces anything shaped like a MAC address or UUID. Read the file anyway.

set -u
export LC_ALL=C

# Saved on the Desktop unless you name another folder.
OUT_DIR="$HOME/Desktop"
[ -d "$OUT_DIR" ] || OUT_DIR="."
INCLUDE_COUNTRY=0
for a in "$@"; do
    case "$a" in
        --include-country) INCLUDE_COUNTRY=1;;
        -h|--help) sed -n '2,18p' "$0"; exit 0;;
        *) OUT_DIR=$a;;
    esac
done
if [ "$(uname -s)" != "Darwin" ]; then
    echo "This collector runs on macOS. On Linux, use collect_hw_linux.sh."
    exit 2
fi
mkdir -p "$OUT_DIR" || exit 1
STAMP=$(date +%Y%m%d-%H%M%S)
OUT="$OUT_DIR/airdrop-compat-macos-$STAMP.txt"
OUT_DIR_ABS=$(cd "$OUT_DIR" && pwd)
OUT="$OUT_DIR_ABS/${OUT##*/}"
echo "Collecting. The report will be saved as:"
echo "  $OUT"

HOST_SHORT=$(scutil --get LocalHostName 2>/dev/null || true)
USER_NAME=$(id -un 2>/dev/null || true)
# Replaces MAC addresses, UUIDs, the user name, the home folder and the local host name.
redact() {
    sed -E \
        -e 's/([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}/<mac>/g' \
        -e 's/[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/<uuid>/g' \
        -e "s#${HOME:-/nonexistent}#~#g" \
        ${USER_NAME:+-e "s/${USER_NAME}/<user>/g"} \
        ${HOST_SHORT:+-e "s/${HOST_SHORT}/<host>/g"}
}
section() { printf '\n===== %s =====\n' "$1"; }

{
echo "AirDrop on Intel Wi-Fi: hardware report (macOS)"
echo "Collector version 1, written $(date -u +%Y-%m-%dT%H:%MZ)"
echo "Share this file only after reading it."

section "System"
echo "macOS: $(sw_vers -productVersion 2>/dev/null) ($(sw_vers -buildVersion 2>/dev/null))"
echo "Kernel: $(uname -r) $(uname -m)"
echo "Model identifier: $(sysctl -n hw.model 2>/dev/null)"
echo "CPU: $(sysctl -n machdep.cpu.brand_string 2>/dev/null)"
echo "SIP: $(csrutil status 2>/dev/null | head -1 | sed 's/^System Integrity Protection status: //')"

section "Intel network controllers on PCI (class 0x0280)"
# Each block is one PCI device and its children (the Wi-Fi driver and its interfaces). Only the
# listed keys are kept, and data blobs longer than 32 bytes are cut.
ioreg -r -c IOPCIDevice -l -w0 2>/dev/null | awk '
    /^\+-o / { if (keep) printf "%s", buf; buf=""; keep=0 }
    { buf = buf $0 "\n" }
    /"class-code" = <..8002/ { cls=1 }
    /"vendor-id" = <8680/ { intel=1 }
    /^\+-o / { cls=0; intel=0 }
    { if (cls && intel) keep=1 }
    END { if (keep) printf "%s", buf }' |
awk '
    /\+-o / { show = ($0 ~ /<class (IOPCIDevice|AirportItlwm|itlwm|ItlAWDLInterface|AirportItlwmSkywalkInterface|IOPCIEDeviceWrapper)[,>]/)
              if (show) { line=$0; sub(/^[ |]*/, "", line); sub(/, id 0x.*/, ">", line); print line }
              next }
    show && /"(vendor-id|device-id|subsystem-vendor-id|subsystem-id|revision-id|class-code|IOName|compatible|pcidebug|acpi-path|IOPCIExpressLinkStatus|IOPCIExpressLinkCapabilities|IOPCIExpressASPMDefault|IOModel|IOVendor|CFBundleIdentifier|ItlwmDMAMapper|ItlwmDMARevision|IOInterfaceName|IOMaxPacketSize|IOLinkSpeed)" = / {
        line=$0; sub(/^[ |]*/, "  ", line); print line }' |
sed -E 's/<([0-9a-f]{64})[0-9a-f]+>/<\1...>/' | redact

section "Wi-Fi driver"
kmutil showloaded --list-only 2>/dev/null | awk '{print $6, $7}' | grep -E -i 'itlwm|AirportItlwm|ForbiddenItlwm|IntelBluetooth|IntelBTPatcher|BlueToolFixup|BTLEAdvFixup|Lilu|AirportBrcm|IO80211' | redact
echo "AirDrop build marker: $(ioreg -l -w0 2>/dev/null | sed -n 's/.*"ItlwmAWDLInterfaceBuild" = "\([^"]*\)".*/\1/p' | head -1)"

section "Other third-party kexts"
kmutil showloaded --list-only 2>/dev/null | awk '{print $6, $7}' | grep -v '^com\.apple\.' | grep -v '^Name ' | redact

section "AirDrop-related boot flags"
for t in $(sysctl -n kern.bootargs 2>/dev/null); do
    case "$t" in -itlawdl*|itlawdl*|-btleadv*|-ibt*|-lilu*|-btlfx*|-liludbg*) printf '%s ' "$t";; esac
done
echo

section "Intel Bluetooth controller (USB vendor 0x8087)"
ioreg -p IOUSB -l -w0 2>/dev/null | awk '
    /^[ |]*\+-o / { if (ven == 32903) printf "USB 8087:%04x bcdDevice 0x%04x %s\n", prod, bcd, name; ven=prod=bcd=0; name=$0; sub(/^[ |]*\+-o /, "", name); sub(/  <.*/, "", name) }
    /"idVendor" = / { ven=$NF }
    /"idProduct" = / { prod=$NF }
    /"bcdDevice" = / { bcd=$NF }
    END { if (ven == 32903) printf "USB 8087:%04x bcdDevice 0x%04x %s\n", prod, bcd, name }' | redact
# The controller block only; paired and nearby devices that follow it are left out.
system_profiler SPBluetoothDataType 2>/dev/null | awk '
    /Bluetooth Controller:/ { on=1; next }
    on && /^ {6}[A-Za-z].*:$/ { on=0 }
    on && /(State|Chipset|Firmware Version|Product ID|Vendor ID|Supported services|Transport):/ { sub(/^ +/, ""); print }' | redact
BT_KEYS=$(ioreg -l -w0 2>/dev/null | grep -o '"BTLEAdv[A-Za-z]*" = [0-9]*' | sort -u)
[ -n "$BT_KEYS" ] && echo "$BT_KEYS"

section "Wi-Fi interface (from system_profiler)"
# Interface facts and the current link's channel and mode. Network names are section headings in this
# output, so only listed keys are kept, and nothing from the list of other nearby networks.
system_profiler SPAirPortDataType 2>/dev/null | awk -v country="$INCLUDE_COUNTRY" '
    /Other Local Wi-Fi Networks:/ { stop=1 }
    stop { next }
    /(Card Type|Firmware Version|Supported PHY Modes|Supported Channels|Wake On Wireless|AirDrop|AirDrop Channel|Auto Unlock|Status|PHY Mode|Channel|Network Type|Transmit Rate|MCS Index|Signal \/ Noise):/ {
        sub(/^ +/, ""); print; next }
    country == 1 && /Country Code:/ { sub(/^ +/, ""); print }' | redact

section "Channel 149 and country"
# Whether the firmware has a country (ZZ means none) is kept; the code itself only with --include-country.
CC=$(system_profiler SPAirPortDataType 2>/dev/null | awk -F': ' '/^ *Country Code:/ { print $2; exit }')
case "$CC" in
    ""|ZZ|00) echo "Country learned: no (code ${CC:-none})";;
    *) if [ "$INCLUDE_COUNTRY" = 1 ]; then echo "Country learned: yes ($CC)"; else echo "Country learned: yes (code left out)"; fi;;
esac
sysctl -n kern.bootargs 2>/dev/null | tr ' ' '\n' | grep -q '^itlwm_cc=' && echo "itlwm_cc override boot argument: set"
# Channels of nearby networks only, by band, without names.
system_profiler SPAirPortDataType 2>/dev/null | awk '
    /Other Local Wi-Fi Networks:/ { on=1; next }
    on && /^ *Channel:/ { sub(/^ *Channel: */, ""); c=$1+0; n++; if ($0 ~ /5GHz/) f++; if (c >= 149 && c <= 165) u++; ch[$0]++ }
    END { printf "Nearby networks listed: %d (%d on 5 GHz, %d on 149 to 165)\n", n, f, u
          for (k in ch) printf "  channel %s: %d\n", k, ch[k] }'

section "AirDrop driver status (only while its build runs)"
# Numbers and yes/no values only. Event logs, traces, frame samples and anything with an address in it
# are left out.
ioreg -l -w0 2>/dev/null | grep -o '"\(ITLAWDL\|ItlwmAWDL\)[A-Za-z0-9]*" = \(Yes\|No\|[0-9][0-9]*\|"[A-Za-z0-9._ -]*"\)' |
    grep -v -E 'Sample|Mac"|Addr|Peer[A-Z]?[a-z]*Address|Bssid|Ssid|Name' | sort -u | redact
} > "$OUT" 2>&1

echo
echo "Done. Report saved to:"
echo
echo "  $OUT"
echo
echo "To show it in Finder:  open -R \"$OUT\""
echo "To read it:            open -e \"$OUT\""
echo
echo "Read it before sharing. It should contain no serial numbers, addresses, network names or devices."
