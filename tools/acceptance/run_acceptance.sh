#!/usr/bin/env bash
# Normal acceptance run for se-defense: parse -> dry-check (advisory) -> generate -> run.
# Run from anywhere; the script cd's to the repository root.
# Needs Lua 5.4 (tools/pick-lua.sh) and the acceptance4lua rock (auto-installed
# into .toolcache/luarocks). Game steps boot src/server/main.lua headlessly via
# tools/acceptance/headless.lua; see tools/acceptance/README.md.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
. ./tools/pick-lua.sh
LUA="$(pick_lua)"

GEN_DIR="build/acceptance/generated"
IR_DIR="build/acceptance/ir"
DRY_DIR="build/acceptance/dry"
# Reset generated specs first: stale stems from renamed features would otherwise pile up.
rm -rf "$GEN_DIR"
mkdir -p "$GEN_DIR" "$IR_DIR" "$DRY_DIR"

shopt -s nullglob
features=(features/*.feature)
if [ "${#features[@]}" -eq 0 ]; then
  echo "no feature files under features/" >&2
  exit 1
fi

LUA_PATH_FOR_SPECS="$("$LUA" -e 'package.path="./?.lua;"..package.path; io.write(require("tools.acceptance.bootstrap").lua_path())')"

fail=0
for feature in "${features[@]}"; do
  echo "== $feature"
  stem="$(basename "$feature" .feature)"
  tools/acceptance/gherkin-parser "$feature" "$IR_DIR/$stem.json"
  tools/acceptance/ir-dry-checker "$IR_DIR/$stem.json" "$DRY_DIR/$stem.json" || true
  mkdir -p "$GEN_DIR/$stem"
  tools/acceptance/entrypoint_generator "$IR_DIR/$stem.json" "$GEN_DIR/$stem/feature_acceptance_spec.lua"
  if ! ACCEPTANCE_FEATURE_JSON="$IR_DIR/$stem.json" LUA_PATH="$LUA_PATH_FOR_SPECS" \
       "$LUA" "$GEN_DIR/$stem/feature_acceptance_spec.lua"; then
    echo "FAILED: $feature" >&2
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  echo "acceptance run FAILED" >&2
  exit 1
fi
echo "acceptance run OK"
