/*
 * Raw cFS commander: message layouts. The payload is opaque random bytes.
 */
#ifndef RAW_COMMANDER_MSG_H
#define RAW_COMMANDER_MSG_H

#include "cfe.h"

#define RAW_COMMANDER_MAX_PAYLOAD 32

typedef struct
{
    CFE_MSG_CommandHeader_t Header;
    uint8                   Payload[RAW_COMMANDER_MAX_PAYLOAD];
} RAW_COMMANDER_EchoCmd_t;

typedef struct
{
    CFE_MSG_TelemetryHeader_t Header;
    uint8                     Payload[RAW_COMMANDER_MAX_PAYLOAD];
} RAW_COMMANDER_EchoTlm_t;

typedef struct
{
    CFE_MSG_CommandHeader_t Header;
} RAW_COMMANDER_Wakeup_t;

#endif
