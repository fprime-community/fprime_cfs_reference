####
# cosmos/cmake/cosmos_plugin.cmake:
#
# COSMOS plugin for the reference: the unmodified nasa/cfs-cosmos-plugin (submodule cosmos/cfs-cosmos-plugin) plus one
# generated top-level COSMOS target per F Prime deployment (fprime-cfs-cosmos-one-app-one-target-generator, submodule
# libs/fprime_cfs_cosmos). The nasa submodule is never written to: it is copied into the build tree, the generated
# F Prime bundles are merged into the copy, and the gem is built from that copy.
#
# Build targets (arch build; `make cosmos_plugin` from the repository root runs the whole chain):
#   cosmos_bundles  generate the F Prime COSMOS target bundle(s) from the topology dictionaries
#   cosmos_merge    stage the nasa plugin and merge the bundles into it
#   cosmos_plugin   build the plugin gem into <arch build>/cosmos/
#
# Cache options (arch build cache, e.g. `cmake -DCOSMOS_NUM_CFS_TARGETS=2 build-artifacts/native/default_cpu1`):
#   COSMOS_PLUGIN            ON (default) to define the targets; OFF leaves the build untouched
#   COSMOS_PLUGIN_VERSION    version of the built gem (default 1.0.0)
#   COSMOS_NUM_CFS_TARGETS   number of cFS instances the nasa plugin connects to (default 1; the submodule's source
#                            says 2 and has no VARIABLE for it, so the staged copy is patched; bounded by the
#                            cfs_<n>_intf_ip VARIABLEs its plugin.txt declares)
#
# Why not the generator's own CMake route (its arch_build.cmake autocoder + fprime_cfs_cosmos_merge()): the autocoder
# wants a flag file inside the topology module, which lives in the apps/fprime_app submodule; the reference owns the
# COSMOS delivery, so it drives the same two command line tools from here instead.
#
# Prerequisites: `pip install -r requirements.txt` (installs libs/fprime_cfs_cosmos, which provides the two command
# line tools used here) and initialized submodules. Without the tools the targets are not defined (a warning says so)
# and the rest of the build is unaffected.
#
# Dependency tracking: the commands depend on the dictionaries, every file of both submodules (globbed with
# CONFIGURE_DEPENDS so a submodule bump is seen without reconfiguring by hand) and cosmos/config.txt, which records
# the cache options above and both file lists; Makefiles would otherwise notice neither an option change nor a
# removed file.
####
option(COSMOS_PLUGIN "Define the COSMOS plugin build targets (cosmos_bundles, cosmos_merge, cosmos_plugin)" ON)
set(COSMOS_PLUGIN_VERSION "1.0.0" CACHE STRING "Version of the built COSMOS plugin gem")
set(COSMOS_NUM_CFS_TARGETS "1" CACHE STRING "Number of cFS instances the COSMOS plugin connects to")

if (NOT COSMOS_PLUGIN)
    return()
endif()

set(COSMOS_SOURCE_DIR "${CMAKE_CURRENT_LIST_DIR}/..")
set(COSMOS_PLUGIN_SOURCE "${COSMOS_SOURCE_DIR}/cfs-cosmos-plugin")
set(COSMOS_GENERATOR_SOURCE "${COSMOS_SOURCE_DIR}/../libs/fprime_cfs_cosmos")
set(COSMOS_BUILD_DIR "${CMAKE_BINARY_DIR}/cosmos")
set(COSMOS_BUNDLES_DIR "${COSMOS_BUILD_DIR}/bundles")
set(COSMOS_STAGE_DIR "${COSMOS_BUILD_DIR}/cfs-cosmos-plugin")
set(COSMOS_GEM "${COSMOS_BUILD_DIR}/openc3-cosmos-cfs-${COSMOS_PLUGIN_VERSION}.gem")

if (NOT EXISTS "${COSMOS_PLUGIN_SOURCE}/plugin.txt" OR NOT EXISTS "${COSMOS_GENERATOR_SOURCE}/pyproject.toml")
    message(FATAL_ERROR "[cosmos] submodules cosmos/cfs-cosmos-plugin and libs/fprime_cfs_cosmos are not checked out; run: git submodule update --init cosmos/cfs-cosmos-plugin libs/fprime_cfs_cosmos (or configure with -DCOSMOS_PLUGIN=OFF)")
endif()

find_program(FPRIME_TO_CFS_COSMOS_TARGET fprime-to-cfs-cosmos-target)
find_program(FPRIME_CFS_COSMOS_MERGE fprime-cfs-cosmos-merge)
if (NOT FPRIME_TO_CFS_COSMOS_TARGET OR NOT FPRIME_CFS_COSMOS_MERGE)
    message(WARNING "[cosmos] fprime-to-cfs-cosmos-target / fprime-cfs-cosmos-merge not found on PATH: the cosmos_plugin targets are not defined. Run `pip install -r requirements.txt` in the build's Python environment and reconfigure, or silence this with -DCOSMOS_PLUGIN=OFF")
    return()
