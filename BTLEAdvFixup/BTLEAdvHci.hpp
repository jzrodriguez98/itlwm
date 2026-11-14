// Decisions on outgoing HCI commands, kept free of kernel types for host tests.
#pragma once
#include <stdint.h>
#include <stddef.h>
namespace BTLEAdv {
enum : uint16_t {
    kOpReset = 0x0c03, kOpLeEventMask = 0x2001, kOpLeRandomAddress = 0x2005,
    kOpSetRandomAddress = 0x2035, kOpExtAdvParams = 0x2036,
    kOpRemoveSet = 0x203c, kOpClearSets = 0x203d,
};
// IntelBTPatcher sends this fixed address before the first legacy scan, to work around a
// bluetoothd bug. Lilu panics if a second plugin hooks the same function as IntelBTPatcher,
// so with this kext active, IntelBTPatcher is disabled and that job moves here. The address
// must never become an advertising address, because that would make the Mac trackable.
static const uint8_t kFixedPatcherAddress[6] = {0x94,0x50,0x64,0xd0,0x78,0x6b};
// address is the general fallback: bluetoothd's LE random address, or until that arrives, the
// last set address seen. setAddress is what bluetoothd chose for each set.
struct State {
    uint8_t address[6]; bool haveAddress; bool haveGeneralAddress;
    uint32_t addressedSets; bool legacyAddressSent;
    uint8_t setAddress[32][6]; uint32_t knownSetAddresses;
};
enum : uint16_t { kOpLeScanParams = 0x200b };
// True once per controller start, before the first legacy scan parameters command.
inline bool wantsLegacyScanAddress(State &s, const uint8_t *hci, size_t length) {
    if (!hci || length < 3 || uint16_t(hci[0] | hci[1] << 8) != kOpLeScanParams || s.legacyAddressSent)
        return false;
    s.legacyAddressSent = true;
    return true;
}
struct Action { bool sendSetAddress, sendEventMask; uint8_t output[11]; size_t outputLength; };
inline bool same(const uint8_t *a, const uint8_t *b) {
    for (unsigned i = 0; i < 6; ++i) if (a[i] != b[i]) return false;
    return true;
}
// hci is the whole command, opcode first. Call this for every outgoing command. The returned
// action must be sent after the command itself, since a set exists only after 0x2036.
inline Action onCommand(State &s, const uint8_t *hci, size_t length, bool extendedScanning) {
    Action a{};
    if (!hci || length < 3) return a;
    const uint16_t op = uint16_t(hci[0] | hci[1] << 8);
    switch (op) {
    case kOpReset:
        s = State{};
        break;
    case kOpLeRandomAddress:
        if (length >= 9 && !same(hci + 3, kFixedPatcherAddress)) {
            for (unsigned i = 0; i < 6; ++i) s.address[i] = hci[3 + i];
            s.haveAddress = true;
            s.haveGeneralAddress = true;
        }
        break;
    case kOpSetRandomAddress:
        // bluetoothd's address for this set. It's rejected if the set doesn't exist yet, so
        // this doesn't count as the set having one, but it's kept for when the set is created.
        if (length >= 10 && !same(hci + 4, kFixedPatcherAddress)) {
            if (hci[3] < 32) {
                for (unsigned i = 0; i < 6; ++i) s.setAddress[hci[3]][i] = hci[4 + i];
                s.knownSetAddresses |= 1U << hci[3];
            }
            if (!s.haveGeneralAddress) {
                for (unsigned i = 0; i < 6; ++i) s.address[i] = hci[4 + i];
                s.haveAddress = true;
            }
        }
        break;
    case kOpExtAdvParams:
        // Handle at parameter 0, Own_Address_Type at parameter 10.
        if (length >= 14 && hci[13] == 1 && hci[3] < 32 && !(s.addressedSets & (1U << hci[3])) &&
            (s.haveAddress || (s.knownSetAddresses & (1U << hci[3])))) {
            const uint8_t *chosen = (s.knownSetAddresses & (1U << hci[3])) ? s.setAddress[hci[3]] : s.address;
            s.addressedSets |= 1U << hci[3];
            a.sendSetAddress = true;
            a.output[0] = kOpSetRandomAddress & 0xff; a.output[1] = kOpSetRandomAddress >> 8; a.output[2] = 7;
            a.output[3] = hci[3];
            for (unsigned i = 0; i < 6; ++i) a.output[4 + i] = chosen[i];
            a.outputLength = 10;
        }
        break;
    case kOpRemoveSet:
        // A removed set forgets its address too: a set made later with the same handle must not be
        // given an address from before bluetoothd rotated it.
        if (length >= 4 && hci[3] < 32) {
            s.addressedSets &= ~(1U << hci[3]);
            s.knownSetAddresses &= ~(1U << hci[3]);
            for (unsigned i = 0; i < 6; ++i) s.setAddress[hci[3]][i] = 0;
        }
        break;
    case kOpClearSets:
        s.addressedSets = 0;
        s.knownSetAddresses = 0;
        for (auto &address : s.setAddress)
            for (unsigned i = 0; i < 6; ++i) address[i] = 0;
        break;
    case kOpLeEventMask:
        // Extended scanning reports are bit 12, which bluetoothd leaves off for this chip.
        if (extendedScanning && length >= 11 && !(hci[4] & 0x10)) {
            a.sendEventMask = true;
            for (unsigned i = 0; i < 11; ++i) a.output[i] = hci[i];
            a.output[4] |= 0x10;
            a.outputLength = 11;
        }
        break;
    default:
        break;
    }
    return a;
}
// Intel Bluetooth controllers never send an LE Data Length Change event on Tahoe, so bluetoothd
// stays at LE_READY_WAIT_FOR_LENGTH after the link encrypts and a new BLE HID device (a mouse, a
// keyboard) never binds: "No database exists". Already bonded devices skip GATT discovery, which
// is why they still work. IntelBTPatcher's fix is to send LE Read Remote Features twice more and
// rewrite the two duplicate completions into the events bluetoothd is waiting for. Lilu panics if
// two plugins hook the same function, so with this kext active that job is here instead.
// OpenIntelWireless/IntelBluetoothFirmware#514.
enum : uint16_t { kOpLeReadRemoteFeatures = 0x2016 };
enum : uint8_t { kEvtLeMeta = 0x3e, kLeMetaReadRemoteFeaturesComplete = 0x04 };
// The link is up and encrypted when this runs, so the two events describe that link: the handle
// comes from the completion being replaced. Values are IntelBTPatcher's: 27 octets, 328 us.
enum : size_t { kPhyUpdateEventLength = 8, kDataLengthEventLength = 13 };
struct DataLengthState {
    uint32_t outstanding;  // duplicate commands whose completion hasn't been rewritten yet
    unsigned stage;        // 0: the real completion, 1: fake PHY update, 2: fake data length
};
// How many copies of this command to send after it. Only LE Read Remote Features, and a
// controller start forgets any command still in flight.
inline unsigned extraRemoteReads(DataLengthState &s, const uint8_t *hci, size_t length) {
    if (!hci || length < 3)
        return 0;
    const uint16_t op = uint16_t(hci[0] | hci[1] << 8);
    if (op == kOpReset) {
        s = DataLengthState{};
        return 0;
    }
    if (op != kOpLeReadRemoteFeatures)
        return 0;
    s.stage = 0;
    s.outstanding += 2;
    return 2;
}
// A copy that couldn't be sent never produces an event, so it's not waited for.
inline void forgetRemoteRead(DataLengthState &s) {
    if (s.outstanding && !--s.outstanding)
        s.stage = 0;
}
// Rewrites one incoming event in place and returns its new size. Everything except a duplicate
// LE Read Remote Features Complete passes through untouched; the first of the two duplicates
// becomes PHY Update Complete, the second LE Data Length Change, as in IntelBTPatcher.
inline size_t rewriteEvent(DataLengthState &s, uint8_t *event, size_t length) {
    if (!event || length < 6 || !s.outstanding || event[0] != kEvtLeMeta ||
        event[2] != kLeMetaReadRemoteFeaturesComplete)
        return length;
    if (s.stage == 0) {  // the real completion goes to bluetoothd as it is
        s.stage = 1;
        return length;
    }
    // Status 0, both directions 2M.
    const uint8_t handleLow = event[4], handleHigh = event[5];
    if (s.stage == 1) {
        const uint8_t fake[kPhyUpdateEventLength] = {kEvtLeMeta, 6, 0x0c, 0x00, handleLow, handleHigh, 0x02, 0x02};
        for (unsigned i = 0; i < kPhyUpdateEventLength; ++i)
            event[i] = fake[i];
        s.stage = 2;
        --s.outstanding;
        return kPhyUpdateEventLength;
    }
    // A Data Length Change has no status byte, so the handle moves to parameter 0.
    const uint8_t fake[kDataLengthEventLength] = {kEvtLeMeta, 11, 0x07, handleLow, handleHigh,
                                                  0x1b, 0x00, 0x48, 0x01, 0x1b, 0x00, 0x48, 0x01};
    for (unsigned i = 0; i < kDataLengthEventLength; ++i)
        event[i] = fake[i];
    s.stage = 0;
    --s.outstanding;
    return kDataLengthEventLength;
}
}
