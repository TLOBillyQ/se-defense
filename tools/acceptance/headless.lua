-- tools/acceptance/headless.lua — 无头 harness：在当前进程内启动全新一局
-- （SE 桩 + 真适配层 + 真服务端入口），并向步骤层暴露编排与读取面。
-- 不 mock 业务模块：server./client. 前缀模块与 SE 桩整体从 package.loaded
-- 复位后重新 require，模块级状态（适配层注册表、桩信号列表）从零开始。
local M = {}

local real_print = print
local verbose = os.getenv("VERBOSE") == "1"

local paths_added = false
local function add_search_paths()
  if paths_added then return end
  paths_added = true
  local paths = { "./?.lua", "./?/init.lua", "./src/?.lua", "./src/?/init.lua" }
  package.path = table.concat(paths, ";") .. ";" .. package.path
end

local function reset_modules()
  for name in pairs(package.loaded) do
    if name:match("^server%.") or name:match("^client%.")
      or name == "tools.headless.se_stub" then
      package.loaded[name] = nil
    end
  end
end

local function quiet(fn, ...)
  print = function(...) if verbose then real_print(...) end end
  local results = table.pack(pcall(fn, ...))
  print = real_print
  if not results[1] then error(results[2], 0) end
  return table.unpack(results, 2, results.n)
end

-- 启动全新一局；返回 session { stub, match }。
function M.boot()
  add_search_paths()
  reset_modules()
  local stub = require("tools.headless.se_stub")
  quiet(function() assert(loadfile("src/server/main.lua"))() end)
  return { stub = stub, match = require("server.adapter.host").match }
end

-- 玩家意图经真实通道上行（RemoteEvent → 适配层）。
function M.send(s, msg) quiet(s.stub.client_send, msg) end

-- 推进 n 秒：宿主固定步长 1/30 秒，由适配层驱动规则层。
function M.advance(s, seconds) quiet(s.stub.steps, seconds * 30, 1 / 30) end

return M