endif()

if (NOT COSMOS_NUM_CFS_TARGETS MATCHES "^[1-9][0-9]*$")
    message(FATAL_ERROR "[cosmos] COSMOS_NUM_CFS_TARGETS must be a positive integer, got '${COSMOS_NUM_CFS_TARGETS}'")
endif()

# Everything the installed generator was built from: a libs/fprime_cfs_cosmos bump (followed by pip install) must
# regenerate and re-merge even when no dictionary changed.
file(GLOB_RECURSE COSMOS_GENERATOR_SOURCES CONFIGURE_DEPENDS LIST_DIRECTORIES false
     "${COSMOS_GENERATOR_SOURCE}/src/*" "${COSMOS_GENERATOR_SOURCE}/pyproject.toml")
list(FILTER COSMOS_GENERATOR_SOURCES EXCLUDE REGEX "/__pycache__/")
# Every file of the nasa plugin (the submodule's .git is a gitlink file)
file(GLOB_RECURSE COSMOS_PLUGIN_SOURCES CONFIGURE_DEPENDS LIST_DIRECTORIES false "${COSMOS_PLUGIN_SOURCE}/*")
list(FILTER COSMOS_PLUGIN_SOURCES EXCLUDE REGEX "/\\.git(/|$)")

# Cache options and the two file lists as one file dependency: Makefiles track neither command-line changes nor a
# file that disappeared from a DEPENDS list (a removed nasa file would otherwise linger in the stage). The timestamp
# only moves when the content changes.
set(COSMOS_CONFIG_STAMP "${COSMOS_BUILD_DIR}/config.txt")
string(REPLACE ";" "\n" COSMOS_PLUGIN_SOURCE_LIST "${COSMOS_PLUGIN_SOURCES}")
string(REPLACE ";" "\n" COSMOS_GENERATOR_SOURCE_LIST "${COSMOS_GENERATOR_SOURCES}")
file(WRITE "${COSMOS_CONFIG_STAMP}.in"
     "num_cfs_targets=${COSMOS_NUM_CFS_TARGETS}\nversion=${COSMOS_PLUGIN_VERSION}\n"
     "generate=${FPRIME_TO_CFS_COSMOS_TARGET}\nmerge=${FPRIME_CFS_COSMOS_MERGE}\n"
     "[plugin sources]\n${COSMOS_PLUGIN_SOURCE_LIST}\n[generator sources]\n${COSMOS_GENERATOR_SOURCE_LIST}\n")
configure_file("${COSMOS_CONFIG_STAMP}.in" "${COSMOS_CONFIG_STAMP}" COPYONLY)

####
# cosmos_add_fprime_target(DEPLOYMENT <name> TARGET_NAME <COSMOS target> DICTIONARY <json> DICTIONARY_TARGET <target>)
#
# Register one F Prime deployment as a generated COSMOS target bundle. Call it once per F Prime app.
#
# DEPLOYMENT         F Prime deployment name (reporting only)
# TARGET_NAME        COSMOS target name (one top-level target per app); letters, digits and underscores
# DICTIONARY         path of the deployment's JSON topology dictionary in this build
# DICTIONARY_TARGET  CMake target that produces that dictionary
####
function(cosmos_add_fprime_target)
    cmake_parse_arguments(APP "" "DEPLOYMENT;TARGET_NAME;DICTIONARY;DICTIONARY_TARGET" "" ${ARGN})
    foreach(REQUIRED DEPLOYMENT TARGET_NAME DICTIONARY DICTIONARY_TARGET)
        if ("${APP_${REQUIRED}}" STREQUAL "")
            message(FATAL_ERROR "[cosmos] cosmos_add_fprime_target: ${REQUIRED} is required")
        endif()
    endforeach()
    if (NOT APP_TARGET_NAME MATCHES "^[A-Za-z0-9_]+$")
        message(FATAL_ERROR "[cosmos] cosmos_add_fprime_target: TARGET_NAME '${APP_TARGET_NAME}' must match [A-Za-z0-9_]+")
    endif()
    set(BUNDLE_DIR "${COSMOS_BUNDLES_DIR}/${APP_TARGET_NAME}")
    set(MANIFEST "${BUNDLE_DIR}/manifest.json")
    add_custom_command(
        OUTPUT "${MANIFEST}"
        COMMAND "${CMAKE_COMMAND}" -E rm -rf "${BUNDLE_DIR}"
        COMMAND "${FPRIME_TO_CFS_COSMOS_TARGET}"
                --dictionary "${APP_DICTIONARY}" --output "${COSMOS_BUNDLES_DIR}" --target-name "${APP_TARGET_NAME}"
        DEPENDS "${APP_DICTIONARY}" "${APP_DICTIONARY_TARGET}" ${COSMOS_GENERATOR_SOURCES} "${COSMOS_CONFIG_STAMP}"
        COMMENT "[cosmos] Generating COSMOS target ${APP_TARGET_NAME} from ${APP_DEPLOYMENT}"
        VERBATIM
    )
    set(COSMOS_BUNDLE_MANIFESTS ${COSMOS_BUNDLE_MANIFESTS} "${MANIFEST}" PARENT_SCOPE)
    set(COSMOS_BUNDLE_DIRS ${COSMOS_BUNDLE_DIRS} "${BUNDLE_DIR}" PARENT_SCOPE)
    set(COSMOS_TARGET_NAMES ${COSMOS_TARGET_NAMES} "${APP_TARGET_NAME}" PARENT_SCOPE)
