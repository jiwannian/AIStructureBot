-- 基地维护：补弹优先，然后维修受损建筑。
-- 补弹和维修都不翻箱子、不拿玩家背包，只按建造模式采集合成。
local util = require("scripts.util")
local inventory = require("scripts.inventory")
local builder = require("scripts.builder")
local craft = require("scripts.craft")

local maintain = {}

local AMMO_INV = {
  ["ammo-turret"] = defines.inventory.turret_ammo,
  ["artillery-turret"] = defines.inventory.artillery_turret_ammo
}

local DEFAULT_RULES = {
  ["gun-turret"] = {ammo = "firearm-magazine", min = 10, max = 50, enabled = true},
  ["artillery-turret"] = {ammo = "artillery-shell", min = 2, max = 10, enabled = true}
}

local SKIP_REPAIR_TYPES = {
  character = true,
  ["spider-vehicle"] = true,
  car = true,
  tank = true,
  unit = true,
  tree = true,
  fish = true,
  resource = true,
  ["entity-ghost"] = true,
  ["tile-ghost"] = true,
  ["item-entity"] = true,
  corpse = true
}

local function category_name(value)
  if not value then
    return nil
  end
  if type(value) == "string" then
    return value
  end
  return value.name
end

local function turret_categories(proto)
  local cats = {}
  local params = proto and proto.attack_parameters
  if params then
    if params.ammo_categories then
      for _, name in pairs(params.ammo_categories) do
        local key = category_name(name)
        if key then
          cats[key] = true
        end
      end
    end
    if params.ammo_type then
      local key = category_name(params.ammo_type.category)
      if key then
        cats[key] = true
      end
    end
  end
  local proto_cat = proto and category_name(proto.ammo_category)
  if proto_cat then
    cats[proto_cat] = true
  end
  return cats
end

function maintain.compatible_ammo(turret_name)
  local proto = prototypes.entity[turret_name]
  local cats = turret_categories(proto)
  local items = {}
  if not next(cats) then
    return items
  end
  for name, item in pairs(prototypes.item) do
    local cat = category_name(item.ammo_category)
    if cat and cats[cat] and not item.hidden then
      table.insert(items, name)
    end
  end
  table.sort(items)
  return items
end

function maintain.ammo_turret_names()
  local names = {}
  for name, proto in pairs(prototypes.entity) do
    if (proto.type == "ammo-turret" or proto.type == "artillery-turret") and not proto.hidden then
      table.insert(names, name)
    end
  end
  table.sort(names)
  return names
end

function maintain.default_rule(turret_name)
  local ammo_list = maintain.compatible_ammo(turret_name)
  local preset = DEFAULT_RULES[turret_name] or {}
  local ammo = preset.ammo
  if ammo and not prototypes.item[ammo] then
    ammo = nil
  end
  if ammo then
    local ok = false
    for _, name in ipairs(ammo_list) do
      if name == ammo then
        ok = true
        break
      end
    end
    if not ok then
      ammo = nil
    end
  end
  if not ammo then
    ammo = ammo_list[1]
  end
  return {
    enabled = preset.enabled ~= false and ammo ~= nil,
    ammo = ammo,
    min = preset.min or 10,
    max = preset.max or 50
  }
end

function maintain.list_bots(player)
  if not player or not player.valid then
    return {}
  end
  return player.surface.find_entities_filtered{
    name = "ai-structure-bot",
    force = player.force
  }
end

function maintain.list_mode_bots(player, mode)
  local out = {}
  for _, bot in ipairs(maintain.list_bots(player)) do
    if bot.valid then
      local state = maintain.get_bot_state(bot.unit_number)
      if state.mode == mode and not state.paused and not state.recalling then
        table.insert(out, bot)
      end
    end
  end
  return out
end

local function closer_teammate(bot, teammates, position)
  if not teammates or #teammates <= 1 then
    return nil
  end
  local my_dist = util.distance(bot.position, position)
  local best, best_dist
  for _, other in ipairs(teammates) do
    if other.valid and other.unit_number ~= bot.unit_number then
      local dist = util.distance(other.position, position)
      if dist + 0.1 < my_dist and (not best_dist or dist < best_dist) then
        best = other
        best_dist = dist
      end
    end
  end
  return best
end

