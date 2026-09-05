-- 05_BaseDefence 建筑通用组件。
--
-- 职责：为每栋建筑挂载生命值、血条、footprint 碰撞体、受击闪烁与死亡回收。
-- 对应上游 Examples/05_BaseDefence/Scripts/Units/Buildings/Building.cs。
--
-- 既定裁剪（ADR）：
--   - 命中闪烁 → 实体变色（红），0.1 秒后恢复为当前电力 tint 目标色；
--   - 碎裂动画裁掉，死亡直接 despawn/destroy；
--   - 断电变暗 → 实体 tint（set_color）。
--
-- 建筑实体由外部注入（pool 或组合方拥有生命周期），本组件不自行 spawn 实体。

local spoke = require("vendor.spoke")
local Epoch = spoke.Epoch
local Effect = spoke.Effect
local Phase = require("vendor.spoke.reactive.phase")
local Memo = require("vendor.spoke.reactive.memo")
local Reaction = require("vendor.spoke.reactive.reaction")
local Health = require("src.game.health")
local HealthBar = require("src.game.health_bar")

-- 注册 s:coroutine() 扩展。
require("src.game.coroutine")

local Building
Building = Epoch.extend("Building", {
  constructor = function(self, config)
    config = config or {}
    self.host = config.host or require("src.adapter.host")
    self.entity = config.entity or error("Building requires entity", 2)
    self.max_hp = config.max_hp or error("Building requires max_hp", 2)
    self.display_name = config.display_name or "Building"
    self.cost = config.cost or 0
    self.radius = config.radius or 0.6
    self.unpowered_dim = config.unpowered_dim or 0.35
    self.ground_zone = config.ground_zone
    self.ground_collider_owner = config.ground_collider_owner or self
    self.power = config.power
    self.game_tick = config.game_tick
    self.pool = config.pool
    self.pool_instance = config.pool_instance
  end,

  init = function(self, s)
    local host = self.host
    local entity = self.entity
    local radius = self.radius
    local unpowered_dim = self.unpowered_dim
    local power = self.power
    local game_tick = self.game_tick

    -- 1. 生命值。
    self.health = Health.attach(s, { max_hp = self.max_hp })

    -- 2. 血条：委托给 HealthBar（存活且未满血时显示，颜色随分数阈值变化）。
    self.health_bar = s:call(HealthBar.new({
      host = host,
      path = "building_" .. entity.id .. "_hp",
      fraction = self.health.hp_fraction,
      is_alive = self.health.is_alive,
    }))

    -- 辅助：当前断电 tint 目标色。
    local function current_tint_color()
      local has = power and power.has_power and power.has_power:now() or true
      if has then
        return { r = 1, g = 1, b = 1, a = 1 }
      end
      local d = unpowered_dim
      return { r = d, g = d, b = d, a = 1 }
    end

    -- 辅助：安全地给实体上色（防御 destroy/despawn 路径）。
    local function safe_set_color(c)
      if entity and host.entity.by_id[entity.id] and entity:is_active() then
        entity:set_color(c)
      end
    end

    -- 3. 存活阶段：注册全局表、footprint、受击闪烁。
    s:call(Phase.new("Building.alive", self.health.is_alive, function(s2)
      table.insert(Building._all, self)
      s2:on_cleanup(function()
        for i, b in ipairs(Building._all) do
          if b == self then
            table.remove(Building._all, i)
            break
          end
        end
      end)

      -- Footprint：供点选/范围伤害使用。
      if self.ground_zone then
        s2:use(self.ground_zone:add_collider(self.ground_collider_owner, function()
          return { center = entity:get_position(), radius = radius }
        end))
      end

      -- 受击闪烁。无 game_tick 时只变红不恢复。
      s2:reaction("Building.blink", function(s3)
        safe_set_color({ r = 1, g = 0, b = 0, a = 1 })
        if not game_tick then
          return
        end
        s3:coroutine(game_tick, function(_, wait_seconds)
          wait_seconds(0.1)
          safe_set_color(current_tint_color())
        end)
      end, self.health.damaged)
    end))

    -- 4. 死亡阶段：日志 + 回收/销毁。
    local is_dead = s:call(Memo.new("Building.is_dead", function(s2)
      return not s2:d(self.health.is_alive)
    end, self.health.is_alive))

    s:call(Phase.new("Building.dead", is_dead, function(s2)
      -- 对应上游 Building.cs：死亡时禁用 PowerNode，使其退出电网；
      -- 在 phase 清理（pool 复用/复活）时恢复。
      if power and power.is_enabled then
        power.is_enabled:set(false)
        s2:on_cleanup(function()
          power.is_enabled:set(true)
        end)
      end

      -- 死亡消息；使用 print 避免无 logger 时默认日志打印完整调用栈。
      print(self.display_name .. " destroyed")
      -- pool_instance 可能由外部在 spawn 后补填，因此运行时读 self.*。
      if self.pool and self.pool_instance then
        self.pool:despawn(self.pool_instance)
      elseif entity and entity.destroy then
        entity:destroy()
      end
    end))

    -- 5. 断电变暗。
    local has_power_signal = power and power.has_power
    if has_power_signal then
      s:call(Effect.new("Building.power_tint", function(s2)
        local has = s2:d(has_power_signal)
        if has then
          safe_set_color({ r = 1, g = 1, b = 1, a = 1 })
        else
          local d = unpowered_dim
          safe_set_color({ r = d, g = d, b = d, a = 1 })
        end
      end, has_power_signal))
    end
  end,
})

-- 模块级存活建筑表（上游 static All 的等价物）。
Building._all = {}

-- 返回当前存活建筑的快照（避免外部直接修改内部表）。
function Building.all()
  local out = {}
  for i, b in ipairs(Building._all) do
    out[i] = b
  end
  return out
end

return Building
