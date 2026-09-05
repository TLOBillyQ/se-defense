-- tools/acceptance/cli/runner_worker.lua — persistent APS runner-worker for
-- gherkin-mutator. One JSON job per stdin line:
--   {id, feature_json, generated_dir, timeout}
-- One JSON result per stdout line:
--   {id, outcome: test_success|test_failure|infrastructure_error, output, error, duration}
-- stdout is protocol only; diagnostics go to stderr.
package.path = "./?.lua;./?/init.lua;" .. package.path
local bootstrap = require("tools.acceptance.bootstrap")
local ok, err = bootstrap.ensure()
if not ok then
  io.stderr:write(tostring(err) .. "\n")
  os.exit(1)
end
local json = require("acceptance4lua.json")
local runner = require("acceptance4lua.runner")

local lua_bin = os.getenv("ACCEPTANCE_LUA_BIN") or arg[-1] or "lua"
local lua_path = bootstrap.lua_path()

local function respond(job, outcome, output, error_text, duration)
  return { id = job and job.id, outcome = outcome, output = tostring(output or ""),
    error = tostring(error_text or ""), duration = tonumber(duration) or 0 }
end

local function run_job(job)
  if type(job) ~= "table" or type(job.id) ~= "string" or job.id == "" then
    return respond(job, "infrastructure_error", "", "runner worker job requires id", 0)
  end
  if type(job.feature_json) ~= "string" or type(job.generated_dir) ~= "string" then
    return respond(job, "infrastructure_error", "", "runner worker job requires feature_json and generated_dir", 0)
  end
  local spec = job.generated_dir:gsub("/+$", "") .. "/feature_acceptance_spec.lua"
  local okr, result = pcall(runner.run_generated, spec, {
    feature_json = job.feature_json, lua_bin = lua_bin, lua_path = lua_path, timeout = job.timeout,
  })
  if not okr then return respond(job, "infrastructure_error", "", "acceptance runner failed: " .. tostring(result), 0) end
  if tostring(result.error or "") ~= "" then
    return respond(job, "infrastructure_error", result.output, result.error, result.duration)
  end
  return respond(job, result.passed and "test_success" or "test_failure", result.output, "", result.duration)
end

for line in io.stdin:lines() do
  if line:match("%S") then
    local okd, job = pcall(json.decode, line)
    local result
    if okd and type(job) == "table" then
      result = run_job(job)
    else
      result = respond(nil, "infrastructure_error", "", "invalid runner worker request: " .. tostring(job), 0)
    end
    io.stdout:write(json.encode_compact and json.encode_compact(result) or json.encode(result), "\n")
    io.stdout:flush()
  end
end
