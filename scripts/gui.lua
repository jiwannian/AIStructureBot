-- 可拖动普通菜单：总控 / 蓝图 / 资源 / 设置。
-- 不再使用全屏遮罩，避免挡住点地图盖章。
local util = require("scripts.util")
local inventory = require("scripts.inventory")
local catalog = require("scripts.catalog")
local maintain = require("scripts.maintain")
local library = require("scripts.library")
local blueprint = require("scripts.blueprint")

local gui = {}

local FRAME_NAME = "ai_bot_frame"
local PLANNER_NAME = "ai_bot_planner"
local LINEPLAN_NAME = "ai_bot_lineplan"

local function player_store(player)
  storage.players = storage.players or {}
  storage.players[player.index] = storage.players[player.index] or {
    enabled = true,
    menu_open = false,
    menu_location = nil,
    selected_bp = nil,
    bp_filter = "",
    blueprints = {},
    queue = {},
    next_id = 0,
    assigned_bot = nil,
    last_status = "idle",
    last_need = {},
    last_missing = {},
    warnings = {},
    stamp = nil,
    plan_filter = "",
    mt_dirty = true
  }
  local store = storage.players[player.index]
  store.blueprints = store.blueprints or {}
  store.queue = store.queue or {}
  store.warnings = store.warnings or {}
  store.plan_filter = store.plan_filter or ""
  return store
end

gui.player_store = player_store

local function add_titlebar(frame, caption, close_name)
  local bar = frame.add{type = "flow", name = "titlebar", direction = "horizontal"}
  bar.drag_target = frame
  local title = bar.add{
    type = "label",
    name = "title",
    caption = caption,
    style = "frame_title"
  }
  title.drag_target = frame
  local pusher = bar.add{
    type = "empty-widget",
    name = "drag_handle",
    style = "draggable_space_header"
  }
  pusher.style.height = 24
  pusher.style.horizontally_stretchable = true
  pusher.drag_target = frame
  bar.add{
    type = "sprite-button",
    name = close_name or "ai_bot_close",
    style = "frame_action_button",
    sprite = "utility/close",
    tooltip = {"gui.close"}
  }
  return bar
end

local function rebuild_bot_roster(list, player)
  list.clear()
  local store = player_store(player)
  local bots = maintain.list_bots(player)
  if #bots == 0 then
    list.add{type = "label", caption = {"ai-bot.no-bot"}}
    return
  end
  for _, bot in ipairs(bots) do
    local state = maintain.get_bot_state(bot.unit_number)
    local selected = store.assigned_bot == bot.unit_number
    local row = list.add{type = "flow", direction = "horizontal"}
    row.add{
      type = "button",
      name = "ai_bot_pick_" .. bot.unit_number,
      caption = (selected and "> #" or "#") .. bot.unit_number,
      tags = {ai_bot_pick = bot.unit_number}
    }
    row.add{
      type = "button",
      name = "ai_bot_set_mode_" .. bot.unit_number,
      caption = state.mode == "maintain" and {"ai-bot.mode-maintain-short"} or {"ai-bot.mode-build-short"},
      tags = {ai_bot_set_mode = bot.unit_number}
    }
    if state.paused then
      row.add{type = "label", caption = {"ai-bot.paused-mark"}}
    end
  end
end

