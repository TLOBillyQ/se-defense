-- Minimal property-based testing harness for the offline Lua 5.4 toolchain.
--
-- Not a LuaUnit test: this lives under tests/property/support/ and files under
-- tests/property/ are excluded from tests/run.lua's *_test.lua discovery by
-- name; tests/property/run.lua (via `lua tools/cli.lua property`) runs them here.
--
-- API:
--   property.forall(name, generators, predicate)
--     generators: array of function(rng) -> value (see property.gen.*)
--     predicate:  receives the generated values, returns truthy on pass,
--                 falsy (or a string message) on failure; errors count as
--                 failures too.
--   property.run_all()
--     Runs every registered property for SPOKE_PROPERTY_CASES cases (default
--     200) with a splitmix64 PRNG seeded from SPOKE_PROPERTY_SEED or the
--     clock, always printing the seed so a failure is reproducible. Failures
--     report seed, 1-based case index, the inputs, and a naively shrunk
--     counterexample. Returns true iff all properties passed.
--   property.gen.*   boolean, integer(lo,hi), float(lo,hi), string(max_len,
--                    charset), array(gen, max_len), one_of(...).

local property = {}

-- PRNG: splitmix64, bit-exact on Lua 5.4 integers (wrap at 2^64) -------------

local MASK64 = 0xFFFFFFFFFFFFFFFF

local Rng = {}
Rng.__index = Rng

function Rng.new(seed)
  local self = setmetatable({ state = seed & MASK64 }, Rng)
  for _ = 1, 8 do
    self:next() -- burn-in so close seeds decorrelate quickly
  end
  return self
end

function Rng:next()
  self.state = (self.state + 0x9E3779B97F4A7C15) & MASK64
  local z = self.state
  z = (z ~ (z >> 30)) * 0xBF58476D1CE4E5B9 & MASK64
  z = (z ~ (z >> 27)) * 0x94D049BB133111EB & MASK64
  return (z ~ (z >> 31)) & MASK64
end

function Rng:int(lo, hi)
  return lo + (self:next() % (hi - lo + 1))
end

function Rng:float() -- [0, 1), 53-bit mantissa, never negative
  return (self:next() & 0x1FFFFFFFFFFFFF) / 9007199254740992.0
end

function Rng:boolean()
  return (self:next() & 1) == 1
end

