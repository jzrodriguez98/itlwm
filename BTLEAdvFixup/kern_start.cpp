// SPDX-License-Identifier: GPL-3.0-only
// The HCI hook follows IntelBTPatcher (OpenIntelWireless/IntelBluetoothFirmware, GPLv3),
// the page hook follows BlueToolFixup (acidanthera/BrcmPatchRAM).
//
// Separate Lilu plugin: lets bluetoothd use extended LE advertising on a third-party
// controller. It only patches a process in memory, and does nothing without its boot
// flag. See docs/HOW-IT-WORKS.md. Nothing on disk changes.
#include <Headers/kern_api.hpp>
#include <Headers/kern_user.hpp>
#include <Headers/kern_util.hpp>
#include <Headers/plugin_start.hpp>
#include <IOKit/IOBufferMemoryDescriptor.h>
#include <IOKit/usb/IOUSBHostDevice.h>
#include "BTLEAdvPatches.hpp"
#include "BTLEAdvHci.hpp"

// Patches bluetoothd's pages as they're validated, the same way BlueToolFixup does.
// Lilu's onProcLoad route was tried first and didn't apply to this process.
static mach_vm_address_t orig_cs_validate {};
static bool patchScanning {};

static void patched_cs_validate_page(vnode_t vp, memory_object_t pager, memory_object_offset_t page_offset,
                                     const void *data, int *validated_p, int *tainted_p, int *nx_p) {
    char path[PATH_MAX];
    int pathlen = PATH_MAX;
    FunctionCast(patched_cs_validate_page, orig_cs_validate)(vp, pager, page_offset, data, validated_p, tainted_p, nx_p);
    if (vn_getpath(vp, path, &pathlen) != 0 || LIKELY(strcmp(path, "/usr/sbin/bluetoothd") != 0))
        return;
    // Each set only matches its own bluetoothd build; on any other build nothing changes.
    for (const auto &patch : BTLEAdv::kPatches)
        if (!patch.scanningOnly || patchScanning)
            KernelPatcher::findAndReplace(const_cast<void *>(data), PAGE_SIZE, patch.find, patch.size,
                                          patch.replace, patch.size);
}

// bluetoothd talks to the controller over USB control requests. Commands it doesn't send in
// the required order are added here, after the command they depend on. Their completion
// events reach bluetoothd as unmatched, as they already do for IntelBTPatcher's command.
static mach_vm_address_t orig_device_request {};
// deviceRequest runs on many threads at once. hciState is only read or changed with hciLock held,
// never across a USB call, and belongs to the one controller in hciOwner.
static BTLEAdv::State hciState {};
static IOLock *hciLock {};
static void *hciOwner {};
// An added command never waits longer than this, even when the caller's request had no timeout.
static constexpr uint32_t kExtraTimeoutMS = 1000;

// The LE Data Length Change fix (OpenIntelWireless#514) needs the controller's interrupt IN pipe,
// which is only reachable through IOUSBHostPipe: the pipe is remembered when it's created.
static mach_vm_address_t orig_pipe_io {};
static mach_vm_address_t orig_init_pipe {};
static mach_vm_address_t orig_init_pipe_config {};
static void *interruptPipe {};
// Written when a command goes out, read when its completion arrives on the USB workloop, so no
// lock: a missed rewrite only leaves bluetoothd on a timeout it already had.
static BTLEAdv::DataLengthState lengthState {};
static uint32_t lengthRewrites {}, lengthFailures {};

static IOReturn patched_device_request(void *that, IOService *provider, StandardUSB::DeviceRequest &request, void *data,
                                       IOMemoryDescriptor *descriptor, unsigned int &length,
                                       IOUSBHostCompletion *completion, uint32_t timeout);

// Evidence for tests, in the I/O Registry root. Set only on rare events, in thread context.
static uint32_t extraCommands {}, setAddresses {}, extraFailures {};
static void noteHook(const char *key, uint32_t value) {
    IORegistryEntry::getRegistryRoot()->setProperty(key, value, 32);
}

