#!/usr/bin/env bash
# Check a built COSMOS plugin against what the reference build promised.
#
#   check-plugin.sh <staged-plugin-dir> <gem> <num-cfs-targets> <bundle-dir>...
#
# Each bundle's manifest.json (written by fprime-to-cfs-cosmos-target) names the target, the files the merge must have
# placed (target_files, shared_files) and the compatibility helpers it requires. Fails when any of those is missing from
# the staged tree or the gem, when an F Prime MAP_TARGET does not precede every other MAP_TARGET in plugin.txt (nasa's
# ID-less file packets would then swallow every F Prime packet), or when the staged instance count is not the requested
# one. Needs python3 for the JSON.
set -euo pipefail

if [ $# -lt 4 ]; then
    echo "usage: $0 <staged-plugin-dir> <gem> <num-cfs-targets> <bundle-dir>..." >&2
    exit 2
fi
stage=$1; gem=$2; count=$3; shift 3
status=0
fail() { echo "check-plugin: $*" >&2; status=1; }

[ -f "$gem" ] || { echo "check-plugin: $gem is not a file" >&2; exit 1; }
gem_files=$(tar -xOf "$gem" data.tar.gz | tar -tz)
plugin_txt="$stage/plugin.txt"

# plugin.txt: nasa maps its own target(s) through ERB (MAP_TARGET <%= cfs_target_name_from_cpu_num(...) %>), the merge
# maps generated targets through plugin variables (<%= fprime_<target>_target_name %>) or literally. Every F Prime
# mapping must come before every other one.
map_lines=$(grep -nE '^[[:space:]]*MAP_TARGET[[:space:]]' "$plugin_txt" || true)
[ -n "$map_lines" ] || fail "plugin.txt has no MAP_TARGET lines"
first_other=$(grep -vE 'MAP_TARGET[[:space:]]+(<%=[^%]*fprime_[a-z0-9_]*_target_name[^%]*%>|[A-Za-z0-9_]+)[[:space:]]*$' <<<"$map_lines" | head -1 | cut -d: -f1 || true)
[ -n "$first_other" ] || fail "plugin.txt has no CFS MAP_TARGET (nasa plugin layout changed?)"

targets=()
for bundle in "$@"; do
    manifest="$bundle/manifest.json"
    [ -f "$manifest" ] || { fail "$manifest missing"; continue; }
    target=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["target"])' "$manifest")
    targets+=("$target")
    # files the merge placed: directories in the manifest expand to every file the bundle holds under them
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        [ -f "$stage/$f" ] || fail "stage lacks $f (from $target manifest)"
        grep -qxF "$f" <<<"$gem_files" || fail "gem lacks $f (from $target manifest)"
    done < <(python3 - "$manifest" "$bundle" <<'PY'
import json, os, sys
manifest, bundle = json.load(open(sys.argv[1])), sys.argv[2]
for entry in manifest.get("target_files", []) + manifest.get("shared_files", []):
    path = os.path.join(bundle, entry)
    if os.path.isdir(path):
        for root, _, files in os.walk(path):
            for name in sorted(files):
                print(os.path.relpath(os.path.join(root, name), bundle))
    else:
        print(entry)
for helper in manifest.get("required_helpers", []):
    print(f"lib/{helper}.rb")
PY
)
    literal_target=$(grep -E "MAP_TARGET[[:space:]]+${target}[[:space:]]*$" <<<"$map_lines" | head -1 | cut -d: -f1 || true)
    variable_target=$(grep -E "MAP_TARGET[[:space:]]+<%=[^%]*fprime_${target,,}_target_name[^%]*%>[[:space:]]*$" <<<"$map_lines" | head -1 | cut -d: -f1 || true)
    fprime_line=${variable_target:-$literal_target}
    [ -n "$fprime_line" ] || fail "plugin.txt has no MAP_TARGET for $target"
    if [ -n "$fprime_line" ] && [ -n "$first_other" ] && [ "$fprime_line" -gt "$first_other" ]; then
        fail "plugin.txt maps $target (line $fprime_line) after the CFS target (line $first_other)"
    fi
done

grep -qxF plugin.txt <<<"$gem_files" || fail "gem lacks plugin.txt"
grep -qxF targets/CFS_FLEET/lib/cfs_fleet_globals.rb <<<"$gem_files" || fail "gem lacks nasa's CFS_FLEET target"

globals="$stage/targets/CFS_FLEET/lib/cfs_fleet_globals.rb"
grep -qE "^[[:space:]]*\\\$cfs_fleet_globals_num_cfs_targets[[:space:]]*=[[:space:]]*${count}([[:space:]#]|$)" "$globals" \
    || fail "$globals does not set \$cfs_fleet_globals_num_cfs_targets = $count"

if [ "$status" -eq 0 ]; then
    echo "check-plugin: OK ($gem: ${#targets[@]} F Prime target(s) [${targets[*]}], $count cFS instance(s), $(wc -l <<<"$gem_files") files)"
fi
exit "$status"
