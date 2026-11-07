#!/usr/bin/env bash
# Check a built COSMOS plugin against what the reference build promised.
#
#   check-plugin.sh <staged-plugin-dir> <gem> <num-cfs-targets> <fprime target>...
#
# Fails when the staged tree or the gem lacks an F Prime target or the merge's compatibility helpers, when an F Prime
# MAP_TARGET does not precede the first CFS MAP_TARGET in plugin.txt (nasa's ID-less file packets would then swallow
# every F Prime packet), or when the staged instance count is not the requested one.
set -euo pipefail

if [ $# -lt 4 ]; then
    echo "usage: $0 <staged-plugin-dir> <gem> <num-cfs-targets> <fprime target>..." >&2
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
first_other=$(grep -vE "MAP_TARGET[[:space:]]+(<%=[^%]*fprime_[a-z0-9_]*_target_name[^%]*%>|$(IFS='|'; echo "$*"))[[:space:]]*$" <<<"$map_lines" | head -1 | cut -d: -f1 || true)
[ -n "$first_other" ] || fail "plugin.txt has no CFS MAP_TARGET (nasa plugin layout changed?)"

for target in "$@"; do
    for f in "targets/$target/target.txt" "targets/$target/cmd_tlm/fprime_cmd.txt" "targets/$target/cmd_tlm/fprime_tlm.txt"; do
        [ -f "$stage/$f" ] || fail "stage lacks $f"
        grep -qxF "$f" <<<"$gem_files" || fail "gem lacks $f"
    done
    fprime_line=$(grep -E "MAP_TARGET[[:space:]]+(<%=[^%]*fprime_${target,,}_target_name[^%]*%>|$target)[[:space:]]*$" <<<"$map_lines" | head -1 | cut -d: -f1 || true)
    [ -n "$fprime_line" ] || fail "plugin.txt has no MAP_TARGET for $target"
    if [ -n "$fprime_line" ] && [ -n "$first_other" ] && [ "$fprime_line" -gt "$first_other" ]; then
        fail "plugin.txt maps $target (line $fprime_line) after the CFS target (line $first_other)"
    fi
done

for helper in lib/global_defs.rb lib/cfs_ccsds.rb lib/fsw_msg_id.rb lib/fsw_config_param.rb; do
    [ -f "$stage/$helper" ] || fail "stage lacks compatibility helper $helper"
    grep -qxF "$helper" <<<"$gem_files" || fail "gem lacks compatibility helper $helper"
done
grep -qxF plugin.txt <<<"$gem_files" || fail "gem lacks plugin.txt"
grep -qxF targets/CFS_FLEET/lib/cfs_fleet_globals.rb <<<"$gem_files" || fail "gem lacks nasa's CFS_FLEET target"

globals="$stage/targets/CFS_FLEET/lib/cfs_fleet_globals.rb"
grep -qE "^[[:space:]]*\\\$cfs_fleet_globals_num_cfs_targets[[:space:]]*=[[:space:]]*${count}[[:space:]]*$" "$globals" \
    || fail "$globals does not set \$cfs_fleet_globals_num_cfs_targets = $count"

if [ "$status" -eq 0 ]; then
    echo "check-plugin: OK ($gem: $# F Prime target(s) [$*], $count cFS instance(s), $(wc -l <<<"$gem_files") files)"
fi
exit "$status"
