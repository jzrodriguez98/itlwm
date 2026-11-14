// Experimental native AWDL interface. No AWDL radio data path is implemented.
#pragma once
#include <Airport/IO80211AWDLProtocol.h>
#include <Airport/IOSkywalkQueueFactories.h>
#include "AWDLRequestedValue.hpp"
#include "AWDLInactiveProtocol.hpp"
#include <IOKit/IOLocks.h>

class ItlAWDLInterface : public IO80211AWDLProtocol {
    OSDeclareDefaultStructors(ItlAWDLInterface)
public:
    struct FrameConfiguration {
        apple80211_awdl_sync_params parameters;
        bool hasRequestedTiming;
        uint8_t address[6];
        size_t templateLength;
        uint8_t staticTLVs[ItlAWDLFrameTemplate::capacity];
    };
    // Caller retains this interface and holds the shared controller gate.
    // The copy owns every byte and does not activate the native transport.
    IOReturn copyFrameConfiguration(FrameConfiguration*);
    void observeDataFrame(const uint8_t*, size_t);
    void acceptNativeRequests();
    // Under the shared gate. Completes accepted packets and reports whether work remains.
    bool serviceTransmit();
    // Under the shared gate. Prepared TLVs for a master indication frame, if any.
    bool copyMasterIndication(uint8_t *, size_t, size_t *);
    bool hasMasterIndication() const { return masterIndicationLength != 0; }
    // Under the shared gate. Converts the oldest queued frame into a caller-owned buffer.
    bool popTransmit(uint8_t *, size_t, size_t *, const uint8_t *holdPayloadFor, bool holdEverySize = false);
    // Frames macOS has queued that the driver hasn't taken yet.
    unsigned queuedTransmit() const { return transmitQueued; }
    unsigned heldShortTransmit() const { return transmitHeldShort; }
    IOReturn initializeNetwork(IO80211Controller*, IOWorkLoop*, const ether_addr&);
    IOReturn receiveManagementFrame(IO80211Controller*, const uint8_t*, size_t, uint32_t, int32_t);
    void stop(IOService*) override;
    void free() override;
    // #13 diagnostics: who opens and closes this interface (the BSD client that owns awdl0,
    // the Wi-Fi daemons' user clients), and when the BSD interface is prepared and finalised.
    bool handleOpen(IOService*, IOOptionBits, void*) override;
    void handleClose(IOService*, IOOptionBits) override;
#if __IO80211_TARGET == __MAC_15_2
    IOReturn prepareBSDInterface(struct __ifnet*, unsigned int) override;
    void finalizeBSDInterface(struct __ifnet*, unsigned int) override;
#endif
    // Pure in IO80211VirtualInterface on Tahoe, and in IO80211SkywalkInterface on Sequoia.
#if __IO80211_TARGET != __MAC_14_4   // not a virtual on Sonoma
    IOReturn setMacAddress(ether_addr&) override { return unsupported("setMacAddress"); }
#endif
    IOReturn getSSID(apple80211_ssid_data*) override { return unsupported("getSSID"); }
    IOReturn getCHANNEL(apple80211_channel_data*) override { return unsupported("getCHANNEL"); }
    IOReturn getBSSID(apple80211_bssid_data*) override { return unsupported("getBSSID"); }
    IOReturn getSTATE(apple80211_state_data*) override { return unsupported("getSTATE"); }
    IOReturn getAWDL_SYNC_PARAMS(apple80211_awdl_sync_params *data) override { return readRequested(requested_AWDL_SYNC_PARAMS, data); }
    IOReturn getAWDL_SYNC_ENABLED(apple80211_awdl_sync_enabled *data) override;
    IOReturn getAWDL_EXTENSION_STATE_MACHINE_PARAMETERS(apple80211_awdl_extension_state_machine_parameter *data) override { return readRequested(requested_AWDL_EXTENSION_STATE_MACHINE_PARAMETERS, data); }
    IOReturn getAWDL_ELECTION_ID(apple80211_awdl_election_id *data) override { return readRequested(requested_AWDL_ELECTION_ID, data); }
    IOReturn getAWDL_ELECTION_METRIC(apple80211_awdl_election_metric *data) override { return readRequested(requested_AWDL_ELECTION_METRIC, data); }
    IOReturn getAWDL_SYNCHRONIZATION_CHANNEL_SEQUENCE(apple80211_awdl_sync_channel_sequence *data) override { return readRequested(requested_AWDL_SYNCHRONIZATION_CHANNEL_SEQUENCE, data); }
    IOReturn getPEER_CACHE_MAXIMUM_SIZE(apple80211_peer_cache_maximum_size*) override { return unsupported("getPEER_CACHE_MAXIMUM_SIZE"); }
    IOReturn getAWDL_MASTER_CHANNEL(apple80211_awdl_master_channel *data) override { return readRequested(requested_AWDL_MASTER_CHANNEL, data); }
    IOReturn getAWDL_SYNC_STATE(apple80211_awdl_sync_state *data) override { return nativeState.getState(data); }
    IOReturn getAWDL_ELECTION_RSSI_THRESHOLDS(apple80211_awdl_election_rssi_thresholds *data) override { return readRequested(requested_AWDL_ELECTION_RSSI_THRESHOLDS, data); }
    IOReturn getAWDL_PRESENCE_MODE(apple80211_awdl_presence_mode *data) override { return readRequested(requested_AWDL_PRESENCE_MODE, data); }
    IOReturn getAWDL_ELECTION_PARAMS(apple80211_awdl_election_params*) override { return unsupported("getAWDL_ELECTION_PARAMS"); }
    IOReturn getAWDL_DEVICE_CAPABILITIES(apple80211_awdl_device_capabilities*) override { return unsupported("getAWDL_DEVICE_CAPABILITIES"); }
    IOReturn getAWDL_SECONDARY_MASTER_CHANNEL(apple80211_awdl_secondary_master_channel *data) override { return readRequested(requested_AWDL_SECONDARY_MASTER_CHANNEL, data); }
    IOReturn getAWDL_AF_TX_MODE(apple80211_awdl_af_tx_mode *) override;
    IOReturn getAWDL_MIN_RATE(apple80211_awdl_min_rate*) override { return unsupported("getAWDL_MIN_RATE"); }
    IOReturn getAWDL_ENCRYPTION_TYPE(apple80211_encrypt*) override { return unsupported("getAWDL_ENCRYPTION_TYPE"); }
    IOReturn getAWDL_TXCAL_PERIOD(apple80211_awdl_txcal_period*) override { return unsupported("getAWDL_TXCAL_PERIOD"); }
    IOReturn getAWDL_DEV_STATS(apple80211_awdl_dev_stats*) override { return unsupported("getAWDL_DEV_STATS"); }
    IOReturn getAWDL_DFSP_CONFIG(apple80211_awdl_dfsp_config*) override { return unsupported("getAWDL_DFSP_CONFIG"); }
    IOReturn getAWDL_CCA(apple80211_awdl_cca*) override { return unsupported("getAWDL_CCA"); }
    IOReturn getAWDL_AF_SECONDARY_PAYLOAD_CAPABILITIES(apple80211_awdl_cap *) override;
    IOReturn getLLW_PARAMS(apple80211_llw_params*) override { return unsupported("getLLW_PARAMS"); }
    IOReturn setSSID(apple80211_ssid_data*) override { return unsupported("setSSID"); }
    IOReturn setCHANNEL(apple80211_channel_data*) override { return unsupported("setCHANNEL"); }
    IOReturn setAWDL_SYNC_PARAMS(apple80211_awdl_sync_params *data) override { return storeRequested(requested_AWDL_SYNC_PARAMS, data, "AWDL_SYNC_PARAMS"); }
    IOReturn setAWDL_SYNC_ENABLED(apple80211_awdl_sync_enabled *data) override;
    IOReturn setAWDL_EXTENSION_STATE_MACHINE_PARAMETERS(apple80211_awdl_extension_state_machine_parameter *data) override { return storeRequested(requested_AWDL_EXTENSION_STATE_MACHINE_PARAMETERS, data, "AWDL_EXTENSION_STATE_MACHINE_PARAMETERS"); }
    IOReturn setAWDL_ELECTION_ID(apple80211_awdl_election_id *data) override { return storeRequested(requested_AWDL_ELECTION_ID, data, "AWDL_ELECTION_ID"); }
    IOReturn setAWDL_BSSID(apple80211_awdl_bssid *data) override { return storeRequested(requestedBSSID, data, "AWDL_BSSID"); }
    IOReturn setAWDL_ELECTION_METRIC(apple80211_awdl_election_metric *data) override { return storeRequested(requested_AWDL_ELECTION_METRIC, data, "AWDL_ELECTION_METRIC"); }
    IOReturn setAWDL_SYNCHRONIZATION_CHANNEL_SEQUENCE(apple80211_awdl_sync_channel_sequence *data) override { return storeRequested(requested_AWDL_SYNCHRONIZATION_CHANNEL_SEQUENCE, data, "AWDL_SYNCHRONIZATION_CHANNEL_SEQUENCE"); }
    IOReturn setAWDL_MASTER_CHANNEL(apple80211_awdl_master_channel *data) override { return storeRequested(requested_AWDL_MASTER_CHANNEL, data, "AWDL_MASTER_CHANNEL"); }
    IOReturn setAWDL_SYNC_STATE(apple80211_awdl_sync_state *data) override;
    IOReturn setAWDL_ELECTION_RSSI_THRESHOLDS(apple80211_awdl_election_rssi_thresholds *data) override { return storeRequested(requested_AWDL_ELECTION_RSSI_THRESHOLDS, data, "AWDL_ELECTION_RSSI_THRESHOLDS"); }
    IOReturn setAWDL_PRESENCE_MODE(apple80211_awdl_presence_mode *data) override { return storeRequested(requested_AWDL_PRESENCE_MODE, data, "AWDL_PRESENCE_MODE"); }
    IOReturn setPEER_CACHE_CONTROL(apple80211_peer_cache_control*) override { return unsupported("setPEER_CACHE_CONTROL"); }
    IOReturn setAWDL_OOB_REQUEST(apple80211_awdl_oob_request *) override;
    IOReturn setAWDL_SYNC_FRAME_TEMPLATE(apple80211_awdl_sync_frame_template *data) override;
    IOReturn setAWDL_ELECTION_PARAMS(apple80211_awdl_election_params *) override;
    IOReturn setAWDL_PEER_TRAFFIC_REGISTRATION(apple80211_awdl_peer_traffic_registration *) override;
    IOReturn setAWDL_SECONDARY_MASTER_CHANNEL(apple80211_awdl_secondary_master_channel *data) override { return storeRequested(requested_AWDL_SECONDARY_MASTER_CHANNEL, data, "AWDL_SECONDARY_MASTER_CHANNEL"); }
    IOReturn setAWDL_AF_TX_MODE(apple80211_awdl_af_tx_mode *) override;
    IOReturn setAWDL_MIN_RATE(apple80211_awdl_min_rate*) override { return unsupported("setAWDL_MIN_RATE"); }
    IOReturn setAWDL_ENCRYPTION_KEYS(apple80211_key*) override { return unsupported("setAWDL_ENCRYPTION_KEYS"); }
    IOReturn setAWDL_ENCRYPTION_TYPE(apple80211_encrypt*) override { return unsupported("setAWDL_ENCRYPTION_TYPE"); }
    IOReturn setAWDL_OOB_AUTO_REQUEST(apple80211_awdl_oob_request *) override;
    IOReturn setAWDL_TXCAL_PERIOD(apple80211_awdl_txcal_period*) override { return unsupported("setAWDL_TXCAL_PERIOD"); }
    IOReturn setAWDL_AWDL_ADVERTISERS(awdl_peer_advert_add*) override { return unsupported("setAWDL_AWDL_ADVERTISERS"); }
    IOReturn setAWDL_DFSP_CONFIG(apple80211_awdl_dfsp_config*) override { return unsupported("setAWDL_DFSP_CONFIG"); }
    IOReturn setAWDL_DFSP_UCSA_CONFIG(apple80211_awdl_dfsp_ucsa_config*) override { return unsupported("setAWDL_DFSP_UCSA_CONFIG"); }
    IOReturn setCOMPANION_SKYWALK_IF_CREATE(apple80211_companion_skywalk_if_create*) override { return unsupported("setCOMPANION_SKYWALK_IF_CREATE"); }
    IOReturn setAWDL_OOB_SEC_PAYLOAD_REQUEST(apple80211_awdl_af_sec_payload_request*) override { return unsupported("setAWDL_OOB_SEC_PAYLOAD_REQUEST"); }
    IOReturn setLLW_PARAMS(apple80211_llw_params*) override { return unsupported("setLLW_PARAMS"); }
    IOReturn setTX_RATE(apple80211_tx_rate*) override { return unsupported("setTX_RATE"); }
    IOReturn setP2P_COEX_PROTECTION(apple80211_p2p_coex_protection*) override { return unsupported("setP2P_COEX_PROTECTION"); }
    IOReturn setPSF_DWELL(apple80211_awdl_psf_dwell_params*) override { return unsupported("setPSF_DWELL"); }
#if __IO80211_TARGET != __MAC_14_4   // Sonoma's AWDL protocol has no setAWDL_CONFIG (62 methods, not 63)
    IOReturn setAWDL_CONFIG(apple80211_awdl_config_request*) override { return unsupported("setAWDL_CONFIG"); }
#endif
    IOReturn setAWDL_RTG_PEER_STATS_CONFIG(apple80211_rtg_peer_stats_cfg*) override { return unsupported("setAWDL_RTG_PEER_STATS_CONFIG"); }
private:
    void noteClientEvent(const char *what, IOService *client, long result, bool trace);
    static constexpr unsigned clientEventCapacity = 12;
    char clientEvents[clientEventCapacity][200] = {};
    unsigned clientEventCount = 0;
    // These are desired host settings, not an active radio schedule. Native
    // synchronization/state/frame operations remain unsupported.
    IOLock *configurationLock = nullptr;
    ItlAWDLFrameTemplate frameTemplate;
    uint8_t localFrameAddress[6] = {};
    bool dataCopyProbeEnabled = false;
    unsigned dataCopyAttempts = 0, dataCopySuccess = 0;
    bool dataDeliverEnabled = false;
    unsigned dataDelivered = 0, dataDeliverFailed = 0;
    unsigned transmitCallbacks = 0, transmitPackets = 0, receiveSupplyCallbacks = 0;
    bool transmitSampled = false;
    void noteTransmit(IOSkywalkPacket *const *, UInt32);
    void noteQueueState(const char *);
    UInt32 acceptTransmit(IOSkywalkPacket *const *, UInt32);
    // Only under the shared gate. Each frame is a copy, so no packet waits on the radio.
    struct TransmitFrame { uint16_t length; uint8_t bytes[1514]; };
    // itlawdltxqueue=N, 128 to 4096: frames held while the radio can't send, such as while the
    // peer is on another channel. A full queue drops, and the sender's transport reads that as loss.
    // Set once, before the frames are allocated (about 1.5 KB each).
    static constexpr unsigned transmitFrameCapacity = 4096, transmitFrameDefault = 128;
    unsigned transmitFrameCount = transmitFrameDefault;
    TransmitFrame *transmitFrames = nullptr;
    unsigned transmitHead = 0, transmitQueued = 0, transmitDropped = 0, transmitAccepted = 0;
    unsigned transmitHeldShort = 0;  // Short frames kept in order behind a paused or full aggregate queue.
    unsigned transmitPopped = 0, transmitHeldMark = 0;
    IOSkywalkPacket *transmitDone[transmitFrameCapacity] = {};
    unsigned transmitDoneCount = 0, transmitCompleted = 0, transmitLastPublished = 0;
    void drainTransmitDone();
    uint32_t transmitDepthBins[9] = {};
    uint16_t transmitSequence = 0;
    bool dataTransmitEnabled = false;
    ItlAWDLNativeState nativeState;
    unsigned oobRequests = 0;
    bool oobSampled = false, debugFlagsSet = false, debugFlagsWanted = false;
    IOReturn noteOobRequest(const apple80211_awdl_oob_request *, const char *);
    // Native 25G241 layout read from both the sender and Apple's Broadcom handler:
    // length at +0x28 and a pointer to peer manager storage at +0x30, 0x4b0 bytes at most.
    void storeMasterIndication(const apple80211_awdl_oob_request *);
    uint8_t masterIndication[0x4b0] = {};
    size_t masterIndicationLength = 0;
    bool masterIndicationEnabled = false;
    uint16_t masterIndicationSampledLength = 0;
    unsigned masterIndicationUpdates = 0, masterIndicationRejected = 0;
    uint32_t afTxModeValue = 0;
    ItlAWDLRequestedValue<apple80211_awdl_bssid> requestedBSSID;
    ItlAWDLRequestedValue<apple80211_awdl_sync_params> requested_AWDL_SYNC_PARAMS;
    ItlAWDLRequestedValue<apple80211_awdl_extension_state_machine_parameter> requested_AWDL_EXTENSION_STATE_MACHINE_PARAMETERS;
    ItlAWDLRequestedValue<apple80211_awdl_election_id> requested_AWDL_ELECTION_ID;
    ItlAWDLRequestedValue<apple80211_awdl_election_metric> requested_AWDL_ELECTION_METRIC;
    ItlAWDLRequestedValue<apple80211_awdl_sync_channel_sequence> requested_AWDL_SYNCHRONIZATION_CHANNEL_SEQUENCE;
    ItlAWDLRequestedValue<apple80211_awdl_master_channel> requested_AWDL_MASTER_CHANNEL;
    ItlAWDLRequestedValue<apple80211_awdl_secondary_master_channel> requested_AWDL_SECONDARY_MASTER_CHANNEL;
    ItlAWDLRequestedValue<apple80211_awdl_election_rssi_thresholds> requested_AWDL_ELECTION_RSSI_THRESHOLDS;
    ItlAWDLRequestedValue<apple80211_awdl_presence_mode> requested_AWDL_PRESENCE_MODE;
    template <typename T> IOReturn storeRequested(ItlAWDLRequestedValue<T> &slot,
                                                 const T *data, const char *name) {
        if (!configurationLock)
            return kIOReturnNotReady;
        IOLockLock(configurationLock);
        const IOReturn result = slot.set(data);
        IOLockUnlock(configurationLock);
        if (result == kIOReturnSuccess)
            setProperty("ItlwmAWDLLastStoredRequest", name);
        return result;
    }
    template <typename T> IOReturn readRequested(const ItlAWDLRequestedValue<T> &slot,
                                                T *data) {
        if (!configurationLock)
            return kIOReturnNotReady;
        IOLockLock(configurationLock);
        const IOReturn result = slot.get(data);
        IOLockUnlock(configurationLock);
        return result;
    }
    void releaseNetworkResources();
    static UInt32 rejectTransmit(OSObject*, IOSkywalkTxSubmissionQueue*, IOSkywalkPacket *const*, UInt32, void*);
    static UInt32 deferReceive(OSObject*, IOSkywalkRxSubmissionQueue*, IOSkywalkPacket *const*, UInt32, void*);
    IOSkywalkPacketBufferPool *txPool = nullptr;
    IOSkywalkPacketBufferPool *rxPool = nullptr;
    IOEventSource *packetQueues[4] = {};
    IOWorkLoop *queueWorkLoop = nullptr;
    UInt32 addedQueues = 0;
    bool nativeStarted = false;
    bool registrationAttempted = false;
    uint32_t managementSubmissions = 0;
    IOReturn unsupported(const char *operation) {
        setProperty("ItlwmAWDLLastUnsupported", operation);
        return kIOReturnUnsupported;
    }
};
