####
# patch_num_cfs_targets.cmake: `cmake -DFILE=<cfs_fleet_globals.rb> -DCOUNT=<n> -P patch_num_cfs_targets.cmake`
#
# nasa/cfs-cosmos-plugin hard-codes the number of cFS instances in targets/CFS_FLEET/lib/cfs_fleet_globals.rb (no plugin
# VARIABLE). Rewrite that assignment in the staged copy; fail if the file no longer has the expected line.
####
if (NOT FILE OR NOT COUNT)
    message(FATAL_ERROR "patch_num_cfs_targets.cmake: FILE and COUNT are required")
endif()
if (NOT COUNT MATCHES "^[1-9][0-9]*$")
    message(FATAL_ERROR "patch_num_cfs_targets.cmake: COUNT must be a positive integer, got '${COUNT}'")
endif()
file(READ "${FILE}" CONTENT)
set(PATTERN "\\$cfs_fleet_globals_num_cfs_targets[ \t]*=[ \t]*[0-9]+")
if (NOT CONTENT MATCHES "${PATTERN}")
    message(FATAL_ERROR "patch_num_cfs_targets.cmake: no '$cfs_fleet_globals_num_cfs_targets = <n>' line in ${FILE}; the nasa plugin layout changed, update cosmos/cmake")
endif()
string(REGEX REPLACE "${PATTERN}" "$cfs_fleet_globals_num_cfs_targets = ${COUNT}" CONTENT "${CONTENT}")
file(WRITE "${FILE}" "${CONTENT}")
