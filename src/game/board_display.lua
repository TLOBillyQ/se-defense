-- 05_BaseDefence 棋盘表现层（BoardInteractions 的 #23 表现层部分）。
--
-- 职责：按 placing/hovering 状态把覆盖圈与电力连线渲染为 EUI ring/line 节点
-- （host-mock 下只保留可断言状态）。这是 BoardInteractions 的纯渲染面，
-- 选择/放置逻辑留在 src.game.board_interactions。
--
-- 调色板对齐上游 BoardInteractions.cs 的序列化默认值；上游用合并轮廓 mesh
-- 渲染覆盖圈并集，本端口按 #18 Q8 裁为“每圆一个 EUI ring”（见
-- CoverageDisplay / LinkDisplay）。

local CoverageDisplay = require("src.game.coverage_display")
local LinkDisplay = require("src.game.link_display")

local POWER_COVERAGE_COLOUR = { r = 1, g = 0.7372549, b = 0, a = 1 }
local RADAR_COVERAGE_COLOUR = { r = 1, g = 0.7372549, b = 0, a = 1 }
local TURRET_COVERAGE_COLOUR = { r = 1, g = 0.7372549, b = 0, a = 1 }
local REPAIR_COVERAGE_COLOUR = { r = 1, g = 0.7372549, b = 0, a = 1 }
local POWER_LINK_COLOUR = { r = 0, g = 1, b = 1, a = 1 }
local UNIT_RING_COLOUR = { r = 0, g = 1, b = 1, a = 1 }
local VALID_PLACEMENT_COLOUR = { r = 0, g = 1, b = 0, a = 1 }
local INVALID_PLACEMENT_COLOUR = { r = 1, g = 0, b = 0, a = 1 }

local BoardDisplay = {}

local function zone_for(game_state, coverage)
  if coverage == "Power" then
    return game_state.power_zone, function(owner)
      return owner.is_provider == true
    end
  elseif coverage == "Radar" then
    return game_state.radar_zone, nil
  elseif coverage == "Turret" then
    return game_state.turret_zone, nil
  elseif coverage == "Repair" then
    return game_state.repair_zone, nil
  end
  return nil, nil
end

local function coverage_colour(coverage)
  if coverage == "Radar" then return RADAR_COVERAGE_COLOUR end
  if coverage == "Turret" then return TURRET_COVERAGE_COLOUR end
  if coverage == "Repair" then return REPAIR_COVERAGE_COLOUR end
  return POWER_COVERAGE_COLOUR
end

-- 把棋盘交互的显示 effect 挂到 playing phase 的作用域 s 上。
-- opts: host / game_state / view / placing / hovering / hovering_circle /
-- placement_valid。
function BoardDisplay.mount(s, opts)
  local host = opts.host
  local game_state = opts.game_state
  local view = opts.view
  local placing = opts.placing
  local hovering = opts.hovering
  local hovering_circle = opts.hovering_circle
  local placement_valid = opts.placement_valid

  -- ═══ #23 表现层：覆盖圈 / 电力连线 → EUI ring/line ═══
  local bounds = game_state:level_bounds()
  local half_x = (bounds.max.x - bounds.min.x) / 2
  local half_z = (bounds.max.z - bounds.min.z) / 2
  local board_area = {
    center = { x = bounds.center.x, y = 0, z = bounds.center.z },
    radius = math.sqrt(half_x * half_x + half_z * half_z),
  }
  local function board_area_fn()
    return board_area
  end

  -- 把“某类型覆盖圈”挂成一个分支 effect（key 为 effect 名，path 为节点前缀）。
  -- zone 为 nil 时什么都不画（hover_info 没有对应 zone 的类型）。
  local function draw_coverage_zone(s3, key, path, zone, filter, coverage)
    if zone == nil then
      return
    end
    s3:effect(key, function(s4)
      CoverageDisplay.draw_zone(s4, {
        host = host,
        zone = zone,
        path = path,
        area = board_area_fn,
        filter = filter,
        colour = coverage_colour(coverage),
      })
    end)
  end

  -- 把“单个圆信号”挂成一个分支 effect（高亮环 / 放置 footprint）。
  local function draw_ring(s3, key, path, circle, colour)
    s3:effect(key, function(s4)
      CoverageDisplay.draw_circle(s4, {
        host = host,
        path = path,
        circle = circle,
        colour = colour,
      })
    end)
  end

  -- 无悬停且无放置：显示电网完整生成树。
  s:effect("BoardInteractions.idle_links", function(s3)
    if s3:d(hovering) ~= nil or s3:d(placing) ~= nil then
      return
    end
    LinkDisplay.draw_all(s3, {
      host = host,
      path = "board/power_links",
      colour = POWER_LINK_COLOUR,
    })
  end, hovering, placing)

  -- 悬停：覆盖圈 + 该单位 parent 链 + 单位高亮环。
  s:effect("BoardInteractions.show_hovered", function(s3)
    local hovered = s3:d(hovering)
    if hovered == nil then
      return
    end

    local info = s3:d(hovered.hover_info)
    local zone, filter = zone_for(game_state, info.coverage)
    draw_coverage_zone(s3, "BoardInteractions.hover_coverage", "board/hover_coverage", zone, filter, info.coverage)

    if info.power_node then
      s3:effect("BoardInteractions.hover_link", function(s4)
        LinkDisplay.draw_chain(s4, {
          host = host,
          path = "board/hover_link",
          start = info.power_node,
          colour = POWER_LINK_COLOUR,
        })
      end)
    end

    local circle = s3:d(hovering_circle)
    if circle then
      -- 上游高亮环 = footprint 半径 × 1.5（BoardInteractions.ShowHovered）。
      local ring = {
        center = circle.center,
        radius = circle.radius * 1.5,
      }
      draw_ring(s3, "BoardInteractions.hover_ring", "board/hover_ring", ring, UNIT_RING_COLOUR)
    end
  end, hovering, hovering_circle)

  -- 放置：电力覆盖 + 放置类型覆盖 + 随鼠标移动的 footprint。
  s:effect("BoardInteractions.placement_display", function(s3)
    local item = s3:d(placing)
    if item == nil then
      return
    end

    s3:effect("BoardInteractions.placement_power", function(s4)
      CoverageDisplay.draw_zone(s4, {
        host = host,
        zone = game_state.power_zone,
        path = "board/placement_power",
        area = board_area_fn,
        filter = function(owner)
          return owner.is_provider == true
        end,
        colour = POWER_COVERAGE_COLOUR,
      })
    end)

    if item.coverage and item.coverage ~= "Power" then
      local zone, filter = zone_for(game_state, item.coverage)
      draw_coverage_zone(s3, "BoardInteractions.placement_coverage", "board/placement_coverage", zone, filter, item.coverage)
    end

    local footprint = s3:memo(function(m)
      local p = m:d(view.mouse_point)
      if p == nil then
        return nil
      end
      return {
        center = { x = p.x, y = 0, z = p.z },
        radius = item.radius or 0.6,
      }
    end)
    local footprint_colour = s3:memo(function(m)
      if m:d(placement_valid) then
        return VALID_PLACEMENT_COLOUR
      end
      return INVALID_PLACEMENT_COLOUR
    end)

    draw_ring(s3, "BoardInteractions.placement_footprint", "board/placement_footprint", footprint, footprint_colour)
  end, placing)
end

return BoardDisplay