local function rebuild_maintain_box(player)
  local frame = player.gui.screen[FRAME_NAME]
  if not frame or not frame.valid or not frame.ai_bot_tabs then
    return
  end
  local mt_tab = frame.ai_bot_tabs.ai_bot_tab_maintain
  if not mt_tab or not mt_tab.ai_bot_mt_box then
    return
  end
  local box = mt_tab.ai_bot_mt_box
  box.clear()
  local bot = gui.get_assigned_bot(player)
  if not bot then
    box.add{type = "label", caption = {"ai-bot.no-bot"}}
    return
  end
  local state = maintain.ensure_rules(bot.unit_number)
  box.add{
    type = "checkbox",
    name = "ai_mt_repair",
    caption = {"ai-bot.maintain-repair"},
    state = state.repair ~= false,
    tags = {ai_mt_field = "repair"}
  }
  box.add{type = "label", caption = {"ai-bot.maintain-repair-hint"}}
  local names = maintain.ammo_turret_names()
  if #names == 0 then
    box.add{type = "label", caption = {"ai-bot.maintain-empty"}}
    return
  end
  for _, name in ipairs(names) do
    local rule = state.rules[name]
    if rule then
      local ammo_list = maintain.compatible_ammo(name)
      local row = box.add{type = "flow", name = "ai_mt_row_" .. name, direction = "vertical"}
      row.add{type = "label", caption = prototypes.entity[name] and prototypes.entity[name].localised_name or name}
      if #ammo_list == 0 then
        row.add{type = "label", caption = {"ai-bot.maintain-no-ammo"}}
      else
        row.add{
          type = "checkbox",
          name = "ai_mt_on_" .. name,
          caption = {"ai-bot.maintain-enable"},
          state = rule.enabled and true or false,
          tags = {ai_mt_turret = name, ai_mt_field = "enabled"}
        }
        local ammo_flow = row.add{type = "flow", direction = "horizontal"}
        ammo_flow.add{type = "label", caption = {"ai-bot.maintain-ammo"}}
        for _, ammo in ipairs(ammo_list) do
          ammo_flow.add{
            type = "sprite-button",
            name = "ai_mt_ammo_" .. name .. "_" .. ammo,
            sprite = "item/" .. ammo,
            tooltip = prototypes.item[ammo] and prototypes.item[ammo].localised_name or ammo,
            tags = {ai_mt_turret = name, ai_mt_field = "ammo", ai_mt_ammo = ammo},
            style = rule.ammo == ammo and "yellow_slot_button" or "slot_button"
          }
        end
        row.add{type = "label", name = "ai_mt_min_" .. name .. "_caption", caption = {"ai-bot.maintain-min"}}
        local min_flow = row.add{type = "flow", name = "ai_mt_min_flow_" .. name, direction = "horizontal"}
        min_flow.add{
          type = "slider",
          name = "ai_mt_min_" .. name,
          minimum_value = 0,
          maximum_value = 9999,
          value = math.min(9999, rule.min or 0),
          value_step = 1,
          tags = {ai_mt_turret = name, ai_mt_field = "min"}
        }
        min_flow.add{
          type = "textfield",
          name = "ai_mt_min_" .. name .. "_box",
          text = tostring(rule.min or 0),
          numeric = true,
          allow_decimal = false,
          allow_negative = false,
          lose_focus_on_confirm = true,
          tags = {ai_mt_turret = name, ai_mt_field = "min"}
        }.style.width = 60
        row.add{type = "label", name = "ai_mt_max_" .. name .. "_caption", caption = {"ai-bot.maintain-max"}}
        local max_flow = row.add{type = "flow", name = "ai_mt_max_flow_" .. name, direction = "horizontal"}
        max_flow.add{
          type = "slider",
          name = "ai_mt_max_" .. name,
          minimum_value = 0,
          maximum_value = 9999,
          value = math.min(9999, rule.max or 0),
          value_step = 1,
          tags = {ai_mt_turret = name, ai_mt_field = "max"}
        }
        max_flow.add{
          type = "textfield",
          name = "ai_mt_max_" .. name .. "_box",
          text = tostring(rule.max or 0),
          numeric = true,
          allow_decimal = false,
          allow_negative = false,
          lose_focus_on_confirm = true,
          tags = {ai_mt_turret = name, ai_mt_field = "max"}
        }.style.width = 60
      end
    end
  end
end

local function add_count_table(parent, title, map, warn_threshold)
  parent.add{type = "label", caption = title, style = "caption_label"}
  local keys = {}
  for key in pairs(map or {}) do
    table.insert(keys, key)
  end
  table.sort(keys)
  if #keys == 0 then
    parent.add{type = "label", caption = "-"}
    return
  end
  for _, key in ipairs(keys) do
    local entry = map[key]
    local caption = entry.name .. "  x" .. entry.count
    if entry.quality and entry.quality ~= "normal" then
      caption = caption .. "  [" .. entry.quality .. "]"
    end
    local label = parent.add{type = "label", caption = caption}
    if warn_threshold and entry.count <= warn_threshold then
      label.style.font_color = {1, 0.45, 0.35}
    end
  end
