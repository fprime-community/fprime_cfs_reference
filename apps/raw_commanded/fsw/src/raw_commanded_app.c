/*
 * Raw cFS commanded application (plain C, cFS APIs only; no F Prime).
 *
 * Subscribes to a cFS command from the fprime_app carrying a random raw-byte
 * payload, verifies it (checksum, function code, length), reports it via EVS
 * and echoes the payload back in a cFS telemetry packet.
 */
#include "cfe.h"
#include "raw_commanded_msgids.h"
#include "raw_commanded_msg.h"
#include "raw_commanded_eventids.h"

#include <string.h>

#define RAW_COMMANDED_PIPE_DEPTH 16
#define RAW_COMMANDED_PIPE_NAME  "RAW_CMDD_PIPE"

typedef struct
{
    CFE_SB_PipeId_t         Pipe;
    RAW_COMMANDED_EchoTlm_t Tlm;
    uint32                  Received;
    uint32                  Rejected;
} RAW_COMMANDED_Global_t;

static RAW_COMMANDED_Global_t RAW_COMMANDED_Global;

void RAW_COMMANDED_Main(void);

static int32 RAW_COMMANDED_Init(void)
{
    int32 status;

    memset(&RAW_COMMANDED_Global, 0, sizeof(RAW_COMMANDED_Global));

    status = CFE_EVS_Register(NULL, 0, CFE_EVS_EventFilter_BINARY);
    if (status != CFE_SUCCESS)
    {
        return status;
    }
    status = CFE_SB_CreatePipe(&RAW_COMMANDED_Global.Pipe, RAW_COMMANDED_PIPE_DEPTH, RAW_COMMANDED_PIPE_NAME);
    if (status == CFE_SUCCESS)
    {
        status = CFE_SB_Subscribe(CFE_SB_ValueToMsgId(RAW_COMMANDED_ECHO_CMD_MID), RAW_COMMANDED_Global.Pipe);
    }
    if (status != CFE_SUCCESS)
    {
        CFE_EVS_SendEvent(RAW_COMMANDED_PIPE_ERR_EID, CFE_EVS_EventType_ERROR,
                          "RAW_COMMANDED: pipe/subscribe failed, RC = 0x%08lX", (unsigned long)status);
        return status;
    }
    CFE_EVS_SendEvent(RAW_COMMANDED_INIT_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "RAW_COMMANDED initialized: cmd MID 0x%04X fc %d, echo tlm MID 0x%04X", RAW_COMMANDED_ECHO_CMD_MID,
                      RAW_COMMANDED_ECHO_CMD_FC, RAW_COMMANDED_ECHO_TLM_MID);
    return CFE_SUCCESS;
}