// Intel's vendor ID is also on hubs and other devices. Without the controller's product name, it
// must at least be a wireless controller (USB class 0xE0).
static bool isIntelBluetooth(void *that) {
    auto *device = static_cast<IORegistryEntry *>(that);
    auto *vendor = OSDynamicCast(OSNumber, device->getProperty("idVendor"));
    if (!vendor || vendor->unsigned32BitValue() != 0x8087)
        return false;
    if (auto *name = OSDynamicCast(OSString, device->getProperty("USB Product Name")))
        return name->isEqualTo("Bluetooth USB Host Controller");
    auto *deviceClass = OSDynamicCast(OSNumber, device->getProperty("bDeviceClass"));
    return deviceClass && deviceClass->unsigned32BitValue() == 0xE0;
}

static IOReturn sendExtra(void *that, IOService *provider, const StandardUSB::DeviceRequest &request,
                          const uint8_t *bytes, size_t size, uint32_t timeout) {
    auto *extra = IOBufferMemoryDescriptor::withBytes(bytes, size, kIODirectionOut);
    if (!extra)
        return kIOReturnNoMemory;
    StandardUSB::DeviceRequest extraRequest = request;
    extraRequest.wLength = uint16_t(size);
    unsigned int extraLength = uint32_t(size);
    // Synchronous (no completion), so bounded: a stalled controller can't hold the thread forever.
    const uint32_t extraTimeout = timeout == 0 || timeout > kExtraTimeoutMS ? kExtraTimeoutMS : timeout;
    IOReturn result = extra->prepare(kIODirectionOut);
    if (result == kIOReturnSuccess) {
        result = FunctionCast(patched_device_request, orig_device_request)(that, provider, extraRequest, nullptr, extra,
                                                                           extraLength, nullptr, extraTimeout);
        extra->complete(kIODirectionOut);
    }
    extra->release();
    return result;
}

static IOReturn patched_device_request(void *that, IOService *provider, StandardUSB::DeviceRequest &request, void *data,
                                       IOMemoryDescriptor *descriptor, unsigned int &length,
                                       IOUSBHostCompletion *completion, uint32_t timeout) {
    uint8_t hci[32] = {};
    size_t hciLength = 0;
    // Every USB device comes through here, so only look at the Intel Bluetooth controller.
    // Class requests to the device carry HCI commands; bRequest isn't reliable for this.
    // HCI commands are class requests, host to device, addressed to the device (or its interface).
    if (hciLock && (request.bmRequestType == 0x20 || request.bmRequestType == 0x21) && isIntelBluetooth(that)) {
        if (data) {
            hciLength = min(size_t(request.wLength), sizeof(hci));
            lilu_os_memcpy(hci, data, hciLength);
        } else if (descriptor && descriptor->prepare(kIODirectionOut) == kIOReturnSuccess) {
            hciLength = min(size_t(descriptor->getLength()), sizeof(hci));
            descriptor->readBytes(0, hci, hciLength);
            descriptor->complete(kIODirectionOut);
        }
    }
    bool legacyScanAddress = false;
    unsigned remoteReads = 0;
    BTLEAdv::Action action {};
    if (hciLength) {
        IOLockLock(hciLock);
        // A different controller than last time starts from nothing.
        if (hciOwner != that) {
            hciState = BTLEAdv::State{};
            hciOwner = that;
        }
        legacyScanAddress = BTLEAdv::wantsLegacyScanAddress(hciState, hci, hciLength);
        action = BTLEAdv::onCommand(hciState, hci, hciLength, patchScanning);
        IOLockUnlock(hciLock);
        remoteReads = BTLEAdv::extraRemoteReads(lengthState, hci, hciLength);
    }
    for (unsigned i = 0; i < remoteReads; ++i) {
        // Sent before the real command, as IntelBTPatcher does: the three completions carry the
        // same features, so the first one reaches bluetoothd unchanged and the other two are
        // rewritten into the events it's missing.
        if (sendExtra(that, provider, request, hci, hciLength, timeout) != kIOReturnSuccess) {
            BTLEAdv::forgetRemoteRead(lengthState);
            noteHook("BTLEAdvLengthFailures", ++lengthFailures);
        }
    }
    if (legacyScanAddress) {
        // IntelBTPatcher's workaround, sent before the scan command like the original.
        uint8_t fixed[9] = {0x05, 0x20, 0x06};
        lilu_os_memcpy(fixed + 3, BTLEAdv::kFixedPatcherAddress, 6);
        sendExtra(that, provider, request, fixed, sizeof(fixed), timeout);
    }
    static bool sawCommand {};
    if (hciLength >= 3 && !sawCommand) {
        sawCommand = true;
        noteHook("BTLEAdvFirstRequest", request.bRequest);
    }
    const IOReturn result = FunctionCast(patched_device_request, orig_device_request)(that, provider, request, data, descriptor, length, completion, timeout);
    if (action.sendSetAddress || action.sendEventMask) {
        // Only after the command it depends on was accepted. A set address that didn't go out is
        // forgotten, so the next parameters command for that set tries again.
        const IOReturn extra = result == kIOReturnSuccess ?
            sendExtra(that, provider, request, action.output, action.outputLength, timeout) : result;
        if (action.sendSetAddress && extra != kIOReturnSuccess) {
            IOLockLock(hciLock);
            if (hciOwner == that)
                hciState.addressedSets &= ~(1U << action.output[3]);
            IOLockUnlock(hciLock);
        }
        if (extra == kIOReturnSuccess) {
            noteHook("BTLEAdvExtraCommands", ++extraCommands);
            if (action.sendSetAddress)
                noteHook("BTLEAdvSetAddresses", ++setAddresses);
        } else {
            noteHook("BTLEAdvExtraFailures", ++extraFailures);
        }
    }
    return result;
}