end

function gui.refresh(player)
  local store = player_store(player)
  local frame = player.gui.screen[FRAME_NAME]
  if not frame or not frame.valid then
    return
  end
  local tabs = frame.ai_bot_tabs
  if not tabs then
    return
  end

  local main = tabs.ai_bot_tab_main
  if main then
    if main.ai_bot_status then
      main.ai_bot_status.caption = {"ai-bot.status-" .. (store.last_status or "idle")}
    end
    if main.ai_bot_bot_label then
      main.ai_bot_bot_label.caption = store.assigned_bot and ("#" .. store.assigned_bot) or {"ai-bot.no-bot"}
    end
    if main.ai_bot_recall then
      local bot = gui.get_assigned_bot(player)
      local recalling = bot and maintain.get_bot_state(bot.unit_number).recalling
      main.ai_bot_recall.caption = recalling and {"ai-bot.recall-cancel"} or {"ai-bot.recall"}
    end
    if main.ai_bot_plan then
      main.ai_bot_plan.caption = store.planning and {"ai-bot.plan-stop"} or {"ai-bot.plan-start"}
    end
    if main.ai_bot_toggle then
      local bot = gui.get_assigned_bot(player)
      local paused = bot and maintain.get_bot_state(bot.unit_number).paused
      main.ai_bot_toggle.caption = paused and {"ai-bot.toggle-bot"} or {"ai-bot.toggle-bot-off"}
    end
    if main.ai_bot_roster then
      rebuild_bot_roster(main.ai_bot_roster, player)
    end
  end

  if store.mt_dirty then
    rebuild_maintain_box(player)
    store.mt_dirty = false
  end

  local res_tab = tabs.ai_bot_tab_resources
  if res_tab and res_tab.ai_bot_res_box then
    local box = res_tab.ai_bot_res_box
    box.clear()
    local bot = gui.get_assigned_bot(player)
    local sources = inventory.scan_sources(player, bot)
    local warn = util.player_setting(player, "ai-bot-warn-threshold", 20)
    add_count_table(box, {"ai-bot.resource-player"}, sources.player)
    add_count_table(box, {"ai-bot.resource-bot"}, sources.bot)
    add_count_table(box, {"ai-bot.resource-network"}, sources.network)
    if store.last_need and next(store.last_need) then
      add_count_table(box, {"ai-bot.resource-need"}, store.last_need)
    end
    if store.last_missing and next(store.last_missing) then
      add_count_table(box, {"ai-bot.resource-missing"}, store.last_missing)
    end
    if store.last_wait_reasons and #store.last_wait_reasons > 0 then
      box.add{type = "label", caption = {"ai-bot.resource-wait"}, style = "caption_label"}
      for _, text in ipairs(store.last_wait_reasons) do
        local label = box.add{type = "label", caption = text}
        label.style.single_line = false
      end
    end
    if store.warnings and #store.warnings > 0 then
      box.add{type = "label", caption = {"ai-bot.resource-warn"}, style = "caption_label"}
      for _, text in ipairs(store.warnings) do
        local label = box.add{type = "label", caption = text}
        label.style.font_color = {1, 0.55, 0.3}
      end
    end
  end
end

function gui.close_lineplan(player)
  util.safe_destroy(player.gui.screen[LINEPLAN_NAME])
end

function gui.close_planner(player)
  util.safe_destroy(player.gui.screen[PLANNER_NAME])
  gui.close_lineplan(player)
end

function gui.give_plan_item(player, item_name)
  if not item_name or not prototypes.item[item_name] then
    return
  end
  local store = player_store(player)
  store.plan_item = item_name
  store.lib_export = nil
  store.lib_id = nil
  if not player.clear_cursor() then
    return
  end
  local cursor = player.cursor_stack
  if cursor and cursor.valid then
    -- 规划模式连续放置：一次选中，一直留在光标上。
    cursor.set_stack({name = item_name, count = 1})
    player.cursor_stack_temporary = true
  end
end

function gui.schedule_plan_restore(player)
  local store = player_store(player)
  if store.planning and (store.lib_export or store.plan_item) then
    store.plan_restore_tick = game.tick + 1
  end
