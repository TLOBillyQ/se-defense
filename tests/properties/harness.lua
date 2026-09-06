-- tests/properties/harness.lua — 小型性质测试 harness（Lua 5.4）。
-- 无合适的外部框架（luarocks 仅服务 acceptance4lua），按角色约定自建设施。
-- 用法：
--   local prop = require("tests.properties.harness")
--   prop.seed(42)
--   prop.check("性质名", 200, function(run) ... return true or nil, msg end)
-- 性质测试与常规验证分离：由 tests/properties/run.lua 单独驱动，
-- 不进 tests/run.lua 的 *_test.lua 发现 glob。
local M = { failures = 0 }

-- 固定种子保证可复现；失败信息带 run 序号，重跑同种子即复现。
function M.seed(s) math.randomseed(s) end

function M.int(lo, hi) return math.random(lo, hi) end

function M.number(lo, hi) return lo + (hi - lo) * math.random() end

function M.pick(list) return list[math.random(#list)] end

-- 单条性质：fn(run) 返回 true，或 nil + 失败说明。
function M.check(name, runs, fn)
  for run = 1, runs do
    local ok, msg = fn(run)
    if not ok then
      M.failures = M.failures + 1
      io.stderr:write(string.format("FAIL %s (run %d): %s\n", name, run, tostring(msg)))
      return
    end
  end
  print(string.format("ok - %s (%d runs)", name, runs))
end

function M.exit()
  if M.failures == 0 then os.exit(0) end
  io.stderr:write(string.format("%d property check(s) FAILED\n", M.failures))
  os.exit(1)
end

return M
