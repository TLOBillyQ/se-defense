-- 05_BaseDefence 对象池。
--
-- 对应上游 Examples/05_BaseDefence/Scripts/Pool.cs 的 Spawn/Despawn 语义，
-- 但按本端口无 GameObject 的假设重新实现：
--   - 池化单元 = 宿主实体复用 + 每次 spawn 新建 epoch；
--   - 实体按 spec.key 分 idle 栈；
--   - 复用时 set_position + set_active(true)，然后 spec.create(ctx) 生成新 epoch
--     并挂到内部 Dock；
--   - Despawn 时 Dock drop 摘掉 epoch（触发其 cleanup/生命周期重置），实体
--     set_active(false) 回 idle 栈；
--   - 外来（非本池 spawn 的）实体 Despawn 直接 destroy，与上游 Pool.cs 一致。
--
-- 状态重置（如 Health 回满）靠 epoch detach/attach 生命周期自然发生，Pool
-- 自身不维护业务状态。
--
-- 本实现不做 prewarm（上游 PrewarmEntry），由后续 ticket 扩展；文件头注明。
--
-- 关于 flush 中自回收：despawn 直接操作 Dock:drop。Dock 会在被 drop 的 epoch
-- 自己的 frame handle 存活时通过 on_pop_self 延迟 detach 到当前帧结束，因此
-- 在 effect / tick 内调用是安全的，无需额外批处理。

local spoke = require("common.spoke")
local Epoch = spoke.Epoch
local Dock = spoke.Dock

local Pool = Epoch.extend("Pool", {
  constructor = function(self, config)
    config = config or {}
    self.host = config.host or error("Pool requires host", 2)
    self._live_by_entity_id = {}
    self._idle_by_key = {}
    self._idle_entity_ids = {}
    self._next_serial = 1
    self._live_dock = nil
  end,

  init = function(self, s)
    self._live_dock = s:call(Dock.new("Pool.Live"))

    s:on_cleanup(function()
      -- Pool 销毁时先 drop 所有 live epoch，让它们各自清理；再销毁剩余实体
      -- （包括 live epoch 未自行 destroy 的实体）以及所有 idle 实体。
      local live_records = {}
      for _, record in pairs(self._live_by_entity_id) do
        live_records[#live_records + 1] = record
      end
      for _, record in ipairs(live_records) do
        self._live_dock:drop(record.dock_key)
      end
      for _, record in ipairs(live_records) do
        record.entity:destroy()
      end
      for _, stack in pairs(self._idle_by_key) do
        for _, entity in ipairs(stack) do
          entity:destroy()
        end
      end
      self._live_by_entity_id = {}
      self._idle_by_key = {}
      self._idle_entity_ids = {}
    end)
  end,
})

function Pool:spawn(spec, position)
  if not self._live_dock then
    error("Pool must be attached to a tree before spawn", 2)
  end
  if type(spec) ~= "table"
      or type(spec.key) ~= "string"
      or type(spec.prefab) ~= "string"
      or type(spec.create) ~= "function" then
    error("Pool:spawn expects spec with key, prefab, create", 2)
  end

  local idle_stack = self._idle_by_key[spec.key]
  local entity
  local reused = false

  if idle_stack and #idle_stack > 0 then
    entity = table.remove(idle_stack)
    entity:set_position(position)
    entity:set_active(true)
    self._idle_entity_ids[entity.id] = nil
    reused = true
  else
    entity = self.host.entity.spawn(spec.prefab, position)
  end

  local dock_key = "live_" .. self._next_serial
  self._next_serial = self._next_serial + 1

  local ok, epoch_or_err = pcall(function()
    return spec.create({ entity = entity, position = position })
  end)

  if not ok then
    if reused then
      entity:set_active(false)
      table.insert(idle_stack, entity)
      self._idle_entity_ids[entity.id] = true
    else
      entity:destroy()
    end
    error(epoch_or_err, 0)
  end

  local epoch = epoch_or_err
  local ok2, err2 = pcall(function()
    self._live_dock:call(dock_key, epoch)
  end)

  if not ok2 then
    if type(epoch.detach) == "function" then
      pcall(epoch.detach, epoch)
    end
    if reused then
      entity:set_active(false)
      table.insert(idle_stack, entity)
      self._idle_entity_ids[entity.id] = true
    else
      entity:destroy()
    end
    error(err2, 0)
  end

  self._live_by_entity_id[entity.id] = {
    entity = entity,
    spec = spec,
    dock_key = dock_key,
    epoch = epoch,
  }

  return { entity = entity, spec = spec, epoch = epoch }
end

function Pool:despawn(inst)
  if not self._live_dock then
    error("Pool must be attached to a tree before despawn", 2)
  end
  if not inst or not inst.entity then
    return
  end
  local entity = inst.entity
  local record = self._live_by_entity_id[entity.id]

  if record then
    self._live_dock:drop(record.dock_key)
    entity:set_active(false)
    local stack = self._idle_by_key[record.spec.key]
    if not stack then
      stack = {}
      self._idle_by_key[record.spec.key] = stack
    end
    table.insert(stack, entity)
    self._idle_entity_ids[entity.id] = true
    self._live_by_entity_id[entity.id] = nil
    return
  end

  if self._idle_entity_ids[entity.id] then
    -- 已经是 idle，幂等忽略
    return
  end

  -- 外来实例：直接 destroy（host.entity.destroy 幂等）
  if entity.id then
    entity:destroy()
  end
end

function Pool:idle_count(key)
  local stack = self._idle_by_key[key]
  return stack and #stack or 0
end

return Pool
