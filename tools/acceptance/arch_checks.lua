-- tools/acceptance/arch_checks.lua — pure predicates over the arch_view
-- architecture model, backing features/engineering/dependencies.feature.
--
-- Split from repo_checks.lua because the two answer different questions from
-- different truth sources: repo_checks reads Lua source text, this reads the
-- scanned arch_view model and its config. Everything here is pure over the
-- tables it is handed, so unit tests can feed synthetic models.
--
-- Deliberately absent: any judgement of whether the gate would reject an edge.
-- That decision procedure is arch_view's; asking it is arch_probe.lua's job.
local M = {}

-- True if the graph's edge list contains a direct from -> to edge.
-- `graph` is arch_view's `{ nodes = [...], edges = [{from,to}, ...] }`.
function M.arch_edge_exists(graph, from_id, to_id)
  for _, edge in ipairs((graph or {}).edges or {}) do
    if edge.from == from_id and edge.to == to_id then
      return true
    end
  end
  return false
end

-- The declared gate layer for a component name, as configured. Returns the
-- integer layer, the string "基座" for a substrate component, or nil when the
-- component is not declared.
function M.arch_component_layer(config, component)
  for _, rule in ipairs((config or {}).component_rules or {}) do
    if rule.component == component then
      if rule.substrate == true then return "基座" end
      return rule.layer
    end
  end
  return nil
end

-- Count of reported projection cycles that are NOT waived by config
-- allowed_cycles: the ones the gate treats as violations.
function M.arch_unwaived_cycle_count(check)
  local count = 0
  for _, entry in ipairs((check or {}).projection_cycles or {}) do
    if entry.waived ~= true then count = count + 1 end
  end
  return count
end

return M
