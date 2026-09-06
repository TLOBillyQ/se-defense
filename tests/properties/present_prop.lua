-- tests/properties/present_prop.lua — 快照路由（server.adapter.eui）与
-- 客户端哑镜像（client.eui_render）的性质测试。
-- 覆盖维度：round trip / 收敛（任意推进序列 + 周期性全量重同步后，
-- 客户端镜像与最新快照一致）、不变式（seq 单调递增）、宽输入范围
-- （随机对局操作序列驱动出的真实快照流）。
local prop = require("tests.properties.harness")
local match_flow = require("server.game.match_flow")
local presenter = require("server.present.presenter")
local eui = require("server.adapter.eui")
local client = require("client.eui_render")
local world = require("server.game.world")

prop.seed(31)

local function state_equal(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return a == b end
  for k, v in pairs(a) do
    if type(v) == "table" or type(b[k]) == "table" then
      if not state_equal(v, b[k]) then return false end
    elseif v ~= b[k] then
      return false
    end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

-- 假通道：FireAllClients 即送达客户端哑镜像（有序、不丢包）；客户端上行
-- client_ready（握手 / 序号缺口）直达路由器全量重同步。
local function wired()
  local handler, router
  local channel = {
    FireAllClients = function(_, msg) handler(msg) end,
    OnClientEvent = { Connect = function(_, fn) handler = fn end },
    FireServer = function(_, msg)
      if router and msg.action == "client_ready" then router:client_ready() end
    end,
  }
  client.applied = {}
  client.connect(channel)
  router = eui.new(channel)
  return router
end

-- PR-P1 round trip：任意快照流经增量路由后，镜像 == 最新快照
-- （消失节点按协议以 visible=false 收尾）；client_ready 全量重同步亦收敛。
prop.check("PR-P1 快照路由收敛", 100, function()
  local g = match_flow.new()
  local pres = presenter.new(g)
  local router = wired() -- 上一轮残留的客户端序号靠缺口→client_ready 自愈
  local last_seq = 0
  g:start()
  for _ = 1, prop.int(1, 25) do
    local op = prop.int(1, 5)
    if op == 1 then
      g:advance(prop.number(0.05, 2))
    elseif op == 2 then
      g.entities:add_building(prop.pick({ "Relay", "Radar", "Turret", "Repair" }),
        prop.number(-15, 15), prop.number(-15, 15))
    elseif op == 3 then
      local b = g.entities.list[prop.int(1, #g.entities.list)]
      g.entities:hurt(b, 1)
    elseif op == 4 then
      pres:hover_at(prop.number(-5, 5), prop.number(-5, 5))
    else
      router:client_ready()
    end
    pres:tick(0.1)
    local snap = pres:snapshot()
    local msg = router:push(snap)
    if msg then
      if msg.seq <= last_seq then return nil, "seq 未单调递增" end
      last_seq = msg.seq
    end
    for path, state in pairs(snap) do
      if not state_equal(client.applied[path], state) then
        return nil, "镜像与快照不一致: " .. path
      end
    end
    for path, state in pairs(client.applied) do
      if snap[path] == nil and state.visible ~= false then
        return nil, "消失节点未按隐藏收尾: " .. path
      end
    end
  end
  return true
end)

-- PR-P2 不变式：任意倒计时值的倒计时颜色分量都在 [0,1]；
-- 边界：满 30 秒为淡蓝、0 秒为危险红。
prop.check("PR-P2 倒计时颜色分量有界", 100, function()
  local g = match_flow.new()
  g:start()
  local pres = presenter.new(g)
  g.wave.countdown = prop.number(0, world.wave.calm)
  local c = pres:countdown_color()
  for i = 1, 3 do
    if c[i] < -1e-9 or c[i] > 1 + 1e-9 then
      return nil, string.format("颜色分量越界: (%s, %s, %s)", c[1], c[2], c[3])
    end
  end
  g.wave.countdown = world.wave.calm
  local top = pres:countdown_color()
  if math.abs(top[1] - 0.6) > 1e-9 then return nil, "满倒计时不是淡蓝" end
  g.wave.countdown = 0
  local bottom = pres:countdown_color()
  if math.abs(bottom[1] - 1) > 1e-9 or math.abs(bottom[3] - 0.3) > 1e-9 then
    return nil, "零倒计时不是危险红"
  end
  return true
end)
