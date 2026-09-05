-- 05_BaseDefence 电力网节点（PowerNode）。
--
-- 忠实移植上游 Examples/05_BaseDefence/Scripts/Units/Buildings/PowerNode.cs：
--   - 节点构成以 root（Core）为根的树：receiver 从覆盖自己的 provider 取电，
--     只有链路通到 root 才有电；
--   - has_power 变化带 0.15s debounce（游戏时间，经 s:coroutine 实现），
--     吸收短暂抖动（上游 powerDelay）；
--   - 更近的 provider 可窃取节点，但不可窃取自己的祖先（防环）；
--   - 断电传播：provider 失电/出范围/被禁用时，下游经 debounce 后断电；
--   - is_enabled 对应上游 Behaviour.enabled：Building 死亡时禁用本节点，
--     使其退出电网（collider 撤掉、has_power 置 false、从 all 移除）。
--
-- 与上游的偏差：
--   - 无 game_tick 时 debounce 退化为立即生效（仅供无头纯响应式单测上下文；
--     游戏内始终传 game_tick）；
--   - chain 遍历加了 visited 防死循环保险（正常拓扑不触发；上游靠窃取守卫
--     保证无环，Lua 侧无限循环不可恢复，故留保险）。

local spoke = require("vendor.spoke")
local Epoch = spoke.Epoch
local State = spoke.State
local Phase = spoke.Phase

-- 注册 s:coroutine() 扩展（debounce 用）。
require("server.game.coroutine")

local POWER_DELAY = 0.15
local POWER_NODE_SERIAL = 0

local function dist2(a, b)
  local dx = a.x - b.x
  local dz = a.z - b.z
  return dx * dx + dz * dz
end

