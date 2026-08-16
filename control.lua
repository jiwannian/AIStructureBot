-- AI 建造机器人主入口。Factorio 2.0 使用 storage，不再使用 global。
local gui = require("scripts.gui")
local ai = require("scripts.ai")
local util = require("scripts.util")
local jobs = require("scripts.jobs")
local plan = require("scripts.plan")

local function ensure_storage()
  storage.players = storage.players or {}
end

local function unlock_force(force)
  if not force or not force.valid then
    return
  end
  local recipe = force.recipes["ai-structure-bot"]
  if recipe then
    recipe.enabled = true
  end
  local tech = force.technologies["ai-structure-bot"]
  if tech then
    tech.researched = true
  end
end

local function force_has_bot(force)
  for _, surface in pairs(game.surfaces) do
    local found = surface.find_entities_filtered{
      name = "ai-structure-bot",
      force = force,
      limit = 1
    }
    if found[1] then
      return true
    end
  end
  return false
end

local function grant_starter_bot(player)
  local store = gui.player_store(player)
  if store.starter_granted then
    return
  end
  if player.get_item_count("ai-structure-bot") > 0 or force_has_bot(player.force) then
    store.starter_granted = true
    return
  end
  player.insert({name = "ai-structure-bot", count = 1})
  store.starter_granted = true
  player.print({"ai-bot.starter-granted"})
end

local function init_player(player)
  if not player or not player.valid then
    return
  end
  unlock_force(player.force)
  gui.player_store(player)
  grant_starter_bot(player)
end

script.on_init(function()
  ensure_storage()
  for _, force in pairs(game.forces) do
    unlock_force(force)
  end
  for _, player in pairs(game.players) do
    init_player(player)
    player.print({"ai-bot.welcome"})
  end
end)

script.on_configuration_changed(function()
  ensure_storage()
  for _, force in pairs(game.forces) do
    unlock_force(force)
  end
  for _, player in pairs(game.players) do
    init_player(player)
  end
end)

script.on_event(defines.events.on_player_created, function(event)
  local player = game.get_player(event.player_index)
  init_player(player)
  if player then
    player.print({"ai-bot.welcome"})
  end
end)

script.on_event(defines.events.on_player_joined_game, function(event)
  local player = game.get_player(event.player_index)
  init_player(player)
end)

script.on_event(defines.events.on_player_removed, function(event)
  if storage.players then
    storage.players[event.player_index] = nil
  end
end)

script.on_event(defines.events.on_pre_player_left_game, function(event)
  local player = game.get_player(event.player_index)
  if player then
    plan.on_player_left(player)
  end
end)

-- 规划模式不再使用地图编辑器。

local function toggle_menu(player)
  if player then
    gui.toggle(player)
  end
end

script.on_event("ai-bot-toggle-menu", function(event)
  toggle_menu(game.get_player(event.player_index))
end)

script.on_event("ai-bot-close-menu", function(event)
  local player = game.get_player(event.player_index)
  if player and gui.player_store(player).menu_open then
    gui.close(player)
  end
end)

local function after_plan_toggle(player)
  if plan.is_on(player) then
    gui.open_planner(player)
  else
    gui.close_planner(player)
  end
  gui.refresh(player)
end

script.on_event("ai-bot-toggle-plan", function(event)
  local player = game.get_player(event.player_index)
  if player then
    plan.toggle(player)
    after_plan_toggle(player)
  end
end)

script.on_event("ai-bot-assign-ghosts", function(event)
  local player = game.get_player(event.player_index)
  if player then
    plan.toggle_assign(player)
    ai.tick_player(player)
    gui.refresh(player)
  end
end)

script.on_event(defines.events.on_lua_shortcut, function(event)
  local player = game.get_player(event.player_index)
  if event.prototype_name == "ai-bot-open-menu" then
    toggle_menu(player)
  elseif event.prototype_name == "ai-bot-toggle-plan" and player then
    plan.toggle(player)
    after_plan_toggle(player)
  end
end)

script.on_event(defines.events.on_gui_closed, function(event)
  local player = game.get_player(event.player_index)
  local element = event.element
  if player and element and element.valid and element.name == "ai_bot_frame" then
    gui.close(player)
  end
end)

script.on_event(defines.events.on_gui_click, function(event)
  local player = game.get_player(event.player_index)
  local element = event.element
  if not player or not element or not element.valid then
    return
  end
  if element.name == "ai_bot_close" then
    gui.close(player)
    return
  end
  if element.name == "ai_bot_plan" then
    plan.toggle(player)
    after_plan_toggle(player)
    return
  end
  if element.name == "ai_bot_plan_close" then
    gui.close_planner(player)
    return
  end
  if element.tags and element.tags.ai_bot_plan_item then
    gui.give_plan_item(player, element.tags.ai_bot_plan_item)
    return
  end
  if element.name == "ai_bot_build" then
    plan.toggle_assign(player)
    ai.tick_player(player)
    gui.refresh(player)
    return
  end
  if element.name == "ai_bot_toggle" then
    local store = gui.player_store(player)
    store.enabled = not store.enabled
    gui.refresh(player)
    return
  end
  if element.name == "ai_bot_assign" then
    if not util.give_temp_tool(player, "ai-bot-assign-tool") then
      player.print({"ai-bot.no-bot"})
    end
    return
  end
  if element.name == "ai_bot_save_cursor" then
    gui.save_cursor_blueprint(player)
    return
  end
  if element.name == "ai_bot_stamp" then
    gui.begin_stamp(player)
    return
  end
  if element.name == "ai_bot_delete_bp" then
    gui.delete_selected(player)
    return
  end
  if element.name == "ai_bot_cancel_job" then
    gui.cancel_current_job(player)
    return
  end
  if element.name == "ai_bot_skip_job" then
    gui.skip_current_job(player)
    return
  end
  if element.name == "ai_bot_save_settings" then
    local frame = player.gui.screen.ai_bot_frame
    local tabs = frame and frame.ai_bot_tabs
    gui.apply_settings(player, tabs and tabs.ai_bot_tab_settings)
    return
  end
  if element.tags and element.tags.ai_bot_bp_id then
    gui.player_store(player).selected_bp = element.tags.ai_bot_bp_id
    gui.refresh(player)
  end
end)

