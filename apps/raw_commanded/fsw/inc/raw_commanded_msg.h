#ifndef RAW_COMMANDED_MSG_H
#define RAW_COMMANDED_MSG_H

#include "cfe.h"

#define RAW_COMMANDED_MAX_PAYLOAD 32

typedef struct
{
    CFE_MSG_CommandHeader_t Header;
    uint8                   Payload[RAW_COMMANDED_MAX_PAYLOAD];
} RAW_COMMANDED_EchoCmd_t;

typedef struct
{
    CFE_MSG_TelemetryHeader_t Header;
    uint8                     Payload[RAW_COMMANDED_MAX_PAYLOAD];
} RAW_COMMANDED_EchoTlm_t;

#endif