endfunction()

# One COSMOS target per F Prime app in this mission
cosmos_add_fprime_target(
    DEPLOYMENT FPrimeDeployment
    TARGET_NAME FPRIME_APP
    DICTIONARY "${CMAKE_BINARY_DIR}/apps/fprime_app/FPrimeDeployment/Top/FPrimeDeploymentTopologyDictionary.json"
    DICTIONARY_TARGET FPrimeDeployment_Top_dictionary
)
add_custom_target(cosmos_bundles DEPENDS ${COSMOS_BUNDLE_MANIFESTS})

# Stage: fresh copy of the nasa plugin (minus the submodule's .git link), patched for COSMOS_NUM_CFS_TARGETS, then the
# registered F Prime bundles (and only those) merged in. Rebuilt from scratch whenever a bundle, an option or any
# plugin source file changes. The stamp lives inside the stage so deleting the stage by hand also invalidates it; the
# gemspec's globs skip dotfiles, so it never ships.
set(COSMOS_STAGE_STAMP "${COSMOS_STAGE_DIR}/.stage.stamp")
add_custom_command(
    OUTPUT "${COSMOS_STAGE_STAMP}"
    COMMAND "${CMAKE_COMMAND}" -E rm -rf "${COSMOS_STAGE_DIR}"
    COMMAND "${CMAKE_COMMAND}" -E copy_directory "${COSMOS_PLUGIN_SOURCE}" "${COSMOS_STAGE_DIR}"
    COMMAND "${CMAKE_COMMAND}" -E rm -rf "${COSMOS_STAGE_DIR}/.git"
    COMMAND "${CMAKE_COMMAND}" -DCOUNT=${COSMOS_NUM_CFS_TARGETS}
            "-DFILE=${COSMOS_STAGE_DIR}/targets/CFS_FLEET/lib/cfs_fleet_globals.rb"
            "-DPLUGIN_TXT=${COSMOS_STAGE_DIR}/plugin.txt"
            -P "${CMAKE_CURRENT_LIST_DIR}/patch_num_cfs_targets.cmake"
    COMMAND "${FPRIME_CFS_COSMOS_MERGE}" --plugin "${COSMOS_STAGE_DIR}" --force ${COSMOS_BUNDLE_DIRS}
    COMMAND "${CMAKE_COMMAND}" -E touch "${COSMOS_STAGE_STAMP}"
    DEPENDS ${COSMOS_BUNDLE_MANIFESTS} ${COSMOS_PLUGIN_SOURCES} ${COSMOS_GENERATOR_SOURCES} "${COSMOS_CONFIG_STAMP}"
            "${CMAKE_CURRENT_LIST_DIR}/patch_num_cfs_targets.cmake"
    COMMENT "[cosmos] Staging nasa/cfs-cosmos-plugin and merging F Prime targets into ${COSMOS_STAGE_DIR}"
    VERBATIM
)
add_custom_target(cosmos_merge DEPENDS "${COSMOS_STAGE_STAMP}")

# Gem, then a content check of what was built (F Prime targets and helpers present, F Prime MAP_TARGETs before the CFS
# ones, patched instance count) so a regression in either submodule fails the build instead of shipping.
add_custom_command(
    OUTPUT "${COSMOS_GEM}"
    COMMAND "${COSMOS_SOURCE_DIR}/build-plugin.sh" "${COSMOS_STAGE_DIR}" "${COSMOS_PLUGIN_VERSION}" "${COSMOS_BUILD_DIR}"
    COMMAND "${COSMOS_SOURCE_DIR}/check-plugin.sh" "${COSMOS_STAGE_DIR}" "${COSMOS_GEM}" "${COSMOS_NUM_CFS_TARGETS}"
            ${COSMOS_TARGET_NAMES}
    DEPENDS "${COSMOS_STAGE_STAMP}" "${COSMOS_SOURCE_DIR}/build-plugin.sh" "${COSMOS_SOURCE_DIR}/check-plugin.sh"
    COMMENT "[cosmos] Building and checking ${COSMOS_GEM}"
    VERBATIM
)
add_custom_target(cosmos_plugin DEPENDS "${COSMOS_GEM}")
