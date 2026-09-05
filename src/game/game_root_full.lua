-- 05_BaseDefence 完整组合根（GameRootFull）。
--
-- 职责：在 GameRoot 的垂直切片之上补全 Pool（四建筑 specs）、BoardInteractions、
-- 放置流与敌人波次变体键，形成「四建筑 + 放置」可玩的完整游戏组合。
--
-- 与 GameRoot 的关系：本文件是独立的组合根，不修改 GameRoot；se-defense
-- 部署时选择加载本组合根即可到达目的地切片。现有业务模块（Building/Enemy/
-- Turret 等）合约保持不变。
--
-- 集成范式：Auto-first（ADR 0004）。宿主/测试按需要选择 SpokeTree.spawn（Auto）
-- 或 spawn_manual（Manual）。

local spoke = require("vendor.spoke")
local Epoch = spoke.Epoch
local Effect = spoke.Effect
local Dock = spoke.Dock

local GameState = require("src.game.game_state")
local Core = require("src.game.core")
local WaveDirector = require("src.game.wave_director")
local Resource = require("src.game.resource")
local StatusUI = require("src.game.status_ui")
local SideBar = require("src.game.sidebar")
local Announcer = require("src.game.announcer")
local InputSignals = require("src.game.input_signals")
local BoardInteractions = require("src.game.board_interactions")
local Pool = require("src.game.pool")
local BuildingSpecs = require("src.game.building_specs")

-- 确保 s:coroutine 扩展已加载。
require("src.game.coroutine")

-- Enemy 采用惰性 require，避免加载本组合根时污染 package.loaded。
local Enemy
local function get_enemy_class()
  if not Enemy then
    package.loaded["src.game.health"] = nil
    package.loaded["src.game.enemy"] = nil
    Enemy = require("src.game.enemy")
  end
  return Enemy
end

local host_default = require("src.adapter.host")

local function default_resources()
  return {
    { position = { x = -2.5, y = 0, z = 2.5 }, start_resources = 20 },
    { position = { x = 2.5, y = 0, z = 2.5 }, start_resources = 20 },
    { position = { x = -2.5, y = 0, z = -2.5 }, start_resources = 20 },
    { position = { x = 2.5, y = 0, z = -2.5 }, start_resources = 20 },
  }
end

