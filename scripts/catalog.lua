-- 规划用物品目录：当前势力已解锁、能放下的建筑/地砖。
local catalog = {}

local function product_name(product)
  if not product then
    return nil
  end
  if product.type and product.type ~= "item" then
    return nil
  end
  return product.name
end

function catalog.unlocked_placeables(force)
  local seen = {}
  local items = {}
  for _, recipe in pairs(force.recipes) do
    if recipe.enabled and not recipe.hidden then
      for _, product in pairs(recipe.products or {}) do
        local name = product_name(product)
        if name and not seen[name] then
          local proto = prototypes.item[name]
          if proto and not proto.hidden and (proto.place_result or proto.place_as_tile_result) and not proto.has_flag("only-in-cursor") then
            seen[name] = true
            table.insert(items, {
              name = name,
              localised_name = proto.localised_name,
              order = proto.order or "",
              group = proto.group and proto.group.name or "other",
              subgroup = proto.subgroup and proto.subgroup.name or "other"
            })
          end
        end
      end
    end
  end
  table.sort(items, function(a, b)
    if a.group ~= b.group then
      return a.group < b.group
    end
    if a.subgroup ~= b.subgroup then
      return a.subgroup < b.subgroup
    end
    if a.order ~= b.order then
      return a.order < b.order
    end
    return a.name < b.name
  end)
  return items
end

return catalog
