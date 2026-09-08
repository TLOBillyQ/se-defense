-- 双端共用：单位名约定（#18 决策 4 + #28 代数后缀）。
--
-- 首局（gen=0）单位名为裸业务实体 id；重开后为 "<id>g<gen>"。服务端
-- entity.spawn 与客户端血条按名找单位都依赖这条约定，所以住 common/。
local unit_name = {}

function unit_name.format(id, gen)
  if (gen or 0) == 0 then return tostring(id) end
  return tostring(id) .. "g" .. tostring(gen)
end

return unit_name
