-- sync：与 deploy 反方向，把 SE 工作区里由编辑器维护的内容回同步进仓库。
-- 先例：monopoly tools/packages/data_sync/sync_data.lua。
--
--   <工作区>/eggy.json    → eggy.json    工作区绑定信息（projectID / isSEMap 等）；
--                                          落在仓库根后 Claude Code 的 SessionStart 钩子
--                                          据 isSEMap 注入 SE 规则与技能。
--   <工作区>/EggyAPI.lua  → EggyAPI.lua  宿主 API 存根（第三方边界；工作区 excludePatterns
--                                          已排除它，部署不会带回去）。
--   <工作区>/data/**      → data/**      编辑器导出（Prefab / UINodes / FontData 等），整目录镜像：
--                                          仓库 data/ 里源侧已不存在的文件一并删除。
--                                          放仓库根、不在部署白名单 client/common/server 内，deploy 不会把它推回工作区。
--
-- 内容原样搬运，只把 CRLF 统一成 LF（仓库 .gitattributes 全局 eol=lf；编辑器在
-- Windows 侧写出的文件是 CRLF，不转的话工作树与索引永远不一致）。
-- 全部源读成功才落盘；任一必需源缺失即失败，不写任何文件。
local workspace = require("tools.eggy_workspace")

local M = {}

-- 单文件清单：{ src = 工作区相对路径, dst = 仓库相对路径 }。
M.FILES = {
  { src = "eggy.json", dst = "eggy.json" },
  { src = "EggyAPI.lua", dst = "EggyAPI.lua" },
}
-- 目录清单：整目录镜像。
M.DIRS = {
  { src = "data", dst = "data" },
}

function M.normalize_lf(text)
  return (text:gsub("\r\n", "\n"))
end

local function q(path)
  return "'" .. path:gsub("'", "'\\''") .. "'"
end

local function read_file(path)
  local f, err = io.open(path, "rb")
  if not f then return nil, err end
  local data = f:read("a")
  f:close()
  return data
end

local function write_file(path, data)
  local parent = path:match("^(.*)/[^/]+$")
  if parent then os.execute("mkdir -p " .. q(parent)) end
  local f, err = io.open(path, "wb")
  if not f then return nil, err end
  f:write(data)
  f:close()
  return true
end

-- 目录下全部文件的相对路径（排序保证报告稳定）；目录不存在返回 nil。
local function list_files(dir)
  if not workspace.is_dir(dir) then return nil end
  local out = {}
  local h = io.popen("find " .. q(dir) .. " -type f 2>/dev/null")
  for line in h:lines() do
    out[#out + 1] = line:sub(#dir + 2)
  end
  h:close()
  table.sort(out)
  return out
end

-- 纯搬运：ws_dir → repo_dir。成功返回 { {dst=, bytes=, changed=|removed=true}, ... }；
-- 失败返回 nil, err。
function M.sync(ws_dir, repo_dir)
  local staged = {}
  for _, item in ipairs(M.FILES) do
    local raw, err = read_file(ws_dir .. "/" .. item.src)
    if not raw then
      return nil, "工作区缺少 " .. item.src .. "（" .. tostring(err) .. "）"
    end
    staged[#staged + 1] = { dst = item.dst, data = M.normalize_lf(raw) }
  end
  local removals = {}
  for _, d in ipairs(M.DIRS) do
    local rels = list_files(ws_dir .. "/" .. d.src)
    if not rels then
      return nil, "工作区缺少目录 " .. d.src
    end
    local keep = {}
    for _, rel in ipairs(rels) do
      local raw, err = read_file(ws_dir .. "/" .. d.src .. "/" .. rel)
      if not raw then
        return nil, "读取失败 " .. d.src .. "/" .. rel .. "（" .. tostring(err) .. "）"
      end
      staged[#staged + 1] = { dst = d.dst .. "/" .. rel, data = M.normalize_lf(raw) }
      keep[rel] = true
    end
    for _, rel in ipairs(list_files(repo_dir .. "/" .. d.dst) or {}) do
      if not keep[rel] then removals[#removals + 1] = d.dst .. "/" .. rel end
    end
  end

  local report = {}
  for _, s in ipairs(staged) do
    local dst = repo_dir .. "/" .. s.dst
    local old = read_file(dst)
    local ok, err = write_file(dst, s.data)
    if not ok then
      return nil, "写入失败 " .. dst .. "（" .. tostring(err) .. "）"
    end
    report[#report + 1] = { dst = s.dst, bytes = #s.data, changed = old ~= s.data }
  end
  for _, rel in ipairs(removals) do
    os.remove(repo_dir .. "/" .. rel)
    report[#report + 1] = { dst = rel, bytes = 0, removed = true }
  end
  return report
end

function M.usage()
  local lines = {
    "用法: lua5.4 tools/cli.lua sync",
    "",
    "从 SE 工作区把编辑器维护的内容回同步进仓库（CRLF 统一为 LF）：",
  }
  for _, item in ipairs(M.FILES) do
    lines[#lines + 1] = string.format("  %-14s → %s", item.src, item.dst)
  end
  for _, d in ipairs(M.DIRS) do
    lines[#lines + 1] = string.format("  %-14s → %s/（整目录镜像，多余文件删除）", d.src .. "/", d.dst)
  end
  lines[#lines + 1] = "零参数；工作区默认 " .. workspace.DEFAULT .. "，环境变量 EGGY_WORKSPACE 可覆盖。"
  lines[#lines + 1] = ""
  return table.concat(lines, "\n") .. "\n"
end

-- 退出码：0 成功 / 1 业务失败 / 2 用法错误。
function M.main(args)
  args = args or {}
  for _, a in ipairs(args) do
    if a == "--help" or a == "-h" then
      io.write(M.usage())
      return 0
    end
  end
  if #args > 0 then
    io.stderr:write("sync: 不接受参数: " .. table.concat(args, " ") .. "\n")
    return 2
  end

  local ws = workspace.resolve()
  if not workspace.is_dir(ws) then
    io.stderr:write("sync: SE 工作区不存在；可用环境变量 EGGY_WORKSPACE 覆盖（" .. ws .. "）\n")
    return 1
  end

  print("sync ← " .. ws)
  local report, err = M.sync(ws, ".")
  if not report then
    io.stderr:write("sync: " .. err .. "\n")
    return 1
  end
  for _, r in ipairs(report) do
    local flag = r.removed and "已删除" or (r.changed and "有更新" or "无变化")
    print(string.format("  %-24s %8d bytes  %s", r.dst, r.bytes, flag))
  end
  return 0
end

if ... == "tools.sync" then
  return M
end

os.exit(M.main(arg))
