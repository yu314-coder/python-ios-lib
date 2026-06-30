#!/bin/bash
# Rebuild the host-native Blender code generators so they MATCH the current
# target (iOS) configuration. makesrna/makesdna bake the active WITH_* flags into
# the C source they emit, so whenever an RNA/DNA-affecting flag changes, the host
# generators must be regenerated or the target build hits "undeclared identifier"
# mismatches (e.g. rna_fluid_gen.cc vs WITH_MOD_FLUID).
#
# build_host_tools.py harvests compile commands from build/blender's build.ninja,
# but the IMPORTED-target patch removes the generator build rules. So we toggle:
#   1. reconfigure WITHOUT HOST_TOOLS_DIR  -> generators are native (rules exist)
#   2. build host tools (harvest + strip iOS triple + host link)
#   3. reconfigure WITH HOST_TOOLS_DIR     -> generators IMPORTED again
set -e
set -o pipefail   # so a failed host-tool build in a pipe isn't masked by tail
cd "$(dirname "$0")"
export DEVELOPER_DIR=/Volumes/D/Xcode.app/Contents/Developer TMPDIR=/Volumes/D/tmp
B=build/blender

echo "== [1/3] reconfigure WITHOUT HOST_TOOLS_DIR (expose native generator rules) =="
cmake "$B" -U HOST_TOOLS_DIR > "$B"/host_toggle_off.log 2>&1
echo "   done ($(grep -c 'Generating done' "$B"/host_toggle_off.log))"

echo "== [2/3] build host generators =="
export HOST_EXTRA_LIBS="$PWD/build/host-fmt/libfmt.a"
python3 build_host_tools.py bin/makesdna.app/makesdna   makesdna    | tail -1
python3 build_host_tools.py bin/datatoc.app/datatoc     datatoc     | tail -1
python3 build_host_tools.py bin/shader_tool.app/shader_tool shader_tool | tail -1
python3 build_host_tools.py bin/makesrna.app/makesrna   makesrna    | tail -1

echo "== [3/3] reconfigure WITH HOST_TOOLS_DIR (generators IMPORTED) =="
cmake "$B" -DHOST_TOOLS_DIR="$PWD/build/host-tools" > "$B"/host_toggle_on.log 2>&1
echo "   done ($(grep -c 'Generating done' "$B"/host_toggle_on.log))"
echo "host tools rebuilt + reconfigured."
