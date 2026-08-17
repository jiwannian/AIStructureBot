-- 规划模式：不进地图编辑器。玩家照常走动，世界实体冻结，放下的建筑立刻变成幽灵。
local util = require("scripts.util")
local inventory = require("scripts.inventory")
local builder = require("scripts.builder")
local lineplan = require("scripts.lineplan")

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
  ["spider-vehicle"] = true,
  ["spider-leg"] = true
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

function plan.should_freeze_world()
  -- 单人：冻结全局，方便慢慢摆。多人：只让规划者进上帝视角，不冻别人的厂。
  if game.is_multiplayer() then
    return false
  end
  return plan.any_planning()
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

function plan.sync_world_freeze()
  freeze_world(plan.should_freeze_world())
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
  if want then
    enter_god_view(player, store)
    -- 上帝视角会打开作弊制作，进入后立刻关掉。
    player.cheat_mode = false
    store.craft_warned = false
    plan.cancel_all_crafting(player)
    pcall(function()
      player.opened = nil
    end)
  else
    store.plan_item = nil
    leave_god_view(player, store)
    player.cheat_mode = false
  end
  if player.set_shortcut_toggled then
    player.set_shortcut_toggled("ai-bot-toggle-plan", want)
  end
  plan.sync_world_freeze()
  if want then
    if game.is_multiplayer() then
      player.print({"ai-bot.plan-on-mp"})
    else
      player.print({"ai-bot.plan-on"})
    end
  else
    player.print({"ai-bot.plan-off"})
  end
end

function plan.toggle(player)
  plan.set(player, not plan.is_on(player))
end

function plan.cancel_all_crafting(player)
  local size = player.crafting_queue_size or 0
  for i = size, 1, -1 do
    pcall(function()
      player.cancel_crafting{index = i, count = 999999}
    end)
  end
end

function plan.block_crafting(player, event)
  if not plan.is_on(player) then
    return
  end
  local count = event.queued_count or event.cancel_count or 1
  local recipe = event.recipe
  local name = type(recipe) == "table" and recipe.name or recipe
  if not name then
    return
  end
  pcall(function()
    player.cancel_crafting{index = player.crafting_queue_size or 1, count = count}
  end)
  local store = store_of(player)
  if not store.craft_warned then
    store.craft_warned = true
    player.print({"ai-bot.plan-no-craft"})
  end
end

function plan.sync_from_editor(_player)
  -- 规划不再使用地图编辑器。
end

function plan.on_player_left(player)
  if plan.is_on(player) then
    plan.set(player, false)
  end
end

-- 地下传送带 / 地下管道需要等配对完成后再转幽灵，否则外观不会连通。
local PAIR_DELAY_TYPES = {
  ["underground-belt"] = true,
  ["pipe-to-ground"] = true,
  ["linked-belt"] = true
}

function plan.queue_or_convert(player, entity)
  if not plan.is_on(player) or not entity or not entity.valid then
    return false
  end
  if PAIR_DELAY_TYPES[entity.type] then
    storage.plan_pair_queue = storage.plan_pair_queue or {}
    table.insert(storage.plan_pair_queue, {
      entity = entity,
      player_index = player.index,
      tick = game.tick
    })
    return true
  end
  return plan.convert_built_to_ghost(player, entity)
end

function plan.block_controller_gui(player)
  if not player or not player.valid or not plan.is_on(player) then
    return
  end
  player.cheat_mode = false
  plan.cancel_all_crafting(player)
  local gui_type = player.opened_gui_type
  if gui_type == defines.gui_type.controller then
    pcall(function()
      player.opened = nil
    end)
    local store = store_of(player)
    if not store.craft_warned then
      store.craft_warned = true
      player.print({"ai-bot.plan-no-craft"})
    end
  end
end

