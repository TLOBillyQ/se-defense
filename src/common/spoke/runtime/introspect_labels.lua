-- How epochs and frames are labelled in a trace: the type name, the frame kind,
-- the fault suffix, and the frame indices an epoch appears at.
--
-- Split out of spoke_introspect.lua so both the frame trace and the tree trace
-- render names the same way.
local IntrospectLabels = {}

-- SE server Lua sandbox may not expose the standard `rawequal` function.
-- Frame/epoch identity is what matters here; epochs never overload __eq, so
-- `==` behaves as raw equality in practice.
local rawequal = rawequal or function(a, b) return a == b end

function IntrospectLabels.frame_kind(frame)
  return frame.type or frame.kind or "None"
end

function IntrospectLabels.epoch_type_name(epoch)
  if type(epoch) ~= "table" then
    return "<unknown>"
  end
  local metatable = getmetatable(epoch)
  if type(metatable) ~= "table" then
    return "<unknown>"
  end
  -- Base Epoch has no _default_name; every extended class sets one.
  return metatable._default_name or "Epoch"
end

function IntrospectLabels.epoch_frame_name(epoch)
  if epoch == nil then
    return "<null>"
  end
  return tostring(epoch)
end

function IntrospectLabels.append_fault_suffix(label, epoch)
  if type(epoch) == "table" and epoch.fault ~= nil then
    label = label .. " [Faulted: " .. tostring(epoch.fault.cause) .. "]"
  end
  return label
end

--- An epoch's tree-trace label, prefixed with the frame indices it occupies.
function IntrospectLabels.frame_epoch_label(epoch, frames)
  local indices = {}
  for index, frame in ipairs(frames) do
    if rawequal(frame.epoch, epoch) then
      indices[#indices + 1] = tostring(index - 1)
    end
  end
  if #indices == 0 then
    return tostring(epoch)
  end
  return "(" .. table.concat(indices, ",") .. ")-" .. tostring(epoch)
end

return IntrospectLabels