function maintain.get_bot_state(unit_number)
  storage.bot_modes = storage.bot_modes or {}
  storage.bot_modes[unit_number] = storage.bot_modes[unit_number] or {
    mode = "build",
    repair = true,
    paused = false,
    recalling = false,
    rules = {}
  }
  local state = storage.bot_modes[unit_number]
  if state.repair == nil then
    state.repair = true
  end
  return state
end

function maintain.set_mode(unit_number, mode, origin)
  local state = maintain.get_bot_state(unit_number)
  state.mode = mode
  state.announced = false
  state.current_turret = nil
  state.current_repair = nil
  state.mine_target = nil
  state.ammo_plan = nil
  state.repair_plan = nil
  state.search_origin = origin
  return state
end

function maintain.ensure_rules(unit_number)
  local state = maintain.get_bot_state(unit_number)
  for _, name in ipairs(maintain.ammo_turret_names()) do
    if not state.rules[name] then
      state.rules[name] = maintain.default_rule(name)
    end
  end
  return state
end

function maintain.update_rule(unit_number, turret_name, field, value)
  local state = maintain.ensure_rules(unit_number)
  if field == "repair" then
    state.repair = value and true or false
    return state
  end
  local rule = state.rules[turret_name]
  if not rule then
    return nil
  end
  if field == "enabled" then
    rule.enabled = value and true or false
  elseif field == "ammo" then
    rule.ammo = value
  elseif field == "min" then
    rule.min = math.max(0, math.min(9999, math.floor(tonumber(value) or 0)))
    if (rule.max or 0) < rule.min then
      rule.max = rule.min
    end
  elseif field == "max" then
    rule.max = math.max(0, math.min(9999, math.floor(tonumber(value) or 0)))
    if rule.max < (rule.min or 0) then
      rule.min = rule.max
    end
  end
  return rule
end

local function search_origin(player, state, bot)
  if bot and bot.valid then
    return bot.position
  end
  if state and state.search_origin then
    return state.search_origin
  end
  if player.character and player.character.valid then
    return player.character.position
  end
  return player.position
end

local function turret_ammo_count(turret, ammo_name)
  local inv_index = AMMO_INV[turret.type]
  if not inv_index then
    return 0, nil
  end
  local inv = turret.get_inventory(inv_index)
  if not inv then
    return 0, nil
  end
  if ammo_name then
    return util.count_item(inv, ammo_name), inv
  end
  local total = 0
  for _, stack in pairs(inv.get_contents() or {}) do
    total = total + (stack.count or 0)
  end
  return total, inv
end

function maintain.collect_ammo_jobs(bot, state, teammates)
  local turrets = bot.surface.find_entities_filtered{
    force = bot.force,
    type = {"ammo-turret", "artillery-turret"}
  }
  local jobs = {}
  local totals = {}
  for _, turret in pairs(turrets) do
    if turret.valid then
      local rule = state.rules[turret.name]
      if rule and rule.enabled and rule.ammo and (rule.min or 0) > 0 then
        local count = turret_ammo_count(turret, rule.ammo)
        local cap = math.max(rule.min, rule.max or rule.min)
        if count < rule.min then
          local need = math.max(0, cap - count)
          local closer = closer_teammate(bot, teammates, turret.position)
          if not closer then
            table.insert(jobs, {
              turret = turret,
              ammo = rule.ammo,
              cap = cap,
              need = need
            })
            totals[rule.ammo] = (totals[rule.ammo] or 0) + need
          end
        end
      end
    end
  end
  if #jobs == 0 and teammates and #teammates > 1 then
    -- 近处都被同伴认领时，改去帮最近的一处，避免闲站。
    local best, best_need, best_dist
    for _, turret in pairs(turrets) do
      if turret.valid then
        local rule = state.rules[turret.name]
        if rule and rule.enabled and rule.ammo and (rule.min or 0) > 0 then
          local count = turret_ammo_count(turret, rule.ammo)
          local cap = math.max(rule.min, rule.max or rule.min)
          if count < rule.min then
            local dist = util.distance(bot.position, turret.position)
            if not best_dist or dist < best_dist then
              best = turret
              best_need = math.max(0, cap - count)
              best_dist = dist
            end
          end
        end
      end
    end
    if best then
      local rule = state.rules[best.name]
      table.insert(jobs, {
        turret = best,
        ammo = rule.ammo,
        cap = math.max(rule.min, rule.max or rule.min),
        need = best_need
      })
      totals[rule.ammo] = best_need
    end
  end
  return jobs, totals