// The controller's events arrive on its interrupt IN pipe, and only the pipe object can be used
// to wrap them, so it's remembered when it's created. Anything else on the bus is left alone.
static void captureInterruptPipe(void *that, StandardUSB::EndpointDescriptor const *descriptor, IOUSBHostDevice *device) {
    if (!descriptor || !device || !isIntelBluetooth(device))
        return;
    // The endpoint is picked apart by hand: StandardUSB::getEndpointType/getEndpointDirection are
    // exports of IOUSBHostFamily, and OpenCore's prelinker resolves them to 0 (RIP-relative
    // overflow), which makes injection fail. The descriptor is the 7-byte USB layout:
    // bEndpointAddress (offset 2, bit 7 = direction in), bmAttributes (offset 3, bits 0-1 = type).
    auto *bytes = reinterpret_cast<const uint8_t *>(descriptor);
    if (bytes[2] & 0x80 && (bytes[3] & 0x03) == 0x03)
        interruptPipe = that;
}

// The pipe is created through one of two overloads, depending on the macOS version.
static int patched_init_pipe(void *that, StandardUSB::EndpointDescriptor const *descriptor,
                             StandardUSB::SuperSpeedEndpointCompanionDescriptor const *companion, void *controller,
                             IOUSBHostDevice *device, void *interface, unsigned char a7, unsigned short a8) {
    const int result = FunctionCast(patched_init_pipe, orig_init_pipe)(that, descriptor, companion, controller, device,
                                                                       interface, a7, a8);
    captureInterruptPipe(that, descriptor, device);
    return result;
}

static int patched_init_pipe_config(void *that, StandardUSB::EndpointDescriptor const *descriptor,
                                    StandardUSB::ConfigurationDescriptor const *config, void *controller,
                                    IOUSBHostDevice *device, void *interface, unsigned char a7, unsigned short a8) {
    const int result = FunctionCast(patched_init_pipe_config, orig_init_pipe_config)(that, descriptor, config, controller,
                                                                                     device, interface, a7, a8);
    captureInterruptPipe(that, descriptor, device);
    return result;
}

// A completion owns the caller's closure, so the original one is kept here while ours runs.
struct DelayedCompletion {
    IOUSBHostCompletion original;
    IOMemoryDescriptor *buffer;
};

