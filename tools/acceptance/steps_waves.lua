-- tools/acceptance/steps_waves.lua — 敌人与波次步骤（enemies-waves.feature，
-- GDD 07 W1–W10、E1–E7；同时供 detection-fire.feature 的敌人读取）。
-- 编排：设定波次 / 固定随机源 / 定向生成敌人 / 第 N 个敌人死亡（GM 面）；
-- 读取：方向公布、进攻期、生成数、层级、成本总和、敌人位置/血量/存活/揭示。
-- 血量与位置比较按 feature 约定 ±0.05（steps_support.NEAR）。
local S = require("tools.acceptance.steps_support")
local headless, needs_session, expect_yes_no =
  S.headless, S.needs_session, S.expect_yes_no

local function nth_enemy(s, n)
  local e = headless.enemy_nth(s, tonumber(n))
  if not e then return nil, "还没有第 " .. n .. " 个敌人" end
  return e
end

-- 本波生成层级序列（含编排生成）的最高层级。
local function max_tier(s)
  local top = 0
  for _, t in ipairs(headless.wave(s).spawn_log) do top = math.max(top, t) end
  return top
end

return { patterns = {
  { "^随机源固定为最大值$", needs_session(function(w, s)
      headless.gm(s, "fix_rng_max")
      return true end) },
  { "^设定当前波次为(%d+)$", needs_session(function(w, s, n)
      headless.gm(s, "set_wave", tonumber(n))
      return true end) },
  { "^在%((%-?[%d.]+),(%-?[%d.]+)%)生成一个航线朝(%S+)的(%d+)型敌人$",
    needs_session(function(w, s, x, z, dir_name, tier)
      headless.gm(s, "spawn_enemy_at", tonumber(x), tonumber(z), dir_name, tonumber(tier))
      return true end) },
  { "^第(%d+)个敌人死亡$", needs_session(function(w, s, n)
      local e, bad = nth_enemy(s, n)
      if not e then return nil, bad end
      headless.gm(s, "kill_enemy_nth", tonumber(n))
      return true end) },
  { "^第(%d+)个敌人位于%((%-?[%d.]+),(%-?[%d.]+)%)$", needs_session(function(w, s, n, x, z)
      local e, bad = nth_enemy(s, n)
      if not e then return nil, bad end
      local p = headless.enemy_pos(e)
      if math.abs(p.x - tonumber(x)) <= S.NEAR and math.abs(p.z - tonumber(z)) <= S.NEAR then
        return true
      end
      return nil, string.format("第 %s 个敌人期望位于(%s,%s)，实际位于(%.4f,%.4f)",
        n, x, z, p.x, p.z) end) },
  { "^第(%d+)个敌人血量为([%d.]+)$", needs_session(function(w, s, n, expect)
      local e, bad = nth_enemy(s, n)
      if not e then return nil, bad end
      return S.near_num(headless.enemy_hp(e), expect, "第 " .. n .. " 个敌人血量") end) },
  { "^第(%d+)个敌人是否已揭示为(%S+)$", needs_session(function(w, s, n, expect)
      local e, bad = nth_enemy(s, n)
      if not e then return nil, bad end
      local want, bad_w = expect_yes_no(expect)
      if bad_w then return nil, bad_w end
      if headless.enemy_tracked(e) == want then return true end
      return nil, string.format("第 %s 个敌人揭示期望 %s，实际 %s",
        n, expect, headless.enemy_tracked(e) and "是" or "否") end) },
  { "^第(%d+)个敌人是否存活为(%S+)$", needs_session(function(w, s, n, expect)
      local e, bad = nth_enemy(s, n)
      if not e then return nil, bad end
      local want, bad_w = expect_yes_no(expect)
      if bad_w then return nil, bad_w end
      if headless.enemy_alive(e) == want then return true end
      return nil, string.format("第 %s 个敌人存活期望 %s，实际 %s",
        n, expect, headless.enemy_alive(e) and "是" or "否") end) },
  { "^第(%d+)个敌人血量与推进前相同$", needs_session(function(w, s, n)
      if not w.before or not w.before.enemies then
        return nil, "尚未推进（缺「与推进前相同」的基准）"
      end
      local e, bad = nth_enemy(s, n)
      if not e then return nil, bad end
      local b = w.before.enemies[tonumber(n)]
      if not b then return nil, "推进前还没有第 " .. n .. " 个敌人（或已死亡）" end
      local hp = headless.enemy_hp(e)
      if math.abs(hp - b) <= S.EPS then return true end
      return nil, string.format("第 %s 个敌人血量期望与推进前 %s 相同，实际 %s", n, b, hp) end) },
  { "^第(%d+)个敌人血量低于推进前$", needs_session(function(w, s, n)
      if not w.before or not w.before.enemies then
        return nil, "尚未推进（缺「低于推进前」的基准）"
      end
      local e, bad = nth_enemy(s, n)
      if not e then return nil, bad end
      local b = w.before.enemies[tonumber(n)]
      if not b then return nil, "推进前还没有第 " .. n .. " 个敌人（或已死亡）" end
      local hp = headless.enemy_hp(e)
      if hp < b - S.EPS then return true end
      return nil, string.format("第 %s 个敌人血量期望低于推进前 %s，实际 %s", n, b, hp) end) },
  { "^来袭方向为未知$", needs_session(function(w, s)
      if headless.wave_direction(s) == nil then return true end
      return nil, "来袭方向期望未知，实际 " .. tostring(headless.wave_direction(s)) end) },
  { "^来袭方向属于东南西北之一$", needs_session(function(w, s)
      local d = headless.wave_direction(s)
      if d == "东" or d == "南" or d == "西" or d == "北" then return true end
      return nil, "来袭方向期望属于东南西北之一，实际 " .. tostring(d) end) },
  { "^是否处于进攻期为(%S+)$", needs_session(function(w, s, expect)
      local want, bad = expect_yes_no(expect)
      if bad then return nil, bad end
      if headless.wave(s).assault == want then return true end
      return nil, string.format("进攻期期望 %s，实际 %s",
        expect, headless.wave(s).assault and "是" or "否") end) },
  { "^本波已生成(%d+)个敌人$", needs_session(function(w, s, expect)
      return S.eq_num(#headless.wave(s).spawn_log, expect, "本波已生成敌人数") end) },
  { "^本波生成的敌人层级都不超过(%d+)$", needs_session(function(w, s, cap)
      local top = max_tier(s)
      if top <= tonumber(cap) then return true end
      return nil, string.format("本波最高层级期望不超过 %s，实际 %s", cap, top) end) },
  { "^本波生成的敌人层级最高为(%d+)$", needs_session(function(w, s, expect)
      return S.eq_num(max_tier(s), expect, "本波最高层级") end) },
  { "^本波生成的敌人成本总和为([%d.]+)$", needs_session(function(w, s, expect)
      return S.eq_num(headless.wave(s).cost_sum, expect, "成本总和") end) },
  { "^本波生成的敌人成本总和不低于([%d.]+)$", needs_session(function(w, s, low)
      local sum = headless.wave(s).cost_sum
      if sum >= tonumber(low) - 1e-9 then return true end
      return nil, string.format("成本总和期望不低于 %s，实际 %s", low, sum) end) },
  { "^本波生成的敌人成本总和不超过([%d.]+)$", needs_session(function(w, s, high)
      local sum = headless.wave(s).cost_sum
      if sum <= tonumber(high) + 1e-9 then return true end
      return nil, string.format("成本总和期望不超过 %s，实际 %s", high, sum) end) },
  { "^当前为第(%d+)波$", needs_session(function(w, s, expect)
      return S.eq_num(headless.wave(s).number, expect, "当前波号") end) },
} }
