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

local spoke = require("common.spoke")
local Epoch = spoke.Epoch
local Effect = spoke.Effect
local Memo = require("common.spoke.reactive.memo")
local Phase = require("common.spoke.reactive.phase")

local GameState = require("server.match.game_state")
local Core = require("server.power.core")
local WaveDirector = require("server.waves.wave_director")
local Resource = require("server.economy.resource")
local StatusUI = require("server.ui.status_ui")
local SideBar = require("server.ui.sidebar")
local Announcer = require("server.ui.announcer")
local InputSignals = require("server.board.input_signals")
local BoardInteractions = require("server.board.board_interactions")
local BoardDisplay = require("server.ui.board_display")
local Pool = require("server.kernel.pool")
local BuildingSpecs = require("server.board.building_specs")

-- 确保 s:coroutine 扩展已加载。
require("server.kernel.spoke_coroutine")

-- Enemy 采用惰性 require，避免加载本组合根时污染 package.loaded。
-- 模块缓存复位由无头 harness（tools/acceptance/headless.lua）负责，
-- 业务不写 package.loaded（真机 SE 沙盒没有 package 库）。
local Enemy
local function get_enemy_class()
  if not Enemy then
    Enemy = require("server.waves.enemy")
  end
  return Enemy
end

local World = require("server.kernel.world_data")

local host_default = require("server.host")

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
      self.resource_configs = World.near_core_resource_configs()
    end

    self.building_spec_overrides = config.building_specs
    self.op_log = config.op_log

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
        max_hp = self.core_config.max_hp or self.game_state_config.core_max_hp or World.specs.Core.health,
        display_name = self.core_config.display_name or "Core",
        provide_range = self.core_config.provide_range or World.specs.Core.provide,
        radius = self.core_config.radius or World.specs.Core.footprint,
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
        op_log = self.op_log,
      }))
      self.board_interactions = board_interactions

      -- board▶ui 的翻转（#44 步骤 0）：board_interactions 只暴露信号，
      -- 表现层由组合根在 Playing phase 内挂载；离开 Playing 时 phase 清理
      -- 显示节点（覆盖圈 5：对局结束后不再显示链路线）。
      local is_playing = ss:call(Memo.new("GameRootFull.is_playing", function(ms)
        return ms:d(game_state.mode) == "Playing"
      end, game_state.mode))

      ss:call(Phase.new("GameRootFull.board_display", is_playing, function(ps)
        BoardDisplay.mount(ps, {
          host = self.host,
          game_state = game_state,
          view = input_signals.view,
          placing = board_interactions.placing,
          hovering = board_interactions.hovering,
          hovering_circle = board_interactions.hovering_circle,
          placement_valid = board_interactions.placement_valid,
        })
      end))

      -- 敌人：常驻 Dock 盛放（波次自动生成与编排生成同一序列，「第 N 个
      -- 敌人」序号即 self.enemies 顺序）；死亡敌人 epoch 失活但留在 Dock，
      -- 整局重建（session.restart 拆树）时一并清理。
      local enemies_dock = ss:dock("enemies")
      local enemy_serial = 0

      -- spawn_enemy(spec)：spec = { x, z, tier, heading={x,z} }（GDD 07 W7/E2）。
      -- 数值取 world.enemy_tiers / 全局敌人常量，可被 config.enemy 覆盖。
      local function spawn_enemy(spec)
        enemy_serial = enemy_serial + 1
        local key = "enemy_" .. enemy_serial
        local base_cfg = self.enemy_config
        local tier_cfg = World.enemy_tiers[spec.tier or 1]
        local enemy = get_enemy_class().new({
          host = self.host,
          game_tick = self.game_tick,
          game_state = game_state,
          position = { x = spec.x, y = 0, z = spec.z },
          heading = spec.heading,
          tier = spec.tier,
          prefab = base_cfg.prefab or "enemy",
          max_hp = base_cfg.max_hp or tier_cfg.health,
          move_speed = base_cfg.move_speed or World.enemy_speed,
          stop_distance = base_cfg.stop_distance or World.enemy_stop_distance,
          radius = base_cfg.radius or tier_cfg.footprint,
          enemy_zone = game_state.enemy_zone,
          radar_zone = game_state.radar_zone,
        })

        enemies_dock:call(key, enemy)

        self.enemies[#self.enemies + 1] = enemy
        return enemy
      end
      -- 编排生成经 GM 面直达（tools/acceptance headless 步骤用）。
      self.spawn_enemy = spawn_enemy

      local wave_director = ss:call(WaveDirector.new({
        game_state = game_state,
        game_tick = self.game_tick,
        spawn_enemy = spawn_enemy,
        rng01 = self.wave_director_config.rng01,
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

      -- 实时操作日志：模式切换到终局/胜局时补一条，让玩家知道发生了什么。
      if self.op_log then
        ss:effect("GameRootFull.oplog_mode", function(ms)
          local mode = ms:d(game_state.mode)
          if mode == "GameOver" then
            self.op_log:push("error", "基地被摧毁，对局失败")
          elseif mode == "Victory" then
            self.op_log:push("success", "全部矿点采空，胜利！")
          end
        end, game_state.mode)
      end

    end))
  end,
})

return GameRootFull
