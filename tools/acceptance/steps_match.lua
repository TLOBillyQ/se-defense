-- tools/acceptance/steps_match.lua — 对局流程步骤（match-flow.feature，GDD 01
-- R1–R8）与所有 gameplay feature 共用的基础步骤：启动一局、玩家开始/重开/
-- 复合放置、推进秒数（记下资金、倒计时、矿点剩余量、敌人血量供
-- 「与推进前相同」「低于推进前」比较）、实体在场/计数等编排动作与读取。
local S = require("tools.acceptance.steps_support")
local headless, needs_session, expect_yes_no, known_kind, find_building =
  S.headless, S.needs_session, S.expect_yes_no, S.known_kind, S.find_building

return { patterns = {
  { "^一局新对局$", function(w)
      w.game = headless.boot()
      return true end },
  { "^对局阶段为(%S+)$", needs_session(function(w, s, expect)
      local actual = headless.mode(s)
      if actual == expect then return true end
      return nil, string.format("对局阶段期望 %s，实际 %s", expect, actual) end) },
  { "^玩家开始对局$", needs_session(function(w, s)
      headless.send(s, { kind = "input", itype = "start" })
      return true end) },
  { "^玩家重开$", needs_session(function(w, s)
      headless.send(s, { kind = "input", itype = "restart" })
      return true end) },
  { "^玩家在%((%-?[%d.]+),(%-?[%d.]+)%)放置(%w+)$", needs_session(function(w, s, x, z, kind)
      local _, bad = known_kind(kind)
      if bad then return nil, bad end
      -- 已处于该类型的放置态时不再发 place：再按当前类型按钮 = 取消（GDD 16 I4，
      -- placement 场景 7 第一次放置被拒后仍处于放置态，第二次复合步骤直接 tap）。
      if headless.placing(s) ~= string.lower(kind) then
        headless.send(s, { kind = "input", itype = "place", key = string.lower(kind) })
      end
      headless.send(s, { kind = "input", itype = "tap", x = tonumber(x), z = tonumber(z) })
      headless.steps(s, 3) -- tap 边沿两个步长后举起（见 steps_placement.lua）
      return true end) },
  -- 「推进 N 秒」记下推进前的资金、波次倒计时、每个矿点的剩余量与每个
  -- 敌人的血量，供「与推进前相同」「低于推进前」比较。
  { "^推进([%d.]+)秒$", needs_session(function(w, s, seconds)
      local sites = {}
      for _, r in ipairs(headless.site_list(s)) do
        sites[#sites + 1] = { x = r.entity.position.x, z = r.entity.position.z, remaining = r.remaining:now() }
      end
      local enemy_healths = {}
      for i, e in ipairs(headless.enemy_list(s)) do
        enemy_healths[i] = e.health.is_alive:now()
          and (e.health.hp_fraction:now() * e.health.max_hp:now()) or nil
      end
      w.before = {
        money = headless.money(s),
        countdown = headless.wave(s).countdown,
        sites = sites,
        enemies = enemy_healths,
      }
      headless.advance(s, tonumber(seconds))
      return true end) },
  { "^资金为(%d+)$", needs_session(function(w, s, expect)
      return S.eq_num(headless.money(s), expect, "资金") end) },
  { "^资金与推进前相同$", needs_session(function(w, s)
      if not w.before then return nil, "尚未推进（缺「与推进前相同」的基准）" end
      return S.eq_num(headless.money(s), w.before.money, "资金（与推进前相同）") end) },
  { "^波次倒计时与推进前相同$", needs_session(function(w, s)
      if not w.before then return nil, "尚未推进（缺「与推进前相同」的基准）" end
      return S.eq_num(headless.wave(s).countdown, w.before.countdown, "波次倒计时（与推进前相同）") end) },
  { "^第(%d+)波倒计时为([%d.]+)秒$", needs_session(function(w, s, number, countdown)
      local wave = headless.wave(s)
      if wave.number ~= tonumber(number) then
        return nil, string.format("波号期望 %s，实际 %s", number, wave.number)
      end
      return S.eq_num(wave.countdown, countdown, "第 " .. number .. " 波倒计时") end) },
  { "^采空(%d+)个矿点$", needs_session(function(w, s, n)
      headless.gm(s, "mine_n", tonumber(n))
      return true end) },
  { "^剩余矿点数为(%d+)$", needs_session(function(w, s, expect)
      return S.eq_num(headless.sites_remaining(s), expect, "剩余矿点数") end) },
  { "^(%w+)死亡$", needs_session(function(w, s, kind)
      local _, bad = known_kind(kind)
      if bad then return nil, bad end
      headless.gm(s, "kill", kind)
      return true end) },
  { "^一座已建好的(%w+)位于%((%-?[%d.]+),(%-?[%d.]+)%)$", needs_session(function(w, s, kind, x, z)
      local _, bad = known_kind(kind)
      if bad then return nil, bad end
      headless.gm(s, "spawn_building", kind, tonumber(x), tonumber(z))
      return true end) },
  { "^(%w+)是否在场为(%S+)$", needs_session(function(w, s, kind, expect)
      local _, bad_kind = known_kind(kind)
      if bad_kind then return nil, bad_kind end
      local want, bad = expect_yes_no(expect)
      if bad then return nil, bad end
      if headless.building_present(s, kind) == want then return true end
      return nil, string.format("%s 在场期望 %s，实际 %s",
        kind, expect, headless.building_present(s, kind) and "是" or "否") end) },
  { "^场上建筑数为(%d+)$", needs_session(function(w, s, expect)
      return S.eq_num(headless.building_count(s), expect, "场上建筑数") end) },
} }
