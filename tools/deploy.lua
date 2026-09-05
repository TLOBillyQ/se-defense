-- 部署脚本：把部署树 byte 镜像进 SE 工作区（票 #6）。
-- 运行：在仓库根执行 `lua5.4 tools/deploy.lua`（WSL；经 /mnt/c 直接操作 Windows 侧）。
-- 先例：monopoly tools/packages/ops/deploy.lua（镜像部署 + WSL→Windows 接缝）。
--
-- 部署树（CONTEXT.md「部署树」词条）：
--   src/common/spoke/                       → 工作区 src/common/spoke/     （spoke 运行时，已从 spoke-lua 内联）
--   src/adapter/（不含 swap/）              → 工作区 src/adapter/          （适配层）
--   vendor/spoke-lua/examples/base_defence/ → 工作区 examples/base_defence/
--     其中 4 个 mock 文件由 src/adapter/swap/ 同路径替换（业务零改动机制）
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

require_dir("src/common/spoke", "本仓库缺 src/common/spoke（spoke 运行时）")
require_dir("vendor/spoke-lua/examples/base_defence", "base_defence 业务模块尚未迁入本仓库（spoke-lua 子模块已移除，只内联了运行时与测试）")
require_dir("src/adapter", "本仓库缺 src/adapter")
require_dir(WORKSPACE, "SE 工作区不存在；可用环境变量 EGGY_WORKSPACE 覆盖")

-- ── 镜像：先重置目标子树，再拷贝 ──────────────────────────────────────────

-- 1) spoke 运行时
rm_rf(WORKSPACE .. "/src/common/spoke")
cp_dir("src/common/spoke", WORKSPACE .. "/src/common/spoke")
print("src/common/spoke: " .. file_count(WORKSPACE .. "/src/common/spoke") .. " 文件")

-- 2) 适配层（swap/ 是部署源材料，不进部署树）
rm_rf(WORKSPACE .. "/src/adapter")
run("mkdir -p " .. q(WORKSPACE .. "/src/adapter"))
run("find src/adapter -maxdepth 1 -name '*.lua' -exec cp {} " .. q(WORKSPACE .. "/src/adapter") .. " \\;")
print("src/adapter: " .. file_count(WORKSPACE .. "/src/adapter") .. " 文件")

-- 3) 业务模块 + 四个 mock 同路径替换
rm_rf(WORKSPACE .. "/examples/base_defence")
cp_dir("vendor/spoke-lua/examples/base_defence", WORKSPACE .. "/examples/base_defence")
cp_file("src/adapter/swap/host_mock.lua", WORKSPACE .. "/examples/base_defence/host_mock.lua")
cp_file("src/adapter/swap/eui_mock.lua", WORKSPACE .. "/examples/base_defence/eui_mock.lua")
cp_file("src/adapter/swap/input_mock.lua", WORKSPACE .. "/examples/base_defence/input_mock.lua")
cp_file("src/adapter/swap/host_mock_base.lua", WORKSPACE .. "/examples/host_mock.lua")
print("examples/base_defence: " .. file_count(WORKSPACE .. "/examples/base_defence") .. " 文件（4 mock 已替换）")

-- 4) 双端入口（单文件覆盖，server/ client/ 其余内容不碰）
cp_file("src/server/main.lua", WORKSPACE .. "/server/main.lua")
cp_file("src/client/main.lua", WORKSPACE .. "/client/main.lua")
print("入口: server/main.lua client/main.lua")

print("deploy ok → " .. WORKSPACE)
print("下一步: $CLI code validate && $CLI code diff（经 cmd.exe 从工作区 cwd 执行）")
