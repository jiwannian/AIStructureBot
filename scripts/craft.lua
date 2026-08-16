-- 缺料补给：就近采矿、按已解锁配方瞬间合成；缺对应建筑则提示。
local util = require("scripts.util")
local inventory = require("scripts.inventory")

local craft = {}

local MACHINE_FOR_CATEGORY = {
  smelting = "stone-furnace",
  crafting = "assembling-machine-1",
  ["advanced-crafting"] = "assembling-machine-2",
  ["crafting-with-fluid"] = "assembling-machine-2",
  chemistry = "chemical-plant",
  ["oil-processing"] = "oil-refinery",
  centrifuging = "centrifuge",
  ["rocket-building"] = "rocket-silo"
}

local MACHINE_LABEL = {
  ["stone-furnace"] = {"entity-name.stone-furnace"},
  ["assembling-machine-1"] = {"entity-name.assembling-machine-1"},
  ["assembling-machine-2"] = {"entity-name.assembling-machine-2"},
  ["chemical-plant"] = {"entity-name.chemical-plant"},
  ["oil-refinery"] = {"entity-name.oil-refinery"},
  ["centrifuge"] = {"entity-name.centrifuge"},
  ["rocket-silo"] = {"entity-name.rocket-silo"}
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
  return math.max(1, math.floor((min + max) / 2))
end

local function item_label(name)
  local proto = prototypes.item[name]
  return proto and proto.localised_name or name
end

function craft.machine_for(category)
  return MACHINE_FOR_CATEGORY[category or "crafting"] or "assembling-machine-1"
end

-- 角色能手搓的配方：crafting，或不在专用机器分类里。
function craft.can_hand_craft(recipe)
  if not recipe then
    return false
  end
  local proto = recipe.prototype
  if proto and proto.hidden_from_player_crafting then
    return false
  end
  local category = recipe.category or "crafting"
  if category == "crafting" then
    return true
  end
  -- 专用机器分类不能手搓。
  if MACHINE_FOR_CATEGORY[category] and category ~= "crafting" then
    return false
  end
  return true
end

function craft.machine_label(machine_name)
  return MACHINE_LABEL[machine_name] or machine_name
end

function craft.force_has_machine(force, machine_name)
  if not force or not machine_name then
    return false
  end
  local count = force.get_entity_count(machine_name)
  return count and count > 0
end

function craft.find_recipe(force, item_name)
  local best
  for _, recipe in pairs(force.recipes) do
    if recipe.enabled and not recipe.hidden then
      for _, product in pairs(recipe.products or {}) do
        if product.type == "item" and product.name == item_name and product_amount(product) > 0 then
          local fluids = false
          for _, ing in pairs(recipe.ingredients or {}) do
            if ing.type == "fluid" then
              fluids = true
              break
            end
          end
          if not fluids then
            if (not best) or #(recipe.ingredients or {}) < #(best.ingredients or {}) then
              best = recipe
            end
          end
        end
      end
    end
  end
  return best
end

function craft.is_raw_resource(item_name)
  local proto = prototypes.entity[item_name]
  return proto and proto.resource_category ~= nil
end

function craft.find_nearest_resource(surface, position, resource_name)
  local chunks = {
    {64, 64},
    {256, 64},
    {1024, 256},
    {4096, 512}
  }
  local best, best_dist
  for _, step in ipairs(chunks) do
    local radius, limit = step[1], step[2]
    local found = surface.find_entities_filtered{
      position = position,
      radius = radius,
      name = resource_name,
      type = "resource",
      limit = limit
    }
    for _, entity in pairs(found) do
      if entity.valid and (entity.amount or 0) > 0 then
        local dist = util.distance(position, entity.position)
        if not best_dist or dist < best_dist then
          best = entity
          best_dist = dist
        end
      end
    end
    if best then
      return best, best_dist
    end
  end
  return nil, nil
end

local function give(bot, player, name, count)
  if count <= 0 then
    return 0
  end
  local leftover = count
  if util.valid_entity(bot) then
    leftover = leftover - (bot.insert({name = name, count = leftover}) or 0)
  end
  if leftover > 0 then
    leftover = leftover - (player.insert({name = name, count = leftover}) or 0)
  end
  return count - leftover
end

function craft.mine_resource(bot, player, resource, want)
  if not resource or not resource.valid then
    return 0
  end
  local available = resource.amount or 0
  local take = math.min(want, available)
  if take <= 0 then
    return 0
  end
  local given = give(bot, player, resource.name, take)
  if given <= 0 then
    return 0
  end
  local ok = pcall(function()
    if available > given then
      resource.amount = available - given
    else
      resource.destroy({raise_destroy = false})
    end
  end)
  if not ok then
    pcall(function()
      resource.destroy({raise_destroy = false})
    end)
  end
  return given
end

-- 按总需求一次采够：当前矿格不够就继续采附近同种矿。
function craft.mine_enough(bot, player, resource_name, want)
  local given = 0
  local remain = want
  local guard = 0
  while remain > 0 and guard < 80 do
    guard = guard + 1
    local ore = craft.find_nearest_resource(player.surface, bot.position, resource_name)
    if not ore then
      break
    end
    if util.distance(bot.position, ore.position) > 8 then
      return given, ore.position, remain
    end
    local got = craft.mine_resource(bot, player, ore, remain)
    if got <= 0 then
      break
    end
    given = given + got
    remain = remain - got
  end
  return given, nil, remain
end

local function count_have(bot, player, name)
  local total = util.count_item(player, name)
  if util.valid_entity(bot) then
    local trunk = bot.get_inventory(defines.inventory.spider_trunk)
    if trunk then
      total = total + util.count_item(trunk, name)
    end
    local trash = bot.get_inventory(defines.inventory.spider_trash)
    if trash then
      total = total + util.count_item(trash, name)
    end
  end
  return total
end

local function take(bot, player, name, count)
  local left = count
  if util.valid_entity(bot) then
    local trunk = bot.get_inventory(defines.inventory.spider_trunk)
    if trunk then
      left = left - (trunk.remove({name = name, count = left}) or 0)
    end
  end
  if left > 0 then
    left = left - (player.remove_item({name = name, count = left}) or 0)
  end
  return count - left
end

local function recipe_output(recipe, item_name)
  for _, product in pairs(recipe.products or {}) do
    if product.type == "item" and product.name == item_name then
      return math.max(1, product_amount(product))
    end
  end
  return 1
end

-- 把缺口拆到矿石，并扣掉已有库存：有铜线就不再采铜矿。
function craft.expand_needs(force, item_name, count, mines, crafts, need_machine, seen, stock)
  if count <= 0 then
    return
  end
  seen = seen or {}
  stock = stock or {}
  local have = stock[item_name] or 0
  if have > 0 then
    local used = math.min(have, count)
    stock[item_name] = have - used
    count = count - used
  end
  if count <= 0 then
    return
  end
  local key = item_name
  if seen[key] and seen[key] > 8 then
    return
  end
  seen[key] = (seen[key] or 0) + 1
  if craft.is_raw_resource(item_name) or item_name == "wood" then
    mines[item_name] = (mines[item_name] or 0) + count
    return
  end
  local recipe = craft.find_recipe(force, item_name)
  if not recipe then
    mines[item_name] = (mines[item_name] or 0) + count
    return
  end
  local machine = craft.machine_for(recipe.category)
  local hand = craft.can_hand_craft(recipe)
  if not hand and not craft.force_has_machine(force, machine) then
    need_machine[machine] = need_machine[machine] or {}
    table.insert(need_machine[machine], item_name)
    return
  end
  local out_each = recipe_output(recipe, item_name)
  local crafts_needed = math.ceil(count / out_each)
  table.insert(crafts, {
    name = item_name,
    count = count,
    recipe = recipe,
    machine = machine,
    by_hand = hand,
    crafts = crafts_needed
  })
  for _, ing in pairs(recipe.ingredients or {}) do
    if ing.type == "item" or not ing.type then
      craft.expand_needs(
        force,
        ing.name,
        crafts_needed * math.max(1, ing.amount),
        mines,
        crafts,
        need_machine,
        seen,
        stock
      )
    end
  end
end

function craft.find_nearest_tree(surface, position)
  local trees = surface.find_entities_filtered{
    position = position,
    radius = 1024,
    type = "tree",
    limit = 80
  }
  local best, best_dist
  for _, tree in pairs(trees) do
    if tree.valid then
      local dist = util.distance(position, tree.position)
      if not best_dist or dist < best_dist then
        best = tree
        best_dist = dist
      end
    end
  end
  return best, best_dist
end

function craft.try_fulfill(player, bot, missing)
  local reports = {}
  local produced = false
  local need_machine = {}
  local mines = {}
  local crafts = {}
  local stock = {}
  local contents = inventory.scan_available(player, bot, false, true)
  for _, entry in pairs(contents) do
    stock[entry.name] = (stock[entry.name] or 0) + entry.count
  end
  for _, item in pairs(missing) do
    craft.expand_needs(player.force, item.name, item.count, mines, crafts, need_machine, {}, stock)
  end

  local mine_jobs = {}
  for name, count in pairs(mines) do
    if count > 0 then
      local target, dist
      if name == "wood" then
        target, dist = craft.find_nearest_tree(player.surface, bot.position)
      else
        target, dist = craft.find_nearest_resource(player.surface, bot.position, name)
      end
      if target then
        table.insert(mine_jobs, {
          kind = "mine",
          name = name,
          count = count,
          target = target,
          distance = dist or 0
        })
      else
        table.insert(reports, {kind = "no-ore", name = name})
      end
    end
  end
  table.sort(mine_jobs, function(a, b)
    return a.distance < b.distance
  end)

  -- 由近到远：先走到最近矿，再按总需求一次采够。
  if mine_jobs[1] then
    local row = mine_jobs[1]
    if util.distance(bot.position, row.target.position) > 6 then
      table.insert(reports, {
        kind = "going-mine",
        name = row.name,
        count = row.count,
        distance = math.floor(row.distance)
      })
      return {
        action = "move",
        target = row.target.position,
        reports = reports,
        need_machine = need_machine,
        produced = false
      }
    end
    if row.name == "wood" then
      local remain = row.count
      local got_total = 0
      local hops = 0
      while remain > 0 and hops < 40 do
        hops = hops + 1
        local tree = craft.find_nearest_tree(player.surface, bot.position)
        if not tree then
          break
        end
        if util.distance(bot.position, tree.position) > 8 then
          return {
            action = "move",
            target = tree.position,
            reports = reports,
            need_machine = need_machine,
            produced = produced
          }
        end
        tree.destroy({raise_destroy = false})
        local got = give(bot, player, "wood", math.min(remain, 4))
        got_total = got_total + got
        remain = remain - got
      end
      if got_total > 0 then
        produced = true
        table.insert(reports, {kind = "mined", name = "wood", count = got_total})
      end
    else
      local got, next_pos, remain = craft.mine_enough(bot, player, row.name, row.count)
      if got > 0 then
        produced = true
        table.insert(reports, {kind = "mined", name = row.name, count = got})
      end
      if remain and remain > 0 and next_pos then
        return {
          action = "move",
          target = next_pos,
          reports = reports,
          need_machine = need_machine,
          produced = produced
        }
      end
    end
  end

  -- 从原料往成品瞬间合成（列表末尾是成品）。
  for i = #crafts, 1, -1 do
    local row = crafts[i]
    local out_each = recipe_output(row.recipe, row.name)
    local crafts_needed = math.ceil(row.count / out_each)
    local can = crafts_needed
    for _, ing in pairs(row.recipe.ingredients or {}) do
      if ing.type == "item" or not ing.type then
        local have = count_have(bot, player, ing.name)
        can = math.min(can, math.floor(have / math.max(1, ing.amount)))
      end
    end
    if can > 0 then
      for _, ing in pairs(row.recipe.ingredients or {}) do
        if ing.type == "item" or not ing.type then
          take(bot, player, ing.name, ing.amount * can)
        end
      end
      local made = can * out_each
      give(bot, player, row.name, made)
      produced = true
      table.insert(reports, {
        kind = "crafted",
        name = row.name,
        count = made,
        machine = row.machine,
        by_hand = row.by_hand
      })
    end
  end

  if not produced and mine_jobs[2] then
    return {
      action = "move",
      target = mine_jobs[2].target.position,
      reports = reports,
      need_machine = need_machine,
      produced = false
    }
  end

  return {
    action = produced and "produced" or "wait",
    reports = reports,
    need_machine = need_machine,
    produced = produced
  }
end

function craft.announce(player, result)
  if not result then
    return
  end
  local seen_machine = {}
  for machine, items in pairs(result.need_machine or {}) do
    for _, name in ipairs(items) do
      local key = machine .. "|" .. name
      if not seen_machine[key] then
        seen_machine[key] = true
        player.print({"", "请先建造 ", craft.machine_label(machine), " 才能合成 ", item_label(name)})
      end
    end
  end
  for _, row in ipairs(result.reports or {}) do
    if row.kind == "going-mine" then
      player.print({"", "正在前往采集 ", item_label(row.name), " x", tostring(row.count), "（距离 ", tostring(row.distance), "）"})
    elseif row.kind == "mined" then
      player.print({"", "已采集 ", item_label(row.name), " x", tostring(row.count)})
    elseif row.kind == "crafted" then
      if row.by_hand then
        player.print({"", "已用手搓合成 ", item_label(row.name), " x", tostring(row.count), "（也可用 ", craft.machine_label(row.machine), "）"})
      else
        player.print({"", "已用 ", craft.machine_label(row.machine), " 合成 ", item_label(row.name), " x", tostring(row.count)})
      end
    elseif row.kind == "no-ore" then
      player.print({"", "地图上找不到 ", item_label(row.name), " 矿点"})
    elseif row.kind == "no-recipe" then
      player.print({"", "没有已解锁的 ", item_label(row.name), " 配方"})
    end
  end
end

return craft
