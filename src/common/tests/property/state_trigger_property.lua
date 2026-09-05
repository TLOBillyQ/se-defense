-- Property tests for src/common/spoke/reactive/state.lua and
-- src/common/spoke/reactive/trigger.lua: a State notifies subscribers exactly when
-- the stored value actually changes (repeated writes of the same value are
-- silent), subscriber counts are conserved across subscribe/unsubscribe
-- sequences, and unsubscribed callbacks never fire again.
local property = require("src.common.tests.property.support.property")
local State = require("src.common.spoke.reactive.state")
local Trigger = require("src.common.spoke.reactive.trigger")

local gen = property.gen

-- Values compared by the default `==` equals, including duplicates so
-- repeated writes of the same value occur naturally. nil is included because
-- it is the default State value and the initial write of nil is a no-op.
local VALUE_POOL = { nil, 0, 1, 2, -1, "a", "b", "", true, false }

-- Trigger payloads: non-nil so payload logs stay dense arrays.
local PAYLOAD_POOL = { 0, 1, -1, "a", "b", true, false }

local function pick_value(rng)
  return VALUE_POOL[rng:int(1, #VALUE_POOL)]
end

-- A random write sequence: set(value) and update(constant-returning fn),
-- modeled against the previously stored value.
local function write_ops_gen(rng)
  local ops = {}
  for _ = 1, rng:int(1, 60) do
    local value = pick_value(rng)
    if rng:boolean() then
      ops[#ops + 1] = { op = "set", value = value }
    else
      ops[#ops + 1] = { op = "update", value = value }
    end
  end
  return ops
end

-- State notifies listeners exactly when the value actually changes: the
-- notification log must equal the model's change sequence (which skips every
-- write whose value equals the previously stored one).
property.forall("state_notifies_only_when_value_changes", { write_ops_gen },
  function(ops)
    local state = State.new()
    local log = {}
    state:subscribe(function(value)
      log[#log + 1] = value
    end)

    local stored = state:now()
    local expected_log = {}
    for _, op in ipairs(ops) do
      if op.op == "set" then
        state:set(op.value)
      elseif op.op == "update" then
        state:update(function()
          return op.value
        end)
      else
        return "unknown write op " .. tostring(op.op)
      end
      if op.value ~= stored then
        stored = op.value
        expected_log[#expected_log + 1] = op.value
      end
    end

    if #log ~= #expected_log then
      return string.format("got %d notifications, model says %d",
        #log, #expected_log)
    end
    for i = 1, #expected_log do
      if log[i] ~= expected_log[i] then
        return string.format("notification %d is %s, model says %s",
          i, tostring(log[i]), tostring(expected_log[i]))
      end
    end
    return true
  end)

-- A subscribe/unsubscribe/write scenario with per-subscriber counters.
local function state_scenario_gen(rng)
  local subscriber_count = rng:int(3, 24)
  local scenario = { subscribers = subscriber_count, ops = {} }
  for _ = 1, rng:int(1, 40) do
    local choice = rng:int(1, 3)
    local sub_id = rng:int(1, subscriber_count)
    if choice == 1 then
      scenario.ops[#scenario.ops + 1] = { op = "unsubscribe_fn", id = sub_id }
    elseif choice == 2 then
      scenario.ops[#scenario.ops + 1] = { op = "dispose", id = sub_id }
    else
      scenario.ops[#scenario.ops + 1] =
        { op = "write", value = pick_value(rng) }
    end
  end
  return scenario
end

-- Subscriber count is conserved across subscribe/unsubscribe sequences and
-- unsubscribed callbacks never fire: after every actual change each live
-- subscriber fires exactly once, dead ones not at all, and a final change
-- after the last unsubscribe wakes no dead callback.
property.forall("subscriber_count_conserved_and_unsubs_never_fire",
  { state_scenario_gen }, function(scenario)
    local state = State.new()
    local subs = {}
    for id = 1, scenario.subscribers do
      local entry = { fired = 0, alive = true }
      entry.fn = function()
        entry.fired = entry.fired + 1
      end
      entry.handle = state:subscribe(entry.fn)
      subs[id] = entry
    end

    local stored = state:now()
    local expected = {}
    for id = 1, scenario.subscribers do
      expected[id] = 0
    end

    for _, op in ipairs(scenario.ops) do
      local entry = subs[op.id]
      if op.op == "unsubscribe_fn" then
        state:unsubscribe(entry.fn)
        if entry.alive then
          entry.alive = false
        end
      elseif op.op == "dispose" then
        entry.handle:dispose()
        if entry.alive then
          entry.alive = false
        end
      elseif op.op == "write" then
        state:set(op.value)
        if op.value ~= stored then
          stored = op.value
          for id = 1, scenario.subscribers do
            if subs[id].alive then
              expected[id] = expected[id] + 1
            end
          end
        end
      else
        return "unknown scenario op " .. tostring(op.op)
      end
    end

    -- A final guaranteed change: nothing in the pool equals this value.
    state:set("final-probe")
    for id = 1, scenario.subscribers do
      if subs[id].alive then
        expected[id] = expected[id] + 1
      end
    end

    for id = 1, scenario.subscribers do
      if subs[id].fired ~= expected[id] then
        local state_name = subs[id].alive and "live" or "unsubscribed"
        return string.format(
          "%s subscriber %d fired %d times, model says %d",
          state_name, id, subs[id].fired, expected[id])
      end
    end
    return true
  end)

-- Trigger-level churn: duplicate subscriptions of the same fn are allowed,
-- unsubscribe(fn) removes all of them, handle dispose removes one, and every
-- invoke reaches exactly the live subscriptions with its payload intact.
local function trigger_scenario_gen(rng)
  local pool_size = rng:int(2, 6)
  local scenario = { pool_size = pool_size, ops = {} }
  for _ = 1, rng:int(1, 40) do
    local choice = rng:int(1, 5)
    if choice == 1 then
      scenario.ops[#scenario.ops + 1] =
        { op = "subscribe", fn = rng:int(1, pool_size) }
    elseif choice == 2 then
      scenario.ops[#scenario.ops + 1] =
        { op = "unsubscribe_fn", fn = rng:int(1, pool_size) }
    elseif choice == 3 then
      scenario.ops[#scenario.ops + 1] =
        { op = "dispose", index = rng:int(1, 12) }
    else
      scenario.ops[#scenario.ops + 1] =
        { op = "invoke", payload = PAYLOAD_POOL[rng:int(1, #PAYLOAD_POOL)] }
    end
  end
  return scenario
end

property.forall("trigger_delivers_to_live_subs_only_with_payload",
  { trigger_scenario_gen }, function(scenario)
    local trigger = Trigger.new()
    local entries = {}
    for i = 1, scenario.pool_size do
      local entry = { fired = 0, payloads = {} }
      entry.fn = function(payload)
        entry.fired = entry.fired + 1
        entry.payloads[#entry.payloads + 1] = payload
      end
      entries[i] = entry
    end

    -- Model: one slot per subscription; slots share the fn value, so a
    -- duplicate subscription is a distinct slot that both fire and die
    -- together with unsubscribe(fn).
    local model = {} -- {fn = index, alive = bool}
    local handles = {} -- model slot index -> handle

    local function live_slots_of(fn_index)
      local count = 0
      for _, slot in ipairs(model) do
        if slot.alive and slot.fn == fn_index then
          count = count + 1
        end
      end
      return count
    end

    local expected = {}
    for i = 1, scenario.pool_size do
      expected[i] = {}
    end

    for _, op in ipairs(scenario.ops) do
      if op.op == "subscribe" then
        local slot_index = #model + 1
        model[slot_index] = { fn = op.fn, alive = true }
        handles[slot_index] = trigger:subscribe(entries[op.fn].fn)
      elseif op.op == "unsubscribe_fn" then
        trigger:unsubscribe(entries[op.fn].fn)
        for _, slot in ipairs(model) do
          if slot.fn == op.fn then
            slot.alive = false
          end
        end
      elseif op.op == "dispose" then
        local slot_index = op.index
        if handles[slot_index] then
          handles[slot_index]:dispose()
          model[slot_index].alive = false
        end
      elseif op.op == "invoke" then
        trigger:invoke(op.payload)
        for i = 1, scenario.pool_size do
          for _ = 1, live_slots_of(i) do
            expected[i][#expected[i] + 1] = op.payload
          end
        end
      else
        return "unknown trigger op " .. tostring(op.op)
      end
    end

    for i = 1, scenario.pool_size do
      if entries[i].fired ~= #expected[i] then
        return string.format("fn %d fired %d times, model says %d",
          i, entries[i].fired, #expected[i])
      end
      for j = 1, #expected[i] do
        if entries[i].payloads[j] ~= expected[i][j] then
          return string.format(
            "fn %d payload %d is %s, model says %s",
            i, j, tostring(entries[i].payloads[j]),
            tostring(expected[i][j]))
        end
      end
    end
    return true
  end)
