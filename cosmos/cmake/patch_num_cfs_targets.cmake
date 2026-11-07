####
# patch_num_cfs_targets.cmake: set the number of cFS instances in a STAGED copy of nasa/cfs-cosmos-plugin.
#
#   cmake -DFILE=<stage>/targets/CFS_FLEET/lib/cfs_fleet_globals.rb -DCOUNT=<n> [-DPLUGIN_TXT=<stage>/plugin.txt] -P ...
#
# The plugin hard-codes `$cfs_fleet_globals_num_cfs_targets = 2` (no plugin VARIABLE). Exactly one such assignment at
# the start of a line (comments do not count) must exist, or the plugin layout changed and this script must be revisited.
# With PLUGIN_TXT, every instance 1..COUNT must have its `VARIABLE cfs_<n>_intf_ip` declaration in the plugin; a
# count beyond them builds a gem that only fails at `openc3.sh cli load`.
####
if (NOT DEFINED FILE OR NOT DEFINED COUNT OR FILE STREQUAL "" OR COUNT STREQUAL "")
    message(FATAL_ERROR "patch_num_cfs_targets.cmake: FILE and COUNT are required")
endif()
if (NOT COUNT MATCHES "^[1-9][0-9]*$")
    message(FATAL_ERROR "patch_num_cfs_targets.cmake: COUNT must be a positive integer, got '${COUNT}'")
endif()
if (NOT EXISTS "${FILE}")
    message(FATAL_ERROR "patch_num_cfs_targets.cmake: ${FILE} does not exist")
endif()
if (DEFINED PLUGIN_TXT AND NOT PLUGIN_TXT STREQUAL "")
    file(READ "${PLUGIN_TXT}" PLUGIN_CONTENT)
    foreach(INDEX RANGE 1 ${COUNT})
        if (NOT PLUGIN_CONTENT MATCHES "(^|\n)[ \t]*VARIABLE[ \t]+cfs_${INDEX}_intf_ip[ \t]")
            message(FATAL_ERROR "patch_num_cfs_targets.cmake: COUNT=${COUNT} but ${PLUGIN_TXT} declares no VARIABLE cfs_${INDEX}_intf_ip (instance ${INDEX} would render as an error at plugin load)")
        endif()
    endforeach()
endif()
file(READ "${FILE}" CONTENT)
set(PATTERN "(^|\n)([ \t]*)\\$cfs_fleet_globals_num_cfs_targets[ \t]*=[ \t]*[0-9]+")
string(REGEX MATCHALL "${PATTERN}" ASSIGNMENTS "${CONTENT}")
list(LENGTH ASSIGNMENTS ASSIGNMENT_COUNT)
if (NOT ASSIGNMENT_COUNT EQUAL 1)
    message(FATAL_ERROR "patch_num_cfs_targets.cmake: expected exactly one '$cfs_fleet_globals_num_cfs_targets = <n>' line in ${FILE}, found ${ASSIGNMENT_COUNT}; the nasa plugin layout changed, update cosmos/cmake")
endif()
string(REGEX REPLACE "${PATTERN}" "\\1\\2$cfs_fleet_globals_num_cfs_targets = ${COUNT}" CONTENT "${CONTENT}")
file(WRITE "${FILE}" "${CONTENT}")
