-- 05_BaseDefence 棋盘交互的鼠标探针。
--
-- BoardInteractions 的三个碰撞传感器：悬停探针（ground_zone）、放置 footprint
-- 探针（ground_zone）与电力覆盖探针（power_zone，只看 provider）。传感器在
-- init 层创建——即使 Manual 树在 game_tick:tick() 不自动 flush，zone:tick()
-- 也能采样到最新鼠标位置，与 BoardInteractions 的 init 时机一致。

local BoardSensors = {}

-- 在作用域 s 上注册三个鼠标圆传感器，返回
-- hover_sensor / footprint_sensor / power_sensor。
-- opts: host / game_state / placing（放置项信号，footprint 半径来源）。
function BoardSensors.create(s, opts)
  local host = opts.host
  local game_state = opts.game_state
  local placing = opts.placing

  local hover_circle = { center = { x = 0, y = 0, z = 0 }, radius = 0 }
  local footprint_circle = { center = { x = 0, y = 0, z = 0 }, radius = 0 }
  local power_circle = { center = { x = 0, y = 0, z = 0 }, radius = 0 }

  local function sample_mouse_to(circle, radius)
    local p = host.input.get_mouse_world_point()
    if p then
      circle.center.x = p.x
      circle.center.z = p.z
    end
    circle.radius = radius
    return circle
  end

  local hover_sensor = s:use(game_state.ground_zone:add_sensor(function()
    return sample_mouse_to(hover_circle, 0)
  end))

  local footprint_sensor = s:use(game_state.ground_zone:add_sensor(function()
    local item = placing:now()
    local radius = item and item.radius or 0
    return sample_mouse_to(footprint_circle, radius)
  end))

  local power_sensor = s:use(game_state.power_zone:add_sensor(function()
    return sample_mouse_to(power_circle, 0)
  end, function(owner)
    return owner.is_provider == true
  end))

  return hover_sensor, footprint_sensor, power_sensor
end

return BoardSensors
