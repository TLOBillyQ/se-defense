local lu = require("luaunit")
local Dock = require("src.common.spoke.runtime.dock")
local Epoch = require("src.common.spoke.runtime.epoch")
local LambdaEpoch = require("src.common.spoke.runtime.lambda_epoch")
local SpokeError = require("src.common.spoke.runtime.spoke_error")
local SpokeIntrospect = require("src.common.spoke.runtime.spoke_introspect")
local SpokeRuntime = require("src.common.spoke.runtime.spoke_runtime")
local SpokeTree = require("src.common.spoke.runtime.spoke_tree")

TestSpokeIntrospect = {}

function TestSpokeIntrospect.test_empty_inputs_render_empty_marker()
  lu.assertEquals(SpokeIntrospect.stack_trace({}), "(empty)")
  lu.assertEquals(SpokeIntrospect.frame_trace({}), "(empty)")
  lu.assertEquals(SpokeIntrospect.tree_trace({}), "(empty)")
  lu.assertEquals(SpokeIntrospect.tree_trace(nil), "(empty)")
end

function TestSpokeIntrospect.test_stack_trace_renders_numbered_frame_lines()
  local CounterEpoch = Epoch.extend("CounterEpoch")
  local base = Epoch.new("A")
  local counter = CounterEpoch.new("C")

  local trace = SpokeIntrospect.stack_trace({
    { epoch = base, type = "Init" },
    { epoch = counter, type = "Tick" },
  })

  lu.assertEquals(
    trace,
    "0: Init A <Epoch>\n1: Tick C <CounterEpoch>")

  local null_trace = SpokeIntrospect.stack_trace({
    { type = "Tick" },
  })
  lu.assertEquals(null_trace, "0: Tick <null> <<unknown>>")
end

function TestSpokeIntrospect.test_stack_trace_right_aligns_indices()
  local frames = {}
  for i = 1, 10 do
    frames[i] = { epoch = Epoch.new("E" .. i), type = "Init" }
  end

  local trace = SpokeIntrospect.stack_trace(frames)
  local lines = {}
  for line in (trace .. "\n"):gmatch("(.-)\n") do
    lines[#lines + 1] = line
  end

  lu.assertEquals(#lines, 10)
  -- width is the digit count of #frames (2): index 0 renders as " 0:",
  -- index 1 as " 1:", and so on.
  lu.assertEquals(string.sub(lines[1], 1, 3), " 0:")
  lu.assertEquals(string.sub(lines[2], 1, 3), " 1:")
  lu.assertEquals(string.sub(lines[10], 1, 3), " 9:")
end

function TestSpokeIntrospect.test_stack_trace_marks_faulted_epochs()
  local epoch = Epoch.new("F")
  epoch.fault = { cause = "stack-boom" }

  local trace = SpokeIntrospect.stack_trace({
    { epoch = epoch, type = "Tick" },
  })

  lu.assertStrContains(trace, "[Faulted: stack-boom]")
end

function TestSpokeIntrospect.test_tree_trace_renders_headers_and_indented_tree()
  local captured
  local Root = Epoch.extend("Root", {
    init = function(self, s)
      s:call(LambdaEpoch.new("Child", function()
        return nil
      end))
      return function()
        captured = SpokeIntrospect.tree_trace(SpokeRuntime.snapshot_frames())
      end
    end,
  })

  local tree = SpokeTree.spawn("SpokeTree", Root.new("Root"))
  lu.assertNotNil(captured)

  lu.assertStrContains(captured, "<------------ Spoke Frame Trace ------------>")
  lu.assertStrContains(captured, "<------------ Spoke Tree Trace ------------>")
  lu.assertStrContains(captured, "|--(0,1)-SpokeTree")
  lu.assertStrContains(captured, "    |--(2)-Root")
  lu.assertStrContains(captured, "        |--Child")
  tree:dispose()
end

function TestSpokeIntrospect.test_tree_trace_labels_ticked_epoch_with_frame_indices()
  local captured
  local Root = Epoch.extend("Root", {
    init = function()
      return function()
        captured = SpokeIntrospect.tree_trace(SpokeRuntime.snapshot_frames())
      end
    end,
  })

  SpokeTree.spawn("SpokeTree", Root.new("Root"))

  -- The tree appears in both the Bootstrap and Tick frames, so the label
  -- collects all of its indices as (0,1); the root only has the Tick frame.
  lu.assertStrContains(captured, "(0,1)-SpokeTree")
  lu.assertStrContains(captured, "(2)-Root")
end

function TestSpokeIntrospect.test_tree_trace_marks_faulted_epochs_and_exception_string_has_tree_section()
  local previous_log = SpokeError.log
  SpokeError.log = function() end
  local Root = Epoch.extend("FaultyRoot", {
    init = function()
      return function()
        error("introspect-boom")
      end
    end,
  })

  local tree = SpokeTree.spawn("T", Root.new("Root"))
  SpokeError.log = previous_log

  lu.assertNotNil(tree.fault)
  local trace = SpokeIntrospect.tree_trace(tree.fault.stack_snapshot)
  lu.assertStrContains(trace, "[Faulted: ")
  lu.assertStrContains(trace, "introspect-boom")
  lu.assertStrContains(tostring(tree.fault), "<------------ Spoke Tree Trace ------------>")
  lu.assertStrContains(tostring(tree.fault), "introspect-boom")
  tree:dispose()
end

function TestSpokeIntrospect.test_tree_trace_truncates_when_tree_has_more_than_50_nodes()
  local root
  local Root = Epoch.extend("WideRoot", {
    init = function(self, s)
      root = self
      for i = 1, 52 do
        s:call(LambdaEpoch.new("C" .. i, function()
          return nil
        end))
      end
      return nil
    end,
  })

  local tree = SpokeTree.spawn("T", Root.new("Root"))
  local trace = SpokeIntrospect.tree_trace({ { epoch = root, type = "Init" } })

  -- The topmost root is the SpokeTree, so the count is tree + root + 52
  -- children = 54, and no child dump lines are rendered.
  lu.assertStrContains(trace, "(tree too large to display - 54 nodes)")
  lu.assertNotStrContains(trace, "|--C52")
  tree:dispose()
end

function TestSpokeIntrospect.test_get_children_and_get_parent_delegate_to_epoch_hooks()
  local dock
  local tree = SpokeTree.spawn(LambdaEpoch.new(function(s)
    dock = s:call(Dock.new())
    return nil
  end))
  local child = LambdaEpoch.new("docked", function()
    return nil
  end)
  dock:call("k", child)

  local children = SpokeIntrospect.get_children(dock)
  lu.assertEquals(#children, 1)
  lu.assertEquals(children[1], child)
  lu.assertEquals(SpokeIntrospect.get_parent(child), dock)

  tree:dispose()
end
