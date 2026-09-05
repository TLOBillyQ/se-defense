local Epoch = require("vendor.spoke.runtime.epoch")
local SpokeRuntime = require("vendor.spoke.runtime.spoke_runtime")
local DockSlots = require("vendor.spoke.runtime.dock_slots")

-- Dock: an Epoch with a dynamic keyed child collection. Children can be attached
-- and detached at any time, outside the Init/Tick builder windows.
--
-- NOTE: In upstream C#, Dock keys are any object (the docs use game-entity
-- instances, e.g. dock.Effect(unit, Aura(unit))). spoke-lua deliberately
-- restricts keys to non-empty strings to match Export/Import key semantics
-- (spec §3.8). When porting C# code that uses entity instances as keys,
-- assign each entity a stable string id (e.g. tostring(entity.id)) and use
-- that instead.

local function identity(value)
  return value
end

-- Guards raise at level 3 so the reported position is the caller of the Dock
-- method, not the guard itself.
local function assert_key(key)
  if type(key) ~= "string" or key == "" then
    error("Dock keys must be non-empty strings", 3)
  end
end

local function assert_unattached_epoch(epoch)
  if type(epoch) ~= "table" or type(epoch._attach) ~= "function" then
    error("Dock:call expects an Epoch", 3)
  end
  if epoch._attached then
    error("Dock:call expects an unattached Epoch", 3)
  end
end

local Dock = Epoch.extend("Dock", {
  constructor = function(self)
    DockSlots.reset(self)
    self._is_detaching = false
  end,

  init = function(self, s)
    s:on_cleanup(function()
      self._is_detaching = true
      DockSlots.detach_all(self)
    end)
    return nil
  end,

  -- Replaces whatever the key held, then files the new epoch in the next slot.
  _install = function(self, key, epoch)
    self:drop(key)
    if DockSlots.should_compact(self) then
      DockSlots.compact(self, false)
    end
    local index = DockSlots.append(self, key, epoch)
    local child_ticker = self._is_ticker and self or self._ticker
    epoch:_attach(self, index, child_ticker, nil, self._tree)
    return epoch
  end,

  call = function(self, key, epoch)
    if self._is_detaching then
      error("Cannot Call while detaching", 2)
    end
    assert_key(key)
    assert_unattached_epoch(epoch)

    SpokeRuntime.push({ type = "Dock", epoch = self, phase = "Dock" })
    local ok, result = xpcall(function()
      return self:_install(key, epoch)
    end, identity)
    SpokeRuntime.pop()

    if not ok then
      error(result, 0)
    end
    return result
  end,

  -- Port of upstream DockExtensions.Dock.Effect: attach a keyed Effect whose
  -- lifetime follows the Dock slot; calling under an existing key detaches the
  -- previous effect first (via call -> drop). Argument shapes match
  -- EffectBuilder:effect: (key, block [, triggers]) or
  -- (key, name, block [, triggers]), with triggers as varargs or one array.
  -- The reactive modules are required lazily to avoid a require cycle
  -- (effect_builder requires dock).
  effect = function(self, a, b, ...)
    assert_key(a)
    local Effect = require("vendor.spoke.reactive.effect")
    local parse_effect_args = require("vendor.spoke.reactive.computation")._parse_effect_args
    local name, block, triggers = parse_effect_args(b, ...)
    if name ~= nil then
      return self:call(a, Effect.new(name, block, triggers))
    end
    return self:call(a, Effect.new(block, triggers))
  end,

  drop = function(self, key)
    if key == nil then
      return
    end
    if type(key) ~= "string" then
      error("Dock keys must be non-empty strings", 2)
    end
    local child = DockSlots.find(self, key)
    if child == nil then
      return
    end

    -- Detaching a child from inside its own frame has to wait for that frame
    -- to pop, or the epoch would tear down under itself.
    local handle = child._frame_handle
    if handle and handle:is_alive() then
      handle:on_pop_self(function()
        child:detach()
      end)
    else
      child:detach()
    end

    DockSlots.release(self, key)
  end,

  _compact = function(self, reindex_all)
    DockSlots.compact(self, reindex_all)
  end,

  _refresh_coords = function(self)
    Epoch._refresh_coords(self)
    -- Dock children live outside the attachment list; compact and renumber
    -- them like upstream Compact(reindexAll: true) so coords stay packable
    -- even when nested docks have holes (each _reindex refreshes the child
    -- subtree's coords).
    DockSlots.compact(self, true)
  end,

  _get_children = function(self, store)
    return DockSlots.children(self, store)
  end,
})

return Dock