end

function gui.flush_plan_restore(player)
  local store = player_store(player)
  if store.plan_restore_tick and game.tick >= store.plan_restore_tick then
    store.plan_restore_tick = nil
    gui.restore_plan_item(player)
  end
end

function gui.restore_plan_item(player)
  local store = player_store(player)
  if not store.planning then
    return
  end
  local cursor = player.cursor_stack
  if cursor and cursor.valid_for_read then
    if store.lib_export and (cursor.is_blueprint or cursor.is_blueprint_book) then
      return
    end
    if store.plan_item and (cursor.name == store.plan_item or cursor.is_blueprint) then
      return
    end
  end
  if store.lib_export then
    blueprint.put_on_cursor(player, store.lib_export)
    return
  end
  if store.plan_item then
    gui.give_plan_item(player, store.plan_item)
  end
end

function gui.open_planner(player)
  gui.close_planner(player)
  local items = catalog.unlocked_placeables(player.force)
  local frame = player.gui.screen.add{
    type = "frame",
    name = PLANNER_NAME,
    direction = "vertical"
  }
  frame.style.minimal_width = 460
  frame.style.maximal_width = 560
  add_titlebar(frame, {"ai-bot.planner-title"}, "ai_bot_plan_close")
  frame.add{type = "label", caption = {"ai-bot.planner-hint"}}
  frame.add{type = "button", name = "ai_bot_lineplan", caption = {"ai-bot.lineplan-open"}}
  local search = frame.add{
    type = "textfield",
    name = "ai_bot_plan_search",
    text = player_store(player).plan_filter or ""
  }
  search.style.maximal_width = 420
  local pane = frame.add{type = "scroll-pane", name = "ai_bot_plan_list"}
  pane.style.maximal_height = 420
  local table_el = pane.add{type = "table", name = "ai_bot_plan_table", column_count = 10}
  local filter = string.lower(player_store(player).plan_filter or "")
  for _, item in ipairs(items) do
    local name = item.name
    if filter == "" or string.find(string.lower(name), filter, 1, true) or (item.localised_name and type(item.localised_name) == "string" and string.find(string.lower(item.localised_name), filter, 1, true)) then
      table_el.add{
        type = "sprite-button",
        name = "ai_bot_plan_item_" .. name,
        sprite = "item/" .. name,
        tooltip = item.localised_name or name,
        tags = {ai_bot_plan_item = name},
        style = "slot_button"
      }
    end
  end
  local resolution = player.display_resolution
  local scale = player.display_scale or 1
  frame.location = {x = 40, y = math.floor(resolution.height / scale / 2 - 240)}
end

local function library_store(player)
  local store = player_store(player)
  store.library = store.library or {category = "", filter = "", selected = nil}
  return store.library
end

local function fill_library_categories(parent, lib)
  parent.clear()
  local cats = {{id = "", caption = {"ai-bot.library-all"}}}
  for _, category in ipairs(library.categories()) do
    table.insert(cats, {id = category, caption = category})
  end
  for index, cat in ipairs(cats) do
    parent.add{
      type = "button",
      name = "ai_bot_lib_cat_" .. tostring(index),
      caption = cat.caption,
      tags = {ai_bot_lib_cat = cat.id},
      style = (lib.category or "") == cat.id and "green_button" or "button"
    }
  end
end

local function fill_library_list(list, lib)
  list.clear()
  local entries = library.entries(lib.category ~= "" and lib.category or nil, lib.filter or "")
  if #entries == 0 then
    list.add{type = "label", caption = {"ai-bot.library-empty"}}
    return
  end
  local last_cat = nil
  for _, item in ipairs(entries) do
    if (not lib.category or lib.category == "") and item.category ~= last_cat then
      list.add{type = "label", caption = item.category, style = "caption_label"}
      last_cat = item.category
    end
    list.add{
      type = "button",
      name = "ai_bot_lib_item_" .. tostring(item.id),
      caption = item.name,
      tags = {ai_bot_lib_id = item.id},
      style = lib.selected == item.id and "green_button" or "button"
    }
  end
end

