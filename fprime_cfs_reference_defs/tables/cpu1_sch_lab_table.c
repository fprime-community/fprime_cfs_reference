/*
** Mission override of the sch_lab schedule table.
**
** Publishes the F Prime tick message: a cFS command with MID 0x1890
** (command type bit + secondary header flag + APID 0x090, function code 0)
** once per second. The fprime_app CfsBridge subscribes to this message and
** routes it to the SchAppDriver, which cycles the F Prime rate groups.
*/

#include "cfe_tbl_filedef.h" /* Required to obtain the CFE_TBL_FILEDEF macro definition */
#include "sch_lab_tbl.h"
#include "cfe_sb_api_typedefs.h" /* Required to use the CFE_SB_MSGID_WRAP_VALUE macro */

#include "cfe_msgids.h"

/* F Prime tick: command MID for APID 0x090 (see fprime_app) */
#define FPRIME_TICK_MID 0x1890
/* Raw cFS commander wakeup (see apps/raw_commander): every 10 seconds */
#define RAW_COMMANDER_WAKEUP_MID 0x18A4

SCH_LAB_ScheduleTable_t Schedule = {
    .TickRate = 100, /* 100 timer ticks per second */
    .Config   = {
        /* Send the F Prime tick once per second (every 100 ticks) */
        {CFE_SB_MSGID_WRAP_VALUE(FPRIME_TICK_MID), 100, 0},
        /* Wake the raw cFS commander every 10 seconds (every 1000 ticks) */
        {CFE_SB_MSGID_WRAP_VALUE(RAW_COMMANDER_WAKEUP_MID), 1000, 0},
    }
};

CFE_TBL_FILEDEF(Schedule, SCH_LAB.Schedule, Schedule Lab MsgID Table, sch_lab_table.tbl)
