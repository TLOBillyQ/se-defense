-- 05_BaseDefence 组合根。
--
-- 职责：把 GameState、Core、WaveDirector、Resource 矿点与 UI 挂载到同一棵
-- SpokeTree 下，并注入 spawn_enemy 把每个 Enemy 挂进树里。胜负条件由
-- GameState 统一判定：所有矿点采空 → Victory；Core 死亡 → GameOver。
-- Restart（无场景重载的宿主等价物）见 server/game/session.lua。
--
-- 集成范式：Auto-first（ADR 0004）。本文件只提供组合根 Epoch；宿主/测试按
-- 需要选择 SpokeTree.spawn（Auto）或 spawn_manual（Manual）。生产环境用 Auto：
-- 宿主事件回调里改状态 → SpokeRuntime 同步排空 → 渲染在回调返回前完成。
-- 无头测试使用 Manual 树 + game_tick:advance(...) 进行确定性步进。

local spoke = require("common.spoke")
local Epoch = spoke.Epoch
local Effect = spoke.Effect

local World = require("server.game.world")
local GameState = require("server.game.game_state")
local Core = require("server.game.core")
local WaveDirector = require("server.game.wave_director")
local Resource = require("server.game.resource")
local StatusUI = require("server.game.status_ui")
local SideBar = require("server.game.sidebar")
local Announcer = require("server.game.announcer")

-- 确保 s:coroutine 扩展已加载（WaveDirector、Enemy、Core/Resource 电网都依赖它）。
require("server.game.coroutine")

-- Enemy 采用惰性 require，避免在加载本组合根时污染 package.loaded。
-- 本组合根属于真实切片，因此加载 Enemy 前重置 Health/Enemy 缓存，确保使用
-- 真实 Health 实现（部分组件测试会注入 Health stub，不影响此处）。
local Enemy
local function get_enemy_class()
  if not Enemy then
    package.loaded["server.game.health"] = nil
    package.loaded["server.game.enemy"] = nil
    Enemy = require("server.game.enemy")
  end
  return Enemy
end

local host_default = require("server.adapter.host")

-- 默认矿点：贴近 Core，使默认配置无需放置 relay 即可开始采掘。
local function default_resources()
  return {
    { position = { x = -2.5, y = 0, z = 2.5 }, start_resources = 20 },
    { position = { x = 2.5, y = 0, z = 2.5 }, start_resources = 20 },
    { position = { x = -2.5, y = 0, z = -2.5 }, start_resources = 20 },
    { position = { x = 2.5, y = 0, z = -2.5 }, start_resources = 20 },
  }
end

local GameRoot = Epoch.extend("GameRoot", {
  constructor = function(self, config)
    config = config or {}
    self.host = config.host or host_default
    self.game_tick = config.game_tick or error("GameRoot requires game_tick", 2)

    self.game_state_config = config.game_state or {}
    self.game_state_config.host = self.game_state_config.host or self.host
    self.game_state_config.game_tick = self.game_state_config.game_tick or self.game_tick
    -- 组合根始终使用完整 Core 组件（电网根），GameState 的内建 Core 只保留给
    -- 单元测试与更小的自定义组合使用。
    self.game_state_config.core = self.game_state_config.core or "external"

    self.core_config = config.core or {}
    self.wave_director_config = config.wave_director or {}
    self.enemy_config = config.enemy or {}
    self.resource_configs = config.resources
    if self.resource_configs == nil then
      self.resource_configs = default_resources()
    end

    self.game_state = nil
    self.core = nil
    self.wave_director = nil
    self.status_ui = nil
    self.side_bar = nil
    self.announcer = nil
    self.enemies = {}
    self.resources = {}
  end,

  init = function(self, s)
    -- effect/memo/phase/dock/subscribe 等组合原语只在 EffectBuilder 上，
    -- 所以用一个不读信号的 Effect 子 epoch 当组合作用域。
    s:call(Effect.new("GameRoot.Composition", function(ss)
      local game_state = ss:call(GameState.new(self.game_state_config))
      self.game_state = game_state

      -- Core 必须在 wave/resource/UI 之前挂载：它是电网根，也是 GameState
      -- 的失败条件与敌人目标。
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

      -- 敌人：常驻 Dock 盛放（与 GameRootFull 同一范式；GDD 07）。
      local enemies_dock = ss:dock("enemies")
      local enemy_serial = 0

      local function spawn_enemy(spec)
        enemy_serial = enemy_serial + 1
        local key = "enemy_" .. enemy_serial
        local tier_cfg = World.enemy_tiers[spec.tier or 1]
        local enemy = get_enemy_class().new({
          host = self.host,
          game_tick = self.game_tick,
          game_state = game_state,
          position = { x = spec.x, y = 0, z = spec.z },
          heading = spec.heading,
          tier = spec.tier,
          max_hp = self.enemy_config.max_hp or tier_cfg.health,
          move_speed = self.enemy_config.move_speed or World.enemy_speed,
          stop_distance = self.enemy_config.stop_distance or World.enemy_stop_distance,
          radius = self.enemy_config.radius or tier_cfg.footprint,
        })

        enemies_dock:call(key, enemy)

        self.enemies[#self.enemies + 1] = enemy
        return enemy
      end

      local wave_director = ss:call(WaveDirector.new({
        game_state = game_state,
        game_tick = self.game_tick,
        spawn_enemy = spawn_enemy,
        rng01 = self.wave_director_config.rng01,
      }))
      self.wave_director = wave_director

      -- 预置矿点：接真电网（Core 为根），非 Playing / 空袭 / 断电时暂停采掘。
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

      -- 最简文本 HUD（#20 切片遗留）与完整 SideBar/Announcer（#23）并存：
      -- 前者保持旧 e2e 的 hud/* 路径稳定，后者补齐四面板路由与事件播报。
      self.status_ui = ss:call(StatusUI.new({
        host = self.host,
        game_state = game_state,
        wave_director = wave_director,
      }))

      self.side_bar = ss:call(SideBar.new({
        host = self.host,
        game_state = game_state,
        wave_director = wave_director,
      }))

      self.announcer = ss:call(Announcer.new({
        host = self.host,
        game_state = game_state,
        wave_director = wave_director,
        game_tick = self.game_tick,
      }))

    end))
  end,
})

return GameRoot