local PowerNode
PowerNode = Epoch.extend("PowerNode", {
  constructor = function(self, config)
    config = config or {}
    self._is_root = config.is_root or false
    self.receive_range = config.receive_range or 0.1
    self.provide_range = config.provide_range or 4
    self.power_zone = config.power_zone or error("PowerNode requires power_zone", 2)
    self.game_tick = config.game_tick

    -- 位置来源：get_position fn 优先，否则持续读 position 表（调用方可原地改）。
    if config.get_position then
      self._get_position = config.get_position
    else
      local pos = config.position or { x = 0, y = 0, z = 0 }
      self._get_position = function()
        return pos
      end
    end

    POWER_NODE_SERIAL = POWER_NODE_SERIAL + 1
    self._serial = POWER_NODE_SERIAL

    self.parent = State.new("PowerNode.parent", nil)
    self.has_power = State.new("PowerNode.has_power", false)
    self.is_enabled = State.new("PowerNode.is_enabled", true)
  end,

  init = function(self, s)
    s:call(Phase.new("PowerNode.enabled", self.is_enabled, function(s2)
      -- 上游 static All：挂载即登记，卸载即移除（每次发布新列表）。
      PowerNode._update_all(function(list)
        list[#list + 1] = self
      end)
      s2:on_cleanup(function()
        PowerNode._update_all(function(list)
          for i, n in ipairs(list) do
            if n == self then
              table.remove(list, i)
              break
            end
          end
        end)
      end)

      self:_debounce(s2)
      if not self._is_root then
        self:_receive_power(s2)
      end
      if not self:is_leaf() then
        s2:call(Phase.new("PowerNode.providing", self.has_power, function(s3)
          self:_provide_power(s3)
        end))
      end
    end))
  end,

  -- DebounceHasPowerChange：root 立即有电；其余节点 has_power = (parent ~= nil)，
  -- 变化经 0.15s 游戏时间后才落。effect 卸载（禁用/detach）时置 false。
  _debounce = function(self, s2)
    s2:effect("PowerNode.debounce", function(s3)
      if self._is_root then
        self.has_power:set(true)
      end

      local next_has_power = s3:memo("PowerNode.next_has_power", function(m)
        return self._is_root or m:d(self.parent) ~= nil
      end)
      local should_change = s3:memo("PowerNode.should_change", function(m)
        return m:d(next_has_power) ~= m:d(self.has_power)
      end)

      s3:phase("PowerNode.settle", should_change, function(s4)
        if not self.game_tick then
          -- 无游戏时钟的纯响应式上下文：退化为立即生效。
          self.has_power:set(next_has_power:now())
          return
        end
        s4:coroutine(self.game_tick, function(_, wait_seconds)
          wait_seconds(POWER_DELAY)
          self.has_power:set(next_has_power:now())
        end)
      end)

      s3:on_cleanup(function()
        self.has_power:set(false)
      end)
    end)
  end,

  -- ReceivePower：注册 receiver collider（只看 provider），并看护 parent：
  -- 出范围或 parent 失电时断开。
  _receive_power = function(self, s2)
    local collider = s2:use(self.power_zone:add_collider(
      { is_provider = false, node = self },
      function()
        return { center = self:position(), radius = self.receive_range }
      end,
      function(owner)
        return owner.is_provider == true
      end
    ))

    s2:on_cleanup(function()
      self.parent:set(nil)
    end)

    s2:effect("PowerNode.watch_parent", function(s3)
      local parent_now = s3:d(self.parent)
      if parent_now == nil then
        return
      end
      s3:effect("PowerNode.parent_in_range", function(s4)
        for _, c in ipairs(s4:d(collider.overlaps)) do
          if c.owner.node == parent_now then
            return
          end
        end
        self.parent:set(nil)
      end)
      s3:effect("PowerNode.parent_powered", function(s4)
        if not s4:d(parent_now.has_power) then
          self.parent:set(nil)
        end
      end)
    end)
  end,

  -- ProvidePower：注册 provider collider（只看 receiver），向覆盖内节点供电；
  -- 更近可窃取，祖先不可窃取（防环）。只有链路通到 root 才供电。
  _provide_power = function(self, s3)
    local self_node = self
    local collider = s3:use(self.power_zone:add_collider(
      { is_provider = true, node = self },
      function()
        return { center = self:position(), radius = self.provide_range }
      end,
      function(owner)
        return owner.is_provider == false
      end
    ))

    -- 一次链走回答两个问题：我的祖先是谁（窃取守卫）、链路是否通到 root。
    local chain = s3:memo("PowerNode.chain", function(m)
      local ancestors = {}
      local visited = {}
      local is_root_connected = false
      local n = self_node
      while n and not visited[n] do
        visited[n] = true
        if n ~= self_node then
          ancestors[n] = true
        end
        if n._is_root then
          is_root_connected = true
        end
        n = m:d(n.parent)
      end
      return { ancestors = ancestors, is_root_connected = is_root_connected }
    end)

    local is_root_connected = s3:memo("PowerNode.is_root_connected", function(m)
      return m:d(chain).is_root_connected
    end)

    s3:phase("PowerNode.connect", is_root_connected, function(s4)
      for _, c in ipairs(s4:d(collider.overlaps)) do
        local node = c.owner.node
        if node ~= self_node and not node._is_root then
          local can_connect = s4:memo("PowerNode.can_connect", function(m)
            local parent_now = m:d(node.parent)
            if parent_now == nil or parent_now == self_node then
              return true
            end
            -- 从更远的 provider 窃取，除非对方是自己的祖先（会成环）。
            local node_pos = node:position()
            local my_pos = self_node:position()
            local their_pos = parent_now:position()
            local mine = dist2(node_pos, my_pos)
            local theirs = dist2(node_pos, their_pos)
            if mine >= theirs then
              return false
            end
            return not m:d(chain).ancestors[node]
          end)
          s4:phase("PowerNode.grant", can_connect, function()
            node.parent:set(self_node)
          end)
        end
      end
    end)
  end,
})

-- 当前位置（XZ 平面取电/供电圆的圆心）。
function PowerNode:position()
  return self._get_position()
end

-- 叶子只取电，不向外供电（上游 IsLeaf => provideRange <= 0）。
function PowerNode:is_leaf()
  return self.provide_range <= 0
end

-- 模块级 all 信号：当前挂载的所有节点（上游 static All）。
PowerNode.all = State.new("PowerNode.all", {})

function PowerNode._update_all(mutate)
  local next = {}
  for _, n in ipairs(PowerNode.all:now()) do
    next[#next + 1] = n
  end
  mutate(next)
  PowerNode.all:set(next)
end

return PowerNode