static void rewriteCompletion(void *owner, void *parameter, IOReturn status, uint32_t bytesTransferred) {
    auto *delayed = static_cast<DelayedCompletion *>(owner);
    IOMemoryDescriptor *buffer = delayed->buffer;
    // Tahoe hands over the buffer the stack already prepared, so prepare() is refused there and
    // the bytes are read directly, the way IntelBTPatcher does it. Only a hold this call took is
    // released again: when prepare() is refused the hold belongs to the USB stack, and completing
    // it here would release that one instead.
    if (status == kIOReturnSuccess && buffer && bytesTransferred >= 6 &&
        buffer->getLength() >= BTLEAdv::kDataLengthEventLength) {
        const IOReturn prepared = buffer->prepare(kIODirectionInOut);
        uint8_t event[32] = {};
        const size_t size = min(size_t(bytesTransferred), sizeof(event));
        buffer->readBytes(0, event, size);
        const size_t rewritten = BTLEAdv::rewriteEvent(lengthState, event, size);
        // writeBytes returns the number of bytes written, not an IOReturn. The shrunk size may only
        // be claimed when every rewritten byte is really in the buffer: forwarding the original
        // size leaves stale feature bytes behind, which the stack parses as garbage events and
        // bluetoothd takes the parser desync as fatal (reason 607).
        if (rewritten != size) {
            if (buffer->writeBytes(0, event, rewritten) == rewritten) {
                bytesTransferred = uint32_t(rewritten);
                noteHook("BTLEAdvLengthRewrites", ++lengthRewrites);
            } else {
                noteHook("BTLEAdvLengthFailures", ++lengthFailures);
            }
        }
        if (prepared == kIOReturnSuccess)
            buffer->complete(kIODirectionInOut);
    }
    const IOUSBHostCompletion original = delayed->original;
    IOFree(delayed, sizeof(*delayed));
    if (original.action)
        original.action(original.owner, parameter, status, bytesTransferred);
}

static IOReturn patched_pipe_io(void *that, IOMemoryDescriptor *dataBuffer, uint32_t bytesTransferred,
                                IOUSBHostCompletion *completion, uint32_t completionTimeoutMs) {
    if (completion && dataBuffer && that == interruptPipe && lengthState.outstanding) {
        auto *delayed = static_cast<DelayedCompletion *>(IOMalloc(sizeof(DelayedCompletion)));
        if (delayed) {
            delayed->original = *completion;
            delayed->buffer = dataBuffer;
            completion->action = rewriteCompletion;
            completion->owner = delayed;
        }
    }
    return FunctionCast(patched_pipe_io, orig_pipe_io)(that, dataBuffer, bytesTransferred, completion, completionTimeoutMs);
}

static const char *usbHostPaths[] {"/System/Library/Extensions/IOUSBHostFamily.kext/Contents/MacOS/IOUSBHostFamily"};
static KernelPatcher::KextInfo usbHostInfo {"com.apple.iokit.IOUSBHostFamily", usbHostPaths, 1, {true}, {}, KernelPatcher::KextInfo::Unloaded};

static const char *bootargOff[] = {"-btleadvoff"};
static const char *bootargDebug[] = {"-btleadvdbg"};
static const char *bootargBeta[] = {"-btleadvbeta"};

