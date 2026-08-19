-- AI 建造机器人主入口。Factorio 2.0 使用 storage，不再使用 global。
local gui = require("scripts.gui")
local ai = require("scripts.ai")
local util = require("scripts.util")
local plan = require("scripts.plan")
local maintain = require("scripts.maintain")


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

script.on_event(defines.events.on_gui_opened, function(event)
  local player = game.get_player(event.player_index)
  if player then
    plan.block_controller_gui(player)
  end
end)

script.on_event(defines.events.on_pre_player_crafted_item, function(event)
  local player = game.get_player(event.player_index)
  if player and plan.is_on(player) then
    plan.block_crafting(player, event)
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

script.on_event("ai-bot-plan-mine", function(event)
  local player = game.get_player(event.player_index)
  if player then
    plan.cancel_selected_ghost(player)
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
  if element.tags and element.tags.ai_bot_pick then
    local entity = game.get_entity_by_unit_number(element.tags.ai_bot_pick)
    if entity then
      gui.assign_bot(player, entity)
    end
    return
  end
  if element.tags and element.tags.ai_bot_set_mode then
    local entity = game.get_entity_by_unit_number(element.tags.ai_bot_set_mode)
    if not entity or not entity.valid then
      return
    end
    gui.assign_bot(player, entity)
    local state = maintain.get_bot_state(entity.unit_number)
    local next_mode = state.mode == "maintain" and "build" or "maintain"
    maintain.set_mode(entity.unit_number, next_mode, entity.position)
    if next_mode == "maintain" then
      gui.player_store(player).enabled = true
    end
    player.print(next_mode == "maintain" and {"ai-bot.mode-switched-maintain"} or {"ai-bot.mode-switched-build"})
    gui.player_store(player).mt_dirty = true
    gui.refresh(player)
    return
  end
  if element.tags and element.tags.ai_mt_field == "ammo" then
    gui.apply_maintain_change(player, element.tags, element.tags.ai_mt_ammo)
    return
  end
  if element.tags and element.tags.ai_mt_field == "fuel" then
    gui.apply_maintain_change(player, element.tags, element.tags.ai_mt_fuel_item)
    return
  end
  if element.name == "ai_bot_recall" then
    plan.recall_bot(player)
    gui.refresh(player)
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
  if element.name == "ai_bot_lineplan" then
    gui.open_lineplan(player)
    return
  end
  if element.name == "ai_bot_lineplan_close" then
    gui.close_lineplan(player)
    return
  end
  if element.tags and element.tags.ai_bot_lib_cat then
    local store = gui.player_store(player)
    store.library = store.library or {category = "", filter = "", selected = nil}
    store.library.category = element.tags.ai_bot_lib_cat
    gui.refresh_library(player)
    return
  end
  if element.tags and element.tags.ai_bot_lib_id then
    gui.give_library_blueprint(player, element.tags.ai_bot_lib_id)
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
  if element.name == "ai_bot_stop" then
    plan.stop_assign(player)
    gui.refresh(player)
    return
  end
  if element.name == "ai_bot_toggle" then
    local bot = gui.get_assigned_bot(player)
    if not bot then
      player.print({"ai-bot.no-bot"})
      return
    end
    local state = maintain.get_bot_state(bot.unit_number)
    state.paused = not state.paused
    if state.paused then
      bot.autopilot_destination = nil
      player.print({"ai-bot.bot-paused"})
    else
      player.print({"ai-bot.bot-resumed"})
    end
    gui.refresh(player)
    return
  end
  if element.name == "ai_bot_save_settings" then
    local frame = player.gui.screen.ai_bot_frame
    local tabs = frame and frame.ai_bot_tabs
    gui.apply_settings(player, tabs and tabs.ai_bot_tab_settings)
    return
  end
end)

script.on_event(defines.events.on_gui_text_changed, function(event)
  local element = event.element
  local player = game.get_player(event.player_index)
  if not player or not element or not element.valid then
    return
  end
  if element.name == "ai_bot_plan_search" then
    gui.player_store(player).plan_filter = element.text or ""
    if plan.is_on(player) then
      gui.open_planner(player)
    end
  elseif element.name == "ai_bot_lp_search" then
    local store = gui.player_store(player)
    store.library = store.library or {category = "", filter = "", selected = nil}
    store.library.filter = element.text or ""
    gui.refresh_library(player)
  elseif element.tags and (element.tags.ai_mt_field == "min" or element.tags.ai_mt_field == "max") then
    gui.apply_maintain_change(player, element.tags, element.text)
  end
end)

script.on_event(defines.events.on_gui_confirmed, function(event)
  local element = event.element
  local player = game.get_player(event.player_index)
  if not player or not element or not element.valid then
    return
  end
  if element.name and string.sub(element.name, 1, 11) == "ai_bot_set_" then
    local frame = player.gui.screen.ai_bot_frame
    local tabs = frame and frame.ai_bot_tabs
    gui.apply_settings(player, tabs and tabs.ai_bot_tab_settings)
  elseif element.tags and (element.tags.ai_mt_field == "min" or element.tags.ai_mt_field == "max") then
    gui.apply_maintain_change(player, element.tags, element.text)
  end
end)

script.on_event(defines.events.on_gui_checked_state_changed, function(event)
  local player = game.get_player(event.player_index)
  local element = event.element
  if not player or not element or not element.valid then
    return
  end
  if element.tags and (element.tags.ai_mt_field == "enabled" or element.tags.ai_mt_field == "repair") then
    gui.apply_maintain_change(player, element.tags, element.state)
  elseif element.name == "ai_bot_set_force" or element.name == "ai_bot_set_network" or element.name == "ai_bot_set_player" then
    local frame = player.gui.screen.ai_bot_frame
    local tabs = frame and frame.ai_bot_tabs
    gui.apply_settings(player, tabs and tabs.ai_bot_tab_settings)
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
  local value_box = parent and parent[element.name .. "_box"]
  if value_box then
    value_box.text = tostring(math.floor(element.slider_value))
  end
  local player = game.get_player(event.player_index)
  if not player then
    return
  end
  if element.tags and (element.tags.ai_mt_field == "min" or element.tags.ai_mt_field == "max") then
    gui.apply_maintain_change(player, element.tags, element.slider_value)
  elseif element.name and string.sub(element.name, 1, 11) == "ai_bot_set_" then
    local frame = player.gui.screen.ai_bot_frame
    local tabs = frame and frame.ai_bot_tabs
    gui.apply_settings(player, tabs and tabs.ai_bot_tab_settings)
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

script.on_event(defines.events.on_pre_build, function(event)
  local player = event.player_index and game.get_player(event.player_index)
  if player then
    plan.remember_build(player, event)
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
    plan.queue_or_convert(player, entity)
    gui.schedule_plan_restore(player)
  end
end)

script.on_event(defines.events.on_player_built_tile, function(event)
  local player = game.get_player(event.player_index)
  if not player then
    return
  end
  if plan.is_on(player) then
    plan.convert_tiles_to_ghosts(player, event)
    gui.schedule_plan_restore(player)
  end
end)

script.on_event(defines.events.on_tick, function(event)
  plan.flush_pair_queue()
  for _, player in pairs(game.connected_players) do
    if plan.is_on(player) then
      player.cheat_mode = false
      plan.block_controller_gui(player)
    end
    gui.flush_plan_restore(player)
  end
  ai.on_tick(event)
end)

script.on_nth_tick(300, function()
  for _, player in pairs(game.connected_players) do
    if gui.player_store(player).menu_open then
      gui.refresh(player)
    end
  end
end)
