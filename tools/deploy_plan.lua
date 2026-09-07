-- Pure mirror plan for tools/deploy.lua (票 src/目录层级调整).
--
-- src/ 的一级目录即 SE 工作区根（client/common/data/server）；部署把
-- src/<端>/<child> 镜像到工作区 <端>/<child>。重置粒度是本仓库拥有的
-- 「端的一级子树」，因此工作区里 server/_trigger、data/、eggy.json 等
-- 不归本仓库的内容原样保留。spoke 运行时住在 src/common/spoke/，走同一条
-- 规则，没有特例。旧布局残留（工作区根的 src/、examples/、vendor/spoke/）随部署清除。
--
-- 纯函数：目录枚举经 entries(dir) 注入，返回 { {name=, dir=}, ... }，
-- 便于单测；执行在 tools/deploy.lua。

local M = {}

-- op 两种形态：
--   { kind = "mirror", src = <仓库相对路径>, dst = <工作区相对路径> }
--   { kind = "remove", dst = <工作区相对路径> }
function M.build(entries)
  local ops = {}
  for _, realm in ipairs(entries("src")) do
    if realm.dir then
      for _, child in ipairs(entries("src/" .. realm.name)) do
        ops[#ops + 1] = {
          kind = "mirror",
          src = "src/" .. realm.name .. "/" .. child.name,
          dst = realm.name .. "/" .. child.name,
        }
      end
    end
  end
  -- 旧部署树残留：src/ 曾整树落在工作区根，业务更早前落在 examples/
  ops[#ops + 1] = { kind = "remove", dst = "src" }
  ops[#ops + 1] = { kind = "remove", dst = "examples" }
  ops[#ops + 1] = { kind = "remove", dst = "vendor/spoke" }
  return ops
end

return M
