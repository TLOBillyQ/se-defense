-- 架构分层门禁的不变式性质测试。
--
-- 目标：把 tools.acceptance.repo_checks 的 arch 谓词按“宽输入范围”扫一遍。
-- 只要抓住 _is_layer_upward 的比较方向写反、同层误判、substrate 方向性
-- 出错，就会在随机层组合下败露。纯 Lua，无宿主依赖，无需扫描仓库。
--
-- 规则真源：arch_view.config.json 的分层语义（数字越大越底层，依赖只从
-- 小数字流向大数字；spoke 是基座 substrate，任意层可依赖它）。
local property = require("tests.spoke.property.support.property")
local repo = require("tools.acceptance.repo_checks")

local gen = property.gen

-- 分层门禁是“不同层恰好一个方向被禁”的全序：层数不相等的任意两模块，
-- 较低层（数字大）依赖较高层（数字小）的方向被禁，反向允许；层数相等时
-- 两个方向都不被层规则禁止。该断言覆盖 1..8 的层组合（含相等）。
property.forall("arch_layer_constraint_is_total_and_antisymmetric",
  { gen.integer(1, 8), gen.integer(1, 8) }, function(a_layer, b_layer)
  local modules = {
    a = { component_layer = a_layer },
    b = { component_layer = b_layer },
  }
  local config = { forbidden_dependency_rules = {} }
  local a_to_b = repo.arch_edge_forbidden(config, modules, "a", "b")
  local b_to_a = repo.arch_edge_forbidden(config, modules, "b", "a")

  if a_layer == b_layer then
    if a_to_b or b_to_a then
      return "equal layers must allow both directions"
    end
  else
    local forbidden = 0
    if a_to_b then forbidden = forbidden + 1 end
    if b_to_a then forbidden = forbidden + 1 end
    if forbidden ~= 1 then
      return "distinct layers must forbid exactly one direction "
        .. "(a_layer=" .. a_layer .. ", b_layer=" .. b_layer
        .. ", a_to_b=" .. tostring(a_to_b) .. ", b_to_a=" .. tostring(b_to_a) .. ")"
    end
    -- 被禁方向必须是数字更大（更底层）的那一方指向另一方。
    if a_layer > b_layer then
      if not a_to_b then
        return "bottom layer a (>b) must be forbidden to depend on higher b"
      end
    elseif not b_to_a then
      return "bottom layer b (>a) must be forbidden to depend on higher a"
    end
  end
  return true
end)

-- substrate 方向性：分层模块 → 基座合法；基座 → 任意分层模块被禁；
-- 基座 → 基座合法。覆盖任意整数层与 substrate 组合。
property.forall("arch_substrate_direction_is_qualitative",
  { gen.integer(1, 8) }, function(layer)
  local config = { forbidden_dependency_rules = {} }
  local modules = {
    layer_mod = { component_layer = layer },
    sub = { component_substrate = true },
  }
  if repo.arch_edge_forbidden(config, modules, "layer_mod", "sub") then
    return "layered -> substrate must be allowed"
  end
  if not repo.arch_edge_forbidden(config, modules, "sub", "layer_mod") then
    return "substrate -> layered must be forbidden"
  end
  local subs = {
    s1 = { component_substrate = true },
    s2 = { component_substrate = true },
  }
  if repo.arch_edge_forbidden(config, subs, "s1", "s2") then
    return "substrate -> substrate must be allowed"
  end
  return true
end)
