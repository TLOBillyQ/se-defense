-- 部署收尾：镜像落盘后，经 Windows 侧 editor-cli 确认编辑器内的代码也是最新的
-- （code validate → code diff → 有差异才 code push → 复核），一步到位，不留下一步。
-- 编辑器 syncEnabled=true 时落盘通常即进编辑器内存（#5 实测），但「通常」不是「一定」。
--
-- 环境不适合模块：依赖外部设备（正在运行的编辑器）与 Windows 侧 exe。editor-cli 必须
-- 用 Windows 侧的 exe 经 cmd.exe 从工作区 cwd 执行：WSL 侧二进制解析不了 eggy.json 里的
-- C:\ 地图目录（实测 MAP_NOT_FOUND）。所以只有工作区真住在 Windows 侧时才调用本模块，
-- 判定见 tools/deploy_plan.crosses_seam。纯解析部分（parse_changelist）单独导出可测。
local seam = require("tools.wsl_seam")

local M = {}

-- 从工作区 cwd 跑一条 editor-cli 子命令，返回 ok, stdout。exe 不存在时返回 nil。
local function editor_cli(ws, argline)
  local wws = seam.win_path(ws)
  if not wws then return nil, "wslpath 失败" end
  local ok, code, out = seam.cmd_batch({
    'if not exist "%USERPROFILE%\\.eggitor\\cli\\editor-cli.exe" exit /b 127',
    'cd /d "' .. wws .. '"',
    '"%USERPROFILE%\\.eggitor\\cli\\editor-cli.exe" ' .. argline,
  })
  if code == 127 then return nil, "未找到 %USERPROFILE%\\.eggitor\\cli\\editor-cli.exe" end
  return ok, out
end

local function project_name(ws)
  local f = io.open(ws .. "/eggy.json", "rb")
  if not f then return nil end
  local body = f:read("*a") or ""
  f:close()
  return body:match('"projectName"%s*:%s*"([^"]+)"')
end

-- 解析 `code diff` 纯文本第三行：changelist: only-local=N differs=N only-on-map=N unchanged=N
function M.parse_changelist(out)
  local line = out:match("changelist:[^\r\n]*")
  if not line then return nil end
  local cl = {}
  for k, v in line:gmatch("([%w%-]+)=(%d+)") do cl[k] = tonumber(v) end
  return cl
end

-- 落后编辑器的文件数：只有本地独有与两侧不同算落后，地图侧多出的不算（deploy 不删）。
function M.behind_count(cl)
  return (cl["only-local"] or 0) + (cl["differs"] or 0)
end

-- 返回 true 表示收尾完成（含「编辑器没开该地图，跳过」）；失败返回 nil, 原因。
function M.run(ws)
  local ok, out = editor_cli(ws, "code validate")
  if ok == nil then
    print("编辑器收尾跳过: " .. tostring(out))
    return true
  end
  if not ok or not out:find("validate: OK", 1, true) then
    return nil, "code validate 未通过:\n" .. out
  end
  print("validate: OK")

  local inst = project_name(ws)
  local inst_arg = inst and ('--editor-instance "' .. inst .. '" ') or ""
  local function diff()
    local dok, dout = editor_cli(ws, inst_arg .. "code diff")
    return dok and M.parse_changelist(dout) or nil, dout
  end

  local cl, raw = diff()
  if not cl then
    print("编辑器未打开该地图，未校验编辑器内代码（磁盘已是最新，打开地图后自动同步）")
    print((raw or ""):match("^[^\r\n]*") or "")
    return true
  end
  local dirty = M.behind_count(cl)
  if dirty > 0 then
    print("编辑器落后 " .. dirty .. " 个文件，code push …")
    local pok, pout = editor_cli(ws, inst_arg .. "code push")
    if not pok then return nil, "code push 失败:\n" .. tostring(pout) end
    cl = diff()
    dirty = cl and M.behind_count(cl) or -1
    if dirty ~= 0 then
      return nil, "push 后复核仍有差异（" .. dirty .. "），请手动 code diff"
    end
  end
  print("编辑器: 已同步（unchanged=" .. (cl["unchanged"] or 0) .. "）")
  local ghosts = cl["only-on-map"] or 0
  if ghosts > 0 then
    print("注意: 地图侧多出 " .. ghosts .. " 个本地没有的文件（deploy 不删）；"
      .. "清理需在工作区跑 editor-cli code push --delete --yes")
  end
  return true
end

return M