end

local REPAIR_TYPES = {
  "wall",
  "gate",
  "ammo-turret",
  "electric-turret",
  "fluid-turret",
  "artillery-turret",
  "radar",
  "roboport",
  "electric-pole",
  "container",
  "logistic-container",
  "assembling-machine",
  "furnace",
  "mining-drill",
  "lab",
  "beacon",
  "solar-panel",
  "accumulator",
  "generator",
  "boiler",
  "pipe",
  "pipe-to-ground",
  "pump",
  "storage-tank",
  "transport-belt",
  "underground-belt",
  "splitter",
  "inserter",
  "lamp"
}

local function repair_item_name(entity)
  if not entity or not entity.valid then
    return nil
  end
  if entity.type == "entity-ghost" or entity.type == "tile-ghost" then
    return util.item_place_name(entity.ghost_prototype) or entity.ghost_name
  end
  return util.item_place_name(entity.prototype) or entity.name
end

local function is_damaged(entity)
  if not (entity and entity.valid) then
    return false
  end
  local ok, ratio = pcall(function()
    return entity.get_health_ratio()
  end)
  if ok and type(ratio) == "number" then
    return ratio < 0.999
  end
  local max_hp = entity.max_health or 0
  local hp = entity.health
  if not hp or max_hp <= 0 then
    return false
  end
  return hp < max_hp - 0.5
end

function maintain.collect_repair_jobs(bot, origin, teammates)
  -- 扫描以 Bot 为中心，避免切模式时玩家站得太远漏掉墙。
  -- 只有一只维护 Bot 时拿下全部任务；多只时谁近谁修。
  local from = (bot and bot.valid and bot.position) or origin
  local jobs = {}
  local totals = {}
  local seen = {}

  local function add_job(entity, kind)
    if not (entity and entity.valid) then
      return
    end
    if entity.unit_number and entity.unit_number == bot.unit_number then
      return
    end
    local id = entity.unit_number
    if id and seen[id] then
      return
    end
    if closer_teammate(bot, teammates, entity.position) then
      return
    end
    local item = repair_item_name(entity)
    if not item then
      return
    end
    if id then
      seen[id] = true
    end
    table.insert(jobs, {
      entity = entity,
      item = item,
      kind = kind
    })
    totals[item] = (totals[item] or 0) + 1
  end

  local function scan(filter)
    local ok, found = pcall(function()
      return bot.surface.find_entities_filtered(filter)
    end)
    if ok then
      return found or {}
    end
    return {}
  end

  -- 只修还在的掉血建筑，不碰规划幽灵。
  for _, entity in pairs(scan{
    force = bot.force,
    position = from,
    radius = 4096,
    type = {"wall", "gate"}
  }) do
    if is_damaged(entity) then
      add_job(entity, "hp")
    end
  end

  for _, entity in pairs(scan{
    force = bot.force,
    position = from,
    radius = 4096,
    type = REPAIR_TYPES
  }) do
    if is_damaged(entity) then
      add_job(entity, "hp")
    end
  end
  if #jobs == 0 and teammates and #teammates > 1 then
    local function help_nearest(entity, kind)
      if not (entity and entity.valid) then
        return
      end
      if entity.unit_number and entity.unit_number == bot.unit_number then
        return
      end
      local item = repair_item_name(entity)
      if not item then
        return
      end
      local dist = util.distance(from, entity.position)
      local current = jobs[1]
      if not current or util.distance(from, current.entity.position) > dist then
        jobs[1] = {entity = entity, item = item, kind = kind}
        totals = {[item] = 1}
      end
    end
    for _, entity in pairs(scan{
      force = bot.force,
      position = from,
      radius = 4096,
      type = REPAIR_TYPES
    }) do
      if is_damaged(entity) then
        help_nearest(entity, "hp")
      end
    end
  end
  return jobs, totals
end

local function bot_item_count(bot, name)
  if not util.valid_entity(bot) then
    return 0
  end
  local trunk = bot.get_inventory(defines.inventory.spider_trunk)
  return util.count_item(trunk, name)
end

local function take_from_bot(bot, name, count)
  return inventory.try_remove_from_bot(bot, name, "normal", count)
end

