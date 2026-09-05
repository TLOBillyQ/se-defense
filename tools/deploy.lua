-- 部署脚本：把部署树 byte 镜像进 SE 工作区（票 #6）。
-- 运行：在仓库根执行 `lua5.4 tools/deploy.lua`（WSL；经 /mnt/c 直接操作 Windows 侧）。
-- 先例：monopoly tools/packages/ops/deploy.lua（镜像部署 + WSL→Windows 接缝）。
--
-- 部署树（CONTEXT.md「部署树」词条）：
--   vendor/spoke/                       → 工作区 vendor/spoke/     （spoke 运行时，已从 spoke-lua 内联）
--   src/adapter/                        → 工作区 src/adapter/     （适配层）
--   src/game/                           → 工作区 src/game/        （业务模块）
--   src/server/main.lua                     → 工作区 server/main.lua
--   src/client/main.lua                     → 工作区 client/main.lua
--
-- 镜像纪律：先重置目标子树再拷贝，不留幽灵文件（spoke-lua 接入指南）。
-- 只重置本脚本拥有的子树；工作区其余内容（eggy.json、_trigger、data 等）不碰。
-- 编辑器 syncEnabled=true：落盘即进编辑器内存，无需 code push（#5 实测）。

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

local function cp_dir(src, dst)
  run("mkdir -p " .. q(dst))
  run("cp -r " .. q(src .. "/.") .. " " .. q(dst))
end

local function cp_file(src, dst)
  run("cp " .. q(src) .. " " .. q(dst))
end

local function file_count(path)
  local handle = io.popen("find " .. q(path) .. " -type f | wc -l")
  local n = tonumber((handle:read("*a") or ""):match("%d+")) or 0
  handle:close()
  return n
end

-- ── 前置检查 ──────────────────────────────────────────────────────────────

local function require_dir(path, msg)
  local ok, _, code = os.execute("test -d " .. q(path))
  if not ok or code ~= 0 then
    fail(msg .. "（缺 " .. path .. "）")
  end
end

require_dir("vendor/spoke", "本仓库缺 vendor/spoke（spoke 运行时）")
require_dir("src/game", "本仓库缺 src/game（业务模块）")
require_dir("src/adapter", "本仓库缺 src/adapter")
require_dir(WORKSPACE, "SE 工作区不存在；可用环境变量 EGGY_WORKSPACE 覆盖")

-- ── 镜像：先重置目标子树，再拷贝 ──────────────────────────────────────────

-- 1) spoke 运行时
rm_rf(WORKSPACE .. "/vendor/spoke")
cp_dir("vendor/spoke", WORKSPACE .. "/vendor/spoke")
print("vendor/spoke: " .. file_count(WORKSPACE .. "/vendor/spoke") .. " 文件")

-- 2) 适配层
rm_rf(WORKSPACE .. "/src/adapter")
cp_dir("src/adapter", WORKSPACE .. "/src/adapter")
print("src/adapter: " .. file_count(WORKSPACE .. "/src/adapter") .. " 文件")

-- 3) 业务模块（README 一并镜像，无害）
rm_rf(WORKSPACE .. "/src/game")
cp_dir("src/game", WORKSPACE .. "/src/game")
-- 旧部署树残留：业务曾落在 examples/，清掉避免幽灵文件
rm_rf(WORKSPACE .. "/examples")
print("src/game: " .. file_count(WORKSPACE .. "/src/game") .. " 文件")

-- 4) 双端入口（单文件覆盖，server/ client/ 其余内容不碰）
cp_file("src/server/main.lua", WORKSPACE .. "/server/main.lua")
cp_file("src/client/main.lua", WORKSPACE .. "/client/main.lua")
print("入口: server/main.lua client/main.lua")

print("deploy ok → " .. WORKSPACE)
print("下一步: $CLI code validate && $CLI code diff（经 cmd.exe 从工作区 cwd 执行）")
