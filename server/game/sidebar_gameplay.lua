-- 05_BaseDefence 侧边栏 Gameplay 面板内容（规则真源 docs/gdd/11-hud.md）。
--
-- SideBar 路由到 Playing 时点亮的面板：资金行（H2，进攻期另起琥珀色停采提示
-- 行）、矿点行（H3）、波次行与倒计时行（H4，倒计时颜色按 H5 插值）、
-- 消息行（H6：放置提示 / 悬停描述 / 空）。节点在 init 阶段创建（路径固定、
-- 由 SideBar 统一登记清理），面板路由时本模块点亮/熄灭子节点并挂载文本
-- effect。对应上游 SideBar.cs 的 Gameplay 面板部分。

local SideBarGameplay = {}

-- H8 颜色常量（与 tools/acceptance/steps_support 的命名色板一致）。
local COLOR_LIGHT_BLUE = { r = 0.6, g = 0.8, b = 1, a = 1 } -- 淡蓝
local COLOR_AMBER = { r = 1, g = 0.737, b = 0, a = 1 }      -- 琥珀
local COLOR_DANGER = { r = 1, g = 0.3, b = 0.3, a = 1 }     -- 危险红

local function is_signal(value)
  return type(value) == "table"
    and type(value.now) == "function"
    and type(value.subscribe) == "function"
end

-- H2：采集速率保留 1 位小数并去尾零（2.5 → "2.5"，4 → "4"）。
local function format_rate(rate)
  local text = ("%.1f"):format(rate)
  return (text:gsub("%.0$", ""))
end

-- H5：接近度 c = 1 − 剩余/30；c < 0.5 淡蓝→琥珀，否则琥珀→危险红。
local function countdown_color(countdown)
  local c = 1 - countdown / 30
  local from, to, t
  if c < 0.5 then
    from, to, t = COLOR_LIGHT_BLUE, COLOR_AMBER, c * 2
  else
    from, to, t = COLOR_AMBER, COLOR_DANGER, (c - 0.5) * 2
  end
  return {
    r = from.r + (to.r - from.r) * t,
    g = from.g + (to.g - from.g) * t,
    b = from.b + (to.b - from.b) * t,
    a = 1,
  }
end

-- init 阶段创建文本节点（面板初始隐藏，由路由 effect 点亮）。
-- owned 为 SideBar 的统一清理登记表；返回 texts 表供路由/挂载使用。
function SideBarGameplay.create(host, owned)
  local function make(path, visible)
    local node = host.eui.node(path)
    node:set_visible(visible == true)
    owned[#owned + 1] = node
    return node
  end

  local money_node = make("sidebar/gameplay/money")
  local pause_node = make("sidebar/gameplay/pause")
  pause_node:set_text("harvesting paused")
  pause_node:set_color(COLOR_AMBER)
  local sites_node = make("sidebar/gameplay/resources")
  local wave_node = make("sidebar/gameplay/wave")
  local countdown_node = make("sidebar/gameplay/countdown")
  local message_node = make("sidebar/gameplay/message")
  message_node:set_text("")

  return {
    money = money_node,
    pause = pause_node,
    resources = sites_node,
    wave = wave_node,
    countdown = countdown_node,
    message = message_node,
  }
end

-- 在 Playing 分支的作用域 sb 上点亮子节点并挂载文本 effect。
function SideBarGameplay.mount(sb, opts)
  local game_state = opts.game_state
  local wave_director = opts.wave_director
  local interactions = opts.interactions
  local texts = opts.texts
  local nodes = {
    texts.money, texts.pause, texts.resources,
    texts.wave, texts.countdown, texts.message,
  }

  -- headless 下 EUI 节点没有父子层级；把 gameplay 子节点一起点亮，
  -- 这样面板路由在扁平 host-mock 里也可断言。停采提示只在进攻期点亮。
  sb:effect("SideBar.visibility", function(s3)
    local assault = s3:d(wave_director.wave).assault == true
    for _, node in ipairs(nodes) do
      node:set_visible(node ~= texts.pause or assault)
    end
  end)
  sb:on_cleanup(function()
    for _, node in ipairs(nodes) do
      node:set_visible(false)
    end
  end)

  -- H2：资金行 `$<资金> (+<速率>)`。
  sb:effect("SideBar.money", function(s3)
    local money = s3:d(game_state.money)
    local rate = s3:d(game_state.collect_rate)
    texts.money:set_text(("$%d (+%s)"):format(money, format_rate(rate)))
  end)

  -- H4：波次行 `Wave <N>`；倒计时行三种形态（H4）+ 颜色插值（H5）。
  sb:effect("SideBar.wave", function(s3)
    local wave = s3:d(wave_director.wave)
    texts.wave:set_text(("Wave %d"):format(wave.number))
    local seconds = math.max(0, math.ceil(wave.countdown))
    local text
    if wave.assault then
      text = ("%s attacking"):format(wave.front)
    elseif wave.front ~= "None" then
      text = ("%s in %ds"):format(wave.front, seconds)
    else
      text = ("in %ds"):format(seconds)
    end
    texts.countdown:set_text(text)
    texts.countdown:set_color(countdown_color(wave.countdown))
  end)

  -- H3：矿点行。
  if is_signal(game_state.resources_remaining) then
    sb:effect("SideBar.resources", function(s3)
      texts.resources:set_text(("Resource Sites: %d"):format(s3:d(game_state.resources_remaining)))
    end)
  else
    texts.resources:set_text("Resource Sites: 0")
  end

  -- H6 + 16 I6：消息行 = 放置提示 / 悬停描述 / 空。
  if interactions and is_signal(interactions.placing) and is_signal(interactions.hovering) then
    sb:effect("SideBar.message", function(s3)
      local placing = s3:d(interactions.placing)
      local hovered = s3:d(interactions.hovering)
      if placing ~= nil then
        local label = placing.display_name
          or (placing.key and (placing.key:gsub("^%l", string.upper)))
          or "Building"
        texts.message:set_text(("Placing %s — tap its button to cancel"):format(label))
      elseif hovered ~= nil and is_signal(hovered.hover_info) then
        local info = s3:d(hovered.hover_info)
        texts.message:set_text(info and info.description or "")
      else
        texts.message:set_text("")
      end
    end)
  end
end

return SideBarGameplay