static void RAW_COMMANDED_ProcessCommand(const CFE_SB_Buffer_t *BufPtr)
{
    int32              status;
    bool               valid       = false;
    CFE_MSG_FcnCode_t  fcnCode     = 0;
    CFE_MSG_Size_t     size        = 0;
    size_t             payloadSize = 0;
    const RAW_COMMANDED_EchoCmd_t *cmd = (const RAW_COMMANDED_EchoCmd_t *)BufPtr;

    status = CFE_MSG_ValidateChecksum(&BufPtr->Msg, &valid);
    if (status == CFE_SUCCESS)
    {
        status = CFE_MSG_GetFcnCode(&BufPtr->Msg, &fcnCode);
    }
    if (status == CFE_SUCCESS)
    {
        status = CFE_MSG_GetSize(&BufPtr->Msg, &size);
    }
    if (status != CFE_SUCCESS)
    {
        RAW_COMMANDED_Global.Rejected++;
        CFE_EVS_SendEvent(RAW_COMMANDED_MSG_ERR_EID, CFE_EVS_EventType_ERROR,
                          "RAW_COMMANDED: command rejected, header read failed, RC = 0x%08lX (%lu rejected)",
                          (unsigned long)status, (unsigned long)RAW_COMMANDED_Global.Rejected);
        return;
    }
    if (!valid)
    {
        RAW_COMMANDED_Global.Rejected++;
        CFE_EVS_SendEvent(RAW_COMMANDED_CHECKSUM_ERR_EID, CFE_EVS_EventType_ERROR,
                          "RAW_COMMANDED: command rejected, bad checksum (%lu rejected)",
                          (unsigned long)RAW_COMMANDED_Global.Rejected);
        return;
    }
    if (fcnCode != RAW_COMMANDED_ECHO_CMD_FC)
    {
        RAW_COMMANDED_Global.Rejected++;
        CFE_EVS_SendEvent(RAW_COMMANDED_FC_ERR_EID, CFE_EVS_EventType_ERROR,
                          "RAW_COMMANDED: command rejected, unexpected function code %u (%lu rejected)",
                          (unsigned int)fcnCode, (unsigned long)RAW_COMMANDED_Global.Rejected);
        return;
    }
    if ((size <= sizeof(CFE_MSG_CommandHeader_t)) || (size > sizeof(RAW_COMMANDED_EchoCmd_t)))
    {
        RAW_COMMANDED_Global.Rejected++;
        CFE_EVS_SendEvent(RAW_COMMANDED_LEN_ERR_EID, CFE_EVS_EventType_ERROR,
                          "RAW_COMMANDED: command rejected, bad length %lu (%lu rejected)", (unsigned long)size,
                          (unsigned long)RAW_COMMANDED_Global.Rejected);
        return;
    }
    payloadSize = size - sizeof(CFE_MSG_CommandHeader_t);
    RAW_COMMANDED_Global.Received++;
    CFE_EVS_SendEvent(RAW_COMMANDED_RECEIVED_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "RAW_COMMANDED: received echo command fc %u, %lu random bytes (first 0x%02X), %lu received",
                      (unsigned int)fcnCode, (unsigned long)payloadSize, cmd->Payload[0],
                      (unsigned long)RAW_COMMANDED_Global.Received);

    /* Echo the exact bytes back as a cFS telemetry packet (SB stamps the time on transmit) */
    status = CFE_MSG_Init(CFE_MSG_PTR(RAW_COMMANDED_Global.Tlm.Header), CFE_SB_ValueToMsgId(RAW_COMMANDED_ECHO_TLM_MID),
                          sizeof(RAW_COMMANDED_Global.Tlm.Header) + payloadSize);
    if (status == CFE_SUCCESS)
    {
        memcpy(RAW_COMMANDED_Global.Tlm.Payload, cmd->Payload, payloadSize);
        status = CFE_SB_TransmitMsg(CFE_MSG_PTR(RAW_COMMANDED_Global.Tlm.Header), true);
    }
    if (status != CFE_SUCCESS)
    {
        CFE_EVS_SendEvent(RAW_COMMANDED_SEND_ERR_EID, CFE_EVS_EventType_ERROR,
                          "RAW_COMMANDED: echo send failed, RC = 0x%08lX", (unsigned long)status);
        return;
    }
    CFE_EVS_SendEvent(RAW_COMMANDED_ECHOED_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "RAW_COMMANDED: echoed %lu bytes on MID 0x%04X", (unsigned long)payloadSize,
                      RAW_COMMANDED_ECHO_TLM_MID);
}

void RAW_COMMANDED_Main(void)
{
    uint32           runStatus = CFE_ES_RunStatus_APP_RUN;
    int32            status;
    CFE_SB_Buffer_t *bufPtr = NULL;
    CFE_SB_MsgId_t   msgId  = CFE_SB_INVALID_MSG_ID;

    status = RAW_COMMANDED_Init();
    if (status != CFE_SUCCESS)
    {
        runStatus = CFE_ES_RunStatus_APP_ERROR;
    }

    while (CFE_ES_RunLoop(&runStatus) == true)
    {
        status = CFE_SB_ReceiveBuffer(&bufPtr, RAW_COMMANDED_Global.Pipe, CFE_SB_PEND_FOREVER);
        if (status != CFE_SUCCESS)
        {
            CFE_EVS_SendEvent(RAW_COMMANDED_PIPE_ERR_EID, CFE_EVS_EventType_ERROR,
                              "RAW_COMMANDED: pipe read error, RC = 0x%08lX", (unsigned long)status);
            runStatus = CFE_ES_RunStatus_APP_ERROR;
            continue;
        }
        status = CFE_MSG_GetMsgId(&bufPtr->Msg, &msgId);
        if (status != CFE_SUCCESS)
        {
            CFE_EVS_SendEvent(RAW_COMMANDED_MSG_ERR_EID, CFE_EVS_EventType_ERROR,
                              "RAW_COMMANDED: message ID read failed, RC = 0x%08lX", (unsigned long)status);
            continue;
        }
        if (CFE_SB_MsgIdToValue(msgId) == RAW_COMMANDED_ECHO_CMD_MID)
        {
            RAW_COMMANDED_ProcessCommand(bufPtr);
        }
        else
        {
            CFE_EVS_SendEvent(RAW_COMMANDED_MID_ERR_EID, CFE_EVS_EventType_ERROR, "RAW_COMMANDED: unexpected MID 0x%04lX",
                              (unsigned long)CFE_SB_MsgIdToValue(msgId));
        }
    }

    CFE_ES_ExitApp(runStatus);
}
