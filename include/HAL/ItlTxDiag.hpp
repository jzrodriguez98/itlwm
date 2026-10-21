//
//  ItlTxDiag.hpp
//  itlwm
//
//  Temporary TX diagnostic counters (plain integers, no locking: values are
//  approximate and only meant to be read through ioreg by a human).
//

#ifndef ItlTxDiag_hpp
#define ItlTxDiag_hpp

#include <stdint.h>

struct ItlTxDiag {
    /* itlwm::outputStart() */
    uint64_t outCalls;      /* calls */
    uint64_t outPkts;       /* packets pulled from the network stack */
    uint64_t outNoRes;      /* returned kIOReturnNoResources (queue full / oactive) */
    uint64_t outQMax;       /* highest if_snd length seen */
    /* iwx_start task */
    uint64_t startRuns;     /* task invocations */
    uint64_t startBlocked;  /* task returned early (oactive / not running) */
    /* iwx_tx() */
    uint64_t txData;        /* data frames handed to the firmware */
    uint64_t txAgg;         /* ...of which on an aggregation (A-MPDU) queue */
    uint64_t txNonAgg;      /* ...of which on the plain data queue */
    uint64_t ringMax;       /* highest ring->queued seen */
    uint64_t qfullSet;      /* times a TX ring was marked full */
    /* Completions */
    uint64_t baNotif;       /* compressed BA notifications */
    uint64_t baTfd;         /* TFDs freed by BA notifications */
    uint64_t baTxed;        /* frames the firmware says it transmitted */
    uint64_t baDone;        /* frames the firmware says were acked */
    uint64_t baRetry;       /* sum of retry_cnt */
    uint64_t respSingle;    /* single-frame TX responses */
    uint64_t respMulti;     /* multi-frame TX responses */
    uint64_t respFail;      /* TX responses with a failure status */
    uint64_t txTimeout;     /* TX watchdog expiries ("device timeout") */
    uint32_t lastTxRate;    /* rate_n_flags of the last BA notification */
    uint32_t lastTlcInfo;   /* tlc_rate_info of the last BA notification */
};

/* A non-static inline function: one shared instance across translation units. */
inline ItlTxDiag &itlTxDiag()
{
    static ItlTxDiag d;
    return d;
}

#define ITL_DIAG_INC(f)      (++itlTxDiag().f)
#define ITL_DIAG_ADD(f, n)   (itlTxDiag().f += (uint64_t)(n))
#define ITL_DIAG_MAX(f, v)   do { if ((uint64_t)(v) > itlTxDiag().f) itlTxDiag().f = (uint64_t)(v); } while (0)

#endif
