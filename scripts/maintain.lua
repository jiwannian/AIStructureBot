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

local DEFAULT_FUEL_RULES = {
  ["stone-furnace"] = {fuel = "coal", min = 5, max = 50, enabled = true},
  ["steel-furnace"] = {fuel = "coal", min = 5, max = 50, enabled = true},
  ["boiler"] = {fuel = "coal", min = 5, max = 50, enabled = true}
}

local FUEL_MACHINE_TYPES = {
  furnace = true,
  boiler = true
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

local function add_category(cats, value)
  local key = category_name(value)
  if key then
    cats[key] = true
  end
end

local function turret_categories(proto)
  local cats = {}
  local params = proto and proto.attack_parameters
  if params then
    -- 2.0 机枪塔用单数 ammo_category = "bullet"
    add_category(cats, params.ammo_category)
    if params.ammo_categories then
      -- 可能是 {"bullet"}，也可能是 {bullet = true}
      for key, value in pairs(params.ammo_categories) do
        if type(key) == "string" and value == true then
          cats[key] = true
        else
          add_category(cats, value)
          if type(key) == "string" then
            cats[key] = true
          end
        end
      end
    end
    if params.ammo_type then
      add_category(cats, params.ammo_type.category)
    end
  end
  add_category(cats, proto and proto.ammo_category)
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

local function burner_of(proto)
  return proto and proto.burner_prototype or nil
end

local function fuel_categories_of(proto)
  local cats = {}
  local burner = burner_of(proto)
  local raw = burner and burner.fuel_categories
  if raw then
    for key, allowed in pairs(raw) do
      if allowed then
        local name = category_name(key)
        if type(key) == "string" and allowed == true then
          name = key
        end
        if name then
          cats[name] = true
        end
      elseif type(key) == "number" then
        local name = category_name(allowed)
        if name then
          cats[name] = true
        end
      end
    end
  end
  if not next(cats) then
    cats.chemical = true
  end
  return cats
end

function maintain.compatible_fuel(machine_name)
  local proto = prototypes.entity[machine_name]
  local cats = fuel_categories_of(proto)
  local items = {}
  for name, item in pairs(prototypes.item) do
    local cat = category_name(item.fuel_category)
    if cat and cats[cat] and not item.hidden then
      table.insert(items, name)
    end
  end
  table.sort(items)
  return items
end

function maintain.fuel_machine_names()
  local names = {}
  for name, proto in pairs(prototypes.entity) do
    if FUEL_MACHINE_TYPES[proto.type] and not proto.hidden then
      local burner = burner_of(proto)
      if DEFAULT_FUEL_RULES[name] or (burner and (burner.fuel_inventory_size or 0) > 0) then
        table.insert(names, name)
      end
    end
  end
  table.sort(names)
  return names
end

function maintain.default_fuel_rule(machine_name)
  local proto = prototypes.entity[machine_name]
  local burner = burner_of(proto)
  if not burner or (burner.fuel_inventory_size or 0) <= 0 then
    local preset = DEFAULT_FUEL_RULES[machine_name] or {}
    return {
      enabled = false,
      fuel = nil,
      min = preset.min or 5,
      max = preset.max or 50
    }
  end
  local fuel_list = maintain.compatible_fuel(machine_name)
  local preset = DEFAULT_FUEL_RULES[machine_name] or {}
  local fuel = preset.fuel or "coal"
  if fuel and not prototypes.item[fuel] then
    fuel = nil
  end
  if fuel then
    local ok = false
    for _, name in ipairs(fuel_list) do
      if name == fuel then
        ok = true
        break
      end
    end
    if not ok then
      fuel = nil
    end
  end
  if not fuel then
    for _, name in ipairs(fuel_list) do
      if name == "coal" then
        fuel = name
        break
      end
    end
    fuel = fuel or fuel_list[1]
  end
  return {
    enabled = preset.enabled ~= false and fuel ~= nil,
    fuel = fuel,
    min = preset.min or 5,
    max = preset.max or 50
  }
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
    if not ok and #ammo_list > 0 then
      ammo = nil
    end
  end
  if not ammo then
    ammo = ammo_list[1]
  end
  -- 类别解析失败时，机枪塔仍用黄弹，不要把规则建成无弹药。
  ammo = ammo or preset.ammo
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
  local bots = {}
  for _, bot in ipairs(inventory.list_force_bots(player)) do
    if bot.valid and bot.surface == player.surface then
      table.insert(bots, bot)
    end
  end
  return bots
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

function maintain.player_presets(player)
  storage.players = storage.players or {}
  local index = player and player.valid and player.index or 1
  storage.players[index] = storage.players[index] or {}
  local store = storage.players[index]
  store.maintain = store.maintain or {repair = true, rules = {}, fuel_rules = {}}
  store.maintain.rules = store.maintain.rules or {}
  store.maintain.fuel_rules = store.maintain.fuel_rules or {}
  return store.maintain
end

local function copy_rule(src)
  if not src then
    return nil
  end
  return {
    enabled = src.enabled,
    ammo = src.ammo,
    fuel = src.fuel,
    min = src.min,
    max = src.max
  }
end

local function merge_ammo_rule(existing, fallback)
  local base = copy_rule(fallback) or {}
  if not existing then
    return base
  end
  if existing.enabled ~= nil then
    base.enabled = existing.enabled
  end
  if existing.ammo then
    base.ammo = existing.ammo
  end
  if existing.min ~= nil then
    base.min = existing.min
  end
  if existing.max ~= nil then
    base.max = existing.max
  end
  return base
end

local function merge_fuel_rule(existing, fallback)
  local base = copy_rule(fallback) or {}
  if not existing then
    return base
  end
  if existing.enabled ~= nil then
    base.enabled = existing.enabled
  end
  if existing.fuel then
    base.fuel = existing.fuel
  end
  if existing.min ~= nil then
    base.min = existing.min
  end
  if existing.max ~= nil then
    base.max = existing.max
  end
  return base
end

function maintain.set_mode(unit_number, mode, origin)
  local state = maintain.get_bot_state(unit_number)
  state.mode = mode
  state.announced = false
  state.current_turret = nil
  state.current_repair = nil
  state.current_machine = nil
  state.mine_target = nil
  state.ammo_plan = nil
  state.fuel_plan = nil
  state.repair_plan = nil
  state.search_origin = origin
  return state
end

function maintain.ensure_rules(unit_number, player)
  local state = maintain.get_bot_state(unit_number)
  local presets = maintain.player_presets(player)
  state.rules = state.rules or {}
  state.fuel_rules = state.fuel_rules or {}
  if presets.repair ~= nil then
    state.repair = presets.repair
  elseif state.repair ~= nil then
    presets.repair = state.repair
  end
  for _, name in ipairs(maintain.ammo_turret_names()) do
    local fallback = maintain.default_rule(name)
    -- 玩家预设优先；没有预设时沿用这只 Bot 已有规则，避免重启后被默认值盖掉。
    local saved = presets.rules[name] or state.rules[name]
    local rule = merge_ammo_rule(saved, fallback)
    -- 只补缺的弹药种类，不覆盖已保存的上下限。
    if not rule.ammo then
      rule.ammo = fallback.ammo
    end
    state.rules[name] = rule
    if not presets.rules[name] then
      presets.rules[name] = copy_rule(rule)
    end
  end
  for _, name in ipairs(maintain.fuel_machine_names()) do
    local fallback = maintain.default_fuel_rule(name)
    local saved = presets.fuel_rules[name] or state.fuel_rules[name]
    local rule = merge_fuel_rule(saved, fallback)
    if not rule.fuel then
      rule.fuel = fallback.fuel
    end
    state.fuel_rules[name] = rule
    if not presets.fuel_rules[name] then
      presets.fuel_rules[name] = copy_rule(rule)
    end
  end
  return state
end

function maintain.update_rule(unit_number, turret_name, field, value, player)
  local state = maintain.ensure_rules(unit_number, player)
  local presets = maintain.player_presets(player)
  if field == "repair" then
    state.repair = value and true or false
    presets.repair = state.repair
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
  presets.rules[turret_name] = copy_rule(rule)
  return rule
end

function maintain.update_fuel_rule(unit_number, machine_name, field, value, player)
  local state = maintain.ensure_rules(unit_number, player)
  local presets = maintain.player_presets(player)
  local rule = state.fuel_rules[machine_name]
  if not rule then
    return nil
  end
  if field == "enabled" then
    rule.enabled = value and true or false
  elseif field == "fuel" then
    rule.fuel = value
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
  presets.fuel_rules[machine_name] = copy_rule(rule)
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

local function turret_ammo_total(turret)
  return select(1, turret_ammo_count(turret, nil))
end

local function ammo_needs_refill(total, wanted, rule, locked)
  wanted = wanted or 0
  local other = math.max(0, (total or 0) - wanted)
  local cap = math.max(rule.min or 0, rule.max or rule.min or 0)
  if cap <= 0 or (total or 0) >= cap then
    return false, cap, 0
  end
  if (total or 0) <= (rule.min or 0) or locked then
    -- 类型不对时先销毁旧弹，再按上限补指定弹药。
    return true, cap, cap - wanted
  end
  return false, cap, 0
end

local DEFAULT_JOB_RADIUS = 256
local SCAN_SNAP = 32
local SCAN_CACHE_TICKS = 300

function maintain.cached_entities(surface, force, origin, radius, types, kind)
  if not surface or not force or not origin then
    return {}
  end
  storage.maintain_scan = storage.maintain_scan or {}
  local key = table.concat({
    tostring(surface.index or surface.name),
    tostring(force.index or force.name),
    tostring(radius or DEFAULT_JOB_RADIUS),
    tostring(kind or "all")
  }, "|")
  local cache = storage.maintain_scan[key]
  if cache and cache.tick and game.tick - cache.tick < SCAN_CACHE_TICKS and cache.origin then
    local moved = util.distance(cache.origin, origin)
    if moved < SCAN_SNAP then
      local kept = {}
      for _, entity in pairs(cache.entities or {}) do
        if entity.valid then
          table.insert(kept, entity)
        end
      end
      cache.entities = kept
      return kept
    end
  end
  local found = surface.find_entities_filtered{
    force = force,
    position = origin,
    radius = radius or DEFAULT_JOB_RADIUS,
    type = types
  } or {}
  storage.maintain_scan[key] = {
    tick = game.tick,
    origin = {x = origin.x, y = origin.y},
    entities = found
  }
  return found
end

-- 名称对不上时按类型套默认规则（机枪塔变体）。
local function ammo_rule_for(state, turret)
  if not state or not turret then
    return nil
  end
  local rules = state.rules or {}
  local rule = rules[turret.name]
  if rule and rule.ammo then
    return rule
  end
  if turret.type == "artillery-turret" then
    return rules["artillery-turret"]
  end
  if turret.type == "ammo-turret" then
    return rules["gun-turret"]
  end
  return rule
end

function maintain.collect_ammo_jobs(bot, state, teammates, origin, radius)
  origin = origin or (bot and bot.valid and bot.position)
  radius = radius or DEFAULT_JOB_RADIUS
  if not origin or not bot or not bot.valid then
    return {}, {}
  end
  local turrets = maintain.cached_entities(
    bot.surface,
    bot.force,
    origin,
    radius,
    {"ammo-turret", "artillery-turret"},
    "ammo"
  )
  local jobs = {}
  local totals = {}
  for _, turret in pairs(turrets) do
    if turret.valid then
      local rule = ammo_rule_for(state, turret)
      if rule and rule.enabled and rule.ammo and (rule.min or 0) > 0 then
        local wanted = turret_ammo_count(turret, rule.ammo)
        local total = turret_ammo_total(turret)
        local locked = state.current_turret and state.current_turret.valid and state.current_turret.unit_number == turret.unit_number
        local below, cap, need = ammo_needs_refill(total, wanted, rule, locked)
        if below then
          local closer = closer_teammate(bot, teammates, turret.position)
          if not closer or locked then
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
        local rule = ammo_rule_for(state, turret)
        if rule and rule.enabled and rule.ammo and (rule.min or 0) > 0 then
          local wanted = turret_ammo_count(turret, rule.ammo)
          local total = turret_ammo_total(turret)
          local below, cap, need = ammo_needs_refill(total, wanted, rule, false)
          if below then
            local dist = util.distance(bot.position, turret.position)
            if not best_dist or dist < best_dist then
              best = turret
              best_need = need
              best_dist = dist
            end
          end
        end
      end
    end
    if best then
      local rule = ammo_rule_for(state, best)
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

local URGENT_FUEL_RADIUS = 48

local function machine_fuel_count(entity, fuel_name)
  if not entity or not entity.valid then
    return 0, nil
  end
  local inv = entity.get_inventory(defines.inventory.fuel)
  if not inv then
    return 0, nil
  end
  if fuel_name then
    return util.count_item(inv, fuel_name), inv
  end
  local total = 0
  for _, stack in pairs(inv.get_contents() or {}) do
    total = total + (stack.count or 0)
  end
  return total, inv
end

local function machine_fuel_inventory(machine)
  if not machine or not machine.valid then
    return nil
  end
  local ok, inv = pcall(function()
    return machine.get_inventory(defines.inventory.fuel)
  end)
  if ok and inv then
    return inv
  end
  return nil
end

-- 名称对不上时按类型套默认规则（钢炉变体）。没有燃料槽的电炉不补煤。
local function fuel_rule_for(state, machine)
  if not state or not machine then
    return nil
  end
  if not machine_fuel_inventory(machine) then
    return nil
  end
  local rules = state.fuel_rules or {}
  local rule = rules[machine.name]
  if rule then
    return rule
  end
  if machine.type == "boiler" then
    return rules["boiler"]
  end
  if machine.type == "furnace" then
    return rules["steel-furnace"] or rules["stone-furnace"]
  end
  return nil
end

function maintain.collect_fuel_jobs(bot, state, teammates, origin, radius)
  origin = origin or (bot and bot.valid and bot.position)
  radius = radius or DEFAULT_JOB_RADIUS
  if not origin or not bot or not bot.valid then
    return {}, {}
  end
  local machines = maintain.cached_entities(
    bot.surface,
    bot.force,
    origin,
    radius,
    {"furnace", "boiler"},
    "fuel"
  )
  local jobs = {}
  local totals = {}
  for _, machine in pairs(machines) do
    if machine.valid then
      local rule = fuel_rule_for(state, machine)
      if rule and rule.enabled and rule.fuel and (rule.min or 0) > 0 then
        local count, inv = machine_fuel_count(machine, rule.fuel)
        if not inv then
          -- 电炉等没有燃料槽，不能当缺煤任务。
        else
          local cap = math.max(rule.min, rule.max or rule.min)
          local locked = state.current_machine and state.current_machine.valid and state.current_machine.unit_number == machine.unit_number
          local below = count < cap and (count <= rule.min or locked)
          if below then
            local need = math.max(0, cap - count)
            local closer = closer_teammate(bot, teammates, machine.position)
            if not closer or locked then
              table.insert(jobs, {
                machine = machine,
                fuel = rule.fuel,
                cap = cap,
                need = need
              })
              totals[rule.fuel] = (totals[rule.fuel] or 0) + need
            end
          end
        end
      end
    end
  end
  if #jobs == 0 and teammates and #teammates > 1 then
    local best, best_need, best_dist
    for _, machine in pairs(machines) do
      if machine.valid then
        local rule = fuel_rule_for(state, machine)
        if rule and rule.enabled and rule.fuel and (rule.min or 0) > 0 then
          local count, inv = machine_fuel_count(machine, rule.fuel)
          if inv then
            local cap = math.max(rule.min, rule.max or rule.min)
            if count < cap and count <= rule.min then
              local dist = util.distance(bot.position, machine.position)
              if not best_dist or dist < best_dist then
                best = machine
                best_need = math.max(0, cap - count)
                best_dist = dist
              end
            end
          end
        end
      end
    end
    if best then
      local rule = fuel_rule_for(state, best)
      table.insert(jobs, {
        machine = best,
        fuel = rule.fuel,
        cap = math.max(rule.min, rule.max or rule.min),
        need = best_need
      })
      totals[rule.fuel] = best_need
    end
  end
  return jobs, totals
end

function maintain.empty_ammo_job(bot, state, teammates, origin, radius)
  if not util.valid_entity(bot) then
    return nil
  end
  local jobs = select(1, maintain.collect_ammo_jobs(bot, state, teammates, origin, radius))
  local best
  for _, job in ipairs(jobs or {}) do
    if job.turret and job.turret.valid and job.need > 0 then
      local count = turret_ammo_total(job.turret)
      if count <= 0 then
        local dist = util.distance(bot.position, job.turret.position)
        if not best or dist < best.dist then
          best = {job = job, dist = dist}
        end
      end
    end
  end
  return best and best.job or nil
end

function maintain.urgent_fuel_job(bot, state, teammates, origin, radius)
  if not util.valid_entity(bot) then
    return nil
  end
  local jobs = select(1, maintain.collect_fuel_jobs(bot, state, teammates, origin, radius))
  local best
  for _, job in ipairs(jobs or {}) do
    if job.machine and job.machine.valid and job.need > 0 then
      local dist = util.distance(bot.position, job.machine.position)
      local have = 0
      local trunk = bot.get_inventory(defines.inventory.spider_trunk)
      if trunk then
        have = util.count_item(trunk, job.fuel)
      end
      local empty = false
      local count = machine_fuel_count(job.machine, job.fuel)
      empty = count <= 0
      -- 空炉优先，不受 48 格限制；手里有煤时只插队附近的炉。
      if empty or (dist <= URGENT_FUEL_RADIUS and have > 0) then
        if not best or (empty and not best.empty) or dist < best.dist then
          best = {job = job, dist = dist, have = have, empty = empty}
        end
      end
    end
  end
  return best and best.job or nil
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

function maintain.collect_repair_jobs(bot, origin, teammates, radius)
  -- 扫描以玩家为中心，范围由设置页「任务搜索半径」决定。
  -- 只有一只维护 Bot 时拿下全部任务；多只时谁近谁修。
  local from = origin or (bot and bot.valid and bot.position)
  radius = radius or DEFAULT_JOB_RADIUS
  if not from or not bot or not bot.valid then
    return {}, {}
  end
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

  -- 只修还在的掉血建筑，不碰规划幽灵。结果缓存，避免走动时每拍重扫工厂。
  local found = maintain.cached_entities(bot.surface, bot.force, from, radius, REPAIR_TYPES, "repair")
  for _, entity in pairs(found) do
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
    for _, entity in pairs(found) do
      if is_damaged(entity) then
        help_nearest(entity, "hp")
      end
    end
  end
  return jobs, totals
end

local function bot_item_count(player, bot, name)
  if player then
    return inventory.count_fleet_item(player, name)
  end
  if not util.valid_entity(bot) then
    return 0
  end
  return util.count_item(bot.get_inventory(defines.inventory.spider_trunk), name)
end

local function take_from_bot(player, bot, name, count)
  if player then
    return inventory.try_remove_from_fleet(player, name, "normal", count, bot)
  end
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

local function remaining_ammo_need(player, bot, totals)
  local remain = {}
  for name, count in pairs(totals or {}) do
    local short = count - bot_item_count(player, bot, name)
    if short > 0 then
      remain[name] = short
    end
  end
  return remain
end

local function craft_into_bot(player, bot, state, totals, origin)
  local remain = remaining_ammo_need(player, bot, totals)
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
  if not locked_ok(state.mine_target) then
    return false
  end
  builder.move_bot(bot, state.mine_target.position)
  return util.distance(bot.position, state.mine_target.position) > 6
end

local function locked_ammo_job(state, jobs)
  local locked = state.current_turret
  if not (locked and locked.valid) then
    return nil
  end
  for _, job in ipairs(jobs or {}) do
    if job.turret and job.turret.valid and job.turret.unit_number == locked.unit_number and job.need > 0 then
      return job
    end
  end
  return nil
end

local function locked_fuel_job(state, jobs)
  local locked = state.current_machine
  if not (locked and locked.valid) then
    return nil
  end
  for _, job in ipairs(jobs or {}) do
    if job.machine and job.machine.valid and job.machine.unit_number == locked.unit_number and job.need > 0 then
      return job
    end
  end
  return nil
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

local function sort_fuel_jobs(jobs, from)
  table.sort(jobs, function(a, b)
    if not (a.machine and a.machine.valid) then
      return false
    end
    if not (b.machine and b.machine.valid) then
      return true
    end
    return util.distance(from, a.machine.position) < util.distance(from, b.machine.position)
  end)
end

local function next_fuel_job(jobs, from)
  sort_fuel_jobs(jobs, from)
  for _, job in ipairs(jobs) do
    if job.machine and job.machine.valid and job.need > 0 then
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

local function clear_foreign_ammo(turret, wanted)
  local _, inv = turret_ammo_count(turret, nil)
  if not inv or not wanted then
    return 0
  end
  local removed = 0
  for i = 1, #inv do
    local stack = inv[i]
    if stack and stack.valid_for_read and stack.name ~= wanted then
      removed = removed + (stack.count or 0)
      stack.clear()
    end
  end
  return removed
end

local function tick_ammo(player, bot, state, origin, teammates, scan_from, scan_radius)
  local jobs, totals = maintain.collect_ammo_jobs(bot, state, teammates, scan_from, scan_radius)
  if #jobs == 0 then
    state.ammo_plan = nil
    state.current_turret = nil
    return false
  end
  state.ammo_plan = {jobs = jobs, totals = totals}
  local job = locked_ammo_job(state, jobs) or next_ammo_job(jobs, bot.position)
  if not job then
    state.ammo_plan = nil
    state.current_turret = nil
    state.announced = false
    return false
  end
  state.current_turret = job.turret

  local have = bot_item_count(player, bot, job.ammo)
  local give = math.min(job.need, have)
  if give > 0 then
    state.mine_target = nil
    if util.distance(bot.position, job.turret.position) > 6 then
      if maintain.urgent_fuel_job(bot, state, teammates, scan_from, scan_radius) then
        return false
      end
      builder.move_bot(bot, job.turret.position)
      return true
    end
    local dumped = clear_foreign_ammo(job.turret, job.ammo)
    if dumped > 0 then
      local wanted = turret_ammo_count(job.turret, job.ammo)
      job.need = math.max(0, job.cap - wanted)
      give = math.min(job.need, have)
      if not state.replace_announced then
        state.replace_announced = true
        player.print({"ai-bot.maintain-ammo-replace"})
      end
      if give <= 0 then
        return true
      end
    end
    give = take_from_bot(player, bot, job.ammo, give)
    local inserted = insert_ammo(job.turret, job.ammo, give)
    if inserted < give then
      give_to_bot(bot, job.ammo, give - inserted)
    end
    if inserted > 0 then
      state.ammo_done = (state.ammo_done or 0) + 1
      return true
    end
    -- 炮塔接不进这种弹，放开锁，去补煤/修墙。
    state.current_turret = nil
    state.announced = false
    return false
  end

  if maintain.urgent_fuel_job(bot, state, teammates, scan_from, scan_radius) then
    return false
  end

  -- 补弹时不要跟着补煤留下的煤矿走。
  if state.mine_target and state.mine_target.valid then
    local locked_name = state.mine_target.name
    if locked_name ~= job.ammo then
      local recipe = craft.find_recipe(player.force, job.ammo)
      local related = false
      if recipe then
        for _, ing in pairs(recipe.ingredients or {}) do
          if (ing.type == "item" or not ing.type) and ing.name == locked_name then
            related = true
            break
          end
        end
      end
      if not related and not craft.is_raw_resource(job.ammo) then
        state.mine_target = nil
      elseif craft.is_raw_resource(job.ammo) and locked_name ~= job.ammo then
        state.mine_target = nil
      end
    end
  end

  -- 先采/合成再走：蜘蛛常停在 6~8 格，follow_locked 会永远赶路、采不到。
  local remain = remaining_ammo_need(player, bot, {[job.ammo] = job.need})
  if next(remain) then
    local result = craft_into_bot(player, bot, state, remain, origin)
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
  end

  if follow_locked(bot, state) then
    return true
  end
  -- 这拍补不了弹，不要占住循环。
  state.announced = false
  return false
end

local function insert_fuel(machine, fuel_name, count)
  local _, inv = machine_fuel_count(machine, fuel_name)
  if inv then
    return inv.insert({name = fuel_name, count = count}) or 0
  end
  return machine.insert({name = fuel_name, count = count}) or 0
end

local function tick_fuel(player, bot, state, origin, teammates, scan_from, scan_radius)
  local jobs, totals = maintain.collect_fuel_jobs(bot, state, teammates, scan_from, scan_radius)
  if #jobs == 0 then
    state.fuel_plan = nil
    state.current_machine = nil
    return false
  end
  state.fuel_plan = {jobs = jobs, totals = totals}
  local job = locked_fuel_job(state, jobs) or next_fuel_job(jobs, bot.position)
  if not job then
    state.fuel_plan = nil
    state.current_machine = nil
    state.fuel_announced = false
    return false
  end
  state.current_machine = job.machine

  local have = bot_item_count(player, bot, job.fuel)
  local give = math.min(job.need, have)
  if give > 0 then
    state.mine_target = nil
    if util.distance(bot.position, job.machine.position) > 6 then
      builder.move_bot(bot, job.machine.position)
      return true
    end
    give = take_from_bot(player, bot, job.fuel, give)
    local inserted = insert_fuel(job.machine, job.fuel, give)
    if inserted < give then
      give_to_bot(bot, job.fuel, give - inserted)
    end
    if inserted > 0 then
      state.fuel_done = (state.fuel_done or 0) + 1
      return true
    end
    state.current_machine = nil
    state.fuel_announced = false
    return false
  end

  -- 补煤时不要跟着补弹留下的铁矿走。
  if state.mine_target and state.mine_target.valid then
    local locked_name = state.mine_target.name
    if locked_name ~= job.fuel and locked_name ~= "coal" then
      state.mine_target = nil
    end
  end

  -- 先采再走：蜘蛛常停在 6~8 格，follow_locked 会永远赶路、采不到。
  local fuel_name = job.fuel
  local got, next_pos, remain, next_ore = craft.mine_enough(bot, player, fuel_name, job.need, bot.position, false)
  if (got or 0) <= 0 and fuel_name ~= "coal" then
    got, next_pos, remain, next_ore = craft.mine_enough(bot, player, "coal", job.need, bot.position, false)
    if (got or 0) > 0 or next_ore then
      fuel_name = "coal"
    end
  end
  if (got or 0) > 0 then
    state.mine_target = nil
    return true
  end
  if next_ore and next_ore.valid then
    state.mine_target = next_ore
    builder.move_bot(bot, next_pos or next_ore.position)
    if not state.fuel_announced then
      state.fuel_announced = true
      player.print({"ai-bot.maintain-fuel-plan"})
      player.print({
        "ai-bot.maintain-need-fuel",
        prototypes.item[job.fuel] and prototypes.item[job.fuel].localised_name or job.fuel,
        tostring(job.need)
      })
    end
    return true
  end
  if follow_locked(bot, state) then
    return true
  end
  local ore = craft.find_nearest_resource(player.surface, bot.position, fuel_name)
  if (not ore) and fuel_name ~= "coal" then
    ore = craft.find_nearest_resource(player.surface, bot.position, "coal")
  end
  if ore and ore.valid then
    state.mine_target = ore
    builder.move_bot(bot, ore.position)
    if not state.fuel_announced then
      state.fuel_announced = true
      player.print({"ai-bot.maintain-fuel-plan"})
      player.print({
        "ai-bot.maintain-need-fuel",
        prototypes.item[job.fuel] and prototypes.item[job.fuel].localised_name or job.fuel,
        tostring(job.need)
      })
    end
    return true
  end

  local remain = remaining_ammo_need(player, bot, {[job.fuel] = job.need})
  if next(remain) then
    local result = craft_into_bot(player, bot, state, remain, origin)
    if result.action == "move" then
      if not state.fuel_announced then
        state.fuel_announced = true
        player.print({"ai-bot.maintain-fuel-plan"})
        for name, count in pairs(remain) do
          player.print({
            "ai-bot.maintain-need-fuel",
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
  end
  state.fuel_announced = false
  return false
end

local function tick_repair(player, bot, state, origin, teammates, scan_from, scan_radius)
  if state.repair == false then
    state.repair_plan = nil
    return false
  end
  local jobs, totals = maintain.collect_repair_jobs(bot, scan_from or origin, teammates, scan_radius)
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
  local fuel = state.fuel_done or 0
  local repaired = state.repair_done or 0
  if ammo <= 0 and fuel <= 0 and repaired <= 0 then
    return
  end
  if not state.last_summary_tick or game.tick - state.last_summary_tick > 600 then
    player.print({"ai-bot.maintain-summary", tostring(ammo), tostring(repaired), tostring(fuel)})
    state.last_summary_tick = game.tick
    state.ammo_done = 0
    state.fuel_done = 0
    state.repair_done = 0
  end
end

function maintain.tick(player, bot, teammates)
  if not util.valid_entity(bot) then
    return
  end
  local state = maintain.ensure_rules(bot.unit_number, player)
  if state.mode ~= "maintain" or state.paused then
    return
  end
  if state.recalling then
    return
  end
  local origin = search_origin(player, state, bot)
  local scan_from = util.player_origin(player)
  local scan_radius = util.job_radius(player)
  teammates = teammates or maintain.list_mode_bots(player, "maintain")

  -- 空炮塔优先于远处空炉，避免蜘蛛停在缺弹塔旁却去挖煤。
  local empty_turret = maintain.empty_ammo_job(bot, state, teammates, scan_from, scan_radius)
  if empty_turret then
    if tick_ammo(player, bot, state, origin, teammates, scan_from, scan_radius) then
      state.current_repair = nil
      say_summary(player, state)
      return
    end
  end

  -- 附近炉子空了或手里有煤时，插队补煤，避免被一座炮塔占死。
  local urgent_fuel = maintain.urgent_fuel_job(bot, state, teammates, scan_from, scan_radius)
  if urgent_fuel then
    state.current_turret = nil
    if tick_fuel(player, bot, state, origin, teammates, scan_from, scan_radius) then
      state.current_repair = nil
      say_summary(player, state)
      return
    end
  end

  -- 补弹优先，再补煤，最后维修。
  if tick_ammo(player, bot, state, origin, teammates, scan_from, scan_radius) then
    state.current_repair = nil
    say_summary(player, state)
    return
  end
  state.current_turret = nil
  if tick_fuel(player, bot, state, origin, teammates, scan_from, scan_radius) then
    state.current_repair = nil
    say_summary(player, state)
    return
  end
  if tick_repair(player, bot, state, origin, teammates, scan_from, scan_radius) then
    say_summary(player, state)
    return
  end
  say_summary(player, state)
  state.announced = false
  state.fuel_announced = false
  state.replace_announced = false
  state.current_turret = nil
  state.current_machine = nil
  state.mine_target = nil
  -- 没有活时停住，避免上一拍去炮塔的自动驾驶还在走。
  pcall(function()
    bot.stop_spider()
  end)
  bot.autopilot_destination = nil
end

return maintain