function gui.refresh_library(player)
  local frame = player.gui.screen[LINEPLAN_NAME]
  if not frame then
    return
  end
  local lib = library_store(player)
  if frame.ai_bot_lib_cats then
    fill_library_categories(frame.ai_bot_lib_cats, lib)
  end
  if frame.ai_bot_lib_list then
    fill_library_list(frame.ai_bot_lib_list, lib)
  end
  if frame.ai_bot_lib_picked then
    local item = lib.selected and library.get(lib.selected)
    frame.ai_bot_lib_picked.caption = item and {"", {"ai-bot.library-selected"}, " ", item.name} or {"ai-bot.library-pick"}
  end
end

function gui.open_lineplan(player)
  gui.close_lineplan(player)
  local lib = library_store(player)
  local frame = player.gui.screen.add{type = "frame", name = LINEPLAN_NAME, direction = "vertical"}
  frame.style.minimal_width = 420
  frame.style.maximal_width = 560
  add_titlebar(frame, {"ai-bot.lineplan-title"}, "ai_bot_lineplan_close")
  frame.add{type = "label", caption = {"ai-bot.lineplan-hint"}}
  frame.add{type = "label", caption = {"ai-bot.library-source"}}
  local search = frame.add{type = "textfield", name = "ai_bot_lp_search", text = lib.filter or ""}
  search.style.maximal_width = 500
  local cats = frame.add{type = "table", name = "ai_bot_lib_cats", column_count = 4}
  cats.style.horizontally_stretchable = true
  local pane = frame.add{type = "scroll-pane", name = "ai_bot_lib_list"}
  pane.style.maximal_height = 360
  pane.style.minimal_width = 400
  frame.add{type = "label", name = "ai_bot_lib_picked", caption = {"ai-bot.library-pick"}}
  local resolution = player.display_resolution
  local scale = player.display_scale or 1
  frame.location = {x = math.floor(resolution.width / scale / 2 - 210), y = 80}
  gui.refresh_library(player)
end

function gui.give_library_blueprint(player, id)
  local ok, item = library.put_on_cursor(player, id)
  local store = player_store(player)
  if not ok or not item then
    player.print({"ai-bot.library-fail"})
    return
  end
  store.lib_export = item.export
  store.lib_id = id
  store.plan_item = nil
  local lib = library_store(player)
  lib.selected = id
  player.print({"ai-bot.library-ready", item.name})
  gui.refresh_library(player)
end

function gui.close(player)
  local store = player_store(player)
  store.menu_open = false
  util.safe_destroy(player.gui.screen[FRAME_NAME])
  if player.is_shortcut_toggled("ai-bot-open-menu") then
    player.set_shortcut_toggled("ai-bot-open-menu", false)
  end
end

