-- Three-way comparison helpers shared by the runtime's comparators.
--
-- Every comparator in the runtime returns -1/0/1, so the tie-breaking chains
-- read as a sequence of "compare this, else fall through".
local Ordering = {}

--- Signed three-way compare.
function Ordering.compare(a, b)
  if a == b then
    return 0
  end
  return a < b and -1 or 1
end

--- Three-way compare of two integers read as unsigned 64-bit words.
function Ordering.compare_unsigned(a, b)
  if a == b then
    return 0
  end
  return math.ult(a, b) and -1 or 1
end

--- Three-way compare of two booleans where true sorts first.
function Ordering.compare_flag(a, b)
  if a == b then
    return 0
  end
  return a and -1 or 1
end

--- Counts one more backward step when `current` sorts before `previous`.
--- Flush loops use this to detect a queue that keeps reordering behind them.
function Ordering.count_regression(count, previous, current, compare)
  if previous and compare(previous, current) > 0 then
    return count + 1
  end
  return count
end

return Ordering
