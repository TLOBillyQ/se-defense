# se-defense acceptance pipeline

APS (Acceptance Pipeline Specification) Gherkin acceptance for the headless
game. All pipeline code is project language (Babashka); the game is driven
through a thin Lua protocol server on top of the existing SE stub harness.

## Layout

- `features/*.feature` — Gherkin features exercising real headless game
  behavior (server `main.lua` + host adapters + `tools/headless/se_stub.lua`).
- `src/acceptance/` — project-specific pipeline components:
  - `generator.clj` — entrypoint generator (thin generated tests + metadata).
  - `runtime.clj` — scenario execution expansion, step dispatch, reports.
  - `handlers.clj` — Gherkin step handlers bridging to the Lua acceptance
    server; regex captures resolve to example values by column name.
  - `lua_bridge.clj` — one headless Lua process per scenario execution.
  - `adapter.clj` — persistent runner adapter for `gherkin-mutator`.
  - `json.clj` — dependency-free JSON codec (bb + JVM Clojure).
- `tools/headless/acceptance_server.lua` — NDJSON command server over the game.
- `tools/acceptance/` — convenience scripts:
  - `entrypoint_generator` — `acceptance-entrypoint-generator <ir> <out>`.
  - `runner_adapter` — NDJSON worker; stdout is protocol only.
  - `run_acceptance.sh` — normal acceptance: parse, gherkin-ir-dry-check
    (advisory), generate, run every feature.
  - `run_mutation.sh [feature]` — acceptance mutation (differential, hard).
- `spec/acceptance/*_spec.clj` — Speclj unit specs for the pipeline components.
- `build/acceptance/`, `acceptance/generated/` — generated artifacts
  (gitignored); generated metadata `implementation_hash` covers generated
  acceptance files only.

## Commands

```sh
tools/acceptance/run_acceptance.sh            # normal acceptance run
tools/acceptance/run_mutation.sh              # mutation run (default feature)
tools/acceptance/run_property.sh              # property tests (test.check, separate command)
speclj                                        # pipeline unit specs
```

Property tests live under `spec-property/`, outside `spec/`, so they are not
picked up by unit coverage (Cloverage), CRAP, language mutation, or Gherkin
mutation runs.

Run everything from the repository root: generated tests and the Lua server
resolve project paths relative to it.
