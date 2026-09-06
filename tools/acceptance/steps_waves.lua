-- tools/acceptance/steps_waves.lua — 敌人与波次步骤（enemies-waves.feature，
-- GDD 07 W1–W10、E1–E7）：波次编排（设定波次、固定随机源、定向生成敌人）、
-- 波次读取（方向、进攻期、生成数、层级、成本总和）、敌人读取（位置、血量、
-- 存活）与建筑血量读取。数值比较按 feature 约定 ±0.05。
local S = require("tools.acceptance.steps_support")
local needs_match, expect_yes_no, find_at = S.needs_match, S.expect_yes_no, S.find_at

local NEAR = 0.05 -- feature 约定：建筑血量与位置比较允许 ±0.05

local function waves_mod() return require("server.game.waves") end
local function enemies_mod() return require("server.game.enemies") end
local function world_mod() return require("server.game.world") end

local function nth_enemy(m, n)
  local e = m.enemies.list[tonumber(n)]
  if not e then return nil, "还没有第 " .. n .. " 个敌人" end
  return e
end

-- 本波生成层级序列（含编排生成）的读取辅助。
local function max_tier(m)
  local top = 0
  for _, t in ipairs(m.wave.spawn_log) do top = math.max(top, t) end
  return top
end

local function expect_enemy_health(e, expect)
  if math.abs(e.health - tonumber(expect)) <= NEAR then return true end
  return nil, string.format("敌人血量期望 %s，实际 %s", expect, e.health)
end

