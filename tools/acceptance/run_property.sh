#!/usr/bin/env bash
# Property test run for the acceptance pipeline (test.check, separate command
# from normal verification). Run from the repository root.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

exec clojure -Sdeps '{:paths ["src" "spec-property"]
                      :deps {speclj/speclj {:mvn/version "3.13.0"}
                             org.clojure/test.check {:mvn/version "1.1.1"}}}' \
  -M -m speclj.main -c spec-property
