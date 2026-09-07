-- Pure mirror plan for tools/deploy.lua (票 src/目录层级调整).
--
-- 部署目录采用白名单：官方 SE 工作区根固定为 client/ common/ server/
-- （见工作区规则「工作区主要目录结构」），本项目跟随，仓库根直接就是这三个
-- 目录，REALMS 即该白名单。部署把 <端>/<child> 镜像到工作区 <端>/<child>；
-- 仓库根的其他内容（docs/、tools/、tests/、data/ 等）不在白名单，不部署。
-- 重置粒度是本仓库拥有的「端的一级子树」，因此工作区里 server/_trigger、
-- data/（编辑器导出，只回同步不部署）、eggy.json 等不归本仓库的内容原样保留。
-- spoke 运行时住在 common/spoke/，走同一条规则，没有特例。
-- 工作区根的无意义杂物（JUNK：编辑器脚手架残留、探针遗留）随部署清除；
-- .vscode/ 与 log.txt 保留（用户决定）。
--
-- 纯函数：目录枚举经 entries(dir) 注入，返回 { {name=, dir=}, ... }，
-- 缺目录返回空表，便于单测；执行在 tools/deploy.lua。

local M = {}

-- 官方强制的工作区根目录；顺序即部署顺序。
M.REALMS = { "client", "common", "server" }

-- 工作区根下每次部署都删掉的杂物；只列这里有的，其他一律不碰。
M.JUNK = { ".gm", "server.TableMgr", "unit_scripts" }

-- op 两种形态（build 产 mirror + JUNK 的 remove，clean 只产 remove）：
--   { kind = "mirror", src = <仓库相对路径>, dst = <工作区相对路径> }
--   { kind = "remove", dst = <工作区相对路径> }
function M.build(entries)
  local ops = {}
  for _, realm in ipairs(M.REALMS) do
    for _, child in ipairs(entries(realm)) do
      ops[#ops + 1] = {
        kind = "mirror",
        src = realm .. "/" .. child.name,
        dst = realm .. "/" .. child.name,
      }
    end
  end
  for _, name in ipairs(M.JUNK) do
    ops[#ops + 1] = { kind = "remove", dst = name }
  end
  return ops
end

-- 清理计划（deploy --clean）：把本仓库拥有的全部子树与 JUNK 从工作区删掉，不拷贝。范围与 build 的目标集合完全一致，工作区其余内容同样不碰。
function M.clean(entries)
  local ops = {}
  for _, op in ipairs(M.build(entries)) do
    ops[#ops + 1] = { kind = "remove", dst = op.dst }
  end
  return ops
end

return M
