-- server/ui/operation_log.lua — 实时操作日志（对局内实况反馈）。
--
-- 职责：把玩家/系统关心的「正在发生什么」投影为一列快照节点 hud/log/<i>，
-- 供客户端 recipe 表渲染成左下角的实时日志。只记录"关键时刻"，不逐帧刷屏；
-- 每 push 一次把最新条目放到 hud/log/0，旧的依次下移，超出 MAX 条丢弃最旧。
--
-- 层级：UI 层（L4），与 build_panel 同级；不反向依赖业务模块。业务通过组合根
-- 注入本对象的 push 接口（board_interactions / build_panel / net / main 编排），
-- 本模块只依赖 host.eui 节点接口。
--
-- 节点：
--   hud/log/0..MAX-1  text=日志行  color=按 kind 着色  visible=true
--
-- 颜色使用 0..1 浮点 RGB（与 GDD 11 H8 色板同风格）：
--   info    白   (1,1,1)
--   success 绿   (0.45,1,0.45)
--   warn    琥珀 (1,0.737,0)
--   error   红   (1,0.3,0.3)
--   system  青蓝 (0.4,0.8,1)
local M = {}
M.MAX = 8

local COLORS = {
  info    = { r = 1,     g = 1,     b = 1,     a = 1 },
  success = { r = 0.45,  g = 1,     b = 0.45,  a = 1 },
  warn    = { r = 1,     g = 0.737, b = 0,     a = 1 },
  error   = { r = 1,     g = 0.3,   b = 0.3,   a = 1 },
  system  = { r = 0.4,   g = 0.8,   b = 1,     a = 1 },
}

-- host: 宿主接缝（需 eui.node / eui.nodes）；opts.max 覆盖日志条数上限。
function M.create(host, opts)
  opts = opts or {}
  local log = {
    host = host,
    max = opts.max or M.MAX,
    entries = {}, -- entries[1] = 最新
    nodes = {},
  }

  -- 幂等建节点：重开后 host.eui.reset() 清空了注册表，重启再建即可。
  local function ensure_nodes()
    for i = 0, log.max - 1 do
      local path = "hud/log/" .. i
      local node = host.eui.nodes[path]
      if not node then
        node = host.eui.node(path)
        node:set_visible(true)
        node:set_text("")
        node:set_color(COLORS.info)
      end
      log.nodes[i] = node
    end
  end

  -- 清空日志（整局开始/重开后调用）。
  function log:reset()
    ensure_nodes()
    log.entries = {}
    for i = 0, log.max - 1 do
      local node = log.nodes[i]
      if node then node:set_text("") end
    end
  end

  -- push(kind, text)：kind 为 COLORS 的键；text 为显示行。最新条目放最上。
  function log:push(kind, text)
    local color = COLORS[kind] or COLORS.info
    ensure_nodes()
    table.insert(log.entries, 1, { text = text, color = color })
    while #log.entries > log.max do
      table.remove(log.entries)
    end
    for i = 0, log.max - 1 do
      local node = log.nodes[i]
      if node then
        local e = log.entries[i + 1]
        if e then
          node:set_text(e.text)
          node:set_color(e.color)
        elseif node.text ~= "" then
          node:set_text("")
        end
      end
    end
  end

  -- 当前条目文本（GM/测试读回用）。
  function log:lines()
    local out = {}
    for i, e in ipairs(log.entries) do
      out[i] = e.text
    end
    return out
  end

  return log
end

return M