return { patterns = {
  { "^随机源固定为最大值$", needs_match(function(w, m)
      m.rng01 = function() return 1 end
      waves_mod().reroll_direction(m) -- 平静期未推进时按新随机源重抽方向
      return true end) },
  { "^设定当前波次为(%d+)$", needs_match(function(w, m, n)
      waves_mod().set_wave(m, tonumber(n))
      return true end) },
  { "^在%((%-?[%d.]+),(%-?[%d.]+)%)生成一个航线朝(%S+)的(%d+)型敌人$",
    needs_match(function(w, m, x, z, dir_name, tier)
      local heading = world_mod().direction(dir_name)
      if not heading then return nil, "未知方向: " .. dir_name end
      enemies_mod().spawn(m, { x = tonumber(x), z = tonumber(z),
        tier = tonumber(tier), heading = heading })
      return true end) },
  { "^第(%d+)个敌人死亡$", needs_match(function(w, m, n)
      local e, bad = nth_enemy(m, n)
      if not e then return nil, bad end
      enemies_mod().kill(e)
      return true end) },
  { "^第(%d+)个敌人位于%((%-?[%d.]+),(%-?[%d.]+)%)$", needs_match(function(w, m, n, x, z)
      local e, bad = nth_enemy(m, n)
      if not e then return nil, bad end
      if math.abs(e.x - tonumber(x)) <= NEAR and math.abs(e.z - tonumber(z)) <= NEAR then
        return true
      end
      return nil, string.format("第 %s 个敌人期望位于(%s,%s)，实际位于(%s,%s)",
        n, x, z, e.x, e.z) end) },
  { "^第(%d+)个敌人血量为([%d.]+)$", needs_match(function(w, m, n, expect)
      local e, bad = nth_enemy(m, n)
      if not e then return nil, bad end
      return expect_enemy_health(e, expect) end) },
  { "^第(%d+)个敌人是否已揭示为(%S+)$", needs_match(function(w, m, n, expect)
      local e, bad = nth_enemy(m, n)
      if not e then return nil, bad end
      local want, bad_want = expect_yes_no(expect)
      if bad_want then return nil, bad_want end
      if e.revealed == want then return true end
      return nil, string.format("第 %s 个敌人揭示期望 %s，实际 %s",
        n, expect, e.revealed and "是" or "否") end) },
  { "^第(%d+)个敌人是否存活为(%S+)$", needs_match(function(w, m, n, expect)
      local e, bad = nth_enemy(m, n)
      if not e then return nil, bad end
      local want, bad_want = expect_yes_no(expect)
      if bad_want then return nil, bad_want end
      if e.alive == want then return true end
      return nil, string.format("第 %s 个敌人存活期望 %s，实际 %s",
        n, expect, e.alive and "是" or "否") end) },
  { "^第(%d+)个敌人血量与推进前相同$", needs_match(function(w, m, n)
      if not w.before or not w.before.enemies then
        return nil, "尚未推进（缺「与推进前相同」的基准）"
      end
      local e, bad = nth_enemy(m, n)
      if not e then return nil, bad end
      local b = w.before.enemies[tonumber(n)]
      if not b then return nil, "推进前还没有第 " .. n .. " 个敌人" end
      if e.health == b then return true end
      return nil, string.format("第 %s 个敌人血量期望与推进前 %s 相同，实际 %s", n, b, e.health) end) },
  { "^第(%d+)个敌人血量低于推进前$", needs_match(function(w, m, n)
      if not w.before or not w.before.enemies then
        return nil, "尚未推进（缺「低于推进前」的基准）"
      end
      local e, bad = nth_enemy(m, n)
      if not e then return nil, bad end
      local b = w.before.enemies[tonumber(n)]
      if not b then return nil, "推进前还没有第 " .. n .. " 个敌人" end
      if e.health < b then return true end
      return nil, string.format("第 %s 个敌人血量期望低于推进前 %s，实际 %s", n, b, e.health) end) },
  { "^来袭方向为未知$", needs_match(function(w, m)
      if waves_mod().revealed_direction(m) == nil then return true end
      return nil, "来袭方向期望未知，实际 " .. tostring(waves_mod().revealed_direction(m)) end) },
  { "^来袭方向属于东南西北之一$", needs_match(function(w, m)
      local d = waves_mod().revealed_direction(m)
      if d == "东" or d == "南" or d == "西" or d == "北" then return true end
      return nil, "来袭方向期望属于东南西北之一，实际 " .. tostring(d) end) },
  { "^是否处于进攻期为(%S+)$", needs_match(function(w, m, expect)
      local want, bad = expect_yes_no(expect)
      if bad then return nil, bad end
      if m.wave.assault == want then return true end
      return nil, string.format("进攻期期望 %s，实际 %s",
        expect, m.wave.assault and "是" or "否") end) },
  { "^本波已生成(%d+)个敌人$", needs_match(function(w, m, expect)
      local actual = #m.wave.spawn_log
      if actual == tonumber(expect) then return true end
      return nil, string.format("本波已生成敌人数期望 %s，实际 %s", expect, actual) end) },
  { "^本波生成的敌人层级都不超过(%d+)$", needs_match(function(w, m, cap)
      if max_tier(m) <= tonumber(cap) then return true end
      return nil, string.format("本波最高层级期望不超过 %s，实际 %s", cap, max_tier(m)) end) },
  { "^本波生成的敌人层级最高为(%d+)$", needs_match(function(w, m, expect)
      if max_tier(m) == tonumber(expect) then return true end
      return nil, string.format("本波最高层级期望 %s，实际 %s", expect, max_tier(m)) end) },
  { "^本波生成的敌人成本总和为([%d.]+)$", needs_match(function(w, m, expect)
      if math.abs(m.wave.cost_sum - tonumber(expect)) <= 1e-6 then return true end
      return nil, string.format("成本总和期望 %s，实际 %s", expect, m.wave.cost_sum) end) },
  { "^本波生成的敌人成本总和不低于([%d.]+)$", needs_match(function(w, m, low)
      if m.wave.cost_sum >= tonumber(low) - 1e-9 then return true end
      return nil, string.format("成本总和期望不低于 %s，实际 %s", low, m.wave.cost_sum) end) },
  { "^本波生成的敌人成本总和不超过([%d.]+)$", needs_match(function(w, m, high)
      if m.wave.cost_sum <= tonumber(high) + 1e-9 then return true end
      return nil, string.format("成本总和期望不超过 %s，实际 %s", high, m.wave.cost_sum) end) },
  { "^当前为第(%d+)波$", needs_match(function(w, m, expect)
      if m.wave.number == tonumber(expect) then return true end
      return nil, string.format("当前波号期望 %s，实际 %s", expect, m.wave.number) end) },
  { "^位于%((%-?[%d.]+),(%-?[%d.]+)%)的(%w+)血量为([%d.]+)$",
    needs_match(function(w, m, x, z, kind, expect)
      local e, bad = find_at(m, kind, x, z)
      if not e then return nil, bad end
      if math.abs(e.health - tonumber(expect)) <= NEAR then return true end
      return nil, string.format("位于(%s,%s)的%s血量期望 %s，实际 %s",
        x, z, kind, expect, e.health) end) },
} }