function plan.flush_pair_queue()
  local queue = storage.plan_pair_queue
  if not queue or #queue == 0 then
    return
  end
  local keep = {}
  for _, item in ipairs(queue) do
    if not item.entity or not item.entity.valid then
      -- 已失效
    elseif game.tick - item.tick < 2 then
      table.insert(keep, item)
    else
      local player = game.get_player(item.player_index)
      if player and plan.is_on(player) then
        plan.convert_built_to_ghost(player, item.entity)
      end
    end
  end
  storage.plan_pair_queue = keep
end

-- 规划时放下的实体改成幽灵，不扣材料。地下带保留 input/output。
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
    mirror = entity.mirroring,
    belt_type = nil,
    linked_type = nil,
    recipe = nil,
    tags = entity.tags
  }
  pcall(function()
    local recipe = entity.get_recipe and entity.get_recipe()
    info.recipe = recipe and (recipe.name or recipe)
  end)
  if not info.recipe then
    local store = store_of(player)
    local stamp = store.lineplan_stamp
    if stamp and stamp.recipes and stamp.position then
      info.recipe = lineplan.recipe_at(stamp.recipes, stamp.position, info.position)
    end
  end
  pcall(function()
    info.belt_type = entity.belt_to_ground_type
  end)
  pcall(function()
    info.linked_type = entity.linked_belt_type
  end)
  entity.destroy({raise_destroy = false})
  local ghost = surface.create_entity{
    name = "entity-ghost",
    inner_name = info.name,
    position = info.position,
    direction = info.direction,
    force = info.force,
    quality = info.quality,
    type = info.belt_type,
    create_build_effect_smoke = false,
    raise_built = false
  }
  if ghost and ghost.valid then
    if info.mirror then
      ghost.mirroring = true
    end
    if info.linked_type then
      pcall(function()
        ghost.linked_belt_type = info.linked_type
      end)
    end
    if info.tags then
      pcall(function()
        ghost.tags = info.tags
      end)
    end
    if info.recipe then
      pcall(function()
        local tags = ghost.tags or {}
        tags.ai_recipe = info.recipe
        ghost.tags = tags
      end)
    end
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

local function is_marked(entity, force)
  if not entity or not entity.valid then
    return false
  end
  if entity.type == "entity-ghost" or entity.type == "tile-ghost" then
    return false
  end
  if entity.name == "ai-structure-bot" then
    return false
  end
  if entity.to_be_deconstructed then
    local ok, marked = pcall(function()
      return entity.to_be_deconstructed(force)
    end)
    if ok and marked then
      return true
    end
    ok, marked = pcall(function()
      return entity.to_be_deconstructed()
    end)
    return ok and marked
  end
  return false
end

