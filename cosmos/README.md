# COSMOS plugin for the F Prime cFS reference

One COSMOS plugin gem carrying both ground styles side by side on the same cFS UDP link:

- the unmodified [nasa/cfs-cosmos-plugin](https://github.com/nasa/cfs-cosmos-plugin) (`cfs-cosmos-plugin/` submodule):
  cFE/cFS commands, telemetry, EVS, file packets as its `CFS-<n>` targets;
- one separate top-level COSMOS target per F Prime app (`FPRIME_APP` for `FPrimeDeployment`), generated from the F Prime
  topology dictionary by [fprime-cfs-cosmos-one-app-one-target-generator](https://github.com/LeStarch/fprime-cfs-cosmos-one-app-one-target-generator)
  (`libs/fprime_cfs_cosmos` submodule).

Nothing is written into the nasa submodule: the build copies it, patches the number of cFS instances, merges the
generated bundles into the copy (`fprime-cfs-cosmos-merge`, which also installs the compatibility helpers the generated
targets need and places the F Prime `MAP_TARGET` lines before the CFS ones) and builds the gem from the copy.

## Building

```bash
pip install -r requirements.txt           # includes libs/fprime_cfs_cosmos (generator + merge tools)
make SIMULATION=native prep
make                                      # cFS + F Prime apps, dictionaries
make cosmos_plugin                        # -> build-artifacts/native/default_cpu1/cosmos/openc3-cosmos-cfs-<version>.gem
```

Intermediate targets: `make cosmos_bundles` (generated F Prime targets under `.../cosmos/bundles/<TARGET>/`),
`make cosmos_merge` (the merged plugin tree under `.../cosmos/cfs-cosmos-plugin/`). CMake cache options (pass with
`make prep` through `PREP_OPTS`, or edit the arch build's `CMakeCache.txt`): `COSMOS_PLUGIN=OFF` skips all of this,
`COSMOS_PLUGIN_VERSION` sets the gem version (default `1.0.0`), `COSMOS_NUM_CFS_TARGETS` the number of cFS instances
the nasa plugin connects to (default 1; its source hard-codes 2). Ruby's `gem` is used when installed, otherwise the
build runs it in the OpenC3 `cmd-tlm-api` container (`COSMOS_IMAGE` to override the image).

CI builds the gem on every push and publishes it with `vars.json` and `compose.override.yaml` as the `cosmos-plugin`
artifact, after rendering the generated target against the real openc3 gem (`libs/fprime_cfs_cosmos/tests/cosmos/run.sh`).

Adding another F Prime app is one `cosmos_add_fprime_target(...)` call in `cmake/cosmos_plugin.cmake`.

## Running

1. COSMOS project ([openc3-project](https://github.com/OpenC3/cosmos-project)): copy `compose.override.yaml` next to its
   `compose.yaml` (publishes UDP 2234 on the operator so cFS `to_lab` telemetry reaches the plugin's `CFS-1`
   interface), then `./openc3.sh run`.
2. Install the plugin with the variables for this reference (`vars.json`):

   ```bash
   ./openc3.sh cli load /path/to/openc3-cosmos-cfs-1.0.0.gem --variables /path/to/vars.json
   ```

   - `cfs_1_intf_ip`: address COSMOS sends commands to (`ci_lab`, UDP 1234). `172.18.0.1` is the gateway of the
     default `openc3-cosmos-network`, i.e. the docker host when cFS runs there; use the cFS host's address otherwise.
   - `global_tlm_output_ip`: address the plugin's TO_LAB enable-output command tells cFS to send telemetry to (UDP
     2234). `127.0.0.1` reaches the published port when cFS runs on the docker host; otherwise the COSMOS host's address.
   - `fprime_fprime_app_target_name`: name of the generated F Prime target (default `FPRIME_APP`).
3. Start the reference (`build-artifacts/exe/cpu1/core-cpu1`) and send `CFS-1 TO_LAB_ENABLE_OUTPUT` (or any command;
   the plugin's `CFS_FLEET` procedures do this) — `to_lab` sends nothing until output is enabled, and it has a single
   destination, so run COSMOS or `fprime-gds` against one cFS instance, not both.

Then `FPRIME_APP` carries the F Prime commands (`CfsCore.cmdDisp.CMD_NO_OP`, ...), channelized and packetized telemetry
(`HEALTH`, ...), and `CFS-1` the cFE/cFS ones; both targets decode on the same `CFS-1_INTF`.

## Known limitations

- F Prime event packets (stream id 0x0802) have no `FPRIME_APP` definition yet and are swallowed by the nasa catch-all
  file packets; use `fprime-gds` for events until the generator emits an EVENTS packet.
- The nasa plugin has no VARIABLE for the number of cFS instances (`$cfs_fleet_globals_num_cfs_targets`), hence the
  staged-copy patch; `COSMOS_NUM_CFS_TARGETS` greater than 1 maps the F Prime target onto every `CFS-<n>_INTF`.
- `libs/fprime_cfs_cosmos` tracks the `nasa-plugin-compat` branch of the autobot fork until the generator PR merges.
