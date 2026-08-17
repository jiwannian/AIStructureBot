-- 一键规划：按目标产能展开配方树，生成占地尽量小的流水线蓝图。
local craft = require("scripts.craft")

local lineplan = {}

local MACHINE_SPEED = {
  ["assembling-machine-1"] = 0.5,
  ["assembling-machine-2"] = 0.75,
  ["assembling-machine-3"] = 1.25,
  ["stone-furnace"] = 1,
  ["steel-furnace"] = 2,
  ["electric-furnace"] = 2,
  ["chemical-plant"] = 1,
  ["oil-refinery"] = 1,
  ["centrifuge"] = 1
}

local CRAFT_MACHINE_TYPES = {
  ["assembling-machine"] = true,
  furnace = true,
  ["rocket-silo"] = true
}

local SEARCH_ALIASES = {
  ["齿轮"] = "iron-gear-wheel",
  ["铁齿轮"] = "iron-gear-wheel",
  ["铁板"] = "iron-plate",
  ["铜板"] = "copper-plate",
  ["钢板"] = "steel-plate",
  ["铁棒"] = "iron-stick",
  ["铜线"] = "copper-cable",
  ["电路板"] = "electronic-circuit",
  ["绿板"] = "electronic-circuit",
  ["红板"] = "advanced-circuit",
  ["主板"] = "processing-unit",
  ["蓝板"] = "processing-unit",
  ["铁矿"] = "iron-ore",
  ["铜矿"] = "copper-ore",
  ["煤矿"] = "coal",
  ["煤"] = "coal",
  ["石头"] = "stone",
  ["石矿"] = "stone",
  ["木头"] = "wood",
  ["红瓶"] = "automation-science-pack",
  ["绿瓶"] = "logistic-science-pack",
  ["蓝瓶"] = "chemical-science-pack",
  ["紫瓶"] = "production-science-pack",
  ["黄瓶"] = "utility-science-pack"
}

local function product_amount(product)
  if not product then
    return 0
  end
  if product.amount then
    return product.amount
  end
  local min = product.amount_min or 0
  local max = product.amount_max or min
  return math.max(1, (min + max) / 2)
end

local function item_label(name)
  local proto = prototypes.item[name] or prototypes.fluid[name]
  return proto and proto.localised_name or name
end

local function recipe_enabled(force, name)
  local recipe = force.recipes[name]
  return recipe and recipe.enabled and not recipe.hidden
end

function lineplan.machine_unlocked(force, entity_name)
  if force.get_entity_count(entity_name) > 0 then
    return true
  end
  for _, recipe in pairs(force.recipes) do
    if recipe.enabled and not recipe.hidden then
      for _, product in pairs(recipe.products or {}) do
        if product.type == "item" and product.name == entity_name then
          return true
        end
      end
    end
  end
  return prototypes.item[entity_name] and recipe_enabled(force, entity_name)
end

local function proto_area(name)
  local proto = prototypes.entity[name]
  if not proto then
    return 9, 3, 3
  end
  local w = proto.tile_width or 3
  local h = proto.tile_height or 3
  return math.max(1, w) * math.max(1, h), w, h
end

local function machine_speed(name)
  local proto = prototypes.entity[name]
  if proto and proto.get_crafting_speed then
    local ok, speed = pcall(function()
      return proto.get_crafting_speed()
    end)
    if ok and speed and speed > 0 then
      return speed
    end
  end
  if proto and proto.speed and proto.speed > 0 then
    return proto.speed
  end
  return MACHINE_SPEED[name] or 1
end

