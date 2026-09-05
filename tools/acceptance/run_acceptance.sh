#!/usr/bin/env bash
# Normal acceptance run for se-defense: parse -> dry-check (advisory) -> generate -> run.
# Run from anywhere; the script cd's to the repository root.
# Needs Lua 5.4 (scripts/pick-lua.sh) and the acceptance4lua rock (auto-installed
# into .toolcache/luarocks). The business tree examples/base_defence must be
# resolvable; see tools/acceptance/README.md (SE_DEFENSE_BUSINESS_DIR).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
. ./scripts/pick-lua.sh
LUA="$(pick_lua)"

GEN_DIR="acceptance/generated"
IR_DIR="build/acceptance/ir"
DRY_DIR="build/acceptance/dry"
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
