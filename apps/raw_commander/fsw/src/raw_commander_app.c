/*
 * Raw cFS commander application (plain C, cFS APIs only; no F Prime).
 *
 * Every 10 seconds (sch_lab wakeup) it sends a cFS command carrying a random
 * raw-byte payload to the fprime_app and expects a cFS telemetry packet echoing
 * the same bytes. Match/mismatch/timeout are reported as EVS events.
 */
#include "cfe.h"
#include "raw_commander_msgids.h"
#include "raw_commander_msg.h"
#include "raw_commander_eventids.h"

#include <string.h>

#define RAW_COMMANDER_PIPE_DEPTH 16
#define RAW_COMMANDER_PIPE_NAME  "RAW_CMDR_PIPE"

typedef struct
{
    CFE_SB_PipeId_t         Pipe;
    RAW_COMMANDER_EchoCmd_t Cmd;
    size_t                  PayloadSize;
    bool                    Outstanding;
    uint32                  Sequence;
    uint32                  Seed;
    uint32                  Matches;
    uint32                  Mismatches;
    uint32                  Timeouts;
} RAW_COMMANDER_Global_t;

static RAW_COMMANDER_Global_t RAW_COMMANDER_Global;

void RAW_COMMANDER_Main(void);

static uint32 RAW_COMMANDER_Random(void)
{
    /* xorshift32: adequate for a test payload, deterministic given the seed */
    uint32 x = RAW_COMMANDER_Global.Seed;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    RAW_COMMANDER_Global.Seed = (x == 0) ? 0x9E3779B9u : x;
    return RAW_COMMANDER_Global.Seed;
}

static int32 RAW_COMMANDER_Init(void)
{
    int32          status;
    OS_time_t      now;
    CFE_SB_MsgId_t wakeupMid = CFE_SB_ValueToMsgId(RAW_COMMANDER_WAKEUP_MID);
    CFE_SB_MsgId_t tlmMid    = CFE_SB_ValueToMsgId(RAW_COMMANDER_ECHO_TLM_MID);

    memset(&RAW_COMMANDER_Global, 0, sizeof(RAW_COMMANDER_Global));
    CFE_PSP_GetTime(&now);
    RAW_COMMANDER_Global.Seed = (uint32)OS_TimeGetTotalMicroseconds(now) | 1u;

    status = CFE_EVS_Register(NULL, 0, CFE_EVS_EventFilter_BINARY);
    if (status != CFE_SUCCESS)
    {
        return status;
    }
    status = CFE_SB_CreatePipe(&RAW_COMMANDER_Global.Pipe, RAW_COMMANDER_PIPE_DEPTH, RAW_COMMANDER_PIPE_NAME);
    if (status != CFE_SUCCESS)
    {
        CFE_EVS_SendEvent(RAW_COMMANDER_PIPE_ERR_EID, CFE_EVS_EventType_ERROR,
                          "RAW_COMMANDER: pipe creation failed, RC = 0x%08lX", (unsigned long)status);
        return status;
    }
    status = CFE_SB_Subscribe(wakeupMid, RAW_COMMANDER_Global.Pipe);
    if (status == CFE_SUCCESS)
    {
        status = CFE_SB_Subscribe(tlmMid, RAW_COMMANDER_Global.Pipe);
    }
    if (status != CFE_SUCCESS)
    {
        CFE_EVS_SendEvent(RAW_COMMANDER_PIPE_ERR_EID, CFE_EVS_EventType_ERROR,
                          "RAW_COMMANDER: subscribe failed, RC = 0x%08lX", (unsigned long)status);
        return status;
    }
    CFE_EVS_SendEvent(RAW_COMMANDER_INIT_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "RAW_COMMANDER initialized: cmd MID 0x%04X fc %d, echo tlm MID 0x%04X, wakeup MID 0x%04X",
                      RAW_COMMANDER_ECHO_CMD_MID, RAW_COMMANDER_ECHO_CMD_FC, RAW_COMMANDER_ECHO_TLM_MID,
                      RAW_COMMANDER_WAKEUP_MID);
    return CFE_SUCCESS;
}