script.on_event(defines.events.on_gui_text_changed, function(event)
  local element = event.element
  local player = game.get_player(event.player_index)
  if not player or not element or not element.valid then
    return
  end
  if element.name == "ai_bot_bp_search" then
    gui.player_store(player).bp_filter = element.text or ""
    gui.refresh(player)
  elseif element.name == "ai_bot_plan_search" then
    gui.player_store(player).plan_filter = element.text or ""
    if plan.is_on(player) then
      gui.open_planner(player)
    end
  end
end)

script.on_event(defines.events.on_gui_value_changed, function(event)
  local element = event.element
  if not element or not element.valid then
    return
  end
  local parent = element.parent
  local value_label = parent and parent[element.name .. "_value"]
  if value_label then
    value_label.caption = tostring(math.floor(element.slider_value))
  end
end)

script.on_event(defines.events.on_gui_location_changed, function(event)
  local player = game.get_player(event.player_index)
  if player then
    gui.save_location(player, event.element)
  end
end)

local function try_assign_from_selection(player, entities)
  if not player then
    return
  end
  for _, entity in pairs(entities or {}) do
    if gui.assign_bot(player, entity) then
      return
    end
  end
  player.print({"ai-bot.no-bot"})
end

script.on_event(defines.events.on_pre_build, function(event)
  local player = game.get_player(event.player_index)
  if not player then
    return
  end
  local store = gui.player_store(player)
  local stamp = store.stamp
  if not stamp then
    return
  end
  local cursor = player.cursor_stack
  if not cursor or not cursor.valid_for_read or not cursor.is_blueprint then
    return
  end
  -- 接受原版蓝图落下：入队并认领随后出现的幽灵，不删不重放。
  if event.created_by_moving and store.last_stamp_tick and event.tick - store.last_stamp_tick < 10 then
    return
  end
  store.last_stamp_tick = event.tick
  local job = gui.enqueue_blueprint(
    player,
    stamp.blueprint_id,
    event.position,
    event.direction,
    {
      horizontal = event.flip_horizontal,
      vertical = event.flip_vertical,
      mirror = event.mirror
    }
  )
  store.stamp = nil
  if job then
    jobs.begin_claim(player, job)
  end
end)

script.on_event(defines.events.on_player_cursor_stack_changed, function(event)
  local player = game.get_player(event.player_index)
  if not player then
    return
  end
  local store = gui.player_store(player)
  if not store.stamp then
    return
  end
  local cursor = player.cursor_stack
  if not cursor or not cursor.valid_for_read or not cursor.is_blueprint then
    store.stamp = nil
  end
end)

script.on_event(defines.events.on_player_selected_area, function(event)
  if event.item == "ai-bot-assign-tool" then
    try_assign_from_selection(game.get_player(event.player_index), event.entities)
  end
end)

script.on_event(defines.events.on_player_alt_selected_area, function(event)
  if event.item == "ai-bot-assign-tool" then
    try_assign_from_selection(game.get_player(event.player_index), event.entities)
  end
end)

script.on_event(defines.events.on_built_entity, function(event)
  local entity = event.entity
  if not entity or not entity.valid then
    return
  end
  local player = event.player_index and game.get_player(event.player_index)
  if entity.name == "ai-structure-bot" and player then
    gui.assign_bot(player, entity)
    return
  end
  if player and plan.is_on(player) then
    plan.convert_built_to_ghost(player, entity)
    gui.restore_plan_item(player)
    return
  end
  if player and (entity.type == "entity-ghost" or entity.type == "tile-ghost") then
    jobs.attach_ghost(player, entity)
  end
end)

script.on_event(defines.events.on_player_built_tile, function(event)
  local player = game.get_player(event.player_index)
  if not player then
    return
  end
  if plan.is_on(player) then
    plan.convert_tiles_to_ghosts(player, event)
    gui.restore_plan_item(player)
    return
  end
  local surface = game.surfaces[event.surface_index]
  if not surface then
    return
  end
  for _, tile in pairs(event.tiles or {}) do
    local ghosts = surface.find_entities_filtered{
      position = tile.position,
      type = "tile-ghost",
      radius = 0.4
    }
    for _, ghost in pairs(ghosts) do
      jobs.attach_ghost(player, ghost)
    end
  end
end)

script.on_nth_tick(2, function()
  for _, player in pairs(game.connected_players) do
    local claim = jobs.claim_window(player)
    if claim and game.tick - claim.tick > 2 then
      jobs.end_claim(player)
    end
  end
end)

script.on_event(defines.events.on_tick, function(event)
  ai.on_tick(event)
end)

script.on_nth_tick(300, function()
  for _, player in pairs(game.connected_players) do
    if gui.player_store(player).menu_open then
      gui.refresh(player)
    end
  end
end)
