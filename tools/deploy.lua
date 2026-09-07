-- 部署脚本：把部署树 byte 镜像进 SE 工作区（票 #6；src/目录层级调整）。
-- 运行：在仓库根执行 `lua5.4 tools/cli.lua deploy`（WSL；经 /mnt/c 直接操作 Windows 侧）；
-- 直接 `lua5.4 tools/deploy.lua` 亦可。反方向回同步见 tools/sync.lua。
-- 先例：monopoly tools/packages/ops/deploy.lua（镜像部署 + WSL→Windows 接缝）。
--
-- 部署树（CONTEXT.md「部署树」词条）：
--   <端>/<child>/...   → 工作区 <端>/<child>/...（端 = 白名单 client/common/server，
--                        即官方强制的工作区根，仓库根直接对齐，见 M.REALMS；
--                        spoke 运行时即 common/spoke/，与业务同规则镜像）
-- 仓库根白名单之外的内容（docs/、tools/、tests/、data/ 等）不部署。
--
-- 镜像纪律：目标子树与源完全一致，不留幽灵文件（spoke-lua 接入指南）。
-- 目录镜像优先让 Windows 侧 robocopy /MIR 做增量（先例 monopoly deploy.lua）：
-- WSL 经 9P 逐文件 rm/cp 每个文件都是一次跨系统调用，树一大就是几十秒；
-- robocopy 只传变化文件。robocopy 不可用或退出码 >= 8 时回落 rm + cp。
-- 重置粒度是本仓库拥有的「端的一级子树」（如 server/game、server/main.lua）；
-- 其余内容（eggy.json、server/_trigger、data、.vscode、log.txt、unit_scripts 等）不碰。
-- 编辑器 syncEnabled=true：落盘即进编辑器内存，通常无需 code push（#5 实测）。
-- 但「通常」不是「一定」：镜像完成后 deploy 自己再跑 Windows 侧 editor-cli 做收尾
-- （code validate → code diff → 有差异才 code push → 复核），一步到位，不留下一步。
-- editor-cli 必须用 Windows 侧的 exe 经 cmd.exe 从工作区 cwd 执行：WSL 侧二进制
-- 解析不了 eggy.json 里的 C:\ 地图目录（实测 MAP_NOT_FOUND）。

package.path = "./?.lua;./?/init.lua;" .. package.path

local workspace = require("tools.eggy_workspace")

local M = {}

-- 官方强制的工作区根目录，即部署白名单；顺序即部署顺序。
-- 重置粒度是每个端下的一级子树；白名单之外的内容（无论仓库根还是工作区）一律不碰。
M.REALMS = { "client", "common", "server" }

-- 业务失败统一 error 出去，由 main 收成 stderr + 退出码 1。
local function fail(msg)
  error("deploy: " .. msg, 0)
end

local function run(cmd)
  local ok, _, code = os.execute(cmd)
  if not ok or code ~= 0 then
    fail("command failed (" .. tostring(code) .. "): " .. cmd)
  end
end

-- 路径里只有仓库内固定字符，但统一加引号防呆。
local function q(path)
  return "'" .. path .. "'"
end

local function rm_rf(path)
  run("rm -rf " .. q(path))
end

local function cp_entry(src, dst)
  local ok, _, code = os.execute("test -d " .. q(src))
  if ok and code == 0 then
    run("mkdir -p " .. q(dst))
    run("cp -r " .. q(src .. "/.") .. " " .. q(dst))
  else
    run("mkdir -p " .. q(dst:match("^(.*)/[^/]+$") or "."))
    run("cp " .. q(src) .. " " .. q(dst))
  end
end

-- wslpath -w 转 Windows 路径；失败返回 nil（由调用方回落）。
local function win_path(path)
  local h = io.popen("wslpath -w " .. q(path) .. " 2>/dev/null")
  local out = (h:read("*a") or ""):match("^[^\r\n]*")
  h:close()
  if out == nil or out == "" then return nil end
  return out
end