PluginConfiguration ADDPR(config) {
    xStringify(PRODUCT_NAME),
    parseModuleVersion(xStringify(MODULE_VERSION)),
    LiluAPI::AllowNormal | LiluAPI::AllowInstallerRecovery | LiluAPI::AllowSafeMode,
    bootargOff, arrsize(bootargOff),
    bootargDebug, arrsize(bootargDebug),
    bootargBeta, arrsize(bootargBeta),
    // Lilu disables a plugin outside this range. Each build declares only its own macOS version:
    // before 0.8.3 the Sequoia build declared Tahoe here too, so Lilu never started it on Sequoia.
#if defined(BTLEADV_SONOMA)
    KernelVersion::Sonoma,
    KernelVersion::Sonoma,
#elif defined(BTLEADV_SEQUOIA)
    KernelVersion::Sequoia,
    KernelVersion::Sequoia,
#else
    KernelVersion::Tahoe,
    KernelVersion::Tahoe,
#endif
    []() {
        // Off unless asked for, so this kext can sit in the EFI doing nothing.
        if (!checkKernelArgument("-btleadv"))
            return;
        // Advertising alone, to compare with both.
        patchScanning = !checkKernelArgument("-btlenoscan");
        lilu.onPatcherLoadForce([](void *, KernelPatcher &patcher) {
            KernelPatcher::RouteRequest route("_cs_validate_page", patched_cs_validate_page, orig_cs_validate);
            if (!patcher.routeMultipleLong(KernelPatcher::KernelID, &route, 1))
                SYSLOG("btleadv", "failed to route cs validation");
        });
        hciLock = IOLockAlloc();
        lilu.onKextLoadForce(&usbHostInfo, 1, [](void *, KernelPatcher &patcher, size_t index, mach_vm_address_t address, size_t size) {
            if (index != usbHostInfo.loadIndex || !hciLock)
                return;
            KernelPatcher::RouteRequest route(
                "__ZN15IOUSBHostDevice13deviceRequestEP9IOServiceRN11StandardUSB13DeviceRequestEPvP18IOMemoryDescriptorRjP19IOUSBHostCompletionj",
                patched_device_request, orig_device_request);
            const bool routed = patcher.routeMultiple(index, &route, 1, address, size);
            if (!routed) {
                SYSLOG("btleadv", "failed to route device request");
                patcher.clearError();
            }
            noteHook("BTLEAdvHookRouted", routed ? 1 : 0);
            // The LE Data Length Change fix also needs the pipe object and its completions.
            KernelPatcher::RouteRequest ioRoute("__ZN13IOUSBHostPipe2ioEP18IOMemoryDescriptorjP19IOUSBHostCompletionj",
                                                patched_pipe_io, orig_pipe_io);
            const bool ioRouted = patcher.routeMultiple(index, &ioRoute, 1, address, size);
            if (!ioRouted) {
                SYSLOG("btleadv", "failed to route pipe io");
                patcher.clearError();
            }
            // 26.5 and later take the configuration descriptor where older builds take the
            // endpoint companion one. Only one of the two exists, so a miss is not an error.
            KernelPatcher::RouteRequest configRoute("__ZN13IOUSBHostPipe28initWithDescriptorsAndOwnersEPKN11StandardUSB18EndpointDescriptorEPKNS0_23ConfigurationDescriptorEP22AppleUSBHostControllerP15IOUSBHostDeviceP18IOUSBHostInterfaceht",
                                                    patched_init_pipe_config, orig_init_pipe_config);
            const bool configRouted = patcher.routeMultiple(index, &configRoute, 1, address, size);
            if (!configRouted)
                patcher.clearError();
            KernelPatcher::RouteRequest initRoute("__ZN13IOUSBHostPipe28initWithDescriptorsAndOwnersEPKN11StandardUSB18EndpointDescriptorEPKNS0_37SuperSpeedEndpointCompanionDescriptorEP22AppleUSBHostControllerP15IOUSBHostDeviceP18IOUSBHostInterfaceht",
                                                  patched_init_pipe, orig_init_pipe);
            const bool initRouted = patcher.routeMultiple(index, &initRoute, 1, address, size);
            if (!initRouted)
                patcher.clearError();
            if (!configRouted && !initRouted)
                SYSLOG("btleadv", "failed to route pipe creation");
            noteHook("BTLEAdvPipeHooks", (configRouted ? 1U : 0U) | (initRouted ? 2U : 0U) | (ioRouted ? 4U : 0U));
        });
    }
};

// Match Xcode's kext lifecycle. The kernel runs C++ initializers; libkmod
// forwards the start/stop callbacks through _realmain and _antimain.
extern "C" {
extern kern_return_t _start(kmod_info_t *, void *);
extern kern_return_t _stop(kmod_info_t *, void *);
extern kern_return_t BTLEAdvFixup_kern_start(kmod_info_t *, void *);
extern kern_return_t BTLEAdvFixup_kern_stop(kmod_info_t *, void *);
__attribute__((visibility("default"))) KMOD_EXPLICIT_DECL(org.forbiddenitlwm.BTLEAdvFixup, "0.9.1", _start, _stop)
__attribute__((visibility("hidden"))) kmod_start_func_t *_realmain = BTLEAdvFixup_kern_start;
__attribute__((visibility("hidden"))) kmod_stop_func_t *_antimain = BTLEAdvFixup_kern_stop;
__attribute__((visibility("hidden"))) int _kext_apple_cc = __APPLE_CC__;
}
