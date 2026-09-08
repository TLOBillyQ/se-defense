-- 05_BaseDefence 四建筑 Pool spec 定义。
--
-- 职责：为 Pool 提供 relay / radar / turret / repair 四种建筑的标准 spec。
-- 每个 spec 包含 {key, prefab, cost, radius, coverage, create}，其中 create(ctx)
-- 接收 {entity, position} 并返回对应建筑 Epoch。
--
-- 使用方式：
--   local specs = building_specs.create({ host=host, game_state=game_state,
--                                         game_tick=game_tick, pool=pool })
--   local inst = pool:spawn(specs.turret, position)
--   inst.epoch.pool_instance = inst   -- 使建筑死亡时能被 Pool 回收
--
-- 本模块只定义标准属性；宿主适配层可通过覆盖表调整 cost/range/hp 等数值。

local Relay = require("server.power.relay")
local Radar = require("server.defense.radar")
local Turret = require("server.defense.turret")
local Repair = require("server.defense.repair")

local World = require("server.kernel.world_data")

local host_default = require("server.host")

local BuildingSpecs = {}

-- 合并覆盖表：base 为默认值，overrides 为调用方提供的覆盖（可嵌套）。
local function merge(base, overrides)
  if not overrides then
    return base
  end
  local out = {}
  for k, v in pairs(base) do
    out[k] = v
  end
  for k, v in pairs(overrides) do
    if type(v) == "table" and type(out[k]) == "table" then
      out[k] = merge(out[k], v)
    else
      out[k] = v
    end
  end
  return out
end

function BuildingSpecs.create(deps)
  deps = deps or {}
  local host = deps.host or host_default
  local game_state = deps.game_state or error("BuildingSpecs requires game_state", 2)
  local game_tick = deps.game_tick or error("BuildingSpecs requires game_tick", 2)
  local pool = deps.pool

  -- GDD 00 实体总表（数值真源 server/kernel/world_data.lua）。
  local specs = World.specs
  local defaults = {
    relay = {
      key = "relay",
      prefab = "relay",
      cost = specs.Relay.price,
      radius = specs.Relay.footprint,
      coverage = "Power",
      building = {
        max_hp = specs.Relay.health,
        display_name = "Relay",
        provide_range = specs.Relay.provide,
        receive_range = specs.Relay.receive,
      },
    },
    radar = {
      key = "radar",
      prefab = "radar",
      cost = specs.Radar.price,
      radius = specs.Radar.footprint,
      coverage = "Radar",
      building = {
        max_hp = specs.Radar.health,
        display_name = "Radar",
        range = specs.Radar.range,
      },
    },
    turret = {
      key = "turret",
      prefab = "turret",
      cost = specs.Turret.price,
      radius = specs.Turret.footprint,
      coverage = "Turret",
      building = {
        max_hp = specs.Turret.health,
        display_name = "Turret",
        range = specs.Turret.range,
        damage = World.fire_damage,
        fire_rate = 1 / World.fire_interval,
        fire_angle = World.turret_fire_angle,
        rotation_speed = World.turret_turn_rate,
        beam_flash_time = World.fire_beam,
      },
    },
    repair = {
      key = "repair",
      prefab = "repair",
      cost = specs.Repair.price,
      radius = specs.Repair.footprint,
      coverage = "Repair",
      building = {
        max_hp = specs.Repair.health,
        display_name = "Repair",
        range = specs.Repair.range,
        repair_rate = World.repair_rate,
      },
    },
  }
  local cfg = merge(defaults, deps.overrides)

  local function make(spec_cfg, EpochClass, extra)
    return {
      key = spec_cfg.key,
      prefab = spec_cfg.prefab,
      cost = spec_cfg.cost,
      radius = spec_cfg.radius,
      coverage = spec_cfg.coverage,
      create = function(ctx)
        local b = spec_cfg.building
        local args = {
          host = host,
          entity = ctx.entity,
          max_hp = b.max_hp,
          display_name = b.display_name,
          radius = spec_cfg.radius,
          power_zone = game_state.power_zone,
          ground_zone = game_state.ground_zone,
          game_tick = game_tick,
          pool = pool,
        }
        for k, v in pairs(extra or {}) do
          args[k] = v
        end
        for k, v in pairs(b) do
          if args[k] == nil then
            args[k] = v
          end
        end
        return EpochClass.new(args)
      end,
    }
  end

  return {
    relay = make(cfg.relay, Relay, {}),
    radar = make(cfg.radar, Radar, { radar_zone = game_state.radar_zone }),
    turret = make(cfg.turret, Turret, {
      enemy_zone = game_state.enemy_zone,
      turret_zone = game_state.turret_zone,
    }),
    repair = make(cfg.repair, Repair, {
      repair_zone = game_state.repair_zone,
    }),
  }
end

return BuildingSpecs