function plan.collect_marked(player, radius)
  local origin = player.position
  if player.character and player.character.valid then
    origin = player.character.position
  end
  local candidates
  if radius then
    candidates = player.surface.find_entities_filtered{
      position = origin,
      radius = radius,
      to_be_deconstructed = true
    }
  else
    candidates = player.surface.find_entities_filtered{to_be_deconstructed = true}
  end
  local marked = {}
  for _, entity in pairs(candidates) do
    if is_marked(entity, player.force) then
      table.insert(marked, entity)
    end
  end
  return marked
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
    -- 不要扫全图：只收角色附近一片，避免把旧规划全塞进一单。
    ghosts = player.surface.find_entities_filtered{
      force = player.force,
      position = origin,
      radius = 80,
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
  for _, bot in ipairs(player.surface.find_entities_filtered{
    name = "ai-structure-bot",
    force = player.force
  }) do
    local bot_state = storage.bot_modes and storage.bot_modes[bot.unit_number]
    if not bot_state or bot_state.mode ~= "maintain" then
      clear_bot_orders(bot)
    end
  end
  player.print({"ai-bot.job-stopped"})
  return true
end

function plan.has_job(player)
  local store = store_of(player)
  return store.queue and #store.queue > 0 and store.enabled
end

local function player_anchor(player)
  if player.character and player.character.valid then
    return player.character.position, player.character.surface
  end
  return player.position, player.surface
end

function plan.get_bot(player)
  local store = store_of(player)
  local bot
  if store.assigned_bot then
    bot = game.get_entity_by_unit_number(store.assigned_bot)
  end
  if not (bot and bot.valid) then
    local bots = player.surface.find_entities_filtered{
      name = "ai-structure-bot",
      force = player.force,
      limit = 1
    }
    bot = bots[1]
    if bot then
      store.assigned_bot = bot.unit_number
    end
  end
  return bot
end

function plan.recall_bot(player)
  local store = store_of(player)
  local bot = plan.get_bot(player)
  if not bot or not bot.valid then
    player.print({"ai-bot.no-bot"})
    return
  end
  local state = storage.bot_modes and storage.bot_modes[bot.unit_number]
  if not state then
    state = {mode = "build"}
    storage.bot_modes = storage.bot_modes or {}
    storage.bot_modes[bot.unit_number] = state
  end
  if state.recalling then
    state.recalling = false
    store.recalling = false
    store.last_status = "idle"
    clear_bot_orders(bot)
    player.print({"ai-bot.recall-cancelled"})
    return
  end
  -- 只召回选中的这一只，不清队列、不停其他 Bot。
  state.recalling = true
  state.mine_target = nil
  store.recalling = true
  store.last_status = "recalling"
  clear_bot_orders(bot)
  local dest = player_anchor(player)
  builder.move_bot(bot, dest)
  player.print({"ai-bot.recall-started"})
end

function plan.tick_recall(player)
  local store = store_of(player)
  local any = false
  for _, bot in ipairs(player.surface.find_entities_filtered{
    name = "ai-structure-bot",
    force = player.force
  }) do
    local state = storage.bot_modes and storage.bot_modes[bot.unit_number]
    if state and state.recalling and bot.valid then
      any = true
      local dest, surface = player_anchor(player)
      if bot.surface ~= surface then
        pcall(function()
          bot.teleport(dest, surface)
        end)
      else
        builder.move_bot(bot, dest)
      end
      if util.distance(bot.position, dest) <= 6 then
        state.recalling = false
        clear_bot_orders(bot)
        player.print({"ai-bot.recall-arrived"})
      end
    end
  end
  store.recalling = any
  if not any and store.last_status == "recalling" then
    store.last_status = "idle"
  end
  return any
end

function plan.nudge_assign(player)
  local store = store_of(player)
  store.planning = false
  store.enabled = true
  local builders = {}
  for _, bot in ipairs(player.surface.find_entities_filtered{
    name = "ai-structure-bot",
    force = player.force
  }) do
    if bot.valid then
      storage.bot_modes = storage.bot_modes or {}
      local bot_state = storage.bot_modes[bot.unit_number] or {mode = "build"}
      storage.bot_modes[bot.unit_number] = bot_state
      if bot_state.mode ~= "maintain" then
        bot_state.paused = false
        bot_state.recalling = false
        builder.wake_bot(bot)
        table.insert(builders, bot)
      end
    end
  end
  if #builders == 0 then
    player.print({"ai-bot.no-build-bot"})
    return
  end
  local job = store.queue and store.queue[1]
  for _, bot in ipairs(builders) do
    local bot_state = storage.bot_modes[bot.unit_number]
    if bot_state and bot_state.mine_target and bot_state.mine_target.valid then
      builder.move_bot(bot, bot_state.mine_target.position)
    elseif job then
      local dest = builder.nearest_work_position(job, bot.position) or job.position
      if dest then
        builder.move_bot(bot, dest)
      end
    end
  end
end

function plan.toggle_assign(player, radius)
  -- Shift+B 只派工/催工，不再来回开关。停工请用菜单「停止派工」。
  if plan.has_job(player) then
    plan.nudge_assign(player)
    return
  end
  plan.assign_nearby(player, radius)
end

function plan.assign_nearby(player, radius)
  if plan.is_on(player) then
    plan.set(player, false)
  end
  local builders = {}
  for _, bot in ipairs(player.surface.find_entities_filtered{
    name = "ai-structure-bot",
    force = player.force
  }) do
    if bot.valid then
      storage.bot_modes = storage.bot_modes or {}
      local bot_state = storage.bot_modes[bot.unit_number] or {mode = "build"}
      storage.bot_modes[bot.unit_number] = bot_state
      if bot_state.mode ~= "maintain" then
        bot_state.paused = false
        bot_state.recalling = false
        bot.active = true
        table.insert(builders, bot)
      end
    end
  end
  if #builders == 0 then
    player.print({"ai-bot.no-build-bot"})
    return
  end
  -- 派工必须解冻世界，并唤醒蜘蛛腿；规划冻结会把腿冻住，只开身体不会走。
  plan.sync_world_freeze()
  local ghosts, cost, center = plan.collect_ghosts(player, radius)
  local marked = plan.collect_marked(player, radius)
  if #ghosts == 0 and #marked == 0 then
    player.print({"ai-bot.no-ghosts"})
    return
  end
  local store = store_of(player)
  store.next_id = (store.next_id or 0) + 1
  -- 记录规划区域，后续只认这一片幽灵，别把全图其他幽灵拖进来。
  local min_x, min_y, max_x, max_y
  for _, ghost in pairs(ghosts) do
    if ghost.valid then
      local x, y = ghost.position.x, ghost.position.y
      min_x = math.min(min_x or x, x)
      min_y = math.min(min_y or y, y)
      max_x = math.max(max_x or x, x)
      max_y = math.max(max_y or y, y)
    end
  end
  for _, entity in pairs(marked) do
    if entity.valid then
      local x, y = entity.position.x, entity.position.y
      min_x = math.min(min_x or x, x)
      min_y = math.min(min_y or y, y)
      max_x = math.max(max_x or x, x)
      max_y = math.max(max_y or y, y)
    end
  end
  if #ghosts == 0 and #marked > 0 then
    center = {x = ((min_x or 0) + (max_x or 0)) / 2, y = ((min_y or 0) + (max_y or 0)) / 2}
  end
  local job = {
    id = store.next_id,
    name = (#ghosts == 0 and #marked > 0)
      and ("decon-" .. tostring(#marked))
      or ("plan-" .. tostring(#ghosts)),
    export = nil,
    cost = cost,
    position = center,
    area = {
      left_top = {x = math.floor((min_x or 0) - 8), y = math.floor((min_y or 0) - 8)},
      right_bottom = {x = math.ceil((max_x or 0) + 8), y = math.ceil((max_y or 0) + 8)}
    },
    direction = defines.direction.north,
    status = "queued",
    placed = true,
    ghosts = ghosts,
    marked = marked,
    expected_count = #ghosts,
    built_count = 0,
    entity_built = 0,
    tile_built = 0,
    tick = game.tick,
    search_origin = (player.character and player.character.valid) and player.character.position or player.position
  }
  table.insert(store.queue, job)
  store.enabled = true
  store.planning = false
  -- 旧存档可能关着「从背包取货」，派工时打开，否则材料在身上 Bot 也不动。
  local player_settings = settings.get_player_settings(player)
  if player_settings["ai-bot-take-from-player"] and player_settings["ai-bot-take-from-player"].value == false then
    player_settings["ai-bot-take-from-player"] = {value = true}
  end
  -- 只派建造模式的 Bot 去工地，维护模式的一只都不动。
  for _, bot in ipairs(builders) do
    if bot.valid then
      builder.wake_bot(bot)
      builder.move_bot(bot, center)
    end
  end
  player.print({"ai-bot.job-assigned", tostring(#ghosts)})
  if #marked > 0 then
    player.print({"ai-bot.job-deconstruct", tostring(#marked)})
  end
  local have = inventory.scan_available(player, builders[1], false, true)
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
