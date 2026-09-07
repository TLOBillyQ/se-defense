local Epoch = require("common.spoke.runtime.epoch")
local Ticker = require("common.spoke.runtime.ticker")
local SpokeError = require("common.spoke.runtime.spoke_error")
local SpokeRuntime = require("common.spoke.runtime.spoke_runtime")
local Ordering = require("common.spoke.runtime.ordering")
local TreeFlush = require("common.spoke.runtime.spoke_tree_flush")

local SpokeTree = {}
SpokeTree.__index = SpokeTree
SpokeTree.__tostring = Epoch.__tostring
SpokeTree._default_name = "SpokeTree"
SpokeTree.is_ticker = true
SpokeTree.auto_arm_tick_after_init = false
setmetatable(SpokeTree, { __index = Ticker })

local function identity(value)
  return value
end

-- Bootstrap runs inside its own runtime frame so anything the root attaches can
-- see a Bootstrap frame on the stack. An Auto tree flushes once inside that
-- frame (when the root attached cleanly) and again after it pops.
local function run_bootstrap(tree, mode, services)
  tree._bootstrapping = true
  tree._timestamp = SpokeRuntime.next_timestamp()
  SpokeRuntime.try_scoped_layer_boost(tree)
  SpokeRuntime.push({
    type = "Bootstrap",
    epoch = tree,
    phase = "Bootstrap",
  })
  local ok, error_value = xpcall(function()
    tree:_attach(nil, 0, nil, services, tree)
  end, identity)
  tree._bootstrapping = false
  if ok and mode == "Auto" then
    SpokeRuntime.try_flush()
  end
  SpokeRuntime.pop()
  return ok, error_value
end

local function create(name, root, mode, layer, services)
  if type(root) ~= "table" or type(root._attach) ~= "function" then
    error("SpokeTree.spawn expects an unattached Epoch root", 2)
  end
  local tree = Epoch._new_instance(
    SpokeTree,
    name,
    root,
    mode,
    layer,
    services)
  local ok, error_value = run_bootstrap(tree, mode, services)
  if not ok then
    tree:_log_error("[SpokeTree] uncaught error in bootstrap", error_value)
  end
  if mode == "Auto" then
    SpokeRuntime.try_flush()
  end
  return tree
end

-- Every spawn entrypoint takes an optional leading name; without one the
-- variant's own default name is used.
local function named_args(default_name, first, second, third)
  if type(first) == "string" then
    return first, second, third
  end
  return default_name, first, second
end

function SpokeTree:constructor(root, mode, layer, services)
  self.main = root
  self.flush_mode = mode or "Auto"
  self._flush_layer = layer or 0
  self.flush_layer = self._flush_layer
  self._is_tree = true
  self._is_manual = self.flush_mode == "Manual"
  -- Note: `x and nil or "flush"` would always yield "flush" (true and nil is
  -- nil, then nil or "flush" wins); manual trees must stay inert until driven.
  self._command = not self._is_manual and "flush" or nil
  self._driving = false
  self._logger = nil
  self._ports = nil
  self._timestamp = nil
  self._runtime_pending = false
end

function SpokeTree.new(first, second, third, fourth, fifth)
  local name, root, mode, layer, services
  if type(first) == "string" then
    name, root, mode, layer, services = first, second, third, fourth, fifth
  else
    name, root, mode, layer, services = "SpokeTree", first, second, third, fourth
  end
  return create(name, root, mode or "Auto", layer or 0, services)
end

function SpokeTree.spawn(first, second, third)
  local name, root, services = named_args("SpokeTree", first, second, third)
  return create(name, root, "Auto", 0, services)
end

function SpokeTree.spawn_eager(first, second, third)
  local name, root, services = named_args("SpokeTree (Eager)", first, second, third)
  return create(name, root, "Auto", -1, services)
end

function SpokeTree.spawn_manual(first, second, third)
  local name, root, services = named_args("SpokeTree (Manual)", first, second, third)
  return create(name, root, "Manual", -math.maxinteger, services)
end

function SpokeTree:bootstrap(s)
  local found, logger = s:try_import("logger")
  if found then
    self._logger = logger
  end
  self._ports = s:ports()
  s:on_tick(function(context)
    self:_drive_pending(context)
  end)
  return self.main
end

-- Trees are ordered by flush layer, then by the order they were created; the
-- runtime's own comparator adds the scoped-boost tier on top of this.
function SpokeTree:compare_to(other)
  local by_layer = Ordering.compare(self._flush_layer, other._flush_layer)
  if by_layer ~= 0 then
    return by_layer
  end
  return Ordering.compare(self._timestamp, other._timestamp)
end

function SpokeTree:_log_error(message, error_value)
  local logger = self._logger
  if type(logger) == "table" and type(logger.error) == "function" then
    pcall(function()
      logger:error(message .. "\n" .. tostring(error_value))
    end)
  else
    SpokeError.log(message, error_value)
  end
end

function SpokeTree:_drive_pending(context)
  TreeFlush.drive(self, context)
end

function SpokeTree:_drive_manual(command)
  if self.flush_mode ~= "Manual" then
    error("Only Manual trees can be explicitly driven", 2)
  end
  if self._driving then
    error("Re-entrant flush detected", 2)
  end
  if self.is_detached then
    return
  end
  self._driving = true
  self._command = command
  SpokeRuntime.tick_tree(self)
  self._command = nil
  self._driving = false
end

function SpokeTree:flush()
  self:_drive_manual("flush")
end

function SpokeTree:tick()
  self:_drive_manual("tick")
end

function SpokeTree:dispose()
  self:detach()
end

return SpokeTree
