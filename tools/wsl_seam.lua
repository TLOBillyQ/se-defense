-- WSL → Windows 接缝：把「怎么在 Windows 侧跑东西」收在一处，deploy 与收尾都不必知道
-- wslpath / cmd.exe / robocopy 的存在。环境不适合模块：需要 WSL 互操作，Linux 与 macOS
-- 上一律降级（win_path 返回 nil），由调用方走本地路径。
local M = {}

local function q(path)
  return "'" .. path .. "'"
end

-- wslpath -w 转 Windows 路径；不在 WSL 或转换失败返回 nil（由调用方回落）。
function M.win_path(path)
  local h = io.popen("wslpath -w " .. q(path) .. " 2>/dev/null")
  local out = (h:read("*a") or ""):match("^[^\r\n]*")
  h:close()
  if out == nil or out == "" then return nil end
  return out
end

-- 把若干行 cmd 命令写成临时 .cmd，cmd.exe 执行一次；返回 ok, exit_code, stdout。
-- 不能把带引号的路径直接放在 cmd.exe 参数里：WSL 互操作转 Windows 命令行时 `\"` 与
-- UNC 前导 `\\` 互相干扰，引号会被当成路径的一部分。批处理由 cmd 自己解析，没有这层
-- 转义。批处理放 WSL 侧 /tmp，cmd.exe 经 \\wsl.localhost UNC 执行（仅工作目录不支持
-- UNC，运行脚本没问题）。cmd.exe 每次启动约 0.25s，所以一批命令只启一次。
function M.cmd_batch(lines)
  local batch = os.tmpname() .. ".cmd"
  local f = io.open(batch, "wb")
  if not f then return false, nil, "" end
  f:write("@echo off\r\n", table.concat(lines, "\r\n"), "\r\n")
  f:close()
  local wbatch = M.win_path(batch)
  local ok, code, out = false, nil, ""
  if wbatch then
    local h = io.popen("cmd.exe /c " .. q(wbatch) .. " 2>/dev/null; echo \"__rc=$?\"")
    out = h:read("*a") or ""
    h:close()
    code = tonumber(out:match("__rc=(%d+)%s*$"))
    out = out:gsub("__rc=%d+%s*$", "")
    ok = code == 0
  end
  os.remove(batch)
  os.remove(batch:sub(1, -5))
  return ok, code, out
end

-- 目录增量镜像：robocopy 只传变化文件，省掉逐文件跨 9P 的 rm/cp。
-- robocopy 必须经 cmd.exe：system32 里是 Robocopy.exe，Linux PATH 大小写敏感。
-- 单个 robocopy 退出码 0-7 均为成功，>= 8 失败；任一失败整批返回 false，
-- 由调用方整批回落本地 rm + cp。
function M.robocopy_mirror(dir_pairs)
  if #dir_pairs == 0 then return true end
  local lines = {}
  for _, pr in ipairs(dir_pairs) do
    local ws, wd = M.win_path(pr.src), M.win_path(pr.dst)
    if not ws or not wd then return false end
    lines[#lines + 1] = 'robocopy "' .. ws .. '" "' .. wd
      .. '" /MIR /NFL /NDL /NJH /NJS /NP /R:2 /W:1 >nul 2>&1'
    lines[#lines + 1] = "if errorlevel 8 exit /b 8"
  end
  lines[#lines + 1] = "exit /b 0"
  return (M.cmd_batch(lines))
end

return M