function lineplan.pick_machine(force, category)
  local best, best_score
  for name, proto in pairs(prototypes.entity) do
    if CRAFT_MACHINE_TYPES[proto.type] and not proto.hidden and proto.is_building then
      local cats = proto.crafting_categories
      if cats and cats[category] and lineplan.machine_unlocked(force, name) then
        local area, w, h = proto_area(name)
        local speed = machine_speed(name)
        local score = (area / math.max(0.1, speed)) + w * 0.01
        if not best_score or score < best_score then
          best = {name = name, speed = speed, w = w, h = h, area = area}
          best_score = score
        end
      end
    end
  end
  if best then
    return best
  end
  local fallback = craft.machine_for(category)
  local area, w, h = proto_area(fallback)
  return {name = fallback, speed = machine_speed(fallback), w = w, h = h, area = area}
end

function lineplan.pick_belt(force, rate_per_min)
  local order = {
    {name = "transport-belt", cap = 900},
    {name = "fast-transport-belt", cap = 1800},
    {name = "express-transport-belt", cap = 2700}
  }
  local chosen
  for _, row in ipairs(order) do
    if lineplan.machine_unlocked(force, row.name) then
      chosen = row
      if rate_per_min <= row.cap then
        return row.name
      end
    end
  end
  return chosen and chosen.name or "transport-belt"
end

function lineplan.pick_inserter(force)
  if lineplan.machine_unlocked(force, "inserter") then
    return "inserter"
  end
  if lineplan.machine_unlocked(force, "burner-inserter") then
    return "burner-inserter"
  end
  return "inserter"
end

function lineplan.pick_pole(force)
  if lineplan.machine_unlocked(force, "medium-electric-pole") then
    return "medium-electric-pole"
  end
  if lineplan.machine_unlocked(force, "small-electric-pole") then
    return "small-electric-pole"
  end
  return "small-electric-pole"
end

function lineplan.pick_chest(force)
  if lineplan.machine_unlocked(force, "iron-chest") then
    return "iron-chest"
  end
  return "wooden-chest"
end

function lineplan.find_recipe(force, item_name)
  local best
  for _, recipe in pairs(force.recipes) do
    if recipe.enabled and not recipe.hidden then
      for _, product in pairs(recipe.products or {}) do
        if product.type == "item" and product.name == item_name and product_amount(product) > 0 then
          if (not best) or #(recipe.ingredients or {}) < #(best.ingredients or {}) then
            best = recipe
          end
        end
      end
    end
  end
  return best
end

local function recipe_has_fluid(recipe)
  for _, ing in pairs(recipe.ingredients or {}) do
    if ing.type == "fluid" then
      return true
    end
  end
  return false
end

function lineplan.is_leaf(force, item_name, cuts)
  if cuts and cuts[item_name] then
    return true
  end
  if craft.is_raw_resource(item_name) or item_name == "wood" then
    return true
  end
  return lineplan.find_recipe(force, item_name) == nil
end

function lineplan.unlocked_products(force)
  local seen = {}
  local items = {}
  for _, recipe in pairs(force.recipes) do
    if recipe.enabled and not recipe.hidden then
      for _, product in pairs(recipe.products or {}) do
        if product.type == "item" and product.name and not seen[product.name] then
          local proto = prototypes.item[product.name]
          if proto and not proto.hidden then
            seen[product.name] = true
            table.insert(items, {
              name = product.name,
              localised_name = proto.localised_name,
              order = proto.order or ""
            })
          end
        end
      end
    end
  end
  table.sort(items, function(a, b)
    if a.order ~= b.order then
      return a.order < b.order
    end
    return a.name < b.name
  end)
  return items
end

