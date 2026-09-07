local lu = require("luaunit")
local Epoch = require("common.spoke.runtime.epoch")
local SpokeTree = require("common.spoke.runtime.spoke_tree")
local Ticker = require("common.spoke.runtime.ticker")

TestTicker = {}

function TestTicker.test_pending_epochs_are_delivered_in_coordinate_order()
  local events = {}
  local Child = Epoch.extend("Child", {
    constructor = function(self, label)
      self.label = label
    end,
    init = function(self)
      return function()
        events[#events + 1] = self.label
      end
    end,
  })
  local Root = Epoch.extend("Root", {
    init = function(_, s)
      s:call(Child.new("Child", "first"))
      s:call(Child.new("Child", "second"))
      return function()
        events[#events + 1] = "root"
      end
    end,
  })

  local tree = SpokeTree.spawn_manual(Root.new())
  tree:flush()

  lu.assertEquals(events, { "first", "second", "root" })
end

function TestTicker.test_pause_keeps_pending_work_until_resume()
  local ports
  local ticks = 0
  local ManagedRoot = Epoch.extend("ManagedRoot", {
    init = function()
      return function()
        ticks = ticks + 1
      end
    end,
  })
  local ManagedTicker = Ticker.extend("ManagedTicker", {
    bootstrap = function(self, s)
      ports = s:ports()
      s:on_tick(function(ctx)
        ctx:tick_next()
      end)
      return ManagedRoot.new()
    end,
  })
  local Root = Epoch.extend("Root", {
    init = function(_, s)
      s:call(ManagedTicker.new())
    end,
  })

  local tree = SpokeTree.spawn_manual(Root.new())
  ports:pause()
  tree:flush()
  lu.assertEquals(ticks, 0)
  lu.assertTrue(ports:has_pending())

  ports:resume()
  tree:flush()
  lu.assertEquals(ticks, 1)
end

function TestTicker.test_on_tick_is_sealed_after_bootstrap()
  local ports
  local ManagedTicker = Ticker.extend("ManagedTicker", {
    bootstrap = function(_, s)
      ports = s:ports()
      s:on_tick(function() end)
      return Epoch.new()
    end,
  })

  local Root = Epoch.extend("Root", {
    init = function(_, s)
      s:call(ManagedTicker.new())
    end,
  })
  local tree = SpokeTree.spawn_manual(Root.new())
  lu.assertNotNil(tree)
  lu.assertError(function()
    ports:on_tick(function() end)
  end)
end

function TestTicker.test_ticker_builder_cannot_mutate_during_child_init()
  local add_on_tick
  local mutation_allowed
  local Guarded = Ticker.extend("Guarded", {
    bootstrap = function(_, s)
      add_on_tick = function()
        s:on_tick(function() end)
      end
      s:call(Epoch.extend("Child", {
        init = function()
          mutation_allowed = pcall(add_on_tick)
        end,
      }).new())
      return Epoch.new()
    end,
  })

  SpokeTree.spawn_manual(Guarded.new())

  lu.assertFalse(mutation_allowed)
end

function TestTicker.test_custom_ticker_can_contain_a_child_fault()
  local ticks = 0
  local ports
  local Faulty = Epoch.extend("Faulty", {
    init = function()
      return function()
        ticks = ticks + 1
        error("contained-boom")
      end
    end,
  })
  local Boundary = Ticker.extend("Boundary", {
    bootstrap = function(_, s)
      ports = s:ports()
      s:on_tick(function(context)
        local ok = pcall(function()
          while ports:has_pending() do
            context:tick_next()
          end
        end)
        if not ok then
          ports:pause()
        end
      end)
      return Faulty.new()
    end,
  })
  local Root = Epoch.extend("Root", {
    init = function(_, s)
      s:call(Boundary.new())
    end,
  })

  local tree = SpokeTree.spawn_manual(Root.new())
  tree:flush()

  lu.assertEquals(ticks, 1)
  lu.assertNil(tree.fault)
end

function TestTicker.test_ticker_faults_when_on_tick_neither_advances_nor_pauses()
  local Idle = Ticker.extend("Idle", {
    bootstrap = function(_, s)
      s:on_tick(function() end)
      return Epoch.new()
    end,
  })

  local tree = SpokeTree.spawn_manual(Idle.new())
  tree:flush()

  lu.assertNotNil(tree.fault)
end

function TestTicker.test_pending_order_survives_packed_depth_and_width_overflow()
  local deep_events = {}
  local deep_ports = {}
  local function chain(level)
    return Epoch.extend("Node" .. level, {
      init = function(_, s)
        deep_ports[level] = s:ports()
        if level < 23 then
          s:call(chain(level + 1))
        end
        return function()
          deep_events[#deep_events + 1] = level
        end
      end,
    }).new()
  end
  local DeepTicker = Ticker.extend("DeepTicker", {
    bootstrap = function(_, s)
      local ports = s:ports()
      s:on_tick(function(context)
        while ports:has_pending() do
          context:tick_next()
        end
      end)
      return chain(0)
    end,
  })

  local deep_tree = SpokeTree.spawn_manual(DeepTicker.new())
  deep_tree:flush()
  lu.assertEquals(#deep_events, 24)
  lu.assertEquals(deep_events[1], 23)
  lu.assertEquals(deep_events[24], 0)

  -- #41: scrambled re-arm beyond packed depth still drains in coordinate
  -- order (upstream Ticker_TicksPending_InTreeCoordOrder_BeyondPackedDepth).
  local seed = 7
  local function rand(n)
    seed = (1103515245 * seed + 12345) % 2147483648
    return seed % n
  end
  local order = {}
  for level = 23, 0, -1 do
    order[#order + 1] = level
  end
  for i = #order, 2, -1 do
    local j = 1 + rand(i)
    order[i], order[j] = order[j], order[i]
  end
  for _, level in ipairs(order) do
    deep_ports[level]:request_tick()
  end
  deep_events = {}
  deep_tree:flush()
  local expected = {}
  for level = 23, 0, -1 do
    expected[#expected + 1] = level
  end
  lu.assertEquals(deep_events, expected)

  local wide_events = {}
  local Child = Epoch.extend("Child", {
    constructor = function(self, index)
      self.index = index
    end,
    init = function(self)
      return function()
        wide_events[#wide_events + 1] = self.index
      end
    end,
  })
  local WideTicker = Ticker.extend("WideTicker", {
    bootstrap = function(_, s)
      local ports = s:ports()
      s:on_tick(function(context)
        while ports:has_pending() do
          context:tick_next()
        end
      end)
      return Epoch.extend("WideRoot", {
        init = function(_, root_s)
          for index = 1, 300 do
            root_s:call(Child.new("Child", index))
          end
        end,
      }).new()
    end,
  })

  local wide_tree = SpokeTree.spawn_manual(WideTicker.new())
  wide_tree:flush()
  lu.assertEquals(#wide_events, 300)
  lu.assertEquals(wide_events[1], 1)
  lu.assertEquals(wide_events[300], 300)
end

-- #34: upstream isTicking spans the whole Tick frame, including the rollback
-- cleanup at the start. A cleanup that schedules a descendant during the
-- ticker's own rollback must not re-request upstream; the current pass
-- absorbs the new schedule (otherwise the ticker gets an extra idle tick).
function TestTicker.test_rollback_schedule_does_not_re_request_upstream()
  local upstream_requests = 0
  local e_ports
  local e_ticks = 0
  local t_ticks = 0
  local T

  local E = Epoch.extend("E", {
    auto_arm_tick_after_init = false,
    init = function(_, s)
      e_ports = s:ports()
      return function()
        e_ticks = e_ticks + 1
      end
    end,
  })
  local TE = Epoch.extend("TE", {
    auto_arm_tick_after_init = false,
    init = function(_, s)
      s:call(E.new())
      return nil
    end,
  })
  local ProbeTicker = Ticker.extend("ProbeTicker", {
    bootstrap = function(_, s)
      s:on_tick(function(ctx)
        ctx:tick_next()
      end)
      return TE.new()
    end,
    -- Wrap Ticker:init's closure: on the first tick, attach a tick-time
    -- cleanup to the ticker itself, so the next rollback runs it.
    init = function(self, s)
      local closure = Ticker.init(self, s)
      return function(builder)
        if not self._probe_attached then
          self._probe_attached = true
          builder:on_cleanup(function()
            e_ports:request_tick()
          end)
        end
        return closure(builder)
      end
    end,
  })
  local Root = Epoch.extend("Root", {
    init = function(_, s)
      T = s:call(ProbeTicker.new())
    end,
  })

  local tree = SpokeTree.spawn_manual(Root.new())
  local orig_upstream = T._request_upstream
  T._request_upstream = function(self, ...)
    upstream_requests = upstream_requests + 1
    return orig_upstream(self, ...)
  end
  local orig_tick_block = T._tick_block
  T._tick_block = function(builder)
    t_ticks = t_ticks + 1
    return orig_tick_block(builder)
  end

  T:_request_tick()  -- initial driver: auto-arm is off, schedule T directly
  tree:flush()  -- tick 1 attaches the cleanup
  lu.assertEquals(t_ticks, 1, "flush 1: single tick")
  lu.assertEquals(e_ticks, 0, "E not armed, must not tick yet")

  T:_request_tick()  -- direct driver, outside any tick
  lu.assertEquals(upstream_requests, 0, "T's own request does not go upstream")

  local upstream_before = upstream_requests
  local ticks_before = t_ticks
  tree:flush()  -- tick 2: rollback runs the cleanup -> schedules E
  lu.assertEquals(upstream_requests, upstream_before,
    "rollback-phase schedule must not re-request upstream")
  lu.assertEquals(t_ticks, ticks_before + 1,
    "T ticks exactly once: the schedule was absorbed")
  lu.assertEquals(e_ticks, 1, "E ticked by the absorbing pass")

  tree:dispose()
end

-- #34: tick_next() must still reject calls outside an on_tick callback
-- (its guard moved from _is_ticking to _in_on_tick when the ticking
-- window widened).
function TestTicker.test_tick_next_outside_on_tick_still_errors()
  local T
  local TE = Epoch.extend("TE", {
    init = function()
      return function() end
    end,
  })
  local ProbeTicker = Ticker.extend("ProbeTicker", {
    bootstrap = function(_, s)
      s:on_tick(function(ctx)
        ctx:tick_next()
      end)
      return TE.new()
    end,
  })
  local Root = Epoch.extend("Root", {
    init = function(_, s)
      T = s:call(ProbeTicker.new())
    end,
  })

  local tree = SpokeTree.spawn_manual(Root.new())
  lu.assertError(function()
    T:tick_next()
  end)
  tree:dispose()
end

-- #40: port of TickerTests.Ticker_AlwaysTicksLowestPendingCoordFirst_UnderChaoticScheduling —
-- fixed-seed fuzz (LCG stands in for upstream's Random): under scrambled
-- request order, every TickNext must deliver the compare_to-min of the
-- pending set; runs both within packed depth and beyond it (re-arm phase).
function TestTicker.test_lowest_pending_coord_first_under_chaotic_scheduling()
  local function run_fuzz(max_level, rounds)
    local seed = 20240816
    local function rand(n)
      seed = (1103515245 * seed + 12345) % 2147483648
      return seed % n
    end

    local ports = {}
    local ticked = {}
    local all_ids = {}
    local function build(level, id)
      local Node = Epoch.extend("Node", {
        -- Only requested nodes may tick: no auto-arm at attach.
        auto_arm_tick_after_init = false,
        constructor = function(self, id)
          self.id = id
        end,
        init = function(self, s)
          ports[self.id] = s:ports()
          all_ids[#all_ids + 1] = self.id
          if level < max_level then
            if level < 4 then
              -- Branch near the root for coordinate variety...
              for i = 1, 2 do
                s:call(build(level + 1, id .. "." .. i))
              end
            else
              -- ...then a single chain so deep levels stay O(depth) nodes.
              s:call(build(level + 1, id .. ".c"))
            end
          end
          return function()
            ticked[#ticked + 1] = self.id
          end
        end,
      })
      -- Pass the name explicitly so _new_instance doesn't consume the id.
      return Node.new("Node", id)
    end

    local ticker_ports
    local RootTicker = Ticker.extend("RootTicker", {
      bootstrap = function(_, s)
        ticker_ports = s:ports()
        s:on_tick(function(context)
          while ticker_ports:has_pending() do
            local expected = ticker_ports:peek_next()
            local got = context:tick_next()
            -- Identity compare: LuaUnit's assertEquals deep-compares tables,
            -- which is O(tree) per epoch and quadratic over a fuzz run.
            lu.assertTrue(got == expected,
              "tick_next must deliver the pending minimum coordinate")
          end
        end)
        return build(0, "r")
      end,
    })

    local tree = SpokeTree.spawn_manual(RootTicker.new())

    for _ = 1, rounds do
      -- Random subset, Fisher-Yates scrambled, always non-empty.
      local shuffled = {}
      for _, id in ipairs(all_ids) do
        if rand(100) < 70 then
          shuffled[#shuffled + 1] = id
        end
      end
      if #shuffled == 0 then
        shuffled[#shuffled + 1] = all_ids[1 + rand(#all_ids)]
      end
      for i = #shuffled, 2, -1 do
        local j = 1 + rand(i)
        shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
      end
      for _, id in ipairs(shuffled) do
        ports[id]:request_tick()
      end
      tree:flush()
      lu.assertEquals(#ticked, #shuffled, "each requested epoch ticks once per round")
      ticked = {}
    end

    tree:dispose()
  end

  run_fuzz(10, 12)  -- within packed depth (16 layers)
  run_fuzz(23, 12)  -- beyond packed depth: coords fall back to cursors
end
