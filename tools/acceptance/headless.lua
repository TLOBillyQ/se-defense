-- tools/acceptance/headless.lua — boots the headless game (SE stub + real
-- adapters + src/server/main.lua) inside the current process and exposes the
-- query surface the step handlers need. Same boot sequence as
-- tools/headless/run_server.lua.
--
-- Fresh game per scenario: every module under src./examples./vendor. and the
-- SE stub are dropped from package.loaded and required again, so module-level
-- state (adapter registries, stub signal lists, _G.bd) starts from scratch.
--
-- The business modules (examples.base_defence.*) are not inlined in this
-- repository yet; point SE_DEFENSE_BUSINESS_DIR at a tree containing
-- examples/base_defence/ (require prefix vendor.spoke) or place it so that
-- ./examples/base_defence/ or vendor/spoke-lua/examples/base_defence/ resolves.
local M = {}

local real_print = print
local verbose = os.getenv("VERBOSE") == "1"

local function add_search_paths()
  local paths = { "./?.lua", "./?/init.lua", "vendor/spoke-lua/?.lua", "vendor/spoke-lua/?/init.lua" }
  local business = os.getenv("SE_DEFENSE_BUSINESS_DIR")
  if business and business ~= "" then
    table.insert(paths, 1, business .. "/?/init.lua")
    table.insert(paths, 1, business .. "/?.lua")
  end
  package.path = table.concat(paths, ";") .. ";" .. package.path
end

local function reset_modules()
  for name in pairs(package.loaded) do
    if name:match("^src%.") or name:match("^examples%.") or name:match("^vendor%.")
      or name == "tools.headless.se_stub" then
      package.loaded[name] = nil
    end
  end
  _G.bd = nil
end

local function business_available()
  local ok = pcall(require, "examples.base_defence.game_root_full")
  return ok
end

-- Boots a fresh game; returns a session table {stub, host}.
function M.boot()
  add_search_paths()
  reset_modules()
  if not business_available() then
    error("业务模块 examples.base_defence 无法加载：请设置 SE_DEFENSE_BUSINESS_DIR 指向含 examples/base_defence/ 的目录（见 tools/acceptance/README.md）")
  end
  package.preload["examples.base_defence.host_mock"] = function() return require("src.adapter.host") end
  package.preload["examples.base_defence.eui_mock"] = function() return require("src.adapter.eui") end
  package.preload["examples.base_defence.input_mock"] = function() return require("src.adapter.input") end
  package.preload["examples.host_mock"] = function() return require("src.adapter.host_base") end

  local stub = require("tools.headless.se_stub")
  print = function(...) if verbose then real_print(...) end end
  local ok, err = pcall(function() assert(loadfile("src/server/main.lua"))() end)
  print = real_print
  if not ok then error(err, 0) end
  return { stub = stub, host = require("src.adapter.host") }
end

local function quiet(fn, ...)
  print = function(...) if verbose then real_print(...) end end
  local results = table.pack(pcall(fn, ...))
  print = real_print
  if not results[1] then error(results[2], 0) end
  return table.unpack(results, 2, results.n)
end

function M.send(s, msg) quiet(s.stub.client_send, msg) end
function M.steps(s, n) quiet(s.stub.steps, n) end

function M.gm(s, fn, ...)
  local f = _G.bd and _G.bd[fn]
  if type(f) ~= "function" then error("GM 命令不存在: " .. tostring(fn)) end
  return quiet(f, ...)
end

local function root()
  local r = _G.bd and _G.bd.root
  if not r then error("_G.bd.root 未就绪") end
  return r
end

function M.mode(_) return root().game_state.mode:now() end
function M.money(_) return root().game_state.money:now() end
function M.placing(_)
  local p = root().board_interactions.placing:now()
  return p and p.key or nil
end

function M.entities(s, prefab)
  local items = {}
  for _, e in ipairs(s.host.entity.all()) do
    if prefab == nil or e.prefab == prefab then items[#items + 1] = e end
  end
  return items
end

function M.has_power(e)
  local pool = root().pool
  local rec = pool and pool._live_by_entity_id and pool._live_by_entity_id[e.id]
  local b = rec and rec.epoch and rec.epoch.building
  local p = b and b.power and b.power.has_power
  return p ~= nil and p:now() == true
end

function M.node_visible(s, path)
  local n = s.host.eui.nodes and s.host.eui.nodes[path]
  return n ~= nil and n.visible == true
end

return M
