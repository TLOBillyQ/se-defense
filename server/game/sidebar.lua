-- 05_BaseDefence 侧边栏（SideBar）。
--
-- 职责：把 GameState.Mode 路由到四个面板（Pregame/Gameplay/GameOver/Victory），
-- Gameplay 面板内维护金钱、波次、剩余资源与悬停/放置消息的反应式文本。
-- 对应上游 Examples/05_BaseDefence/Scripts/UI/SideBar.cs 的面板路由与文本部分；
-- BuildItem 按钮/hotkey 的交互已由 BoardInteractions 的鼠标放置流取代，不在
-- 本模块重复实现。
--
-- 宿主等价物：面板路由用 EUI 节点的 set_visible 表达；文本为纯文本
-- （上游 uGUI rich text 标签在 headless mock 中不保留）。
--
-- Gameplay 子面板的节点与文本 effect 在 server.game.sidebar_gameplay。

local spoke = require("common.spoke")
local Epoch = spoke.Epoch
local Effect = spoke.Effect

local SideBarGameplay = require("server.game.sidebar_gameplay")

local SideBar = Epoch.extend("SideBar", {
  constructor = function(self, config)
    config = config or {}
    self.host = config.host or require("server.adapter.host")
    self.game_state = config.game_state or error("SideBar requires game_state", 2)
    self.wave_director = config.wave_director or error("SideBar requires wave_director", 2)
    self.interactions = config.interactions

    self.panels = nil
    self.texts = nil
  end,

  init = function(self, s)
    local host = self.host
    local game_state = self.game_state
    local wave_director = self.wave_director
    local interactions = self.interactions

    local owned = {}

    local function make(path, visible)
      local node = host.eui.node(path)
      node:set_visible(visible == true)
      owned[#owned + 1] = node
      return node
    end

    -- 上游 Setup()：四个面板初始全部隐藏；路由 effect 只点亮当前模式。
    local pregame = make("sidebar/pregame")
    local gameplay = make("sidebar/gameplay")
    local gameover = make("sidebar/gameover")
    local victory = make("sidebar/victory")

    self.panels = {
      pregame = pregame,
      gameplay = gameplay,
      gameover = gameover,
      victory = victory,
    }
    self.texts = SideBarGameplay.create(host, owned)

    local function mount_panel(panel, sb)
      panel:set_visible(true)
      sb:on_cleanup(function()
        panel:set_visible(false)
      end)
    end

    -- 面板路由：与上游 s.Effect(panel) 同构——effect body 每次按 mode
    -- 选择挂载一个 panel effect；旧 panel effect 清理时把根节点隐藏。
    s:call(Effect.new("SideBar.Route", function(sb)
      local mode = sb:d(game_state.mode)

      if mode == "Pregame" then
        sb:effect("SideBar.Pregame", function(s2)
          mount_panel(pregame, s2)
        end)
      elseif mode == "Playing" then
        sb:effect("SideBar.Gameplay", function(s2)
          mount_panel(gameplay, s2)
          SideBarGameplay.mount(s2, {
            game_state = game_state,
            wave_director = wave_director,
            interactions = interactions,
            texts = self.texts,
          })
        end)
      elseif mode == "GameOver" then
        sb:effect("SideBar.GameOver", function(s2)
          mount_panel(gameover, s2)
        end)
      else
        sb:effect("SideBar.Victory", function(s2)
          mount_panel(victory, s2)
        end)
      end
    end, game_state.mode))

    s:on_cleanup(function()
      for _, node in ipairs(owned) do
        if host.eui.nodes[node.path] == node then
          host.eui.destroy(node)
        end
      end
      self.panels = nil
      self.texts = nil
    end)
  end,
})

return SideBar