-- 目录增量镜像：把全部目录写进一个临时 .cmd 批处理，cmd.exe 执行一次（每次启动约
-- 0.25s，所以只启一次）。不能把带引号的路径直接放在 cmd.exe 参数里：WSL 互操作转
-- Windows 命令行时 `\"` 与 UNC 前导 `\\` 互相干扰，引号会被当成路径的一部分。
-- 批处理由 cmd 自己解析，没有这层转义。批处理放 WSL 侧 /tmp，cmd.exe 经
-- \\wsl.localhost UNC 路径执行（仅工作目录不支持 UNC，运行脚本没问题）。
-- robocopy 必须经 cmd.exe：system32 里是 Robocopy.exe，Linux PATH 大小写敏感。
-- 单个 robocopy 退出码 0-7 均为成功，>= 8 失败；任一失败整批返回 false，
-- 由调用方整批回落 rm + cp。
-- 把若干行 cmd 命令写成临时 .cmd，cmd.exe 执行一次；返回 ok, exit_code, stdout。
-- 见上文：不能把带引号的路径直接放在 cmd.exe 参数里，交给批处理自己解析。
local function cmd_batch(lines)
  local batch = os.tmpname() .. ".cmd"
  local f = io.open(batch, "wb")
  if not f then return false, nil, "" end
  f:write("@echo off\r\n", table.concat(lines, "\r\n"), "\r\n")
  f:close()
  local wbatch = win_path(batch)
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

