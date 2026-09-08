-- 部署计划：仓库根白名单 → 本仓库拥有的子树清单，以及「目的地是否真的跨接缝」。
-- 纯模块：不碰文件系统、不起子进程，目录清单由调用方注入（tools/deploy.lua 用 find
-- 枚举）。部署规则（CONTEXT.md「部署树」）在这里回答一次，镜像与收尾只搬字节。
local M = {}

-- 官方强制的工作区根目录，即部署白名单；顺序即部署顺序。
-- 重置粒度是每个端下的一级子树；白名单之外的内容（无论仓库根还是工作区）一律不碰。
M.REALMS = { "client", "common", "server" }

-- 本仓库拥有的子树清单：<端>/<child>，仓库路径与工作区路径相同。
-- list_entries(realm) 返回 { {name=, dir=}, ... }（调用方保证按名排序）。
-- 返回 { {rel=, dir=, src=, dst=}, ... }；dir 在这里定一次，后续不再问文件系统。
function M.targets(workspace, list_entries, realms)
  local targets = {}
  for _, realm in ipairs(realms or M.REALMS) do
    for _, child in ipairs(list_entries(realm)) do
      local rel = realm .. "/" .. child.name
      targets[#targets + 1] = {
        rel = rel,
        dir = child.dir,
        src = rel,
        dst = workspace .. "/" .. rel,
      }
    end
  end
  return targets
end

-- 目的地是否住在 Windows 侧。入参是 `wslpath -w <目的地>` 的输出（nil = 转不了）。
-- 盘符路径（C:\…）才是真的跨 WSL→Windows 接缝：robocopy 增量传输、editor-cli 收尾
-- 都只有在这一侧才有意义。`\\wsl…` 说明 Windows 要反过来走 9P 读 Linux 侧的树，
-- 那条路比本地 cp 更慢，等于自己造了一次本来不存在的跨系统调用；nil 则根本不在 WSL。
function M.crosses_seam(win_dst)
  if type(win_dst) ~= "string" then return false end
  return win_dst:match("^%a:") ~= nil
end

return M
