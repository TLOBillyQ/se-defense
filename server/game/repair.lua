-- 05_BaseDefence 维修塔组件。
--
-- 职责：通电且存活时，持续修复射程内 HP 占比最低的友方建筑，每次只修一个；
--       满血、死亡或离开范围后释放当前伤员并重新选择。
-- 对应上游 Examples/05_BaseDefence/Scripts/Units/Buildings/Repair.cs。
--
-- 既定裁剪（ADR）：
--   - 没有单独的 fireFrom GameObject，光束起点即实体位置；
--   - 光束用 EUI line 节点表达；
--   - 覆盖圈注册到 repair_zone，由外部按需渲染；
--   - 不自建 GameObject 中间层。

local spoke = require("common.spoke")
local Epoch = spoke.Epoch
local State = spoke.State
local Effect = spoke.Effect
local Memo = spoke.Memo
local Phase = require("common.spoke.reactive.phase")
local Building = require("server.game.building")
local PowerNode = require("server.game.power_node")

-- 注册 s:coroutine() 扩展。
require("server.game.coroutine")

local Repair
Repair = Epoch.extend("Repair", {
  constructor = function(self, config)
    config = config or {}
    self.host = config.host or require("server.adapter.host")
    self.entity = config.entity or error("Repair requires entity", 2)
    self.max_hp = config.max_hp or error("Repair requires max_hp", 2)
    self.display_name = config.display_name or "Repair"
    self.radius = config.radius or 0.5
    self.range = config.range or 5
    self.repair_rate = config.repair_rate or 0.5
    self.power_zone = config.power_zone or error("Repair requires power_zone", 2)
    self.repair_zone = config.repair_zone or error("Repair requires repair_zone", 2)
    self.ground_zone = config.ground_zone or error("Repair requires ground_zone", 2)
    self.game_tick = config.game_tick or error("Repair requires game_tick", 2)
    self.pool = config.pool
    self.pool_instance = config.pool_instance

    self.building = nil
    self.health = nil
    self.power_node = nil
    self.hover_info = nil
    self.patient = nil
  end,

  init = function(self, s)
    local host = self.host
    local entity = self.entity
    local game_tick = self.game_tick

    -- 1. 电力网叶子节点：只取电，不向外供电。
    self.power_node = s:call(PowerNode.new({
      is_root = false,
      receive_range = 0.1,
      provide_range = 0,
      get_position = function()
        return entity:get_position()
      end,
      power_zone = self.power_zone,
      game_tick = game_tick,
    }))

    -- 2. 组合 Building 兄弟组件：负责生命值、footprint、受击反馈与死亡回收。
    self.building = s:call(Building.new({
      host = host,
      entity = entity,
      max_hp = self.max_hp,
      display_name = self.display_name,
      radius = self.radius,
      ground_zone = self.ground_zone,
      -- footprint owner 指向本组件（带 hover_info），悬停命中才能取到描述。
      ground_collider_owner = self,
      power = self.power_node,
      game_tick = game_tick,
      pool = self.pool,
      pool_instance = self.pool_instance,
    }))
    self.health = self.building.health

    -- 3. 悬浮提示。
    self.hover_info = State.new({
      description = self.display_name:upper() .. "\n\n" ..
        "Repairs the most damaged building inside its coverage, one at a time.\n\n" ..
        "Repair buildings can mend each other, but never themselves.",
      coverage = "Repair",
      power_node = self.power_node,
    })

    -- 4. 光束 EUI 节点。
    local beam_path = "repair_" .. entity.id .. "_beam"
    local beam_node = host.eui.node(beam_path)
    beam_node:set_visible(false)

    -- 5. 运转条件：存活且通电。
    local is_running = s:call(Memo.new("Repair.is_running", function(m)
      return m:d(self.health.is_alive) and m:d(self.power_node.has_power)
    end, self.health.is_alive, self.power_node.has_power))

    -- 6. 当前伤员（存 owner 对象而非 Health）。
    self.patient = State.new("Repair.patient", nil)

    s:call(Phase.new("Repair.running", is_running, function(s2)
      -- 断电或死亡时清空当前伤员，避免状态残留。
      s2:on_cleanup(function()
        self.patient:set(nil)
      end)

      -- 注册维修覆盖圈，供状态 UI / 范围查询使用。
      s2:use(self.repair_zone:add_collider(self, function()
        return { center = entity:get_position(), radius = self.range }
      end))

      -- 扫描地面碰撞体（Building/Core 的 footprint）。
      local sensor = s2:use(self.ground_zone:add_sensor(function()
        return { center = entity:get_position(), radius = self.range }
      end))

      -- (a) 释放：伤员满血或已离开 sensor 范围。
      s2:call(Effect.new("Repair.release_patient", function(s3)
        local patient = s3:d(self.patient)
        if patient == nil then
          return
        end
        if s3:d(patient.health.hp_fraction) >= 1 then
          self.patient:set(nil)
          return
        end
        for _, body in ipairs(s3:d(sensor.overlaps)) do
          if body.owner == patient then
            return
          end
        end
        self.patient:set(nil)
      end, self.patient, sensor.overlaps))

      -- (b) 选择：范围内 HP 占比最低且 < 1 的建筑；跳过自己。
      s2:call(Effect.new("Repair.find_patient", function(s3)
        if s3:d(self.patient) ~= nil then
          return
        end
        local best = nil
        local best_frac = 1
        for _, body in ipairs(s3:d(sensor.overlaps)) do
          local owner = body.owner
          if owner ~= self.building and owner ~= self then
            if owner.health and owner.entity then
              local frac = s3:d(owner.health.hp_fraction)
              if frac < best_frac then
                best_frac = frac
                best = owner
              end
            end
          end
        end
        self.patient:set(best)
      end, self.patient, sensor.overlaps))

      -- (c) 修复：拉住光束并每 tick 回血。
      s2:call(Effect.new("Repair.do_repair", function(s3)
        local patient = s3:d(self.patient)
        if patient == nil then
          return
        end
        s3:effect("Repair.beam_and_heal", function(s4)
          beam_node:set_line(entity:get_position(), patient.entity:get_position())
          beam_node:set_visible(true)
          s4:on_cleanup(function()
            beam_node:set_visible(false)
          end)

          s4:coroutine(game_tick, function(yield)
            local last_time = game_tick:time()
            while true do
              yield()
              local now = game_tick:time()
              local dt = now - last_time
              last_time = now
              patient.health:repair(self.repair_rate * dt)
            end
          end)
        end)
      end, self.patient))
    end))

    s:on_cleanup(function()
      host.eui.destroy(beam_node)
    end)
  end,
})

return Repair
