-- 05_BaseDefence 游戏状态中心
--
-- 职责：维护全局模式、金钱、采集速率、资源余量以及 Core（宿主实体 + Health）。
-- 对应上游 GameState.cs 的 Init 语义：进入 Playing 时重置金钱；Playing 期间
-- 所有矿点采空则 Victory，Core 离场（死亡且碎裂完成）则 GameOver（GDD 01 R5）。
--
-- 可选扩展（opt-in，不影响旧测试）：
--   - config.game_tick：提供时创建六个碰撞区并在每 tick 刷新（对应上游
--     GameState.cs 的 powerZone/groundZone/radarZone/turretZone/repairZone/enemyZone）；
--   - config.core == "external"：跳过本模块内建 Core 实体，由组合方后赋值。

local spoke = require("common.spoke")
local Epoch = spoke.Epoch
local State = spoke.State
local Memo = spoke.Memo
local Phase = spoke.Phase
local Health = require("server.units.health")
local CollisionWorld = require("server.kernel.collision")

local host_default = require("server.host")

local GameState = Epoch.extend("GameState", {
  constructor = function(self, config)
    self._config = config or {}
  end,

  init = function(self, s)
    local config = self._config
    local host = config.host or host_default
    local start_money = config.start_money or 100
    local core_max_hp = config.core_max_hp or 50
    local core_position = config.core_position or { x = 0, y = 0, z = 0 }
    local dimensions = config.dimensions or { x = 40, z = 40 }

    self.mode = State.new("Pregame")
    self.money = State.new(0)
    self.collect_rate = State.new(0)
    self.resources_remaining = State.new("GameState.resources_remaining", 0)

    -- 碰撞区：只有传入 game_tick 时才创建，供 BoardInteractions / 敌人 / 炮塔 /
    -- 雷达 / 维修站使用。顺序对齐上游 GameState.LateUpdate。
    local game_tick = config.game_tick
    if game_tick then
      self.power_zone = CollisionWorld.new()
      self.ground_zone = CollisionWorld.new()
      self.radar_zone = CollisionWorld.new()
      self.turret_zone = CollisionWorld.new()
      self.repair_zone = CollisionWorld.new()
      self.enemy_zone = CollisionWorld.new()

      local function tick_zones(dt)
        self.power_zone:tick()
        self.ground_zone:tick()
        self.radar_zone:tick()
        self.turret_zone:tick()
        self.repair_zone:tick()
        self.enemy_zone:tick()
      end
      -- 初始布局收敛：树 spawn 后、仍在 Pregame（t=0）时显式采样一次供电圈
      -- 并令其 flush，Core 圈内的矿点因此在开局瞬间即通电（去抖只约束开局后的
      -- 通断电变化，GDD 03 R8）。宿主入口在挂载/重开后调用一次。
      self.settle_power = function() self.power_zone:tick() end
      local unlisten = game_tick:listen(tick_zones)
      s:on_cleanup(function()
        unlisten()
      end)
    end

    -- Core：默认内建；external 模式由组合方后赋值，避免 GameRoot 重复创建实体。
    if config.core == "external" then
      self.core = nil
    else
      local core_entity = host.entity.spawn("Core", core_position)
      local core_health = Health.attach(s, { max_hp = core_max_hp })

      self.core = {
        entity = core_entity,
        health = core_health,
      }
    end

    local half_x = dimensions.x / 2
    local half_z = dimensions.z / 2
    local cx = core_position.x
    local cz = core_position.z

    function self:level_bounds()
      return {
        min = { x = cx - half_x, z = cz - half_z },
        max = { x = cx + half_x, z = cz + half_z },
        center = { x = cx, z = cz },
      }
    end

    function self:start_game()
      self.mode:set("Playing")
    end

    -- isPlaying memo：上游 s.Memo(s => s.D(mode) == GameMode.Playing)
    local is_playing = s:call(Memo.new(function(ss)
      return ss:d(self.mode) == "Playing"
    end))

    -- 仅在 Playing 阶段挂载：重置金钱并监听胜负条件（上游 GameState.cs）。
    s:call(Phase.new(is_playing, function(ss)
      self.money:set(start_money)

      -- Victory：所有矿点采空（resources_remaining == 0）。
      local all_mined = ss:memo(function(sss)
        return sss:d(self.resources_remaining) == 0
      end, self.resources_remaining)

      ss:phase(all_mined, function()
        self.mode:set("Victory")
      end)

      -- coreLost memo：必须在 Phase(is_playing) 内，因为 external 模式下 core
      -- 由组合方在进入 Playing 前赋值，此处读取才安全。
      -- GDD 01 R5：失败判在 Core「离场」（死亡且碎裂完成），不是死亡瞬间；
      -- 组合 Core 走 building.departed，内建简易 Core 退化为死亡即离场。
      local core_lost = ss:memo(function(sss)
        local core = self.core
        local departed = core.building and core.building.departed
        if departed then
          return sss:d(departed)
        end
        return not sss:d(core.health.is_alive)
      end)

      ss:phase(core_lost, function()
        self.mode:set("GameOver")
      end)
    end))
  end,
})

return GameState