static void RAW_COMMANDER_SendEcho(void)
{
    int32  status;
    size_t i;

    if (RAW_COMMANDER_Global.Outstanding)
    {
        RAW_COMMANDER_Global.Timeouts++;
        CFE_EVS_SendEvent(RAW_COMMANDER_TIMEOUT_ERR_EID, CFE_EVS_EventType_ERROR,
                          "RAW_COMMANDER: no echo received for command seq %lu (%lu timeouts)",
                          (unsigned long)RAW_COMMANDER_Global.Sequence, (unsigned long)RAW_COMMANDER_Global.Timeouts);
    }

    RAW_COMMANDER_Global.Sequence++;
    RAW_COMMANDER_Global.PayloadSize = 1 + (RAW_COMMANDER_Random() % RAW_COMMANDER_MAX_PAYLOAD);

    /* cFS builds the primary/secondary headers; the SB stamps sequence count and checksum on transmit */
    status = CFE_MSG_Init(CFE_MSG_PTR(RAW_COMMANDER_Global.Cmd.Header), CFE_SB_ValueToMsgId(RAW_COMMANDER_ECHO_CMD_MID),
                          sizeof(RAW_COMMANDER_Global.Cmd.Header) + RAW_COMMANDER_Global.PayloadSize);
    if (status == CFE_SUCCESS)
    {
        status = CFE_MSG_SetFcnCode(CFE_MSG_PTR(RAW_COMMANDER_Global.Cmd.Header), RAW_COMMANDER_ECHO_CMD_FC);
    }
    /* Fill the payload after CFE_MSG_Init, which zeroes the whole message */
    for (i = 0; i < RAW_COMMANDER_Global.PayloadSize; i++)
    {
        RAW_COMMANDER_Global.Cmd.Payload[i] = (uint8)(RAW_COMMANDER_Random() & 0xFF);
    }
    if (status == CFE_SUCCESS)
    {
        status = CFE_SB_TransmitMsg(CFE_MSG_PTR(RAW_COMMANDER_Global.Cmd.Header), true);
    }
    if (status != CFE_SUCCESS)
    {
        RAW_COMMANDER_Global.Outstanding = false;
        CFE_EVS_SendEvent(RAW_COMMANDER_SEND_ERR_EID, CFE_EVS_EventType_ERROR,
                          "RAW_COMMANDER: send failed, RC = 0x%08lX", (unsigned long)status);
        return;
    }
    RAW_COMMANDER_Global.Outstanding = true;
    CFE_EVS_SendEvent(RAW_COMMANDER_SENT_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "RAW_COMMANDER: sent echo command seq %lu, %lu random bytes (first 0x%02X)",
                      (unsigned long)RAW_COMMANDER_Global.Sequence, (unsigned long)RAW_COMMANDER_Global.PayloadSize,
                      RAW_COMMANDER_Global.Cmd.Payload[0]);
}

