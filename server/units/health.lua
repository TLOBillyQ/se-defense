-- 05_BaseDefence 生命值模块。
--
-- 职责：维护单位生命值，对外暴露 HP 占比、存活状态、受伤事件，并支持伤害、
-- 修复与清理时回满血。对应上游 Examples/05_BaseDefence/Scripts/Units/Health.cs。
--
-- 使用方式：在 Epoch init(s) 或 effect 块中调用
--   local Health = require("server.units.health")
--   local h = Health.attach(s, { max_hp = 10 })
-- 然后 h:damage(amount) / h:repair(amount)。

local State = require("common.spoke.reactive.state")
local Trigger = require("common.spoke.reactive.trigger")
local Memo = require("common.spoke.reactive.memo")
local Effect = require("common.spoke.reactive.effect")

local Health = {}
Health.__index = Health

-- 把 Health 实例挂到当前 builder s 上，返回可操作句柄 h。
-- config.max_hp：最大生命值（正数）。
function Health.attach(s, config)
  local max_hp = State.new("Health.max_hp", config.max_hp)
  local damage_state = State.new("Health.damage", 0)

  local h = setmetatable({
    max_hp = max_hp,
    _damage = damage_state,
    hp_fraction = State.new("Health.hp_fraction", 1),
    is_alive = State.new("Health.is_alive", true),
    damaged = Trigger.new("Health.damaged"),
  }, Health)

  -- hp = max_hp - accumulated_damage，作为 Memo 供效果使用。
  local hp = s:call(Memo.new("Health.hp", function(s2)
    return s2:d(max_hp) - s2:d(damage_state)
  end, max_hp, damage_state))

  -- 同步 hp 到暴露的 State；HP 占比钳制在 [0, 1]。
  s:call(Effect.new("Health.sync", function(s2)
    local current_hp = s2:d(hp)
    local current_max = s2:d(max_hp)
    local frac = current_hp / current_max
    if frac < 0 then
      frac = 0
    elseif frac > 1 then
      frac = 1
    end
    h.hp_fraction:set(frac)
    h.is_alive:set(current_hp > 0)
  end))

  -- 当 Epoch 被回收（detach）时，累计伤害清零，即回满血。
  s:on_cleanup(function()
    damage_state:set(0)
  end)

  return h
end

-- 造成 amount 点伤害，并触发一次 damaged 事件。
function Health:damage(amount)
  self._damage:update(function(d)
    return d + amount
  end)
  self.damaged:invoke()
end

-- 修复 amount 点生命值；死亡时无操作，且伤害下限为 0（即不会超量修复）。
function Health:repair(amount)
  if not self.is_alive:now() then
    return
  end
  self._damage:update(function(d)
    local healed = d - amount
    if healed < 0 then
      return 0
    end
    return healed
  end)
end

return Health