function lineplan.compute(force, item_name, rate_per_min, cuts)
  cuts = cuts or {}
  local nodes = {}
  local leaves = {}
  local fluids = {}

  local function add_leaf(name, rate, kind)
    if kind == "fluid" then
      fluids[name] = (fluids[name] or 0) + rate
    else
      leaves[name] = (leaves[name] or 0) + rate
    end
  end

  local function expand(name, rate, depth)
    if rate <= 0 or depth > 12 then
      return
    end
    if lineplan.is_leaf(force, name, cuts) then
      add_leaf(name, rate, "item")
      return
    end
    local recipe = lineplan.find_recipe(force, name)
    if not recipe then
      add_leaf(name, rate, "item")
      return
    end
    if recipe_has_fluid(recipe) then
      add_leaf(name, rate, "item")
      local out_each = 1
      for _, product in pairs(recipe.products or {}) do
        if product.type == "item" and product.name == name then
          out_each = math.max(1, product_amount(product))
        end
      end
      local crafts = rate / out_each
      for _, ing in pairs(recipe.ingredients or {}) do
        if ing.type == "fluid" then
          add_leaf(ing.name, crafts * (ing.amount or 0), "fluid")
        end
      end
      return
    end
    local out_each = 1
    for _, product in pairs(recipe.products or {}) do
      if product.type == "item" and product.name == name then
        out_each = math.max(1, product_amount(product))
      end
    end
    local crafts_per_min = rate / out_each
    local machine = lineplan.pick_machine(force, recipe.category or "crafting")
    local per_machine = (60 / math.max(0.1, recipe.energy or 0.5)) * machine.speed * out_each
    if not nodes[name] then
      nodes[name] = {
        name = name,
        recipe = recipe.name,
        category = recipe.category or "crafting",
        machine = machine.name,
        machine_w = machine.w,
        machine_h = machine.h,
        speed = machine.speed,
        out_each = out_each,
        energy = recipe.energy or 0.5,
        rate = 0,
        count = 0,
        depth = depth,
        ings = {}
      }
    end
    local node = nodes[name]
    node.rate = node.rate + rate
    node.count = math.max(1, math.ceil(node.rate / math.max(0.01, per_machine)))
    node.depth = math.min(node.depth, depth)
    for _, ing in pairs(recipe.ingredients or {}) do
      if ing.type == "item" or not ing.type then
        local need = crafts_per_min * math.max(1, ing.amount or 1)
        node.ings[ing.name] = (node.ings[ing.name] or 0) + need
        expand(ing.name, need, depth + 1)
      elseif ing.type == "fluid" then
        add_leaf(ing.name, crafts_per_min * (ing.amount or 0), "fluid")
      end
    end
  end

  expand(item_name, rate_per_min, 0)
  local list = {}
  for _, node in pairs(nodes) do
    table.insert(list, node)
  end
  table.sort(list, function(a, b)
    if a.depth ~= b.depth then
      return a.depth > b.depth
    end
    return a.name < b.name
  end)
  local leaf_list = {}
  for name, rate in pairs(leaves) do
    table.insert(leaf_list, {name = name, rate = rate})
  end
  table.sort(leaf_list, function(a, b)
    return a.name < b.name
  end)
  local fluid_list = {}
  for name, rate in pairs(fluids) do
    table.insert(fluid_list, {name = name, rate = rate})
  end
  return {
    item = item_name,
    rate = rate_per_min,
    nodes = list,
    leaves = leaf_list,
    fluids = fluid_list
  }
end

function lineplan.tree(force, item_name)
  local seen = {}
  local function walk(name, depth)
    if seen[name] or depth > 12 then
      return {name = name, children = {}, fluid = false}
    end
    seen[name] = true
    local node = {name = name, children = {}, fluid = false}
    if craft.is_raw_resource(name) or name == "wood" then
      return node
    end
    local recipe = lineplan.find_recipe(force, name)
    if not recipe then
      return node
    end
    if recipe_has_fluid(recipe) then
      node.fluid = true
      return node
    end
    for _, ing in pairs(recipe.ingredients or {}) do
      if ing.type == "item" or not ing.type then
        table.insert(node.children, walk(ing.name, depth + 1))
      elseif ing.type == "fluid" then
        table.insert(node.children, {name = ing.name, children = {}, fluid = true})
      end
    end
    return node
  end
  return walk(item_name, 0)
end

function lineplan.tree_items(force, item_name)
  local names = {}
  local function walk(node)
    table.insert(names, node.name)
    for _, child in ipairs(node.children or {}) do
      walk(child)
    end
  end
  local tree = lineplan.tree(force, item_name)
  if tree then
    walk(tree)
  end
  return names
