-- 部署脚本：把部署树 byte 镜像进 SE 工作区（票 #6；src/目录层级调整）。
-- 运行：在仓库根执行 `lua5.4 tools/cli.lua deploy`（WSL；经 /mnt/c 直接操作 Windows 侧）；
-- 直接 `lua5.4 tools/deploy.lua` 亦可。反方向回同步见 tools/sync.lua。
-- 先例：monopoly tools/packages/ops/deploy.lua（镜像部署 + WSL→Windows 接缝）。
--
-- 本模块只管搬字节。部署规则（哪些子树归本仓库、目的地是否跨接缝）在 tools/deploy_plan
-- 回答，Windows 侧怎么跑在 tools/wsl_seam，编辑器收尾在 tools/editor_finalize。
--
-- 部署树（CONTEXT.md「部署树」词条）：
--   <端>/<child>/...   → 工作区 <端>/<child>/...（端 = 白名单 client/common/server，
--                        即官方强制的工作区根，仓库根直接对齐，见 deploy_plan.REALMS；
--                        spoke 运行时即 common/spoke/，与业务同规则镜像）
-- 仓库根白名单之外的内容（docs/、tools/、tests/、data/ 等）不部署。
--
-- 镜像纪律：目标子树与源完全一致，不留幽灵文件（spoke-lua 接入指南）。
-- 传输按目的地选：工作区在 Windows 侧（C:\…）时目录交给 robocopy /MIR 增量——WSL 经 9P
-- 逐文件 rm/cp 每个文件都是一次跨系统调用，树一大就是几十秒；robocopy 只传变化文件。
-- 目的地在 Linux 侧（临时工作区、非 WSL 机器）则一律本地 rm + cp：那种情况下 robocopy
-- 反而要 Windows 走 9P 回读 Linux 侧，凭空造出一次本来不存在的跨系统往返。
-- robocopy 不可用或退出码 >= 8 时同样回落 rm + cp。
-- 重置粒度是本仓库拥有的「端的一级子树」（如 server/game、server/main.lua）；
-- 其余内容（eggy.json、server/_trigger、data、.vscode、log.txt、unit_scripts 等）不碰。

package.path = "./?.lua;./?/init.lua;" .. package.path

local workspace = require("tools.eggy_workspace")
local plan = require("tools.deploy_plan")
local seam = require("tools.wsl_seam")
local finalize = require("tools.editor_finalize")

local M = {}

-- 部署白名单的真源在 deploy_plan；这里转出去只为 usage 文案与既有调用方。
M.REALMS = plan.REALMS

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

local function is_dir(path)
  local ok, _, code = os.execute("test -d " .. q(path))
  return ok == true and code == 0
end

-- 本地拷贝一棵子树/一个文件；is_dir 由计划给出，不再问一次文件系统。
local function copy_local(target)
  run("rm -rf " .. q(target.dst))
  if target.dir then
    run("mkdir -p " .. q(target.dst))
    run("cp -r " .. q(target.src .. "/.") .. " " .. q(target.dst))
  else
    run("mkdir -p " .. q(target.dst:match("^(.*)/[^/]+$") or "."))
    run("cp " .. q(target.src) .. " " .. q(target.dst))
  end
end

-- 文件数只为打印一行进度。数源不数目的地：镜像纪律保证两侧相等，而目的地在 Windows
-- 侧时每数一棵子树就是又一次跨系统 find。
local function file_count(target)
  if not target.dir then return 1 end
  local handle = io.popen("find " .. q(target.src) .. " -type f | wc -l")
  local n = tonumber((handle:read("*a") or ""):match("%d+")) or 0
  handle:close()
  return n
end

-- 枚举目录一级条目：{ {name=, dir=}, ... }，按名排序保证计划稳定。
local function entries(dir)
  local out = {}
  local handle = io.popen("find " .. q(dir) .. " -mindepth 1 -maxdepth 1 2>/dev/null")
  for line in handle:lines() do
    out[#out + 1] = { name = line:sub(#dir + 2), dir = is_dir(line) }
  end
  handle:close()
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

-- ── 前置检查 ──────────────────────────────────────────────────────────────

local function require_dir(path, msg)
  if not is_dir(path) then
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
    "工作区在 Windows 侧时目录走 robocopy 增量，并自动经 editor-cli 收尾：",
    "code validate → code diff → 有差异才 push；编辑器没开该地图则跳过收尾（磁盘已最新）。",
    "地图侧多出的文件只提示，不删。工作区在 Linux 侧（如临时工作区）走本地 cp，不做收尾。",
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

  local targets = plan.targets(WORKSPACE, entries)

  if clean_only then
    for _, t in ipairs(targets) do
      run("rm -rf " .. q(t.dst))
      print("removed " .. t.rel)
    end
    print("deploy --clean ok → " .. WORKSPACE)
    return
  end

  require_dir("common/spoke", "本仓库缺 common/spoke（spoke 运行时）")

  -- 目的地跨接缝才值得起 cmd.exe；否则连 wslpath 之外的一次 Windows 往返都不做。
  local crosses = plan.crosses_seam(seam.win_path(WORKSPACE))
  local dir_pairs = {}
  if crosses then
    for _, t in ipairs(targets) do
      if t.dir then dir_pairs[#dir_pairs + 1] = { src = t.src, dst = t.dst } end
    end
  end
  local via_robocopy = crosses and seam.robocopy_mirror(dir_pairs)

  for _, t in ipairs(targets) do
    local how = "cp"
    if via_robocopy and t.dir then
      how = "robocopy"
    else
      copy_local(t)
    end
    print(t.rel .. ": " .. file_count(t) .. " 文件 (" .. how .. ")")
  end

  print("deploy ok → " .. WORKSPACE)

  if not crosses then
    print("工作区在 Linux 侧，跳过编辑器收尾（editor-cli 需要 Windows 侧工作区）")
    return
  end
  local ok, err = finalize.run(WORKSPACE)
  if not ok then fail(err) end
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
