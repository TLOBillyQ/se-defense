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

local Relay = require("src.game.relay")
local Radar = require("src.game.radar")
local Turret = require("src.game.turret")
local Repair = require("src.game.repair")

local host_default = require("src.adapter.host")

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

  local defaults = {
    relay = {
      key = "relay",
      prefab = "relay",
      cost = 50,
      radius = 0.6,
      coverage = "Power",
      building = {
        max_hp = 30,
        display_name = "Relay",
        provide_range = 4,
        receive_range = 0.1,
      },
    },
    radar = {
      key = "radar",
      prefab = "radar",
      cost = 75,
      radius = 0.4,
      coverage = "Radar",
      building = {
        max_hp = 25,
        display_name = "Radar",
        range = 8,
      },
    },
    turret = {
      key = "turret",
      prefab = "turret",
      cost = 100,
      radius = 0.6,
      coverage = "Turret",
      building = {
        max_hp = 40,
        display_name = "Turret",
        range = 5,
        damage = 1,
        fire_rate = 2,
      },
    },
    repair = {
      key = "repair",
      prefab = "repair",
      cost = 80,
      radius = 0.6,
      coverage = "Repair",
      building = {
        max_hp = 30,
        display_name = "Repair",
        range = 5,
        repair_rate = 5,
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
