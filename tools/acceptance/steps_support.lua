-- tools/acceptance/steps_support.lua — gameplay 步骤文件共用的前置包装与校验。
-- 不是步骤表；各 steps_<系统>.lua 从这里取 needs_session / needs_match /
-- expect_yes_no / known_kind / find_at，steps.lua 只做汇总与分发。
local M = { headless = require("tools.acceptance.headless"), EPS = 1e-6 }

-- 前置包装：handler 需要一局已启动的对局。needs_session 注入 session，
-- needs_match 注入规则层对局对象（编排动作与实体读取走 m.entities）；
-- 未启动时返回统一错误。
function M.needs_session(fn)
  return function(w, ...)
    if not w.session then return nil, "尚未启动对局（背景缺「一局新对局」）" end
    return fn(w, w.session, ...)
  end
end

function M.needs_match(fn)
  return M.needs_session(function(w, s, ...)
    return fn(w, s.match, ...)
  end)
end

function M.expect_yes_no(value)
  if value ~= "是" and value ~= "否" then
    return nil, "在场期望只能是 是/否，实际 " .. tostring(value)
  end
  return value == "是"
end

-- 实体名必须来自实体总表，拒绝拼写变体（杀软变异存活体）。只在对局已启动后调用：
-- 实体总表随每场景的模块复位重新加载，因此按需 require 而非模块顶部捕获。
function M.known_kind(kind)
  if require("server.game.world").specs[kind] then return true end
  return nil, "未知实体: " .. tostring(kind)
end

-- 按类型与坐标（步骤捕获的字符串）取在场实体；类型未知或该处无实体时给出原因。
function M.find_at(m, kind, x, z)
  local _, bad = M.known_kind(kind)
  if bad then return nil, bad end
  local e = m.entities:find(kind, tonumber(x), tonumber(z))
  if not e then return nil, string.format("(%s,%s) 处没有 %s", x, z, kind) end
  return e
end

return M
