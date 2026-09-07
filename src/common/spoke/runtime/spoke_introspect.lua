-- SpokeIntrospect: structural introspection for debugging reactive trees,
-- porting upstream SpokeIntrospect's TreeTrace/FrameTrace rendering. The
-- epoch hooks (_get_children / _get_parent) already exist on every epoch;
-- this module is the user-facing renderer built on them.
local IntrospectLabels = require("common.spoke.runtime.introspect_labels")
local IntrospectTree = require("common.spoke.runtime.introspect_tree")

local SpokeIntrospect = {}

local FRAME_TRACE_HEADER = "<------------ Spoke Frame Trace ------------>"
local TREE_TRACE_HEADER = "<------------ Spoke Tree Trace ------------>"
local TREE_SIZE_THRESHOLD = 50

SpokeIntrospect.get_children = IntrospectTree.get_children
SpokeIntrospect.get_parent = IntrospectTree.get_parent

-- Frame trace: one numbered line per frame, outermost first, 0-based and
-- right-aligned to the digit count of the frame count. Accepts the snapshot
-- from SpokeRuntime.snapshot_frames().
function SpokeIntrospect.stack_trace(frames)
  frames = frames or {}
  if #frames == 0 then
    return "(empty)"
  end

  local width = #tostring(#frames)
  local lines = {}
  for index, frame in ipairs(frames) do
    local epoch = frame.epoch
    local label = string.format(
      "%s: %s %s <%s>",
      string.format("%" .. width .. "d", index - 1),
      IntrospectLabels.frame_kind(frame),
      IntrospectLabels.epoch_frame_name(epoch),
      IntrospectLabels.epoch_type_name(epoch))
    lines[index] = IntrospectLabels.append_fault_suffix(label, epoch)
  end
  return table.concat(lines, "\n")
end

-- Compatibility alias kept for callers of the original #35 implementation;
-- both names render the same numbered frame lines.
SpokeIntrospect.frame_trace = SpokeIntrospect.stack_trace

-- A big tree is summarized rather than dumped: the trace is a debugging aid,
-- not a serialization format.
local function tree_section(roots, frames)
  local total_nodes = IntrospectTree.total_nodes(roots)
  if total_nodes > TREE_SIZE_THRESHOLD then
    return "(tree too large to display - " .. total_nodes .. " nodes)"
  end
  return IntrospectTree.render(roots, frames)
end

-- Tree trace: a header, the frame trace, a second header, then a DFS dump of
-- every topmost root reachable from the frame epochs.
function SpokeIntrospect.tree_trace(frames)
  frames = frames or {}
  if #frames == 0 then
    return "(empty)"
  end

  local roots = IntrospectTree.roots_from_frames(frames)
  return FRAME_TRACE_HEADER
    .. "\n" .. SpokeIntrospect.stack_trace(frames)
    .. "\n" .. TREE_TRACE_HEADER
    .. "\n" .. tree_section(roots, frames)
end

return SpokeIntrospect
