local SpokeHandle = {}
SpokeHandle.__index = SpokeHandle

function SpokeHandle.of(id, on_dispose)
  if on_dispose ~= nil and type(on_dispose) ~= "function" then
    error("SpokeHandle.on_dispose must be a function", 2)
  end
  return setmetatable({
    _id = id,
    _on_dispose = on_dispose,
  }, SpokeHandle)
end

function SpokeHandle.new()
  return SpokeHandle.of(nil, nil)
end

function SpokeHandle.is(value)
  return type(value) == "table" and getmetatable(value) == SpokeHandle
end

function SpokeHandle:dispose()
  local on_dispose = self._on_dispose
  if on_dispose then
    self._on_dispose = nil
    on_dispose(self._id)
  end
end

return SpokeHandle
