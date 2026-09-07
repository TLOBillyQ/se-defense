local lu = require("luaunit")
local Heap = require("common.spoke.runtime.heap")

TestHeap = {}

function TestHeap.test_values_are_removed_in_comparator_order()
  local heap = Heap.new(function(a, b)
    return a.priority - b.priority
  end)

  heap:insert({ priority = 3, name = "third" })
  heap:insert({ priority = 1, name = "first" })
  heap:insert({ priority = 2, name = "second" })

  lu.assertEquals(heap:count(), 3)
  lu.assertEquals(heap:peek_min().name, "first")
  lu.assertEquals(heap:remove_min().name, "first")
  lu.assertEquals(heap:remove_min().name, "second")
  lu.assertEquals(heap:remove_min().name, "third")
  lu.assertEquals(heap:count(), 0)
end

function TestHeap.test_empty_operations_raise()
  local heap = Heap.new(function(a, b)
    return a - b
  end)

  lu.assertError(function()
    heap:peek_min()
  end)
  lu.assertError(function()
    heap:remove_min()
  end)
end
