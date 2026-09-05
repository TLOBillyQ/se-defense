local Heap = {}
Heap.__index = Heap

function Heap.new(compare)
  if type(compare) ~= "function" then
    error("Heap.new expects a comparison function", 2)
  end
  return setmetatable({
    _values = {},
    _compare = compare,
  }, Heap)
end

function Heap:count()
  return #self._values
end

function Heap:_swap(a, b)
  self._values[a], self._values[b] = self._values[b], self._values[a]
end

function Heap:_heapify_up(index)
  local value = self._values[index]
  while index > 1 do
    local parent = math.floor(index / 2)
    if self._compare(value, self._values[parent]) >= 0 then
      break
    end
    self._values[index] = self._values[parent]
    index = parent
  end
  self._values[index] = value
end

function Heap:_heapify_down(index)
  local values = self._values
  local count = #values
  while true do
    local left = index * 2
    if left > count then
      return
    end
    local right = left + 1
    local smallest = left
    if right <= count and self._compare(values[right], values[left]) < 0 then
      smallest = right
    end
    if self._compare(values[smallest], values[index]) >= 0 then
      return
    end
    values[index], values[smallest] = values[smallest], values[index]
    index = smallest
  end
end

function Heap:insert(value)
  local values = self._values
  values[#values + 1] = value
  self:_heapify_up(#values)
end

function Heap:peek_min()
  if #self._values == 0 then
    error("Heap is empty", 2)
  end
  return self._values[1]
end

function Heap:remove_min()
  local values = self._values
  local count = #values
  if count == 0 then
    error("Heap is empty", 2)
  end
  local minimum = values[1]
  if count == 1 then
    values[1] = nil
    return minimum
  end
  values[1] = values[count]
  values[count] = nil
  self:_heapify_down(1)
  return minimum
end

function Heap:clear()
  self._values = {}
end

function Heap:rebuild()
  for index = math.floor(#self._values / 2), 1, -1 do
    self:_heapify_down(index)
  end
end

return Heap
