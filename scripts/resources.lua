-- 资源提示：只报告矿点，不改现有工厂配方。
local util = require("scripts.util")

local resources = {}

local ORE_HINT = {
  ["iron-ore"] = "iron-ore",
  ["copper-ore"] = "copper-ore",
  ["coal"] = "coal",
  ["stone"] = "stone",
  ["uranium-ore"] = "uranium-ore",
  ["iron-plate"] = "iron-ore",
  ["copper-plate"] = "copper-ore",
  ["steel-plate"] = "iron-ore",
  ["stone-brick"] = "stone",
  ["stone-wall"] = "stone",
  ["concrete"] = "stone",
  ["hazard-concrete"] = "stone",
  ["refined-concrete"] = "stone"
}

function resources.raw_resource_for(item_name)
  if prototypes.entity[item_name] and prototypes.entity[item_name].resource_category then
    return item_name
  end
  return ORE_HINT[item_name]
end

function resources.find_nearest_resource(surface, position, resource_name, radius)
  local area = {
    {position.x - radius, position.y - radius},
    {position.x + radius, position.y + radius}
  }
  local candidates = surface.find_entities_filtered{
    area = area,
    name = resource_name,
    type = "resource"
  }
  local best, best_dist
  for _, entity in pairs(candidates) do
    if entity.valid and entity.amount and entity.amount > 0 then
      local dist = util.distance(position, entity.position)
      if not best_dist or dist < best_dist then
        best = entity
        best_dist = dist
      end
    end
  end
  return best, best_dist
end

function resources.hint_missing(player, missing, radius)
  local report = {}
  for _, item in pairs(missing) do
    local ore_name = resources.raw_resource_for(item.name)
    local ore, dist
    if ore_name then
      ore, dist = resources.find_nearest_resource(player.surface, player.position, ore_name, radius)
    end
    table.insert(report, {
      name = item.name,
      quality = item.quality,
      count = item.count,
      ore = ore and ore.name or ore_name,
      distance = dist and math.floor(dist) or nil
    })
  end
  return report
end

return resources