function gui.open(player)
  local store = player_store(player)
  gui.close(player)
  store.menu_open = true
  player.set_shortcut_toggled("ai-bot-open-menu", true)

  local frame = player.gui.screen.add{
    type = "frame",
    name = FRAME_NAME,
    direction = "vertical"
  }
  frame.style.minimal_width = 430
  frame.style.maximal_width = 540
  add_titlebar(frame, {"ai-bot.menu-title"})

  local tabs = frame.add{type = "tabbed-pane", name = "ai_bot_tabs"}

  local tab_main = tabs.add{type = "tab", name = "tab_main", caption = {"ai-bot.tab-main"}}
  local main = tabs.add{type = "flow", name = "ai_bot_tab_main", direction = "vertical"}
  main.add{type = "label", caption = {"ai-bot.how-to"}}
  main.add{type = "label", name = "ai_bot_status", caption = {"ai-bot.status-idle"}}
  main.add{type = "label", name = "ai_bot_bot_label", caption = {"ai-bot.no-bot"}}
  main.add{type = "label", caption = {"ai-bot.roster-title"}, style = "caption_label"}
  local roster = main.add{type = "scroll-pane", name = "ai_bot_roster"}
  roster.style.maximal_height = 160
  local plan_flow = main.add{type = "flow", direction = "horizontal"}
  plan_flow.add{type = "button", name = "ai_bot_plan", caption = {"ai-bot.plan-start"}}
  plan_flow.add{type = "button", name = "ai_bot_build", caption = {"ai-bot.assign-ghosts"}}
  plan_flow.add{type = "button", name = "ai_bot_stop", caption = {"ai-bot.job-stop"}}
  local actions = main.add{type = "flow", direction = "horizontal"}
  actions.add{type = "button", name = "ai_bot_recall", caption = {"ai-bot.recall"}}
  actions.add{type = "button", name = "ai_bot_toggle", caption = {"ai-bot.toggle-bot-off"}}
  main.add{type = "label", caption = {"ai-bot.close-hint"}}
  tabs.add_tab(tab_main, main)

  local tab_res = tabs.add{type = "tab", name = "tab_res", caption = {"ai-bot.tab-resources"}}
  local res = tabs.add{type = "flow", name = "ai_bot_tab_resources", direction = "vertical"}
  local res_box = res.add{type = "scroll-pane", name = "ai_bot_res_box"}
  res_box.style.maximal_height = 340
  tabs.add_tab(tab_res, res)

  local tab_set = tabs.add{type = "tab", name = "tab_set", caption = {"ai-bot.tab-settings"}}
  local setf = tabs.add{type = "flow", name = "ai_bot_tab_settings", direction = "vertical"}
  local function add_slider(name, caption, value, min_v, max_v, step)
    setf.add{type = "label", caption = caption}
    setf.add{
      type = "slider",
      name = name,
      minimum_value = min_v,
      maximum_value = max_v,
      value = value,
      value_step = step
    }
    setf.add{type = "label", name = name .. "_value", caption = tostring(value)}
  end
  add_slider("ai_bot_set_radius", {"ai-bot.settings-search"}, util.player_setting(player, "ai-bot-search-radius", 512), 64, 2048, 64)
  add_slider("ai_bot_set_warn", {"ai-bot.settings-warn"}, util.player_setting(player, "ai-bot-warn-threshold", 20), 0, 500, 5)
  add_slider("ai_bot_set_reserve", {"ai-bot.settings-reserve"}, util.player_setting(player, "ai-bot-reserve-stock", 50), 0, 500, 5)
  add_slider("ai_bot_set_range", {"ai-bot.settings-range"}, util.player_setting(player, "ai-bot-work-range", 24), 8, 64, 1)
  add_slider("ai_bot_set_timeout", {"ai-bot.settings-timeout"}, util.player_setting(player, "ai-bot-wait-timeout", 180), 10, 600, 10)
  setf.add{
    type = "checkbox",
    name = "ai_bot_set_force",
    caption = {"ai-bot.settings-force"},
    state = util.player_setting(player, "ai-bot-force-build", false)
  }
  setf.add{
    type = "checkbox",
    name = "ai_bot_set_network",
    caption = {"ai-bot.settings-network"},
    state = util.player_setting(player, "ai-bot-take-from-network", false)
  }
  setf.add{
    type = "checkbox",
    name = "ai_bot_set_player",
    caption = {"ai-bot.settings-player"},
    state = util.player_setting(player, "ai-bot-take-from-player", true)
  }
  setf.add{type = "button", name = "ai_bot_save_settings", caption = {"gui.confirm"}}
  tabs.add_tab(tab_set, setf)

  local tab_mt = tabs.add{type = "tab", name = "tab_mt", caption = {"ai-bot.tab-maintain"}}
  local mt = tabs.add{type = "flow", name = "ai_bot_tab_maintain", direction = "vertical"}
  mt.add{type = "label", caption = {"ai-bot.maintain-hint"}}
  local mt_box = mt.add{type = "scroll-pane", name = "ai_bot_mt_box"}
  mt_box.style.maximal_height = 360
  tabs.add_tab(tab_mt, mt)

  if store.menu_location then
    frame.location = store.menu_location
  else
    local resolution = player.display_resolution
    local scale = player.display_scale or 1
    frame.location = {
      x = math.floor(resolution.width / scale / 2 - 210),
      y = math.floor(resolution.height / scale / 2 - 180)
    }
  end

  player.opened = frame
  store.mt_dirty = true
  gui.refresh(player)
end

function gui.toggle(player)
  local store = player_store(player)
  if store.menu_open and player.gui.screen[FRAME_NAME] then
    gui.close(player)
  else
    gui.open(player)
  end
