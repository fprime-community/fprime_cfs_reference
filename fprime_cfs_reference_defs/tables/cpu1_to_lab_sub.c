/*
** Mission override of the to_lab subscription table.
**
** Subscribes TO_LAB to every F Prime downlink stream so the ground systems
** (F Prime GDS through the fprime_cfs plugins, cFS GroundSystem, others)
** receive them over UDP. The fprime_app framing produces space packets with
** the secondary header flag set, so each message ID is the secondary header
** flag (0x0800) plus the F Prime packet APID (ComCfg.Apid; 0x020 for
** packetized telemetry stays clear of the cFE core housekeeping topics).
*/

#include "cfe_tbl_filedef.h" /* Required to obtain the CFE_TBL_FILEDEF macro definition */
#include "cfe_sb_api_typedefs.h"
#include "to_lab_tbl.h"
#include "cfe_msgids.h"

#include "to_lab_msgids.h"

/* F Prime packetized telemetry: secondary header flag + APID 0x020 (see fprime_app) */
/*
** F Prime downlink messages: telemetry space packets on the F Prime packet APIDs
** (ComCfg.Apid in the fprime_app dictionary). Forwarding them through TO_LAB gives the
** F Prime GDS (fprime-gds --communication-selection cfs-lab --framing-selection cfs) and
** any other ground system on the TO_LAB output the complete F Prime downlink.
*/
#define FPRIME_TELEM_MID          0x0801 /* FW_PACKET_TELEM: telemetry channels */
#define FPRIME_LOG_MID            0x0802 /* FW_PACKET_LOG: events */
#define FPRIME_FILE_MID           0x0803 /* FW_PACKET_FILE: file downlink */
#define FPRIME_DP_MID             0x0805 /* FW_PACKET_DP: data products */
#define FPRIME_PACKETIZED_TLM_MID 0x0820 /* FW_PACKET_PACKETIZED_TLM: packetized telemetry */

/*
** BufLimits: the sum must stay within TO_LAB's telemetry pipe depth (OS_QUEUE_MAX_DEPTH,
** 50 by default) so no subscription is starved when the pipe fills. Events get the
** deepest limit because EVS/event bursts are the largest F Prime downlink burst; this
** reference emits only events (0x0802) and packetized telemetry (0x0820), the other
** MIDs are subscribed so a project adding channel, file or data-product downlink needs
** no table change.
*/
TO_LAB_Subs_t Subscriptions = { .Subs = {
                                    { CFE_SB_MSGID_WRAP_VALUE(FPRIME_TELEM_MID), { 0, 0 }, 8 },
                                    { CFE_SB_MSGID_WRAP_VALUE(FPRIME_LOG_MID), { 0, 0 }, 24 },
                                    { CFE_SB_MSGID_WRAP_VALUE(FPRIME_FILE_MID), { 0, 0 }, 5 },
                                    { CFE_SB_MSGID_WRAP_VALUE(FPRIME_DP_MID), { 0, 0 }, 5 },
                                    { CFE_SB_MSGID_WRAP_VALUE(FPRIME_PACKETIZED_TLM_MID), { 0, 0 }, 8 },

                                    /* CFE_SB_MSGID_RESERVED entry to mark the end of valid MsgIds */
                                    { CFE_SB_MSGID_RESERVED, { 0, 0 }, 0 } } };

CFE_TBL_FILEDEF(Subscriptions, TO_LAB.Subscriptions, TO Lab Sub Tbl, to_lab_sub.tbl)