static void RAW_COMMANDER_ProcessEcho(const CFE_SB_Buffer_t *BufPtr)
{
    CFE_MSG_Size_t size        = 0;
    size_t         payloadSize = 0;
    int32          status;
    const RAW_COMMANDER_EchoTlm_t *tlm = (const RAW_COMMANDER_EchoTlm_t *)BufPtr;

    status = CFE_MSG_GetSize(&BufPtr->Msg, &size);
    if (status != CFE_SUCCESS)
    {
        CFE_EVS_SendEvent(RAW_COMMANDER_MSG_ERR_EID, CFE_EVS_EventType_ERROR,
                          "RAW_COMMANDER: echo header read failed, RC = 0x%08lX", (unsigned long)status);
        return;
    }
    if (size >= sizeof(CFE_MSG_TelemetryHeader_t))
    {
        payloadSize = size - sizeof(CFE_MSG_TelemetryHeader_t);
    }

    if (!RAW_COMMANDER_Global.Outstanding)
    {
        CFE_EVS_SendEvent(RAW_COMMANDER_UNEXPECTED_ERR_EID, CFE_EVS_EventType_ERROR,
                          "RAW_COMMANDER: unexpected echo of %lu bytes with no command outstanding",
                          (unsigned long)payloadSize);
        return;
    }
    RAW_COMMANDER_Global.Outstanding = false;

    if ((payloadSize == RAW_COMMANDER_Global.PayloadSize) && (payloadSize <= RAW_COMMANDER_MAX_PAYLOAD) &&
        (memcmp(tlm->Payload, RAW_COMMANDER_Global.Cmd.Payload, payloadSize) == 0))
    {
        RAW_COMMANDER_Global.Matches++;
        CFE_EVS_SendEvent(RAW_COMMANDER_MATCH_INF_EID, CFE_EVS_EventType_INFORMATION,
                          "RAW_COMMANDER: echo seq %lu matched, %lu bytes (%lu matches)",
                          (unsigned long)RAW_COMMANDER_Global.Sequence, (unsigned long)payloadSize,
                          (unsigned long)RAW_COMMANDER_Global.Matches);
    }
    else
    {
        RAW_COMMANDER_Global.Mismatches++;
        CFE_EVS_SendEvent(RAW_COMMANDER_MISMATCH_ERR_EID, CFE_EVS_EventType_ERROR,
                          "RAW_COMMANDER: echo seq %lu MISMATCH: sent %lu bytes, received %lu bytes (%lu mismatches)",
                          (unsigned long)RAW_COMMANDER_Global.Sequence, (unsigned long)RAW_COMMANDER_Global.PayloadSize,
                          (unsigned long)payloadSize, (unsigned long)RAW_COMMANDER_Global.Mismatches);
    }
}

void RAW_COMMANDER_Main(void)
{
    uint32           runStatus = CFE_ES_RunStatus_APP_RUN;
    int32            status;
    CFE_SB_Buffer_t *bufPtr = NULL;
    CFE_SB_MsgId_t   msgId  = CFE_SB_INVALID_MSG_ID;

    status = RAW_COMMANDER_Init();
    if (status != CFE_SUCCESS)
    {
        runStatus = CFE_ES_RunStatus_APP_ERROR;
    }

    while (CFE_ES_RunLoop(&runStatus) == true)
    {
        status = CFE_SB_ReceiveBuffer(&bufPtr, RAW_COMMANDER_Global.Pipe, CFE_SB_PEND_FOREVER);
        if (status != CFE_SUCCESS)
        {
            CFE_EVS_SendEvent(RAW_COMMANDER_PIPE_ERR_EID, CFE_EVS_EventType_ERROR,
                              "RAW_COMMANDER: pipe read error, RC = 0x%08lX", (unsigned long)status);
            runStatus = CFE_ES_RunStatus_APP_ERROR;
            continue;
        }
        status = CFE_MSG_GetMsgId(&bufPtr->Msg, &msgId);
        if (status != CFE_SUCCESS)
        {
            CFE_EVS_SendEvent(RAW_COMMANDER_MSG_ERR_EID, CFE_EVS_EventType_ERROR,
                              "RAW_COMMANDER: message ID read failed, RC = 0x%08lX", (unsigned long)status);
            continue;
        }
        switch (CFE_SB_MsgIdToValue(msgId))
        {
            case RAW_COMMANDER_WAKEUP_MID:
                RAW_COMMANDER_SendEcho();
                break;
            case RAW_COMMANDER_ECHO_TLM_MID:
                RAW_COMMANDER_ProcessEcho(bufPtr);
                break;
            default:
                CFE_EVS_SendEvent(RAW_COMMANDER_MID_ERR_EID, CFE_EVS_EventType_ERROR,
                                  "RAW_COMMANDER: unexpected MID 0x%04lX", (unsigned long)CFE_SB_MsgIdToValue(msgId));
                break;
        }
    }

    CFE_ES_ExitApp(runStatus);
}