end

function gui.get_assigned_bot(player)
  local store = player_store(player)
  if not store.assigned_bot then
    return nil
  end
  local entity = game.get_entity_by_unit_number(store.assigned_bot)
  if entity and entity.valid and entity.name == "ai-structure-bot" then
    return entity
  end
  store.assigned_bot = nil
  return nil
end

function gui.assign_bot(player, entity)
  local store = player_store(player)
  if entity and entity.valid and entity.name == "ai-structure-bot" then
    store.assigned_bot = entity.unit_number
    store.mt_dirty = true
    player.print({"ai-bot.bot-assigned", tostring(entity.unit_number)})
    gui.refresh(player)
    return true
  end
  return false
end

function gui.apply_maintain_change(player, tags, value)
  local bot = gui.get_assigned_bot(player)
  if not bot or not tags then
    return
  end
  if tags.ai_mt_field == "repair" then
    maintain.update_rule(bot.unit_number, nil, "repair", value)
    return
  end
  if not tags.ai_mt_turret then
    return
  end
  local rule = maintain.update_rule(bot.unit_number, tags.ai_mt_turret, tags.ai_mt_field, value)
  if not rule then
    return
  end
  if tags.ai_mt_field == "ammo" or tags.ai_mt_field == "enabled" then
    player_store(player).mt_dirty = true
    gui.refresh(player)
    return
  end
  local frame = player.gui.screen[FRAME_NAME]
  local box = frame and frame.ai_bot_tabs and frame.ai_bot_tabs.ai_bot_tab_maintain and frame.ai_bot_tabs.ai_bot_tab_maintain.ai_bot_mt_box
  local row = box and box["ai_mt_row_" .. tags.ai_mt_turret]
  if not row then
    return
  end
  local min_flow = row["ai_mt_min_flow_" .. tags.ai_mt_turret]
  local max_flow = row["ai_mt_max_flow_" .. tags.ai_mt_turret]
  local min_slider = min_flow and min_flow["ai_mt_min_" .. tags.ai_mt_turret]
  local max_slider = max_flow and max_flow["ai_mt_max_" .. tags.ai_mt_turret]
  local min_box = min_flow and min_flow["ai_mt_min_" .. tags.ai_mt_turret .. "_box"]
  local max_box = max_flow and max_flow["ai_mt_max_" .. tags.ai_mt_turret .. "_box"]
  if min_slider then
    min_slider.slider_value = math.min(9999, rule.min or 0)
  end
  if max_slider then
    max_slider.slider_value = math.min(9999, rule.max or 0)
  end
  if min_box and min_box.text ~= tostring(rule.min or 0) then
    min_box.text = tostring(rule.min or 0)
  end
  if max_box and max_box.text ~= tostring(rule.max or 0) then
    max_box.text = tostring(rule.max or 0)
  end
end

function gui.save_location(player, element)
  if element and element.valid and element.name == FRAME_NAME then
    player_store(player).menu_location = element.location
  end
end

function gui.apply_settings(player, setf)
  if not setf then
    return
  end
  local player_settings = settings.get_player_settings(player)
  local function write_slider(name, setting_name)
    local slider = setf[name]
    if not slider then
      return
    end
    local value = math.floor(slider.slider_value)
    player_settings[setting_name] = {value = value}
    if setf[name .. "_value"] then
      setf[name .. "_value"].caption = tostring(value)
    end
  end
  write_slider("ai_bot_set_radius", "ai-bot-search-radius")
  write_slider("ai_bot_set_warn", "ai-bot-warn-threshold")
  write_slider("ai_bot_set_reserve", "ai-bot-reserve-stock")
  write_slider("ai_bot_set_range", "ai-bot-work-range")
  write_slider("ai_bot_set_timeout", "ai-bot-wait-timeout")
  player_settings["ai-bot-force-build"] = {value = setf.ai_bot_set_force.state}
  player_settings["ai-bot-take-from-network"] = {value = setf.ai_bot_set_network.state}
  player_settings["ai-bot-take-from-player"] = {value = setf.ai_bot_set_player.state}
  player.print({"ai-bot.settings-saved"})
end

return gui
