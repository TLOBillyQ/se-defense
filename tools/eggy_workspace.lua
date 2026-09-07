-- SE 工作区定位：deploy 与 sync 共用的唯一真源。
-- 工作区 = 编辑器 `code init` 绑定的本地 Lua 工程（根有 eggy.json），住在
-- Windows 侧，WSL 经 /mnt/c 直接读写。环境变量 EGGY_WORKSPACE 可覆盖。
local M = {}

M.DEFAULT = "/mnt/c/Users/Lzx_8/Desktop/dev/eggy/LuaSource_BaseDefence"

function M.resolve()
  return os.getenv("EGGY_WORKSPACE") or M.DEFAULT
end

function M.is_dir(path)
  local ok, _, code = os.execute("test -d '" .. path .. "'")
  return ok == true and code == 0
end

return M
