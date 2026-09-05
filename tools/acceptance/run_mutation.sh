#!/usr/bin/env bash
# APS Gherkin acceptance mutation run for se-defense (differential hard by
# default). Usage: run_mutation.sh [feature-file] [extra gherkin-mutator args]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

FEATURE="${1:-features/base-defence.feature}"
shift 2>/dev/null || true
if [ ! -f "$FEATURE" ]; then
  echo "feature not found: $FEATURE" >&2
  exit 2
fi

WORK="build/acceptance-mutation"
mkdir -p "$WORK"
exec tools/acceptance/gherkin-mutator --feature "$FEATURE" --work-dir "$WORK" \
  --runner-worker "tools/acceptance/runner_adapter" "$@"
