#!/usr/bin/env bash
# Normal acceptance run for se-defense: parse -> dry-check -> generate -> run.
# Run from the repository root (the script cd's there itself).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

GEN_DIR="acceptance/generated"
IR_DIR="build/acceptance/ir"
DRY_DIR="build/acceptance/dry"
mkdir -p "$GEN_DIR" "$IR_DIR" "$DRY_DIR"

slug() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g'
}

shopt -s nullglob
features=(features/*.feature)
if [ "${#features[@]}" -eq 0 ]; then
  echo "no feature files under features/" >&2
  exit 1
fi

fail=0
for feature in "${features[@]}"; do
  echo "== $feature"
  stem="$(basename "$feature" .feature)"
  gherkin-parser "$feature" "$IR_DIR/$stem.json"
  # Advisory only: the dry checker never gates the run.
  ir-dry-checker "$IR_DIR/$stem.json" "$DRY_DIR/$stem.json" || true
  ACCEPTANCE_FEATURE_PATH="$feature" tools/acceptance/entrypoint_generator "$IR_DIR/$stem.json" "$GEN_DIR"
  test_file="$GEN_DIR/$(slug "$feature")_acceptance_test.clj"
  if ! "$test_file"; then
    echo "FAILED: $feature ($test_file)" >&2
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  echo "acceptance run FAILED" >&2
  exit 1
fi
echo "acceptance run OK"
