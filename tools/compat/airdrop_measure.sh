#!/bin/bash
# AirDrop transfer speed and connect times, from macOS's own AirDrop log (sharingd). Read-only: it
# changes nothing, needs no sudo and no sysdiagnose, and sends nothing anywhere.
#
#   bash airdrop_measure.sh            watch live; send or receive files, press Ctrl-C to stop
#   bash airdrop_measure.sh --last 2h  transfers from the last 2 hours (any log show time: 30m, 1d, ...)
#   bash airdrop_measure.sh --csv FILE also append one line per transfer to FILE
#
# For each transfer it prints the direction, the size, the speed macOS measured, and the connect phases:
# - Mac -> iPhone: macOS's own send timings (HELLO and ASK phases, the ASK includes the time the iPhone
#   takes to accept), and the total from the start of the send to the end.
# - iPhone -> Mac: from the first connection the iPhone opens to its ASK, and from the ASK to the end of
#   the data. The moment you tap the Mac on the iPhone isn't visible on the Mac, so the time before the
#   first connection isn't included.
# When ForbiddenItlwm's AirDrop build is running, it also reads the listener's state after each transfer.

set -u
MODE=stream
LAST=""
CSV=""
while [ $# -gt 0 ]; do
    case "$1" in
        --last) MODE=show; LAST="${2:-1h}"; shift 2 ;;
        --csv) CSV="${2:-}"; shift 2 ;;
        -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $1 (try --help)"; exit 1 ;;
    esac
done

PRED='process == "sharingd" AND (category == "AirDropNW" OR category == "Metrics")'

