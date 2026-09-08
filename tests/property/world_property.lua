-- 对局世界事实/波次领域的性质测试。
--
-- 覆盖 server.game.world_data 的来袭方向查表与 wave_merge（浅拷贝合并的幂等/覆盖/
-- 不原地改写），以及 server.game.wave_cycle 的 fresh_wave（预算公式、平静期、
-- 初始标志不随时间/波号变化）。纯 Lua，无宿主依赖。
local property = require("tests.spoke.property.support.property")
local World = require("server.game.world_data")
local WaveCycle = require("server.game.wave_cycle")

local gen = property.gen

-- 方向查表：每个预置方向名都拿到同一表；向量为单位向量（东/南/西/北）；
-- 东西、南北互为反向；未知名返回 nil。
property.forall("direction_lookup_roundtrip_and_unit", {}, function()
  local names = {}
  for _, d in ipairs(World.directions) do
    local found = World.direction(d.name)
    if not found or found ~= d then
      return "roundtrip failed for direction " .. tostring(d.name)
    end
    local len = math.sqrt(d.x * d.x + d.z * d.z)
    if math.abs(len - 1) > 1e-9 then
      return "direction " .. tostring(d.name) .. " is not a unit vector"
    end
    names[d.name] = true
  end
  if World.direction("中间") ~= nil then
    return "unknown direction should resolve to nil"
  end
  if World.direction("东").x ~= -World.direction("西").x
    or World.direction("北").z ~= -World.direction("南").z then
    return "cardinal opposites are not negations"
  end
  return true
end)

-- wave_merge：覆盖键生效、其余基键保留、基表不被原地改写、空覆盖幂等。
property.forall("wave_merge_override_preserve_and_no_mutation", { gen.integer(1, 9) }, function(n)
  local b = {
    number = n,
    countdown = 30,
    assault = false,
    front = "None",
    budget_left = 2 + (n - 1),
  }
  local before = { countdown = b.countdown, front = b.front, number = b.number }
  local merged = World.wave_merge(b, { countdown = 12.5, front = "East" })

  if merged.countdown ~= 12.5 then return "countdown override did not win" end
  if merged.front ~= "East" then return "front override did not win" end
  if merged.number ~= n then return "unoverridden base key was lost" end
  if merged.budget_left ~= 2 + (n - 1) then return "unoverridden base key lost value" end
  if merged.assault ~= false then return "base boolean flipped" end
  if b.countdown ~= before.countdown or b.front ~= before.front or b.number ~= before.number then
    return "base table was mutated in place"
  end
  return true
end)

-- wave_merge：w = merge(merge(w, o), {}) 对任意 o 幂等。
property.forall("wave_merge_idempotent_with_empty_override", { gen.integer(1, 9), gen.boolean }, function(n, flag)
  local w = { number = n, countdown = 30, assault = flag, front = "None" }
  local merged = World.wave_merge(w, { countdown = 8, assault = not flag })
  local again = World.wave_merge(merged, {})
  for k, v in pairs(merged) do
    if again[k] ~= v then
      return "non-idempotent: key " .. tostring(k)
    end
  end
  for k, v in pairs(again) do
    if merged[k] ~= v then
      return "non-idempotent: extra key " .. tostring(k)
    end
  end
  return true
end)

-- fresh_wave：预算公式 2 + (N − 1)、平静期固定、初始标志干净（仅测波号与预算）。
property.forall("fresh_wave_budget_formula", { gen.integer(1, 50) }, function(n)
  local w = WaveCycle.fresh_wave({ rng01 = function() return 0 end }, n)
  if w.number ~= n then
    return "fresh_wave number mismatch"
  end
  if w.budget_left ~= World.wave.budget_base + (n - 1) then
    return "fresh_wave budget does not follow 2+(N-1)"
  end
  if w.countdown ~= World.wave.calm then
    return "fresh_wave countdown is not the calm period"
  end
  if w.spawned ~= 0 or w.spawn_done or w.assault or w.cost_sum ~= 0 then
    return "fresh_wave initial flags not clean"
  end
  return true
end)
