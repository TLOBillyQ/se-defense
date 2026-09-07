-- Walking and rendering an epoch tree for a trace: the structural hooks every
-- epoch exposes, the roots reachable from a set of frames, and the indented
-- depth-first dump.
--
-- Split out of spoke_introspect.lua, which assembles the full trace text.
local IntrospectLabels = require("common.spoke.runtime.introspect_labels")

local IntrospectTree = {}

-- Direct children of an epoch, delegated to the internal _get_children hook
-- (Dock overrides it to walk slot children). Every real Epoch provides the
-- hook, so there is deliberately no attachment-walking fallback; duck-typed
-- callers without the hook simply contribute no children.
function IntrospectTree.get_children(epoch, store)
  store = store or {}
  if type(epoch._get_children) == "function" then
    return epoch:_get_children(store)
  end
  return store
end

function IntrospectTree.get_parent(epoch)
  if type(epoch._get_parent) == "function" then
    return epoch:_get_parent()
  end
  return epoch._parent
end

local function walk_children(epoch, visit)
  for _, child in ipairs(IntrospectTree.get_children(epoch)) do
    visit(child)
  end
end

function IntrospectTree.count_nodes(epoch)
  local count = 1
  walk_children(epoch, function(child)
    count = count + IntrospectTree.count_nodes(child)
  end)
  return count
end

local function collect_distinct(values, key_of)
  local distinct = {}
  local seen = {}
  for _, value in ipairs(values) do
    local key = key_of(value)
    if key ~= nil and not seen[key] then
      seen[key] = true
      distinct[#distinct + 1] = key
    end
  end
  return distinct
end

local function root_of(epoch)
  local root = epoch
  while true do
    local parent = IntrospectTree.get_parent(root)
    if parent == nil then
      return root
    end
    root = parent
  end
end

--- The distinct topmost roots reachable from the epochs on the frame stack.
function IntrospectTree.roots_from_frames(frames)
  local epochs = collect_distinct(frames, function(frame)
    return frame.epoch
  end)
  return collect_distinct(epochs, root_of)
end

function IntrospectTree.total_nodes(roots)
  local total = 0
  for _, root in ipairs(roots) do
    total = total + IntrospectTree.count_nodes(root)
  end
  return total
end

--- The indented depth-first dump of every root, one epoch per line.
function IntrospectTree.render(roots, frames)
  local lines = {}
  local function render_epoch(epoch, depth)
    local label = IntrospectLabels.append_fault_suffix(
      IntrospectLabels.frame_epoch_label(epoch, frames), epoch)
    lines[#lines + 1] = string.rep("    ", depth) .. "|--" .. label
    walk_children(epoch, function(child)
      render_epoch(child, depth + 1)
    end)
  end
  for _, root in ipairs(roots) do
    render_epoch(root, 0)
  end
  return table.concat(lines, "\n")
end

return IntrospectTree
