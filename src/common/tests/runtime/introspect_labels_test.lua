local lu = require("luaunit")
local IntrospectLabels = require("src.common.spoke.runtime.introspect_labels")

-- A tiny object whose tostring is predictable, so we can assert on whole labels.
local function named_epoch(name)
  local epoch = {}
  setmetatable(epoch, {
    __tostring = function() return name end,
    _default_name = "NamedEpoch",
  })
  return epoch
end

TestIntrospectLabels = {}

function TestIntrospectLabels.test_frame_epoch_label_collects_matching_indices()
  local epoch = named_epoch("E")
  local frames = {
    { epoch = epoch },
    { epoch = named_epoch("Other") },
    { epoch = epoch },
  }

  local label = IntrospectLabels.frame_epoch_label(epoch, frames)
  lu.assertEquals(label, "(0,2)-E")
end

function TestIntrospectLabels.test_frame_epoch_label_falls_back_to_tostring_when_no_match()
  local epoch = named_epoch("E")
  local frames = {
    { epoch = named_epoch("Other") },
  }

  local label = IntrospectLabels.frame_epoch_label(epoch, frames)
  lu.assertEquals(label, "E")
end

function TestIntrospectLabels.test_frame_epoch_label_works_without_global_rawequal()
  local saved_rawequal = rawequal
  _G.rawequal = nil
  package.loaded["src.common.spoke.runtime.introspect_labels"] = nil

  local ok, err = pcall(function()
    local Labels = require("src.common.spoke.runtime.introspect_labels")
    local epoch = named_epoch("E")
    local frames = {
      { epoch = epoch },
      { epoch = named_epoch("Other") },
      { epoch = epoch },
    }

    local label = Labels.frame_epoch_label(epoch, frames)
    lu.assertEquals(label, "(0,2)-E")
  end)

  _G.rawequal = saved_rawequal
  package.loaded["src.common.spoke.runtime.introspect_labels"] = nil

  lu.assertTrue(ok, err)
end

function TestIntrospectLabels.test_epoch_type_name_returns_default_or_unknown()
  local instance = named_epoch("E")

  lu.assertEquals(IntrospectLabels.epoch_type_name(instance), "NamedEpoch")
  lu.assertEquals(IntrospectLabels.epoch_type_name({}), "<unknown>")
  lu.assertEquals(IntrospectLabels.epoch_type_name(42), "<unknown>")
end

function TestIntrospectLabels.test_epoch_frame_name_handles_nil()
  lu.assertEquals(IntrospectLabels.epoch_frame_name(nil), "<null>")
end