local function robocopy_mirror_all(pairs_)
  if #pairs_ == 0 then return true end
  local lines = {}
  for _, pr in ipairs(pairs_) do
    local ws, wd = win_path(pr.src), win_path(pr.dst)
    if not ws or not wd then return false end
    lines[#lines + 1] = 'robocopy "' .. ws .. '" "' .. wd .. '" /MIR /NFL /NDL /NJH /NJS /NP /R:2 /W:1 >nul 2>&1'
    lines[#lines + 1] = "if errorlevel 8 exit /b 8"
  end
  lines[#lines + 1] = "exit /b 0"
  local ok = cmd_batch(lines)
  return ok
end

local function is_dir(path)
  local ok, _, code = os.execute("test -d " .. q(path))
  return ok == true and code == 0
end

local function file_count(path)
  local handle = io.popen("find " .. q(path) .. " -type f | wc -l")
  local n = tonumber((handle:read("*a") or ""):match("%d+")) or 0
  handle:close()
  return n
end

-- 枚举目录一级条目：{ {name=, dir=}, ... }，按名排序保证计划稳定。
local function entries(dir)
  local out = {}
  local handle = io.popen("find " .. q(dir) .. " -mindepth 1 -maxdepth 1 2>/dev/null")
  for line in handle:lines() do
    local name = line:sub(#dir + 2)
    local ok, _, code = os.execute("test -d " .. q(line))
    out[#out + 1] = { name = name, dir = ok and code == 0 }
  end
  handle:close()
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

-- ── 编辑器收尾（Windows 侧 editor-cli） ────────────────────────────────────

-- 从工作区 cwd 跑一条 editor-cli 子命令，返回 ok, stdout。exe 不存在时返回 nil。
local function editor_cli(ws, argline)
  local wws = win_path(ws)
  if not wws then return nil, "wslpath 失败" end
  local ok, code, out = cmd_batch({
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
local function parse_changelist(out)
  local line = out:match("changelist:[^\r\n]*")
  if not line then return nil end
  local cl = {}
  for k, v in line:gmatch("([%w%-]+)=(%d+)") do cl[k] = tonumber(v) end
  return cl
end

local function verify_editor(ws)
  local ok, out = editor_cli(ws, "code validate")
  if ok == nil then
    print("编辑器收尾跳过: " .. tostring(out))
    return
  end
  if not ok or not out:find("validate: OK", 1, true) then
    fail("code validate 未通过:\n" .. out)
  end
  print("validate: OK")

  local inst = project_name(ws)
  local inst_arg = inst and ('--editor-instance "' .. inst .. '" ') or ""
  local function diff()
    local dok, dout = editor_cli(ws, inst_arg .. "code diff")
    return dok and parse_changelist(dout) or nil, dout
  end

  local cl, raw = diff()
  if not cl then
    print("编辑器未打开该地图，未校验编辑器内代码（磁盘已是最新，打开地图后自动同步）")
    print((raw or ""):match("^[^\r\n]*") or "")
    return
  end
  local dirty = (cl["only-local"] or 0) + (cl["differs"] or 0)
  if dirty > 0 then
    print("编辑器落后 " .. dirty .. " 个文件，code push …")
    local pok, pout = editor_cli(ws, inst_arg .. "code push")
    if not pok then fail("code push 失败:\n" .. tostring(pout)) end
    cl = diff()
    dirty = cl and ((cl["only-local"] or 0) + (cl["differs"] or 0)) or -1
    if dirty ~= 0 then fail("push 后复核仍有差异（" .. dirty .. "），请手动 code diff") end
  end
  print("编辑器: 已同步（unchanged=" .. (cl["unchanged"] or 0) .. "）")
  local ghosts = cl["only-on-map"] or 0
  if ghosts > 0 then
    print("注意: 地图侧多出 " .. ghosts .. " 个本地没有的文件（deploy 不删）；"
      .. "清理需在工作区跑 editor-cli code push --delete --yes")
  end
end

-- ── 前置检查 ──────────────────────────────────────────────────────────────

local function require_dir(path, msg)
  local ok, _, code = os.execute("test -d " .. q(path))
  if not ok or code ~= 0 then
    fail(msg .. "（缺 " .. path .. "）")
  end
end

function M.usage()
  return table.concat({
    "用法: lua5.4 tools/cli.lua deploy",
    "",
    "把仓库根 <端>/<child> byte 镜像进 SE 工作区 <端>/<child>（先重置目标子树）。",
    "端为白名单 " .. table.concat(M.REALMS, "/") .. "（官方强制的工作区根，仓库根直接对齐）；",
    "仓库根其他内容不部署，工作区其余内容不碰。",
    "镜像后自动经 Windows 侧 editor-cli 收尾：code validate → code diff → 有差异才 push；",
    "编辑器没开该地图则跳过收尾（磁盘已最新）。地图侧多出的文件只提示，不删。",
    "工作区默认 " .. workspace.DEFAULT .. "，环境变量 EGGY_WORKSPACE 可覆盖。",
    "",
    "选项：",
    "  --clean   只清不装：删掉工作区里本仓库拥有的全部子树，不拷贝。",
    "            工作区其余内容（eggy.json、server/_trigger、data/ 等）不碰。",
    "",
    "",
  }, "\n") .. "\n"
end

local function run_deploy(clean_only)
  local WORKSPACE = workspace.resolve()
  for _, realm in ipairs(M.REALMS) do
    require_dir(realm, "本仓库缺部署根 " .. realm)
  end
  require_dir(WORKSPACE, "SE 工作区不存在；可用环境变量 EGGY_WORKSPACE 覆盖")

  -- 本仓库拥有的子树清单：<端>/<child>，仓库路径与工作区路径相同。
  local targets = {}
  for _, realm in ipairs(M.REALMS) do
    for _, child in ipairs(entries(realm)) do
      targets[#targets + 1] = realm .. "/" .. child.name
    end
  end

  if clean_only then
    for _, rel in ipairs(targets) do
      rm_rf(WORKSPACE .. "/" .. rel)
      print("removed " .. rel)
    end
    print("deploy --clean ok → " .. WORKSPACE)
    return
  end

  require_dir("common/spoke", "本仓库缺 common/spoke（spoke 运行时）")
  local dir_pairs = {}
  for _, rel in ipairs(targets) do
    if is_dir(rel) then
      dir_pairs[#dir_pairs + 1] = { src = rel, dst = WORKSPACE .. "/" .. rel }
    end
  end
  local via_robocopy = robocopy_mirror_all(dir_pairs)
  local how = via_robocopy and "robocopy" or "cp"

  for _, rel in ipairs(targets) do
    local dst = WORKSPACE .. "/" .. rel
    if via_robocopy and is_dir(rel) then
      print(rel .. ": " .. file_count(dst) .. " 文件 (robocopy)")
    else
      rm_rf(dst)
      cp_entry(rel, dst)
      print(rel .. ": " .. file_count(dst) .. " 文件 (" .. (is_dir(rel) and how or "cp") .. ")")
    end
  end

  print("deploy ok → " .. WORKSPACE)
  verify_editor(WORKSPACE)
end

-- 退出码：0 成功 / 1 业务失败 / 2 用法错误。
function M.main(args)
  args = args or {}
  local clean_only = false
  for _, a in ipairs(args) do
    if a == "--help" or a == "-h" then
      io.write(M.usage())
      return 0
    elseif a == "--clean" then
      clean_only = true
    else
      io.stderr:write("deploy: 未知参数: " .. a .. "\n")
      return 2
    end
  end
  local ok, err = pcall(run_deploy, clean_only)
  if not ok then
    io.stderr:write(tostring(err) .. "\n")
    return 1
  end
  return 0
end

if ... == "tools.deploy" then
  return M
end

os.exit(M.main(arg))