local function give_to_bot(bot, name, count)
  if not util.valid_entity(bot) or count <= 0 then
    return 0
  end
  return bot.insert({name = name, count = count, quality = "normal"}) or 0
end

local function locked_ok(entity)
  if not (entity and entity.valid) then
    return false
  end
  if entity.type == "resource" then
    local ok, amount = pcall(function()
      return entity.amount
    end)
    return ok and (amount or 0) > 0
  end
  return true
end

local function missing_map(totals)
  local missing = {}
  for name, count in pairs(totals or {}) do
    if count > 0 then
      missing[util.item_key(name, "normal")] = {
        name = name,
        quality = "normal",
        count = count
      }
    end
  end
  return missing
end

local function remaining_ammo_need(bot, totals)
  local remain = {}
  for name, count in pairs(totals or {}) do
    local short = count - bot_item_count(bot, name)
    if short > 0 then
      remain[name] = short
    end
  end
  return remain
end

local function craft_into_bot(player, bot, state, totals, origin)
  local remain = remaining_ammo_need(bot, totals)
  if not next(remain) then
    return {action = "produced", produced = false, reports = {}}
  end
  -- 维护采集以 Bot 为中心，避免切模式时玩家站得太远。
  local from = (bot and bot.valid and bot.position) or origin
  local result = craft.try_fulfill(player, bot, missing_map(remain), from, {include_player = false})
  if result.action == "move" and result.target then
    state.mine_target = result.ore or state.mine_target
    builder.move_bot(bot, result.target)
    return result
  end
  return result
end

local function go_mine_for_item(player, bot, state, item_name, origin, depth)
  depth = depth or 0
  if depth > 6 or not item_name then
    return false
  end
  local from = (bot and bot.valid and bot.position) or origin
  local target
  if item_name == "wood" then
    target = craft.find_nearest_tree(player.surface, from)
  elseif craft.is_raw_resource(item_name) or item_name == "stone" then
    target = craft.find_nearest_resource(player.surface, from, item_name)
  else
    local recipe = craft.find_recipe(player.force, item_name)
    if recipe then
      for _, ing in pairs(recipe.ingredients or {}) do
        if (ing.type == "item" or not ing.type) and (craft.is_raw_resource(ing.name) or ing.name == "stone" or ing.name == "wood") then
          if ing.name == "wood" then
            target = craft.find_nearest_tree(player.surface, from)
          else
            target = craft.find_nearest_resource(player.surface, from, ing.name)
          end
          if target then
            break
          end
        end
      end
      if not target then
        for _, ing in pairs(recipe.ingredients or {}) do
          if ing.type == "item" or not ing.type then
            if go_mine_for_item(player, bot, state, ing.name, origin, depth + 1) then
              return true
            end
          end
        end
      end
    else
      target = craft.find_nearest_resource(player.surface, from, item_name)
    end
  end
  if target and target.valid then
    state.mine_target = target
    builder.move_bot(bot, target.position)
    return true
  end
  return false
end

local function follow_locked(bot, state)
  if locked_ok(state.mine_target) then
    builder.move_bot(bot, state.mine_target.position)
    if util.distance(bot.position, state.mine_target.position) > 6 then
      return true
    end
    state.mine_target = nil
  end
  return false
end

local function sort_jobs_by_distance(jobs, from)
  table.sort(jobs, function(a, b)
    if not (a.turret and a.turret.valid) then
      return false
    end
    if not (b.turret and b.turret.valid) then
      return true
    end
    return util.distance(from, a.turret.position) < util.distance(from, b.turret.position)
  end)
end

local function next_ammo_job(jobs, from)
  sort_jobs_by_distance(jobs, from)
  for _, job in ipairs(jobs) do
    if job.turret and job.turret.valid and job.need > 0 then
      return job
    end
  end
  return nil
end

local function sort_repair_jobs(jobs, from)
  table.sort(jobs, function(a, b)
    if not (a.entity and a.entity.valid) then
      return false
    end
    if not (b.entity and b.entity.valid) then
      return true
    end
    return util.distance(from, a.entity.position) < util.distance(from, b.entity.position)
  end)
end

local function next_repair_job(jobs, from)
  sort_repair_jobs(jobs, from)
  for _, job in ipairs(jobs) do
    if job.entity and job.entity.valid then
      if job.kind == "ghost" or is_damaged(job.entity) then
        return job
      end
    end
  end
  return nil
