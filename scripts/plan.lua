-- 规划模式：不进地图编辑器。玩家照常走动，世界实体冻结，放下的建筑立刻变成幽灵。
local util = require("scripts.util")
local inventory = require("scripts.inventory")
local builder = require("scripts.builder")

local plan = {}

local SKIP_FREEZE_TYPES = {
  ["character"] = true,
  ["entity-ghost"] = true,
  ["tile-ghost"] = true,
  ["item-entity"] = true,
  ["highlight-box"] = true,
  ["speech-bubble"] = true,
  ["flying-text"] = true,
  ["particle"] = true,
  ["leaf-particle"] = true,
  ["spider-vehicle"] = true
}

local function store_of(player)
  storage.players = storage.players or {}
  storage.players[player.index] = storage.players[player.index] or {}
  local store = storage.players[player.index]
  store.queue = store.queue or {}
  return store
end

function plan.any_planning()
  for _, player in pairs(game.connected_players) do
    local store = storage.players and storage.players[player.index]
    if store and store.planning then
      return true
    end
  end
  return false
end

function plan.is_on(player)
  return store_of(player).planning == true
end

local function freeze_world(on)
  storage.plan_frozen = storage.plan_frozen or {}
  if on then
    if storage.plan_world_frozen then
      return
    end
    storage.plan_world_frozen = true
    storage.plan_frozen = {}
    for _, surface in pairs(game.surfaces) do
      for _, entity in pairs(surface.find_entities()) do
        if entity.valid and entity.active and not SKIP_FREEZE_TYPES[entity.type] then
          entity.active = false
          table.insert(storage.plan_frozen, entity)
        end
      end
    end
  else
    if not storage.plan_world_frozen then
      return
    end
    for _, entity in pairs(storage.plan_frozen) do
      if entity.valid then
        entity.active = true
      end
    end
    storage.plan_frozen = {}
    storage.plan_world_frozen = false
  end
end

local function sync_world_freeze()
  freeze_world(plan.any_planning())
end

local function enter_god_view(player, store)
  if player.controller_type == defines.controllers.editor then
    pcall(function()
      player.toggle_map_editor()
    end)
  end
  if player.controller_type == defines.controllers.character and player.character and player.character.valid then
    store.plan_character = player.character
  end
  pcall(function()
    player.set_controller{type = defines.controllers.god}
  end)
end

local function leave_god_view(player, store)
  local character = store.plan_character
  store.plan_character = nil
  if player.controller_type == defines.controllers.editor then
    pcall(function()
      player.toggle_map_editor()
    end)
  end
  if character and character.valid then
    pcall(function()
      player.set_controller{type = defines.controllers.character, character = character}
    end)
  elseif player.controller_type == defines.controllers.god then
    pcall(function()
      player.create_character()
    end)
  end
end

function plan.set(player, enabled)
  local store = store_of(player)
  local want = enabled and true or false
  if store.planning == want then
    return
  end
  store.planning = want
  player.cheat_mode = want
  if want then
    enter_god_view(player, store)
  else
    store.plan_item = nil
    leave_god_view(player, store)
  end
  if player.set_shortcut_toggled then
    player.set_shortcut_toggled("ai-bot-toggle-plan", want)
  end
  sync_world_freeze()
  if want then
    player.print({"ai-bot.plan-on"})
  else
    player.print({"ai-bot.plan-off"})
  end
end

function plan.toggle(player)
  plan.set(player, not plan.is_on(player))
end

function plan.sync_from_editor(_player)
  -- 规划不再使用地图编辑器。
end

function plan.on_player_left(player)
  if plan.is_on(player) then
    plan.set(player, false)
  end
end

-- 规划时放下的实体立刻改成幽灵，不扣材料。
function plan.convert_built_to_ghost(player, entity)
  if not plan.is_on(player) or not entity or not entity.valid then
    return false
  end
  if entity.type == "entity-ghost" or entity.type == "tile-ghost" then
    return true
  end
  if entity.name == "ai-structure-bot" or entity.type == "spider-vehicle" then
    return false
  end
  local proto = entity.prototype
  if not proto or not util.item_place_name(proto) then
    return false
  end
  local surface = entity.surface
  local info = {
    name = entity.name,
    position = entity.position,
    direction = entity.direction,
    force = entity.force,
    quality = entity.quality and entity.quality.name or nil,
    mirror = entity.mirroring
  }
  entity.destroy({raise_destroy = false})
  local ghost = surface.create_entity{
    name = "entity-ghost",
    inner_name = info.name,
    position = info.position,
    direction = info.direction,
    force = info.force,
    quality = info.quality,
    create_build_effect_smoke = false,
    raise_built = false
  }
  if ghost and ghost.valid and info.mirror then
    ghost.mirroring = true
  end
  return ghost and ghost.valid
end

