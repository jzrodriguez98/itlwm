#!/bin/bash
# AirDrop on Intel Wi-Fi: hardware report for adding support (Linux).
#
# For cards the macOS driver doesn't support yet. Boot any recent Linux (a live USB is fine) on the same
# laptop and run this. Linux's iwlwifi driver reports the card's exact name, radio, firmware file and
# firmware API, and `iw` reports what the firmware allows: bands, channel widths, antennas, and how many
# channels it can serve at once. That is what adding a card to the macOS driver needs.
#
# Read-only. It changes nothing and sends nothing anywhere. Run it with sudo for the kernel log on
# distributions that restrict it; without sudo it collects what it can. It writes one text file in the
# current folder (or the folder you name) for you to read and then share.
#
# Usage: [sudo] bash collect_hw_linux.sh [output-folder] [--include-country]
# The report is saved in the current folder unless you name another one. The script prints its full path.
#
# Left out: serial numbers, MAC and Bluetooth addresses, network names, your user and host name and
# (unless --include-country) the regulatory country. Anything shaped like a MAC address or UUID is
# replaced. Read the file anyway.

set -u
export LC_ALL=C

OUT_DIR="."
INCLUDE_COUNTRY=0
for a in "$@"; do
    case "$a" in
        --include-country) INCLUDE_COUNTRY=1;;
        -h|--help) sed -n '2,17p' "$0"; exit 0;;
        *) OUT_DIR=$a;;
    esac
done
if [ "$(uname -s)" != "Linux" ]; then
    echo "This collector runs on Linux. On macOS, use collect_hw_macos.sh."
    exit 2
fi
mkdir -p "$OUT_DIR" || exit 1
OUT="$OUT_DIR/airdrop-compat-linux-$(date +%Y%m%d-%H%M%S).txt"
OUT_DIR_ABS=$(cd "$OUT_DIR" && pwd)
OUT="$OUT_DIR_ABS/${OUT##*/}"
echo "Collecting. The report will be saved as:"
echo "  $OUT"
HOST_SHORT=$(hostname -s 2>/dev/null || true)
USER_NAME=${SUDO_USER:-$(id -un 2>/dev/null || true)}

redact() {
    sed -E \
        -e 's/([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}/<mac>/g' \
        -e 's/[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/<uuid>/g' \
        -e 's/(Serial Number|[Ss]erial)[ :=]+[^ ]+/\1 <removed>/g' \
        -e 's/(SSID|ssid)[ :=]+.*/\1 <removed>/g' \
        ${USER_NAME:+-e "s/${USER_NAME}/<user>/g"} \
        ${HOST_SHORT:+-e "s/${HOST_SHORT}/<host>/g"}
}
section() { printf '\n===== %s =====\n' "$1"; }
have() { command -v "$1" >/dev/null 2>&1; }
klog() {
    if have journalctl && journalctl -k -b --no-pager -q >/dev/null 2>&1; then journalctl -k -b --no-pager -q -o short-monotonic
    else dmesg 2>/dev/null; fi
}

{
echo "AirDrop on Intel Wi-Fi: hardware report (Linux)"
echo "Collector version 1, written $(date -u +%Y-%m-%dT%H:%MZ)"
echo "Share this file only after reading it."

section "System"
echo "Kernel: $(uname -r) $(uname -m)"
[ -r /etc/os-release ] && grep -E '^(PRETTY_NAME|VERSION_ID)=' /etc/os-release
for f in sys_vendor product_name product_family board_name bios_version; do
    [ -r /sys/class/dmi/id/$f ] && echo "DMI $f: $(cat /sys/class/dmi/id/$f 2>/dev/null)"
done
echo "CPU: $(awk -F': ' '/model name/ { print $2; exit }' /proc/cpuinfo)"

section "Intel network controllers on PCI"
if have lspci; then
    lspci -nnk -d 8086::0280 2>/dev/null
    for slot in $(lspci -D -d 8086::0280 2>/dev/null | awk '{print $1}'); do
        echo "--- $slot"
        lspci -vvv -nn -s "$slot" 2>/dev/null | grep -E -v 'Serial Number|Device Serial'
    done
else
    for d in /sys/bus/pci/devices/*; do
        [ "$(cat $d/vendor 2>/dev/null)" = "0x8086" ] || continue
        case "$(cat $d/class 2>/dev/null)" in 0x0280*) ;; *) continue;; esac
        echo "$(basename $d) device $(cat $d/device) subsystem $(cat $d/subsystem_vendor):$(cat $d/subsystem_device) revision $(cat $d/revision)"
    done
fi

section "iwlwifi messages from this boot"
klog | grep -i -E 'iwlwifi|iwlmvm|iwlmld' | grep -v -i -E 'ssid|associat|authenticat|deauth' | head -120

section "Firmware files loaded"
klog | grep -o -i -E 'iwlwifi-[A-Za-z0-9_.-]+\.(ucode|pnvm)' | sort -u
ls /lib/firmware/iwlwifi-* 2>/dev/null | sed 's#.*/##' | head -80

section "Driver and firmware versions"
for i in /sys/class/net/*; do
    [ -e "$i/wireless" ] || [ -e "$i/phy80211" ] || continue
    n=$(basename "$i")
    echo "Interface $n driver $(basename "$(readlink -f "$i/device/driver" 2>/dev/null)")"
    if have ethtool; then ethtool -i "$n" 2>/dev/null | grep -E '^(driver|version|firmware-version|bus-info):'; fi
done
have modinfo && modinfo iwlwifi 2>/dev/null | grep -E '^(version|vermagic|srcversion):'

section "Wireless capabilities (iw list)"
if have iw; then
    iw list 2>/dev/null
else
    echo "iw isn't installed. Install the 'iw' package and run this again for the capability list."
fi

section "Channel 149 to 161 (needed for AirDrop at 80 MHz)"
# "no IR" means listen-only: the firmware hasn't learned a country that allows transmitting there.
if have iw; then iw list 2>/dev/null | grep -E '\[(149|153|157|161|165)\]' | sed 's/^[[:space:]]*//' | sort -u; fi

section "Regulatory"
if have iw; then
    if [ "$INCLUDE_COUNTRY" = 1 ]; then iw reg get 2>/dev/null
    else iw reg get 2>/dev/null | grep -v -E '^(global|country|phy#)' | sed -E 's/country [A-Z0-9]{2}/country <removed>/'
         echo "(Country code left out; rerun with --include-country to add it.)"
    fi
fi

section "Intel Bluetooth controller"
if have lsusb; then lsusb -d 8087: 2>/dev/null; fi
for d in /sys/bus/usb/devices/*; do
    [ "$(cat $d/idVendor 2>/dev/null)" = "8087" ] && echo "USB 8087:$(cat $d/idProduct) bcdDevice $(cat $d/bcdDevice 2>/dev/null)"
done
klog | grep -i -E 'Bluetooth: hci0: (Firmware|Bootloader|Device revision|Secure boot|OTP|Found device|Minimum|Intel)' | head -30
if have btmgmt; then btmgmt info 2>/dev/null | grep -E -i 'version|supported settings|current settings' | head -10; fi
} 2>&1 | redact > "$OUT"

[ -n "${SUDO_USER:-}" ] && chown "$SUDO_USER" "$OUT" 2>/dev/null
echo
echo "Done. Report saved to:"
echo
echo "  $OUT"
echo
echo "To read it:  less \"$OUT\""
echo "On a live USB, copy it to a USB stick or cloud folder before shutting down, or it will be lost."
echo
echo "Read it before sharing. It should contain no serial numbers, addresses, network names or host names."
