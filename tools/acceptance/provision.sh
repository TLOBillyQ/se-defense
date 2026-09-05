#!/usr/bin/env bash
# Writes bash->Lua forwarders for the three APS PATH names into
# <project>/.swarmforge/bin so `gherkin-parser`, `ir-dry-checker` and
# `gherkin-mutator` resolve to the acceptance4lua lane when the SwarmForge
# launcher puts that directory first on PATH. Re-run after a fresh clone or
# whenever `swarm_tool.sh ensure` has replaced them with Babashka wrappers.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$ROOT/.swarmforge/bin"
mkdir -p "$BIN"
for name in gherkin-parser ir-dry-checker gherkin-mutator; do
  cat > "$BIN/$name" <<FWD
#!/usr/bin/env bash
# Forwarder written by tools/acceptance/provision.sh: acceptance4lua lane.
# Do not run \`swarm_tool.sh ensure $name\`; it would swap in the Babashka wrapper.
set -e
exec "$ROOT/tools/acceptance/$name" "\$@"
FWD
  chmod +x "$BIN/$name"
  echo "wrote $BIN/$name"
done
