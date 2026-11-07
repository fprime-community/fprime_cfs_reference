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
# Cache options:
#   COSMOS_PLUGIN            ON (default) to define the targets; OFF leaves the build untouched
#   COSMOS_PLUGIN_VERSION    version of the built gem (default 1.0.0)
#   COSMOS_NUM_CFS_TARGETS   number of cFS instances the nasa plugin connects to (default 1; the submodule's source
#                            says 2 and has no VARIABLE for it, so the staged copy is patched)
#
# Prerequisites: `pip install -r requirements.txt` (installs libs/fprime_cfs_cosmos, which provides the two command
# line tools used here) and initialized submodules.
####
option(COSMOS_PLUGIN "Define the COSMOS plugin build targets (cosmos_bundles, cosmos_merge, cosmos_plugin)" ON)
set(COSMOS_PLUGIN_VERSION "1.0.0" CACHE STRING "Version of the built COSMOS plugin gem")
set(COSMOS_NUM_CFS_TARGETS "1" CACHE STRING "Number of cFS instances the COSMOS plugin connects to")

if (NOT COSMOS_PLUGIN)
    return()
endif()

set(COSMOS_SOURCE_DIR "${CMAKE_CURRENT_LIST_DIR}/..")
set(COSMOS_PLUGIN_SOURCE "${COSMOS_SOURCE_DIR}/cfs-cosmos-plugin")
set(COSMOS_BUILD_DIR "${CMAKE_BINARY_DIR}/cosmos")
set(COSMOS_BUNDLES_DIR "${COSMOS_BUILD_DIR}/bundles")
set(COSMOS_STAGE_DIR "${COSMOS_BUILD_DIR}/cfs-cosmos-plugin")
set(COSMOS_GEM "${COSMOS_BUILD_DIR}/openc3-cosmos-cfs-${COSMOS_PLUGIN_VERSION}.gem")

if (NOT EXISTS "${COSMOS_PLUGIN_SOURCE}/plugin.txt")
    message(FATAL_ERROR "[cosmos] nasa/cfs-cosmos-plugin submodule is empty; run: git submodule update --init cosmos/cfs-cosmos-plugin")
endif()
find_program(FPRIME_TO_CFS_COSMOS_TARGET fprime-to-cfs-cosmos-target)
find_program(FPRIME_CFS_COSMOS_MERGE fprime-cfs-cosmos-merge)
if (NOT FPRIME_TO_CFS_COSMOS_TARGET OR NOT FPRIME_CFS_COSMOS_MERGE)
    message(FATAL_ERROR "[cosmos] fprime-to-cfs-cosmos-target / fprime-cfs-cosmos-merge not found; run: pip install -r requirements.txt (or configure with -DCOSMOS_PLUGIN=OFF)")
endif()

set(COSMOS_BUNDLE_MANIFESTS "")
####
# cosmos_add_fprime_target:
#
# Generate a COSMOS target bundle for one F Prime deployment. Call once per F Prime app in the mission.
#
# DEPLOYMENT         F Prime deployment name (the <DEPLOYMENT>TopologyDictionary.json one)
# TARGET_NAME        COSMOS target name (one top-level target per app)
# DICTIONARY         path of the deployment's JSON topology dictionary in this build
# DICTIONARY_TARGET  CMake target that produces that dictionary
####
function(cosmos_add_fprime_target)
    cmake_parse_arguments(APP "" "DEPLOYMENT;TARGET_NAME;DICTIONARY;DICTIONARY_TARGET" "" ${ARGN})
    foreach(REQUIRED DEPLOYMENT TARGET_NAME DICTIONARY DICTIONARY_TARGET)
        if (NOT APP_${REQUIRED})
            message(FATAL_ERROR "[cosmos] cosmos_add_fprime_target: ${REQUIRED} is required")
        endif()
    endforeach()
    set(BUNDLE_DIR "${COSMOS_BUNDLES_DIR}/${APP_TARGET_NAME}")
    set(MANIFEST "${BUNDLE_DIR}/manifest.json")
    add_custom_command(
        OUTPUT "${MANIFEST}"
        COMMAND "${CMAKE_COMMAND}" -E rm -rf "${BUNDLE_DIR}"
        COMMAND "${FPRIME_TO_CFS_COSMOS_TARGET}"
                --dictionary "${APP_DICTIONARY}" --output "${COSMOS_BUNDLES_DIR}" --target-name "${APP_TARGET_NAME}"
        DEPENDS "${APP_DICTIONARY}" "${APP_DICTIONARY_TARGET}"
        COMMENT "[cosmos] Generating COSMOS target ${APP_TARGET_NAME} from ${APP_DEPLOYMENT}"
        VERBATIM
    )
    set(COSMOS_BUNDLE_MANIFESTS ${COSMOS_BUNDLE_MANIFESTS} "${MANIFEST}" PARENT_SCOPE)
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
# F Prime bundles merged in. Rebuilt from scratch whenever a bundle or any plugin source file changes.
file(GLOB_RECURSE COSMOS_PLUGIN_SOURCES LIST_DIRECTORIES false "${COSMOS_PLUGIN_SOURCE}/*")
list(FILTER COSMOS_PLUGIN_SOURCES EXCLUDE REGEX "/\\.git/")
set(COSMOS_STAGE_STAMP "${COSMOS_BUILD_DIR}/stage.stamp")
add_custom_command(
    OUTPUT "${COSMOS_STAGE_STAMP}"
    COMMAND "${CMAKE_COMMAND}" -E rm -rf "${COSMOS_STAGE_DIR}"
    COMMAND "${CMAKE_COMMAND}" -E copy_directory "${COSMOS_PLUGIN_SOURCE}" "${COSMOS_STAGE_DIR}"
    COMMAND "${CMAKE_COMMAND}" -E rm -rf "${COSMOS_STAGE_DIR}/.git"
    COMMAND "${CMAKE_COMMAND}" -DCOUNT=${COSMOS_NUM_CFS_TARGETS}
            "-DFILE=${COSMOS_STAGE_DIR}/targets/CFS_FLEET/lib/cfs_fleet_globals.rb"
            -P "${CMAKE_CURRENT_LIST_DIR}/patch_num_cfs_targets.cmake"
    COMMAND "${FPRIME_CFS_COSMOS_MERGE}" --plugin "${COSMOS_STAGE_DIR}" --force ${COSMOS_BUNDLES_DIR}
    COMMAND "${CMAKE_COMMAND}" -E touch "${COSMOS_STAGE_STAMP}"
    DEPENDS ${COSMOS_BUNDLE_MANIFESTS} ${COSMOS_PLUGIN_SOURCES} "${CMAKE_CURRENT_LIST_DIR}/patch_num_cfs_targets.cmake"
    COMMENT "[cosmos] Staging nasa/cfs-cosmos-plugin and merging F Prime targets into ${COSMOS_STAGE_DIR}"
    VERBATIM
)
add_custom_target(cosmos_merge DEPENDS "${COSMOS_STAGE_STAMP}")

add_custom_command(
    OUTPUT "${COSMOS_GEM}"
    COMMAND "${COSMOS_SOURCE_DIR}/build-plugin.sh" "${COSMOS_STAGE_DIR}" "${COSMOS_PLUGIN_VERSION}" "${COSMOS_BUILD_DIR}"
    DEPENDS "${COSMOS_STAGE_STAMP}" "${COSMOS_SOURCE_DIR}/build-plugin.sh"
    COMMENT "[cosmos] Building ${COSMOS_GEM}"
    VERBATIM
)
add_custom_target(cosmos_plugin DEPENDS "${COSMOS_GEM}")