driver_state() {
    # One line of the listener's state, or nothing when the AirDrop build isn't running.
    { ioreg -l -w0 -d 1 -k ITLAWDLCoexChannel; ioreg -l -w0 -r -c ItlAWDLInterface -d 1; } 2>/dev/null | awk -F' = ' '
        /"ITLAWDLCoexChannel"/ {ch=$2} /"ITLAWDLCoexOwnWidth"/ {w=$2} /"ITLAWDLCoexBaPeerWidth"/ {pw=$2}
        /"ITLAWDLCoexMultiState"/ {ms=$2; gsub(/"/,"",ms)}
        /"ITLAWDLCoexBaTxStateName"/ {gsub(/"/,"",$2); ba=$2}
        /"ITLAWDLCoexPeerPresentEntries"/ {pe=$2}
        /"ItlwmAWDLTxDropped"/ {dr=$2}
        END { # Sharing the Wi-Fi channel (no -itlawdlcoexmulti, or its fallback), the listener has no width
              # of its own (OwnWidth reads -1); the width of the peer station is the one that counts there.
              shared = (ms == "off" || ms == "fallback-same" || w + 0 < 0 || w + 0 > 1000)
              if (shared) w = (pw == "" || pw + 0 == 0) ? "?" : pw
              if (ch != "") printf "listener %s/%s MHz%s, block ack %s, iPhone on our channel %s/16 slots, TX dropped %s\n", ch, w, (shared ? " (shared with Wi-Fi)" : ""), (ba==""?"-":ba), (pe==""?"-":pe), (dr==""?"-":dr) }'
}
export -f driver_state 2>/dev/null

if [ -n "$CSV" ] && [ ! -s "$CSV" ]; then
    echo "time,direction,bytes,MBps,connect_ms,ask_ms,data_s,total_s,transport" > "$CSV"
fi

echo "AirDrop transfer measurements (Ctrl-C to stop)"
[ "$MODE" = show ] && echo "Reading the log from the last $LAST ..."
state="$(driver_state)"
[ -n "$state" ] && echo "Driver now: $state"
echo

if [ "$MODE" = show ]; then
    SRC=(/usr/bin/log show --last "$LAST" --style compact --predicate "$PRED")
else
    SRC=(/usr/bin/log stream --style compact --level default --predicate "$PRED")
fi

"${SRC[@]}" 2>/dev/null | awk -v csv="$CSV" -v live="$([ "$MODE" = stream ] && echo 1 || echo 0)" '
function ms(ts,   p, h, m, s) {   # "2026-11-12 17:43:56.519" -> milliseconds of the day
    split(ts, p, " "); split(p[2], h, ":")
    return ((h[1] * 60 + h[2]) * 60 + h[3]) * 1000
}
function field(name,   r) {       # a numeric or string field of a MetricEvent line
    if (match($0, "\"" name "\" : \"?[^,\"}]*")) {
        r = substr($0, RSTART, RLENGTH); sub(/.*: "?/, "", r); return r
    }
    return ""
}
function mb(bps) { return sprintf("%.1f", bps / 1000000) }
function state(   cmd, line) {
    if (!live) return ""
    cmd = "bash -c driver_state"; line = ""; cmd | getline line; close(cmd); return line
}
{
    ts = $1 " " $2; t = ms(ts)
}
# iPhone -> Mac milestones
/Found BLE device/                 { if (!rx_conn) rx_ble = t }
/AirDrop connection preparing/     { if (!rx_conn) rx_conn = t }
/Received ASK request/             { if (!rx_ask) rx_ask = t }
/AirDrop receive performance/      { rx_end = t }
# Mac -> iPhone
/MetricEvent .com\.apple\.sharing\.airdrop\.send-start/ { tx_start = t }
/MetricEvent .com\.apple\.sharing\.airdrop\.send-finish/ {
    tx_end = t; tx_size = field("size"); tx_transport = field("transport")
    tx_hello = field("helloFinishedMS"); tx_ask = field("askFinishedMS"); tx_result = field("result")
}
/MetricEvent .com\.apple\.sharing\.AirDrop\.SessionInfo/ {
    d = field("firstDiscoveryMs")
    if (d != "") printf "%s  share sheet found the first device after %d ms\n", ts, d
}
/MetricEvent .com\.apple\.sharing\.AirDrop\.TransferResult/ {
    bps = field("bytesPerSec"); ok = field("success"); sender = field("sender")
    st = state()
    if (sender == "1") {
        total = (tx_start && tx_end >= tx_start) ? (tx_end - tx_start) / 1000 : 0
        data = (bps > 0 && tx_size > 0) ? tx_size / bps : 0
        printf "%s  Mac -> iPhone  %s  %.1f MB at %s MB/s via %s\n", ts, (ok == "true" ? "OK    " : "FAILED"), tx_size / 1000000, mb(bps), (tx_transport == "" ? "?" : tx_transport)
        printf "                         connect: HELLO %s ms, ASK %s ms (includes the iPhone accepting); data about %.1f s; total %.1f s\n", (tx_hello == "" ? "?" : tx_hello), (tx_ask == "" ? "?" : tx_ask), data, total
        if (csv != "") printf "%s,mac_to_iphone,%s,%s,%s,%s,%.1f,%.1f,%s\n", ts, tx_size, mb(bps), tx_hello, tx_ask, data, total, tx_transport >> csv
        tx_start = tx_end = 0; tx_size = ""
    } else {
        bucket = field("totalBytesBucket")
        conn = (rx_conn && rx_ask >= rx_conn) ? rx_ask - rx_conn : -1
        data = (rx_ask && rx_end >= rx_ask) ? (rx_end - rx_ask) / 1000 : 0
        printf "%s  iPhone -> Mac  %s  up to %s at %s MB/s\n", ts, (ok == "true" ? "OK    " : "FAILED"), bucket, mb(bps)
        printf "                         connect: first connection to ASK %s ms; ASK to end of data %.1f s\n", (conn < 0 ? "?" : conn), data
        if (csv != "") printf "%s,iphone_to_mac,%s,%s,%s,,%.1f,,awdl\n", ts, bucket, mb(bps), (conn < 0 ? "" : conn), data >> csv
        rx_ble = rx_conn = rx_ask = rx_end = 0
    }
    if (st != "") printf "                         %s\n", st
    print ""
    fflush()
}'