end

function lineplan.matches_filter(item, filter)
  if not filter or filter == "" then
    return true
  end
  filter = string.lower(filter)
  if string.find(string.lower(item.name), filter, 1, true) then
    return true
  end
  if type(item.localised_name) == "string" and string.find(string.lower(item.localised_name), filter, 1, true) then
    return true
  end
  for alias, name in pairs(SEARCH_ALIASES) do
    if name == item.name and string.find(string.lower(alias), filter, 1, true) then
      return true
    end
  end
  return false
end

local function add_entity(list, name, x, y, direction, recipe)
  if not prototypes.entity[name] then
    return
  end
  table.insert(list, {
    entity_number = #list + 1,
    name = name,
    position = {x = x, y = y},
    direction = direction or defines.direction.north,
    tags = recipe and {ai_recipe = recipe} or nil
  })
end

function lineplan.build_entities(force, computed)
  local entities = {}
  local recipe_spots = {}
  local belt = lineplan.pick_belt(force, computed.rate)
  local inserter = lineplan.pick_inserter(force)
  local pole = lineplan.pick_pole(force)
  local chest = lineplan.pick_chest(force)
  local east = defines.direction.east
  local south = defines.direction.south
  local west = defines.direction.west
  local north = defines.direction.north

  local function opposite(dir)
    if dir == north then
      return south
    end
    if dir == south then
      return north
    end
    if dir == east then
      return west
    end
    return east
  end

  local occ = {}
  local function tile_key(tx, ty)
    return tostring(tx) .. "," .. tostring(ty)
  end
  local function box_origin(cx, cy, tw, th)
    return math.floor(cx - tw / 2 + 0.001), math.floor(cy - th / 2 + 0.001)
  end
  local function add(name, x, y, dir, recipe, replace)
    local proto = prototypes.entity[name]
    if not proto then
      return
    end
    local tw = proto.tile_width or 1
    local th = proto.tile_height or 1
    local x0, y0 = box_origin(x, y, tw, th)
    local key = tile_key(x0, y0)
    if occ[key] then
      if not replace then
        return
      end
      for i = #entities, 1, -1 do
        local e = entities[i]
        if math.floor((e.position.x or 0) - 0.5 + 0.001) == x0
          and math.floor((e.position.y or 0) - 0.5 + 0.001) == y0 then
          table.remove(entities, i)
          break
        end
      end
    end
    for dx = 0, tw - 1 do
      for dy = 0, th - 1 do
        occ[tile_key(x0 + dx, y0 + dy)] = true
      end
    end
    add_entity(entities, name, x, y, dir, recipe)
    if recipe then
      table.insert(recipe_spots, {x = x, y = y, recipe = recipe})
    end
  end
  local function add_drop(x, y, drop_dir)
    add(inserter, x, y, opposite(drop_dir))
  end

  local max_count, max_w = 1, 3
  for _, node in ipairs(computed.nodes) do
    max_count = math.max(max_count, node.count or 1)
    max_w = math.max(max_w, node.machine_w or 3)
  end
  local last_x = math.max(8, 3 + max_count * (max_w + 1))

  local function belt_row(ty, x0, x1, dir)
    for tx = x0, x1 do
      add(belt, tx + 0.5, ty + 0.5, dir)
    end
  end

  local function tap_south(src_y, dest_y)
    if dest_y <= src_y then
      return
    end
    add(belt, last_x + 0.5, src_y + 0.5, south, nil, true)
    for ty = src_y + 1, dest_y - 1 do
      add(belt, last_x + 0.5, ty + 0.5, south)
    end
  end

  local lanes = {}
  for i, leaf in ipairs(computed.leaves) do
    local ty = i - 1
    lanes[leaf.name] = ty
    add(chest, 0.5, ty + 0.5)
    add_drop(1.5, ty + 0.5, east)
    belt_row(ty, 2, last_x, east)
  end
  if #computed.leaves > 0 then
    add(pole, 1.5, -0.5)
  end

  local y = #computed.leaves
  for _, node in ipairs(computed.nodes) do
    local w = node.machine_w or 3
    local h = node.machine_h or 3
    local feed_y = y + 1
    belt_row(feed_y, 2, last_x, west)
    for ing_name in pairs(node.ings or {}) do
      local src_y = lanes[ing_name]
      if src_y ~= nil and src_y < feed_y then
        tap_south(src_y, feed_y)
      end
    end
    local proto = prototypes.entity[node.machine]
    local face = (proto and proto.type == "furnace") and south or north
    for i = 1, node.count do
      local mx = 3 + (i - 1) * (w + 1) + w / 2
      add(node.machine, mx, feed_y + 2 + h / 2, face, node.recipe)
      add_drop(mx, feed_y + 1.5, south)
      add_drop(mx, feed_y + 2 + h + 0.5, south)
    end
    add(pole, 2.5, feed_y + 2 + h / 2)
    local out_y = feed_y + 2 + h + 1
    belt_row(out_y, 2, last_x, east)
    lanes[node.name] = out_y
    y = out_y + 1
  end

  local fy = lanes[computed.item]
  if fy then
    add_drop(last_x + 1.5, fy + 0.5, east)
    add(chest, last_x + 2.5, fy + 0.5)
  end
  return entities, last_x + 4, y + 2, recipe_spots
