#!/usr/bin/env bash
# APS Gherkin acceptance mutation run for se-defense (differential hard by
# default). Usage: run_mutation.sh [feature-file] [extra gherkin-mutator args]
# Without an argument, mutates every feature under features/ (all subdirectory
# lanes: gameplay / presentation / engineering) one at a time.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

shopt -s nullglob
if [ "${1:-}" != "" ] && [[ "$1" == *.feature ]]; then
  if [ ! -f "$1" ]; then
    echo "feature not found: $1" >&2
    exit 2
  fi
  features=("$1")
  shift
else
  features=(features/*.feature features/*/*.feature)
fi
if [ "${#features[@]}" -eq 0 ]; then
  echo "no feature files under features/" >&2
  exit 2
fi

fail=0
for feature in "${features[@]}"; do
  stem="$(echo "${feature#features/}" | sed 's|/|_|g; s|\.feature$||')"
  work="build/acceptance-mutation/$stem"
  mkdir -p "$work"
  echo "== $feature"
  if ! tools/acceptance/gherkin-mutator --feature "$feature" --work-dir "$work" \
       --runner-worker "tools/acceptance/runner_adapter" "$@"; then
    echo "MUTATION FAILED: $feature" >&2
    fail=1
  fi
done
exit "$fail"