end

local function insert_ammo(turret, ammo_name, count)
  local _, inv = turret_ammo_count(turret, ammo_name)
  if inv then
    return inv.insert({name = ammo_name, count = count}) or 0
  end
  return turret.insert({name = ammo_name, count = count}) or 0
end

local function tick_ammo(player, bot, state, origin, teammates)
  local jobs, totals = maintain.collect_ammo_jobs(bot, state, teammates)
  if #jobs == 0 then
    state.ammo_plan = nil
    return false
  end
  state.ammo_plan = {jobs = jobs, totals = totals}

  if follow_locked(bot, state) then
    return true
  end

  local remain = remaining_ammo_need(bot, totals)
  if next(remain) then
    local result = craft_into_bot(player, bot, state, totals, origin)
    if result.action == "move" then
      if not state.announced then
        state.announced = true
        player.print({"ai-bot.maintain-ammo-plan"})
        for name, count in pairs(remain) do
          player.print({
            "ai-bot.maintain-need-ammo",
            prototypes.item[name] and prototypes.item[name].localised_name or name,
            tostring(count)
          })
        end
        craft.announce(player, result)
      end
      return true
    end
    if result.produced then
      craft.announce(player, result)
      return true
    end
    -- 补弹暂时做不了（缺矿/配方），不要占住循环导致维修永远不跑。
  end

  -- 弹药一次备齐后再按由近到远补完，不再中途回头采矿。
  local job = next_ammo_job(jobs, bot.position)
  if not job then
    state.ammo_plan = nil
    state.announced = false
    return false
  end
  local have = bot_item_count(bot, job.ammo)
  local give = math.min(job.need, have)
  if give <= 0 then
    -- 手里没弹药，先去维修，避免空站在炮塔前。
    state.announced = false
    return false
  end
  if util.distance(bot.position, job.turret.position) > 8 then
    builder.move_bot(bot, job.turret.position)
    return true
  end
  give = take_from_bot(bot, job.ammo, give)
  local inserted = insert_ammo(job.turret, job.ammo, give)
  if inserted < give then
    give_to_bot(bot, job.ammo, give - inserted)
  end
  if inserted > 0 then
    state.ammo_done = (state.ammo_done or 0) + 1
  end
  return true
end

local function tick_repair(player, bot, state, origin, teammates)
  if state.repair == false then
    state.repair_plan = nil
    return false
  end
  local jobs, totals = maintain.collect_repair_jobs(bot, origin, teammates)
  if #jobs == 0 then
    state.repair_plan = nil
    return false
  end
  state.repair_plan = {jobs = jobs, totals = totals}

  local job = next_repair_job(jobs, bot.position)
  if not job then
    state.repair_plan = nil
    return false
  end
  if util.distance(bot.position, job.entity.position) > 8 then
    builder.move_bot(bot, job.entity.position)
    return true
  end
  -- 掉血直接回满，不消耗整块建筑。
  job.entity.health = job.entity.max_health
  state.repair_done = (state.repair_done or 0) + 1
  return true
end

local function say_summary(player, state)
  local ammo = state.ammo_done or 0
  local repaired = state.repair_done or 0
  if ammo <= 0 and repaired <= 0 then
    return
  end
  if not state.last_summary_tick or game.tick - state.last_summary_tick > 600 then
    player.print({"ai-bot.maintain-summary", tostring(ammo), tostring(repaired)})
    state.last_summary_tick = game.tick
    state.ammo_done = 0
    state.repair_done = 0
  end
end

function maintain.tick(player, bot, teammates)
  if not util.valid_entity(bot) then
    return
  end
  local state = maintain.ensure_rules(bot.unit_number)
  if state.mode ~= "maintain" or state.paused then
    return
  end
  if state.recalling then
    return
  end
  local origin = search_origin(player, state, bot)
  teammates = teammates or maintain.list_mode_bots(player, "maintain")

  -- 补弹优先于维修：先一次备齐自己认领的弹药，再沿路补完。
  if tick_ammo(player, bot, state, origin, teammates) then
    state.current_repair = nil
    say_summary(player, state)
    return
  end
  state.current_turret = nil
  if tick_repair(player, bot, state, origin, teammates) then
    say_summary(player, state)
    return
  end
  say_summary(player, state)
  state.announced = false
  state.mine_target = nil
end

return maintain
