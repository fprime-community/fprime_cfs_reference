/*
 * Raw cFS commander: message IDs. Pure cFS (no F Prime).
 *
 * Message IDs are cFS v2 style: 0x18xx = command (secondary header), 0x08xx = telemetry.
 * The APIDs match the F Prime side (ComCfg.Apid in fprime_app/fprime_config/config/ComCfg.fpp).
 */
#ifndef RAW_COMMANDER_MSGIDS_H
#define RAW_COMMANDER_MSGIDS_H

#define RAW_COMMANDER_WAKEUP_MID   0x18A4 /* Sent by sch_lab every 10 seconds */
#define RAW_COMMANDER_ECHO_CMD_MID 0x18A0 /* Command sent to fprime_app (EchoResponder), fc 1 */
#define RAW_COMMANDER_ECHO_TLM_MID 0x08A1 /* Telemetry echoed back by fprime_app */

#define RAW_COMMANDER_ECHO_CMD_FC 1

#endif