function Rng:pick(values)
  return values[self:int(1, #values)]
end

-- Generators -----------------------------------------------------------------
-- A generator is a plain function(rng) -> value; constructors return them.

local ALL_BYTES = {}
for i = 0, 255 do
  ALL_BYTES[#ALL_BYTES + 1] = i
end

property.gen = {}

function property.gen.boolean(rng)
  return rng:boolean()
end

function property.gen.integer(lo, hi)
  return function(rng)
    return rng:int(lo, hi)
  end
end

function property.gen.float(lo, hi)
  return function(rng)
    return lo + rng:float() * (hi - lo)
  end
end

function property.gen.string(max_len, charset)
  local bytes = charset or ALL_BYTES
  return function(rng)
    local out = {}
    for _ = 1, rng:int(0, max_len) do
      out[#out + 1] = string.char(bytes[rng:int(1, #bytes)])
    end
    return table.concat(out)
  end
end

function property.gen.array(gen, max_len)
  return function(rng)
    local out = {}
    for _ = 1, rng:int(0, max_len) do
      out[#out + 1] = gen(rng)
    end
    return out
  end
end

function property.gen.one_of(...)
  local values = { ... }
  if #values == 1 and type(values[1]) == "table" then
    values = values[1]
  end
  return function(rng)
    local value = values[rng:int(1, #values)]
    if type(value) == "function" then
      return value(rng) -- generator or plain value both accepted
    end
    return value
  end
end

-- Registration and execution -------------------------------------------------

local registered = {}

function property.forall(name, generators, predicate)
  if type(generators) ~= "table" or type(predicate) ~= "function" then
    error("property.forall expects (name, generators, predicate)", 2)
  end
  registered[#registered + 1] = {
    name = name,
    generators = generators,
    predicate = predicate,
  }
end

local function resolve_seed()
  local raw = os.getenv("SPOKE_PROPERTY_SEED")
  if raw and raw ~= "" then
    local seed = tonumber(raw)
    if not seed or seed ~= math.floor(seed) then
      io.stderr:write(string.format(
        "property: invalid SPOKE_PROPERTY_SEED=%q (expected an integer)\n", raw))
      os.exit(1)
    end
    return seed
  end
  return math.floor(os.time() * 1000003 + os.clock() * 1000000)
end

local function resolve_cases()
  local raw = os.getenv("SPOKE_PROPERTY_CASES")
  if not raw or raw == "" then
    return 200
  end
  local n = tonumber(raw)
  if not n or n < 1 then
    io.stderr:write(string.format(
      "property: invalid SPOKE_PROPERTY_CASES=%q, using 200\n", raw))
    return 200
  end
  return math.min(math.floor(n), 100000)
end

local function repr(value, depth)
  depth = depth or 0
  if depth > 4 then
    return "..."
  end
  local kind = type(value)
  if kind == "string" then
    return string.format("%q", value)
  elseif kind == "number" or kind == "boolean" or kind == "nil" then
    return tostring(value)
  elseif kind == "table" then
    if #value > 0 then
      local parts = {}
      for i = 1, math.min(#value, 6) do
        parts[i] = repr(value[i], depth + 1)
      end
      if #value > 6 then
        parts[#parts + 1] = "..."
      end
      return "{" .. table.concat(parts, ", ") .. "}"
    end
    local keys = {}
    for key in pairs(value) do
      keys[#keys + 1] = key
    end
    if #keys == 0 then
      return "{}"
    end
    table.sort(keys, function(a, b)
      return tostring(a) < tostring(b)
    end)
    local parts = {}
    for i = 1, math.min(#keys, 6) do
      local key = keys[i]
      parts[i] = repr(key, depth + 1) .. "=" .. repr(value[key], depth + 1)
    end
    if #keys > 6 then
      parts[#parts + 1] = "..."
    end
    return "{" .. table.concat(parts, ", ") .. "}"
  end
  return tostring(value)
end

-- Run the predicate and map the outcome to (failed, message).
local function outcome(predicate, sample)
  local ok, result = pcall(predicate, table.unpack(sample))
  if not ok then
    return true, tostring(result)
  end
  if result == false or result == nil then
    return true, nil
  end
  if type(result) == "string" then
    return true, result
  end
  return false, nil
end

local function shrink_candidates(value)
  local kind = type(value)
  if kind == "number" and math.type(value) == "integer" then
    local candidates = {}
    if value ~= 0 then
      candidates[#candidates + 1] = 0
    end
    local half = value // 2
    if half ~= value and half ~= 0 then
      candidates[#candidates + 1] = half
    end
    return candidates
  elseif kind == "string" then
    local candidates = {}
    if #value > 0 then
      candidates[#candidates + 1] = ""
      if #value > 1 then
        candidates[#candidates + 1] = value:sub(1, #value // 2)
      end
    end
    return candidates
  elseif kind == "table" and #value > 0 then
    local candidates = { {} }
    if #value > 1 then
      local shorter = {}
      for i = 1, #value - 1 do
        shorter[i] = value[i]
      end
      candidates[#candidates + 1] = shorter
    end
    return candidates
  end
  return {}
end

-- Naive shrink loop: greedily replace one argument at a time with a smaller
-- candidate while the predicate still fails. Honest and simple on purpose.
local function shrink(sample, predicate)
  local current, message = sample, nil
  for _ = 1, 40 do
    local improved = false
    for i = 1, #current do
      for _, candidate in ipairs(shrink_candidates(current[i])) do
        local trial = {}
        for j = 1, #current do
          trial[j] = current[j]
        end
        trial[i] = candidate
        local failed, trial_message = outcome(predicate, trial)
        if failed then
          current = trial
          message = trial_message
          improved = true
          break
        end
      end
      if improved then
        break
      end
    end
    if not improved then
      break
    end
  end
  return current, message
end

function property.run_all()
  local seed = resolve_seed()
  local cases = resolve_cases()
  io.write(string.format("property: seed=%d cases=%d\n", seed, cases))

  local total_cases = 0
  local failures = 0
  for index, entry in ipairs(registered) do
    local rng = Rng.new(seed + index)
    local failed_case = nil
    local failed_sample = nil
    local failed_message = nil
    for case_index = 1, cases do
      local sample = {}
      local ok = true
      for _, gen in ipairs(entry.generators) do
        local gen_ok, value = pcall(gen, rng)
        if not gen_ok then
          ok = false
          failed_case = case_index
          failed_sample = sample
          failed_message = "generator failed: " .. tostring(value)
          break
        end
        sample[#sample + 1] = value
      end
      if ok then
        local failed, message = outcome(entry.predicate, sample)
        if failed then
          failed_case = case_index
          failed_sample = sample
          failed_message = message
          break
        end
      end
      total_cases = total_cases + 1
    end

    if failed_case then
      failures = failures + 1
      io.write(string.format("FAIL %s (case %d of %d)\n", entry.name, failed_case, cases))
      io.write(string.format("  seed=%d\n", seed))
      local inputs = {}
      for i = 1, #failed_sample do
        inputs[i] = repr(failed_sample[i])
      end
      io.write("  inputs: " .. table.concat(inputs, ", ") .. "\n")
      if failed_message then
        io.write("  message: " .. failed_message .. "\n")
      end
      local shrunk, shrunk_message = shrink(failed_sample, entry.predicate)
      local changed = #shrunk ~= #failed_sample
      if not changed then
        for i = 1, #shrunk do
          if shrunk[i] ~= failed_sample[i] then
            changed = true
            break
          end
        end
      end
      if changed then
        local shrunk_inputs = {}
        for i = 1, #shrunk do
          shrunk_inputs[i] = repr(shrunk[i])
        end
        io.write("  shrunk: " .. table.concat(shrunk_inputs, ", ") .. "\n")
        if shrunk_message and shrunk_message ~= failed_message then
          io.write("  shrunk message: " .. shrunk_message .. "\n")
        end
      end
    else
      io.write(string.format("ok %s (%d cases)\n", entry.name, cases))
      total_cases = total_cases + cases
    end
  end

  io.write(string.format("property: %d %s, %d %s, %d %s\n",
    #registered, #registered == 1 and "property" or "properties",
    total_cases, total_cases == 1 and "case" or "cases",
    failures, failures == 1 and "failure" or "failures"))
  if failures == 0 then
    io.write("property: PASS\n")
  else
    io.write("property: FAIL\n")
  end
  return failures == 0
end

return property
