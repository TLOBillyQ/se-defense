local Epoch = require("vendor.spoke.runtime.epoch")

-- Functional composition epoch: behaves like a custom Epoch subclass without
-- requiring a class declaration. The init_fn receives the Epoch builder and
-- returns the tick function or nil, exactly as Epoch.init does.
local LambdaEpoch = Epoch.extend("LambdaEpoch", {
  constructor = function(self, init_fn)
    self._init_fn = init_fn
  end,

  init = function(self, s)
    return self._init_fn(s)
  end,
})

return LambdaEpoch
