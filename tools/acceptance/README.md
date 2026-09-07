# se-defense acceptance pipeline

APS (Acceptance Pipeline Specification) Gherkin acceptance for the headless
game, in Lua 5.4 on top of the Gitea `acceptance4lua` rock (repo URL in
`tools/acceptance/bootstrap.lua`, follows upstream HEAD). Features are written in Chinese (`# language: zh-CN`,
mandatory for files under `features/`).

## Layout

- `features/*.feature` — Gherkin features exercising the real headless game
  (server `main.lua` + host adapters + `tools/headless/se_stub.lua`).
- `tools/acceptance/steps.lua` — step handlers. acceptance4lua looks handlers
  up by exact step text, so the table resolves keys through Lua patterns and
  literal sentences that differ only by a number share one implementation.
- `tools/acceptance/steps_repo.lua` — steps that inspect the repository itself
  (`source-layout.feature`, `deploy-mirror.feature`); no game is booted. Its
  `patterns` are appended to the `steps.lua` dispatch table.
- `tools/acceptance/headless.lua` — boots a fresh game inside the current
  process for every scenario execution (drops `server.*`, `client.*`, `common.*` and the SE stub from `package.loaded`, re-runs the boot
  sequence of `tools/headless/run_server.lua`) and exposes the query surface.
- `tools/acceptance/bootstrap.lua` — installs `acceptance4lua` into
  `.toolcache/luarocks` on first use (`git clone` + `luarocks make`) and puts
  it on `package.path`.
- `tools/acceptance/cli/*.lua` — thin wrappers over `acceptance4lua.cli.*`;
  `runner_worker.lua` is the NDJSON runner-worker for `gherkin-mutator`.
- `tools/acceptance/{gherkin-parser,ir-dry-checker,gherkin-mutator}` —
  bash entrypoints (Lua 5.4 located by `tools/pick-lua.sh`).
  `entrypoint_generator` binds generated specs to `tools.acceptance.steps`;
  `runner_adapter` is the runner-worker command.
- `tools/acceptance/provision.sh` — writes forwarders for the three PATH
  names into `.swarmforge/bin` so role prompts' bare commands hit this lane.
- `build/acceptance/` (ir, dry, generated specs), `build/acceptance-mutation/`, `.toolcache/` — generated
  artifacts and tool tree (gitignored).

## Commands

```sh
tools/acceptance/run_acceptance.sh            # parse, dry-check (advisory), generate, run
tools/acceptance/run_mutation.sh [feature]    # Gherkin mutation (differential, hard)
tools/acceptance/provision.sh                 # refresh .swarmforge/bin forwarders
```

Run everything from the repository root. Never run `swarm_tool.sh ensure
gherkin-parser|ir-dry-checker|gherkin-mutator`: it swaps the forwarders for
Babashka wrappers.

## Environment

- Lua 5.4 (`brew install lua@5.4`); `tools/pick-lua.sh` finds it even when
  PATH `lua` is another version.
- `luarocks` for the one-time rock install. `SE_DEFENSE_LUA_DIR` can point
  luarocks at a keg-only Lua (e.g. `/opt/homebrew/opt/lua@5.4`).
- `VERBOSE=1` prints the game's `[bd]` logs during scenarios.