local GameRootFull = Epoch.extend("GameRootFull", {
  constructor = function(self, config)
    config = config or {}
    self.host = config.host or host_default
    self.game_tick = config.game_tick or error("GameRootFull requires game_tick", 2)

    self.game_state_config = config.game_state or {}
    self.game_state_config.host = self.game_state_config.host or self.host
    self.game_state_config.game_tick = self.game_state_config.game_tick or self.game_tick
    self.game_state_config.core = "external"

    self.core_config = config.core or {}
    self.wave_director_config = config.wave_director or {}
    self.enemy_config = config.enemy or {}
    self.resource_configs = config.resources
    if self.resource_configs == nil then
      self.resource_configs = default_resources()
    end

    self.building_spec_overrides = config.building_specs

    self.game_state = nil
    self.core = nil
    self.wave_director = nil
    self.pool = nil
    self.building_specs = nil
    self.input_signals = nil
    self.board_interactions = nil
    self.status_ui = nil
    self.side_bar = nil
    self.announcer = nil
    self.enemies = {}
    self.resources = {}
  end,

  init = function(self, s)
    s:call(Effect.new("GameRootFull.Composition", function(ss)
      local game_state = ss:call(GameState.new(self.game_state_config))
      self.game_state = game_state

      -- Core：电网根与失败条件。
      local core_position = self.game_state_config.core_position or { x = 0, y = 0, z = 0 }
      local core_entity = self.host.entity.spawn("Core", core_position)
      local core = ss:call(Core.new({
        host = self.host,
        entity = core_entity,
        max_hp = self.core_config.max_hp or self.game_state_config.core_max_hp or 50,
        display_name = self.core_config.display_name or "Core",
        provide_range = self.core_config.provide_range or 4,
        power_zone = game_state.power_zone,
        ground_zone = game_state.ground_zone,
        game_tick = self.game_tick,
      }))
      game_state.core = core
      self.core = core

      -- Pool + 四建筑 specs。
      local pool = ss:call(Pool.new({ host = self.host }))
      self.pool = pool
      local specs = BuildingSpecs.create({
        host = self.host,
        game_state = game_state,
        game_tick = self.game_tick,
        pool = pool,
        overrides = self.building_spec_overrides,
      })
      self.building_specs = specs

      -- 辅助：放置建筑并回填 pool_instance，使死亡时能正确回收。
      local function place_building(spec, position)
        local inst = pool:spawn(spec, position)
        if inst.epoch and inst.epoch.building then
          inst.epoch.building.pool_instance = inst
        end
        return inst
      end

      -- 输入与棋盘交互。
      local input_signals = ss:call(InputSignals.new({
        host = self.host,
        game_tick = self.game_tick,
      }))
      self.input_signals = input_signals

      local board_interactions = ss:call(BoardInteractions.new({
        host = self.host,
        game_state = game_state,
        input_signals = input_signals,
        pool = pool,
        spawn = place_building,
      }))
      self.board_interactions = board_interactions

      -- 波次：每波敌人用 Dock 盛放。
      local waves_dock = ss:dock("waves")
      local current_wave_dock
      local enemy_serial = 0

      local function spawn_enemy(front, position, wave_enemy_config)
        enemy_serial = enemy_serial + 1
        local key = "enemy_" .. enemy_serial
        local base_cfg = self.enemy_config
        local wave_cfg = wave_enemy_config or {}
        local enemy = get_enemy_class().new({
          host = self.host,
          game_tick = self.game_tick,
          game_state = game_state,
          position = position,
          prefab = wave_cfg.prefab or base_cfg.prefab or "enemy",
          max_hp = wave_cfg.max_hp or base_cfg.max_hp,
          move_speed = wave_cfg.move_speed or base_cfg.move_speed,
          stop_distance = wave_cfg.stop_distance or base_cfg.stop_distance,
          fire_rate = wave_cfg.fire_rate or base_cfg.fire_rate,
          damage = wave_cfg.damage or base_cfg.damage,
          radius = wave_cfg.radius or base_cfg.radius,
          enemy_zone = game_state.enemy_zone,
          radar_zone = game_state.radar_zone,
        })

        if not current_wave_dock then
          error("spawn_enemy called before any wave_started", 2)
        end
        current_wave_dock:call(key, enemy)

        self.enemies[#self.enemies + 1] = enemy
        return enemy
      end

      local wave_director = ss:call(WaveDirector.new({
        game_state = game_state,
        game_tick = self.game_tick,
        spawn_enemy = spawn_enemy,
        waves = self.wave_director_config.waves,
        lull_duration = self.wave_director_config.lull_duration,
        front_reveal_time = self.wave_director_config.front_reveal_time,
        spawn_interval = self.wave_director_config.spawn_interval,
        enemy_count = self.wave_director_config.enemy_count,
        spawn_margin = self.wave_director_config.spawn_margin,
        pick_front = self.wave_director_config.pick_front,
      }))
      self.wave_director = wave_director

      -- 预置矿点。
      for _, site in ipairs(self.resource_configs) do
        local entity = self.host.entity.spawn("Resource", site.position)
        local resource = ss:call(Resource.new({
          host = self.host,
          entity = entity,
          game_state = game_state,
          director = wave_director,
          game_tick = self.game_tick,
          radius = site.radius,
          collect_time = site.collect_time,
          start_resources = site.start_resources,
          power_zone = game_state.power_zone,
          ground_zone = game_state.ground_zone,
        }))
        self.resources[#self.resources + 1] = resource
      end

      -- UI：StatusUI + SideBar（带 interactions）+ Announcer。
      self.status_ui = ss:call(StatusUI.new({
        host = self.host,
        game_state = game_state,
        wave_director = wave_director,
      }))

      self.side_bar = ss:call(SideBar.new({
        host = self.host,
        game_state = game_state,
        wave_director = wave_director,
        interactions = board_interactions,
      }))

      self.announcer = ss:call(Announcer.new({
        host = self.host,
        game_state = game_state,
        wave_director = wave_director,
        game_tick = self.game_tick,
      }))

      -- 每波开始时新建 Dock。
      ss:subscribe(wave_director.wave_started, function(w)
        current_wave_dock = Dock.new("wave_" .. w.number)
        waves_dock:call("wave_" .. w.number, current_wave_dock)
      end)

      -- 波次清场。
      ss:subscribe(wave_director.wave_defeated, function(w)
        waves_dock:drop("wave_" .. w.number)
        current_wave_dock = nil
      end)
    end))
  end,
})

return GameRootFull
