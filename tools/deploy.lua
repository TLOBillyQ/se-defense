-- 部署脚本：把部署树 byte 镜像进 SE 工作区（票 #6；src/目录层级调整）。
-- 运行：在仓库根执行 `lua5.4 tools/deploy.lua`（WSL；经 /mnt/c 直接操作 Windows 侧）。
-- 先例：monopoly tools/packages/ops/deploy.lua（镜像部署 + WSL→Windows 接缝）。
--
-- 部署树（CONTEXT.md「部署树」词条；计划本身在 tools/deploy_plan.lua）：
--   vendor/spoke/          → 工作区 vendor/spoke/   （spoke 运行时，整子树重置）
--   src/<端>/<child>/...   → 工作区 <端>/<child>/...（端 = client/common/data/server）
--
-- 镜像纪律：先重置目标子树再拷贝，不留幽灵文件（spoke-lua 接入指南）。
-- 重置粒度是本仓库拥有的「端的一级子树」（如 server/game、server/main.lua）；
-- 工作区其余内容（eggy.json、server/_trigger、data 等）不碰。
-- 旧布局残留（工作区根的 src/、examples/）随部署清除。
-- 编辑器 syncEnabled=true：落盘即进编辑器内存，无需 code push（#5 实测）。

package.path = "./?.lua;./?/init.lua;" .. package.path

local plan = require("tools.deploy_plan")

local WORKSPACE = os.getenv("EGGY_WORKSPACE")
  or "/mnt/c/Users/Lzx_8/Desktop/dev/eggy/LuaSource_BaseDefence"

local function fail(msg)
  io.stderr:write("deploy: " .. msg .. "\n")
  os.exit(1)
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

-- ── 前置检查 ──────────────────────────────────────────────────────────────

local function require_dir(path, msg)
  local ok, _, code = os.execute("test -d " .. q(path))
  if not ok or code ~= 0 then
    fail(msg .. "（缺 " .. path .. "）")
  end
end

require_dir("vendor/spoke", "本仓库缺 vendor/spoke（spoke 运行时）")
require_dir("src", "本仓库缺 src（源码树）")
require_dir(WORKSPACE, "SE 工作区不存在；可用环境变量 EGGY_WORKSPACE 覆盖")

-- ── 执行镜像计划 ──────────────────────────────────────────────────────────

for _, op in ipairs(plan.build(entries)) do
  rm_rf(WORKSPACE .. "/" .. op.dst)
  if op.kind == "mirror" then
    cp_entry(op.src, WORKSPACE .. "/" .. op.dst)
    print(op.dst .. ": " .. file_count(WORKSPACE .. "/" .. op.dst) .. " 文件")
  end
end

print("deploy ok → " .. WORKSPACE)
print("下一步: $CLI code validate && $CLI code diff（经 cmd.exe 从工作区 cwd 执行）")