function plan.convert_tiles_to_ghosts(player, event)
  if not plan.is_on(player) then
    return
  end
  local surface = game.surfaces[event.surface_index]
  if not surface then
    return
  end
  local tile_name = event.tile and event.tile.name
  if not tile_name then
    return
  end
  for _, old in pairs(event.tiles or {}) do
    local pos = old.position
    surface.set_tiles({{name = old.old_tile.name, position = pos}}, true, false, false)
    surface.create_entity{
      name = "tile-ghost",
      inner_name = tile_name,
      position = pos,
      force = player.force,
      create_build_effect_smoke = false,
      raise_built = false
    }
  end
end

local function ghost_cost(ghost)
  local proto = ghost.ghost_prototype
  local item_name = util.item_place_name(proto)
  if not item_name then
    return nil
  end
  return {
    name = item_name,
    quality = util.quality_name(ghost.quality),
    count = 1
  }
end

function plan.collect_ghosts(player, radius)
  local origin = player.position
  if player.character and player.character.valid then
    origin = player.character.position
  end
  local ghosts
  if radius then
    ghosts = player.surface.find_entities_filtered{
      force = player.force,
      position = origin,
      radius = radius,
      type = {"entity-ghost", "tile-ghost"}
    }
  else
    -- 规划往往飞到远处摆，默认收当前表面上该势力的全部幽灵。
    ghosts = player.surface.find_entities_filtered{
      force = player.force,
      type = {"entity-ghost", "tile-ghost"}
    }
  end
  local kept = {}
  local cost = {}
  local min_x, min_y, max_x, max_y
  for _, ghost in pairs(ghosts) do
    if ghost.valid then
      table.insert(kept, ghost)
      local item = ghost_cost(ghost)
      if item then
        util.add_count(cost, item.name, item.quality, item.count)
      end
      local x, y = ghost.position.x, ghost.position.y
      min_x = math.min(min_x or x, x)
      min_y = math.min(min_y or y, y)
      max_x = math.max(max_x or x, x)
      max_y = math.max(max_y or y, y)
    end
  end
  return kept, cost, {
    x = ((min_x or player.position.x) + (max_x or player.position.x)) / 2,
    y = ((min_y or player.position.y) + (max_y or player.position.y)) / 2
  }
end

local function clear_bot_orders(bot)
  if not bot or not bot.valid then
    return
  end
  pcall(function()
    bot.stop_spider()
  end)
  bot.autopilot_destination = nil
  inventory.clear_bot_requests(bot)
end

function plan.stop_assign(player)
  local store = store_of(player)
  if #store.queue == 0 and store.enabled == false then
    return false
  end
  -- 只取消派工，地上剩余幽灵保留。
  store.queue = {}
  store.enabled = false
  store.last_status = "idle"
  store.last_wait_reasons = {}
  local bot
  if store.assigned_bot then
    bot = game.get_entity_by_unit_number(store.assigned_bot)
  end
  clear_bot_orders(bot)
  player.print({"ai-bot.job-stopped"})
  return true
end

function plan.has_job(player)
  local store = store_of(player)
  return store.queue and #store.queue > 0 and store.enabled
end

function plan.toggle_assign(player, radius)
  if plan.has_job(player) then
    plan.stop_assign(player)
    return
  end
  plan.assign_nearby(player, radius)
end

function plan.assign_nearby(player, radius)
  if plan.is_on(player) then
    plan.set(player, false)
  end
  local ghosts, cost, center = plan.collect_ghosts(player, radius)
  if #ghosts == 0 then
    player.print({"ai-bot.no-ghosts"})
    return
  end
  local store = store_of(player)
  store.next_id = (store.next_id or 0) + 1
  local job = {
    id = store.next_id,
    name = "plan-" .. tostring(#ghosts),
    export = nil,
    cost = cost,
    position = center,
    direction = defines.direction.north,
    status = "queued",
    placed = true,
    ghosts = ghosts,
    expected_count = #ghosts,
    built_count = 0,
    entity_built = 0,
    tile_built = 0,
    tick = game.tick
  }
  table.insert(store.queue, job)
  store.enabled = true
  store.planning = false
  -- 旧存档可能关着「从背包取货」，派工时打开，否则材料在身上 Bot 也不动。
  local player_settings = settings.get_player_settings(player)
  if player_settings["ai-bot-take-from-player"] and player_settings["ai-bot-take-from-player"].value == false then
    player_settings["ai-bot-take-from-player"] = {value = true}
  end
  local bot = nil
  if store.assigned_bot then
    bot = game.get_entity_by_unit_number(store.assigned_bot)
  end
  if not (bot and bot.valid) then
    local bots = player.surface.find_entities_filtered{name = "ai-structure-bot", force = player.force, limit = 1}
    bot = bots[1]
    if bot then
      store.assigned_bot = bot.unit_number
    end
  end
  if bot and bot.valid then
    bot.active = true
    builder.move_bot(bot, center)
  end
  player.print({"ai-bot.job-assigned", tostring(#ghosts)})
  local have = inventory.scan_available(player, bot, false, true)
  local missing = inventory.diff(cost, have)
  if next(missing) then
    player.print({"ai-bot.wait-need-title"})
    for _, line in ipairs(inventory.list_missing(missing)) do
      player.print(line)
    end
  end
  return job
end

return plan
