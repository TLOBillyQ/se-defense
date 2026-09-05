-- 05_BaseDefence 侧边栏 Gameplay 面板内容。
--
-- SideBar 路由到 Playing 时点亮的面板：金钱、波次、剩余资源与悬停/放置消息
-- 四行反应式文本。节点在 init 阶段创建（路径固定、由 SideBar 统一登记清理），
-- 面板路由时本模块点亮/熄灭子节点并挂载文本 effect。
-- 对应上游 Examples/05_BaseDefence/Scripts/UI/SideBar.cs 的 Gameplay 面板部分。

local SideBarGameplay = {}

local function is_signal(value)
  return type(value) == "table"
    and type(value.now) == "function"
    and type(value.subscribe) == "function"
end

-- init 阶段创建四个文本节点（面板初始隐藏，由路由 effect 点亮）。
-- owned 为 SideBar 的统一清理登记表；返回 texts 表供路由/挂载使用。
function SideBarGameplay.create(host, owned)
  local function make(path, visible)
    local node = host.eui.node(path)
    node:set_visible(visible == true)
    owned[#owned + 1] = node
    return node
  end

  local money_node = make("sidebar/gameplay/money")
  local wave_node = make("sidebar/gameplay/wave")
  local resources_node = make("sidebar/gameplay/resources")
  local message_node = make("sidebar/gameplay/message")
  message_node:set_text("")

  return {
    money = money_node,
    wave = wave_node,
    resources = resources_node,
    message = message_node,
  }
end

-- 在 Playing 分支的作用域 sb 上点亮子节点并挂载文本 effect。
function SideBarGameplay.mount(sb, opts)
  local game_state = opts.game_state
  local wave_director = opts.wave_director
  local interactions = opts.interactions
  local texts = opts.texts
  local money_node = texts.money
  local wave_node = texts.wave
  local resources_node = texts.resources
  local message_node = texts.message

  -- headless 下 EUI 节点没有父子层级；把 gameplay 子节点一起点亮，
  -- 这样面板路由在扁平 host-mock 里也可断言。
  money_node:set_visible(true)
  wave_node:set_visible(true)
  resources_node:set_visible(true)
  message_node:set_visible(true)
  sb:on_cleanup(function()
    money_node:set_visible(false)
    wave_node:set_visible(false)
    resources_node:set_visible(false)
    message_node:set_visible(false)
  end)

  sb:effect("SideBar.money", function(s3)
    local money = s3:d(game_state.money)
    local rate = s3:d(game_state.collect_rate)
    local wave = s3:d(wave_director.wave)
    local text = ("Money: $%.0f (+%.0f/s)"):format(money, rate)
    if wave and wave.starts_in == 0 then
      text = text .. "\nharvesting paused"
    end
    money_node:set_text(text)
  end)

  sb:effect("SideBar.wave", function(s3)
    local wave = s3:d(wave_director.wave)
    local header = ("Wave %d"):format(wave.number)
    local text
    if wave.starts_in == 0 then
      text = ("%s: %s attacking"):format(header, wave.front)
    elseif wave.front ~= "None" then
      text = ("%s: %s in %ds"):format(header, wave.front, wave.starts_in)
    else
      text = ("%s: in %ds"):format(header, wave.starts_in)
    end
    wave_node:set_text(text)
  end)

  if is_signal(game_state.resources_remaining) then
    sb:effect("SideBar.resources", function(s3)
      resources_node:set_text(("Resource Sites: %d"):format(s3:d(game_state.resources_remaining)))
    end)
  else
    resources_node:set_text("Resource Sites: 0")
  end

  if interactions and is_signal(interactions.placing) and is_signal(interactions.hovering) then
    sb:effect("SideBar.message", function(s3)
      local placing = s3:d(interactions.placing)
      local hovered = s3:d(interactions.hovering)
      if placing ~= nil then
        local label = placing.display_name or placing.key or "Building"
        message_node:set_text(("Placing %s — press Escape to cancel"):format(label))
      elseif hovered ~= nil and is_signal(hovered.hover_info) then
        local info = s3:d(hovered.hover_info)
        message_node:set_text(info and info.description or "")
      else
        message_node:set_text("")
      end
    end)
  end
end

return SideBarGameplay
