#!/usr/bin/env bash
# Build the staged COSMOS plugin tree into a gem.
#
#   build-plugin.sh <staged-plugin-dir> <version> <output-dir>
#
# COSMOS_GEM_BUILDER=auto (default: the host `gem` when available, otherwise docker) | host | docker. The docker builder
# runs `gem` in the OpenC3 cmd-tlm-api image (override with COSMOS_IMAGE) so no Ruby install is needed. Prints the path
# of the built gem.
set -euo pipefail

if [ $# -ne 3 ]; then
    echo "usage: $0 <staged-plugin-dir> <version> <output-dir>" >&2
    exit 2
fi
stage=$(realpath "$1")
version=$2
out=$(realpath -m "$3")
gemspec=openc3-cosmos-cfs.gemspec

if [ ! -f "$stage/plugin.txt" ] || [ ! -f "$stage/$gemspec" ]; then
    echo "$0: $stage is not a staged nasa/cfs-cosmos-plugin tree (plugin.txt / $gemspec missing)" >&2
    exit 1
fi
mkdir -p "$out"
rm -f "$stage"/*.gem

builder=${COSMOS_GEM_BUILDER:-auto}
if [ "$builder" = auto ]; then
    if command -v gem >/dev/null 2>&1; then builder=host; else builder=docker; fi
fi
case "$builder" in
host)
    (cd "$stage" && VERSION="$version" gem build --quiet "$gemspec")
    ;;
docker)
    image=${COSMOS_IMAGE:-openc3inc/openc3-cosmos-cmd-tlm-api:7.5.1}
    docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -e VERSION="$version" \
        -v "$stage:/plugin" -w /plugin "$image" gem build --quiet "$gemspec"
    ;;
*)
    echo "$0: COSMOS_GEM_BUILDER must be auto, host or docker, got '$builder'" >&2
    exit 2
    ;;
esac

built=$(ls "$stage"/*.gem)
mv "$built" "$out/"
echo "$out/$(basename "$built")"
