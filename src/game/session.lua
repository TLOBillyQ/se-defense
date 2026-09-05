-- 05_BaseDefence 会话壳（Restart 的宿主等价物）。
--
-- 上游 GameState.Restart() 的做法是：
--   UnitySignals.NotifySceneTeardown(activeScene) → SceneManager.LoadScene(...)
-- 即先让 Spoke 拆树，再重载场景。蛋仔宿主没有场景重载，因此本模块把同一
-- 语义落成：
--   1. tree:dispose()             —— 让 Spoke 逆序清理整棵子树；
--   2. host:reset_scene()         —— 清空 mock 场景（EUI / 实体 / 输入）；
--   3. 用同一份 config 创建新的 GameRoot 与 SpokeTree。
--
-- 真机部署时，宿主自己的“离开/重进玩法”流程就是场景重载；本文件只是
-- headless 验证与单局重开的薄壳，不进入核心库。
--
-- 组合根可选：默认 GameRoot（垂直切片）；传 root_class 可换成 GameRootFull
-- 等任何 `.new(config)` 返回 Epoch 的组合根（se-defense 真机重开走这里）。

local spoke = require("vendor.spoke")
local SpokeTree = spoke.SpokeTree
local GameRoot = require("src.game.game_root")

local host_default = require("src.adapter.host")

local Session = {}
Session.__index = Session

local function build(config, mode, root_class)
  local root = (root_class or GameRoot).new(config)
  local tree
  if mode == "Manual" then
    tree = SpokeTree.spawn_manual(root)
    tree:flush()
  else
    tree = SpokeTree.spawn(root)
  end
  return root, tree
end

local function wrap(config, mode, root_class)
  local root, tree = build(config, mode, root_class)
  local self = setmetatable({
    config = config,
    mode = mode,
    root_class = root_class,
    host = config.host or host_default,
    root = root,
    tree = tree,
    game_state = root.game_state,
    wave_director = root.wave_director,
  }, Session)
  return self
end

-- 创建 Auto 会话（默认）；mode 传 "Manual" 可创建 Manual 会话；
-- root_class 缺省为 GameRoot。
function Session.spawn(config, mode, root_class)
  return wrap(config or {}, mode or "Auto", root_class)
end

-- 无头测试常用：Manual 树 + 首帧 flush。
function Session.spawn_manual(config, root_class)
  return wrap(config or {}, "Manual", root_class)
end

-- 拆掉当前树并重建整局游戏；返回自身，字段已指向新树。
function Session:restart()
  if self.tree then
    self.tree:dispose()
  end

  local host = self.host
  if type(host) == "table" and type(host.reset_scene) == "function" then
    host:reset_scene()
  end

  local replacement = wrap(self.config, self.mode, self.root_class)
  self.host = replacement.host
  self.root = replacement.root
  self.tree = replacement.tree
  self.game_state = replacement.game_state
  self.wave_director = replacement.wave_director
  return self
end

function Session:start_game()
  self.game_state:start_game()
  if self.mode == "Manual" then
    self.tree:flush()
  end
end

function Session:dispose()
  if self.tree then
    self.tree:dispose()
    self.tree = nil
  end
end

return Session
