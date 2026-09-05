local SpokeError = {}

local function render(message, cause)
  local text = tostring(message)
  if cause ~= nil then
    text = text .. "\n" .. tostring(cause)
  end
  return text
end

SpokeError.log = function(message, cause)
  if type(print) == "function" then
    local traceback = type(debug) == "table" and debug.traceback or nil
    local suffix = traceback and ("\n" .. traceback("", 2)) or ""
    print(render(message, cause) .. suffix)
  end
end

SpokeError.default_logger = {
  log = function(_, message)
    SpokeError.log(message)
  end,
  error = function(_, message)
    SpokeError.log(message)
  end,
}

return SpokeError
