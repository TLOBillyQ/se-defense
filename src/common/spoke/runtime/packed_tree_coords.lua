-- PackedTreeCoords: an epoch's position in its tree, used to sort epochs by
-- imperative execution order. Port of upstream Spoke.Runtime/PackedTreeCoords.cs
-- (PackedTreeCoords128); design per ADR docs/adr/0001-tree-coords-128bit-simulation.md,
-- facts in docs/research/packed-tree-coords-facts.md.
--
-- Immutable value object: the 128-bit coordinate is simulated as {hi, lo, depth}
-- (two 64-bit words + depth byte), capacity unchanged: 16 layers x 256 wide.
local Ordering = require("src.common.spoke.runtime.ordering")

local PackedTreeCoords = {}
PackedTreeCoords.__index = PackedTreeCoords

local BITS_PER_INDEX = 8 -- one byte per layer
local LAYERS_PER_WORD = 8 -- 64 / BITS_PER_INDEX

--- Largest index a layer can encode. Extending past it yields Invalid.
PackedTreeCoords.MAX_INDEX = (1 << BITS_PER_INDEX) - 1

--- Layers the coordinate can hold. Extending a full one yields Invalid.
PackedTreeCoords.MAX_DEPTH = LAYERS_PER_WORD * 2 -- hi and lo

--- Mirror of the public upstream constructor.
function PackedTreeCoords.new(hi, lo, depth)
  local self = setmetatable({}, PackedTreeCoords)
  rawset(self, "hi", hi)
  rawset(self, "lo", lo)
  rawset(self, "depth", depth)
  return self
end

-- Mirrors the upstream readonly struct: instances never change after creation.
-- extend/compare_to rely on this by construction; hi/lo/depth are read-only by
-- convention (enforcing that cheaply is impossible without a proxy table, which
-- is not worth the cost on this hot path). Unknown keys are rejected outright.
function PackedTreeCoords.__newindex(_, key)
  error("PackedTreeCoords has no writable field '" .. tostring(key) .. "'", 2)
end

--- The default coordinate: all-zero words, depth 0 (upstream `default`).
PackedTreeCoords.ROOT = PackedTreeCoords.new(0, 0, 0)

--- The Invalid coordinate (upstream `Invalid`): what extend yields when a
--- coordinate does not fit. Invalid absorbs further extends.
PackedTreeCoords.INVALID = PackedTreeCoords.new(0, 0, 255)

function PackedTreeCoords:is_valid()
  return self.depth < 255
end

--- The coordinate one layer deeper, at index idx. Invalid if it doesn't fit.
function PackedTreeCoords:extend(idx)
  if not self:can_extend(idx) then
    return PackedTreeCoords.INVALID
  end
  -- Layers fill each word from its most significant byte down, so that
  -- comparing the words as integers compares the layers in order.
  if self.depth < LAYERS_PER_WORD then
    return PackedTreeCoords.new(
      self.hi | (idx << ((LAYERS_PER_WORD - 1 - self.depth) * BITS_PER_INDEX)),
      self.lo,
      self.depth + 1)
  end
  return PackedTreeCoords.new(
    self.hi,
    self.lo | (idx << ((PackedTreeCoords.MAX_DEPTH - 1 - self.depth) * BITS_PER_INDEX)),
    self.depth + 1)
end

--- Whether extending by idx yields a real coordinate rather than Invalid.
function PackedTreeCoords:can_extend(idx)
  return self:is_valid()
    and self.depth ~= PackedTreeCoords.MAX_DEPTH
    and idx >= 0
    and idx <= PackedTreeCoords.MAX_INDEX
end

--- Three-way compare, mirrored from upstream CompareTo: unsigned hi, then
--- unsigned lo, then depth. The depth tiebreak orders a prefix before its
--- extensions, so an ancestor always sorts before its descendants. This is the
--- pure coordinate comparator; deciding what happens when a coordinate is
--- Invalid belongs to the Epoch-level fallback (upstream Epoch.CompareTo).
function PackedTreeCoords:compare_to(other)
  local by_hi = Ordering.compare_unsigned(self.hi, other.hi)
  if by_hi ~= 0 then
    return by_hi
  end
  local by_lo = Ordering.compare_unsigned(self.lo, other.lo)
  if by_lo ~= 0 then
    return by_lo
  end
  return Ordering.compare(self.depth, other.depth)
end

return PackedTreeCoords
