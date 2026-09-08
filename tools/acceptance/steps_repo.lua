-- tools/acceptance/steps_repo.lua — step handlers that inspect the repository
-- itself (features/source-layout.feature, features/deploy-mirror.feature,
-- features/engineering/spoke-primitives.feature,
-- features/engineering/dependencies.feature).
--
-- These steps run from the repository root and never boot a game; they are
-- kept apart from the game-session steps in steps.lua so each file has one
-- job. steps.lua appends `patterns` to its own dispatch table; the entry
-- shape is identical: { lua-pattern, handler(w, captures...) }.
local M = {}
local repo = require("tools.acceptance.repo_checks")
local archc = require("tools.acceptance.arch_checks")
local probe = require("tools.acceptance.arch_probe")

local function read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local body = f:read("*a")
  f:close()
  return body
end

-- Every server/game/*.lua as {name, body} specs (the allowlist check input).
local function server_game_files()
  local specs = {}
  local pipe = io.popen("find server/game -maxdepth 1 -name '*.lua'")
  for f in pipe:lines() do
    local base = f:match("^server/game/(.+)%.lua$")
    local body = base and read_file(f)
    if body then specs[#specs + 1] = { name = base, body = body } end
  end
  pipe:close()
  return specs
end

local function dir_exists(path)
  local ok, _, code = os.execute("test -d '" .. path .. "'")
  return ok ~= nil and code == 0
end

local function q(path)
  return "'" .. path .. "'"
end

-- Lua 5.4 binary that runs this spec (for subprocess steps such as deploy).
local function lua_bin()
  if arg and type(arg[-1]) == "string" and arg[-1]:match("lua") then
    return q(arg[-1])
  end
  return "lua5.4"
end

local function workspace(w)
  if not w.workspace then return nil, "尚未创建临时工作区" end
  return w.workspace
end

-- Lazy arch_view model + config for the dependency-constraints feature.
-- Loaded once per feature process (dependencies.feature never mutates the
-- source tree between scenarios). `arch_view.analyze` scans source_roots and
-- produces the module/graph/check model; the raw config supplies the
-- component/layer declarations that `archc` predicates read. The "would the
-- gate reject this direction" question is not answered from either of these —
-- see arch_probe.lua. package.path is extended by tools.arch_bootstrap.ensure().
local _arch = nil
local function arch_dep()
  if _arch then return _arch end
  require("tools.arch_bootstrap").ensure()
  local arch = require("arch_view")
  local opts = { project_root = ".", config_path = "arch_view.config.json" }
  _arch = {
    model = arch.analyze(opts),
    config = arch.load_config("arch_view.config.json"),
  }
  return _arch
end

M.patterns = {
  -- ── 源码树布局（source-layout.feature，不启动对局）──
  { "^仓库根目录(%S+)是否存在为(%S+)$", function(w, dir, expect)
      if expect ~= "是" and expect ~= "否" then
        return nil, "存在性期望只能是 是/否，实际 " .. expect
      end
      local exists = dir_exists(dir)
      if exists == (expect == "是") then return true end
      return nil, string.format("%s 存在性期望 %s，实际 %s",
        dir, expect, exists and "是" or "否") end },
  { "^部署白名单为(.+)$", function(w, list)
      local want = {}
      for name in list:gmatch("%S+") do want[#want + 1] = name end
      local deploy = require("tools.deploy")
      if table.concat(deploy.REALMS, " ") == table.concat(want, " ") then return true end
      return nil, "部署白名单实际为 " .. table.concat(deploy.REALMS, " ") end },
  { "^源码树中存在文件(%S+)$", function(w, path)
      if read_file(path) then return true end
      return nil, path .. " 不存在" end },
  { "^源码文件(%S+)引用模块(%S+)$", function(w, file, mod)
      local body = read_file(file)
      if not body then return nil, file .. " 不存在" end
      if body:find('"' .. mod .. '"', 1, true) or body:find("'" .. mod .. "'", 1, true) then
        return true
      end
      return nil, string.format("%s 未引用模块 %s", file, mod) end },
  { "^部署树下没有文件引用以src%.开头的模块$", function(w)
      local bad = {}
      local pipe = io.popen("find client common server -name '*.lua'")
      for f in pipe:lines() do
        local body = read_file(f) or ""
        if body:find("require[%s%(]*[\"']src%.")
          or body:find("package%.loaded%s*%[%s*[\"']src%.") then
          bad[#bad + 1] = f
        end
      end
      pipe:close()
      if #bad == 0 then return true end
      return nil, "仍引用 src. 前缀模块: " .. table.concat(bad, ",") end },
  -- ── spoke 原语约束（spoke-primitives.feature，不启动对局）──
  { "^源码文件(%S+)引用common%.spoke下的模块$", function(w, file)
      local body = read_file(file)
      if not body then return nil, file .. " 不存在" end
      if repo.references_common_spoke(body) then return true end
      return nil, file .. " 未引用 common.spoke 下的模块" end },
  { "^源码文件(%S+)使用spoke原语(%S+)$", function(w, file, prim)
      local body = read_file(file)
      if not body then return nil, file .. " 不存在" end
      if repo.uses_spoke_primitive(body, prim) then return true end
      return nil, string.format("%s 未使用 spoke 原语 %s", file, prim) end },
  { "^server/game下不引用common%.spoke的模块都属于(.+)$", function(w, list)
      local want = {}
      for name in list:gmatch("%S+") do want[#want + 1] = name end
      table.sort(want)
      local actual = repo.non_spoke_modules(server_game_files())
      if table.concat(actual, " ") == table.concat(want, " ") then return true end
      return nil, "server/game 不引用 common.spoke 的模块实际为 " .. table.concat(actual, " ") end },
  { "^源码文件(%S+)只引用前缀为server%.的模块$", function(w, file)
      local body = read_file(file)
      if not body then return nil, file .. " 不存在" end
      local bad = repo.non_server_requires(body)
      if #bad == 0 then return true end
      return nil, file .. " 引用非 server. 前缀模块: " .. table.concat(bad, ",") end },
  -- ── 依赖关系约束（dependencies.feature，不启动对局）──
  { "^架构门禁检查通过$", function(w)
      local check = arch_dep().model.check
      if check.ok then return true end
      return nil, "架构门禁未通过（" .. #check.violations .. " 处违规）" end },
  { "^模块(.+)依赖模块(.+)$", function(w, a, b)
      if archc.arch_edge_exists(arch_dep().model.graph, a, b) then return true end
      return nil, string.format("%s 不依赖 %s", a, b) end },
  -- 「禁止」是三重断言：两端都是真实存在的模块、真实源码树上没有这条边、
  -- 且把这条边喂给真门禁时它拒绝。后半句由 arch_probe 交给 arch_view 自己
  -- 判定，不在本仓复刻门禁规则。
  -- 存在性那一条不是多余的：跨层的禁止由组件层级判定，同组件里换个模块名
  -- 结论不变，所以拼错的模块名本来能蒙混过关（变异测试实证）。
  { "^架构门禁禁止模块(.+)依赖模块(.+)$", function(w, a, b)
      local model = arch_dep().model
      for _, id in ipairs({ a, b }) do
        if model.modules[id] == nil then
          return nil, "源码树中不存在模块 " .. id
        end
      end
      if archc.arch_edge_exists(model.graph, a, b) then
        return nil, string.format("源码树上已存在 %s 依赖 %s", a, b)
      end
      local rejected, info = probe.rejects_edge(a, b)
      if rejected == nil then return nil, "架构探针失败: " .. tostring(info) end
      if rejected then return true end
      return nil, string.format("门禁未禁止 %s 依赖 %s", a, b) end },
  { "^组件(.+)的层级为(.+)$", function(w, comp, layer)
      local actual = archc.arch_component_layer(arch_dep().config, comp)
      if tostring(actual) == layer then return true end
      return nil, string.format("%s 层级实际为 %s", comp, tostring(actual)) end },
  { "^未豁免的依赖环数量为(%d+)$", function(w, n)
      local actual = archc.arch_unwaived_cycle_count(arch_dep().model.check)
      if actual == tonumber(n) then return true end
      return nil, string.format("未豁免依赖环实际为 %d", actual) end },
  -- ── 部署镜像（deploy-mirror.feature，临时工作区在 ./tmp 下）──
  { "^一个空的临时工作区$", function(w)
      w.workspace = "tmp/deploy-mirror-workspace"
      os.execute("rm -rf " .. q(w.workspace))
      os.execute("mkdir -p " .. q(w.workspace))
      return true end },
  { "^临时工作区预置文件(%S+)$", function(w, path)
      local ws, err = workspace(w)
      if not ws then return nil, err end
      local full = ws .. "/" .. path
      local parent = full:match("^(.*)/[^/]+$")
      if parent then os.execute("mkdir -p " .. q(parent)) end
      local f = io.open(full, "w")
      if not f then return nil, "无法写入 " .. full end
      f:write("-- preset\n")
      f:close()
      return true end },
  { "^执行部署到临时工作区$", function(w)
      local ws, err = workspace(w)
      if not ws then return nil, err end
      local cmd = "EGGY_WORKSPACE=" .. q(ws)
        .. " " .. lua_bin() .. " tools/deploy.lua > /dev/null"
      local ok, _, code = os.execute(cmd)
      if ok and code == 0 then return true end
      return nil, "deploy 失败 exit=" .. tostring(code) end },
  { "^临时工作区存在文件(%S+)$", function(w, path)
      local ws, err = workspace(w)
      if not ws then return nil, err end
      if read_file(ws .. "/" .. path) then return true end
      return nil, "临时工作区缺文件 " .. path end },
  { "^临时工作区不存在目录(%S+)$", function(w, path)
      local ws, err = workspace(w)
      if not ws then return nil, err end
      if not dir_exists(ws .. "/" .. path) then return true end
      return nil, "临时工作区仍存在目录 " .. path end },
}

return M
