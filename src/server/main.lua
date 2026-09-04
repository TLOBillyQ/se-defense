-- SE 服务端入口（最小形态）：验证部署树可加载（spoke 运行时 + 业务组合根）。
-- GameTick 与游戏流的真实挂载待 realm 拆分决策（票 #7）后迭代。

local spoke = require("src.spoke")
local GameRoot = require("examples.base_defence.game_root")

assert(spoke, "src.spoke 加载失败")
assert(GameRoot, "examples.base_defence.game_root 加载失败")

print("[BaseDefence] server entry loaded: spoke + game_root ok")