end

function lineplan.apply_recipe(entity, recipe_name)
  if not (entity and entity.valid and recipe_name) then
    return
  end
  pcall(function()
    entity.set_recipe(recipe_name)
  end)
  pcall(function()
    local tags = entity.tags or {}
    tags.ai_recipe = recipe_name
    entity.tags = tags
  end)
end

function lineplan.recipe_at(spots, origin, world, max_dist)
  if not (spots and origin and world) then
    return nil
  end
  max_dist = max_dist or 0.8
  for _, spot in ipairs(spots) do
    local dx = (origin.x + spot.x) - world.x
    local dy = (origin.y + spot.y) - world.y
    if dx * dx + dy * dy <= max_dist * max_dist then
      return spot.recipe
    end
  end
  return nil
end

function lineplan.put_on_cursor(player, computed)
  local entities, width, height, recipe_spots = lineplan.build_entities(player.force, computed)
  if #entities == 0 then
    return false, 0, 0, "empty"
  end
  pcall(function()
    player.clear_cursor()
  end)
  local cursor = player.cursor_stack
  if not cursor or not cursor.valid then
    return false, 0, 0, "cursor"
  end
  local stacked = pcall(function()
    cursor.set_stack({name = "blueprint", count = 1})
  end)
  if not stacked or not cursor.valid_for_read then
    return false, 0, 0, "blueprint-item"
  end
  local ok, err = pcall(function()
    cursor.set_blueprint_entities(entities)
    for _, entity in ipairs(entities) do
      if entity.tags then
        cursor.set_blueprint_entity_tags(entity.entity_number, entity.tags)
      end
    end
    cursor.label = (computed.item or "line") .. " " .. tostring(math.floor(computed.rate or 0)) .. "/min"
    local lines = {}
    for _, node in ipairs(computed.nodes) do
      table.insert(lines, node.name .. " = " .. (node.recipe or "?") .. " x" .. tostring(node.count))
    end
    cursor.blueprint_description = table.concat(lines, "\n")
  end)
  if not ok then
    player.clear_cursor()
    return false, 0, 0, err
  end
  if not cursor.is_blueprint_setup() then
    player.clear_cursor()
    return false, 0, 0, "empty"
  end
  player.cursor_stack_temporary = true
  return true, width, height, recipe_spots
end

function lineplan.item_label(name)
  return item_label(name)
end

return lineplan
