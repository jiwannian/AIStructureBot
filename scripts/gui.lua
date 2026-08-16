-- 可拖动普通菜单：总控 / 蓝图 / 资源 / 设置。
-- 不再使用全屏遮罩，避免挡住点地图盖章。
local util = require("scripts.util")
local inventory = require("scripts.inventory")
local blueprint = require("scripts.blueprint")
local jobs = require("scripts.jobs")
local catalog = require("scripts.catalog")

local gui = {}

local FRAME_NAME = "ai_bot_frame"
local PLANNER_NAME = "ai_bot_planner"

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
    plan_filter = ""
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

local function rebuild_queue(list, store)
  list.clear()
  if not store.queue or #store.queue == 0 then
    list.add{type = "label", caption = {"ai-bot.queue-empty"}}
    return
  end
  for index, job in ipairs(store.queue) do
    local pos = job.position or {x = 0, y = 0}
    local caption = string.format(
      "%d. %s [%s] (%d, %d)",
      index,
      job.name or "?",
      job.status or "queued",
      math.floor(pos.x or 0),
      math.floor(pos.y or 0)
    )
    list.add{type = "label", caption = caption}
  end
end

local function rebuild_blueprint_list(list, store, filter)
  list.clear()
  local count = 0
  local ids = {}
  for id in pairs(store.blueprints) do
    table.insert(ids, id)
  end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local entry = store.blueprints[id]
    local name = entry.name or ("BP-" .. id)
    if filter == "" or string.find(string.lower(name), string.lower(filter), 1, true) then
      local selected = store.selected_bp == id
      list.add{
        type = "button",
        name = "ai_bot_bp_" .. id,
        caption = (selected and "> " or "") .. name .. "  (" .. (entry.entity_count or 0) .. ")",
        tags = {ai_bot_bp_id = id}
      }
      count = count + 1
    end
  end
  if count == 0 then
    list.add{type = "label", caption = {"ai-bot.no-blueprint"}}
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
    if main.ai_bot_plan then
      main.ai_bot_plan.caption = store.planning and {"ai-bot.plan-stop"} or {"ai-bot.plan-start"}
    end
    if main.ai_bot_toggle then
      main.ai_bot_toggle.caption = store.enabled and {"ai-bot.toggle-bot-off"} or {"ai-bot.toggle-bot"}
    end
    if main.ai_bot_queue then
      rebuild_queue(main.ai_bot_queue, store)
    end
  end

  local bp_tab = tabs.ai_bot_tab_blueprints
  if bp_tab and bp_tab.ai_bot_bp_list then
    rebuild_blueprint_list(bp_tab.ai_bot_bp_list, store, store.bp_filter or "")
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

function gui.close_planner(player)
  util.safe_destroy(player.gui.screen[PLANNER_NAME])
end

function gui.give_plan_item(player, item_name)
  if not item_name or not prototypes.item[item_name] then
    return
  end
  player_store(player).plan_item = item_name
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

function gui.restore_plan_item(player)
  local store = player_store(player)
  if not store.planning or not store.plan_item then
    return
  end
  local cursor = player.cursor_stack
  if cursor and cursor.valid_for_read and cursor.name == store.plan_item then
    return
  end
  gui.give_plan_item(player, store.plan_item)
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
  local plan_flow = main.add{type = "flow", direction = "horizontal"}
  plan_flow.add{type = "button", name = "ai_bot_plan", caption = {"ai-bot.plan-start"}}
  plan_flow.add{type = "button", name = "ai_bot_build", caption = {"ai-bot.assign-ghosts"}}
  local actions = main.add{type = "flow", direction = "horizontal"}
  actions.add{type = "button", name = "ai_bot_toggle", caption = {"ai-bot.toggle-bot"}}
  actions.add{type = "button", name = "ai_bot_assign", caption = {"ai-bot.assign-bot"}}
  local queue_actions = main.add{type = "flow", direction = "horizontal"}
  queue_actions.add{type = "button", name = "ai_bot_cancel_job", caption = {"ai-bot.cancel-job"}}
  queue_actions.add{type = "button", name = "ai_bot_skip_job", caption = {"ai-bot.skip-job"}}
  main.add{type = "label", caption = {"ai-bot.queue-title"}, style = "caption_label"}
  local queue = main.add{type = "scroll-pane", name = "ai_bot_queue"}
  queue.style.maximal_height = 180
  main.add{type = "label", caption = {"ai-bot.close-hint"}}
  tabs.add_tab(tab_main, main)

  local tab_bp = tabs.add{type = "tab", name = "tab_bp", caption = {"ai-bot.tab-blueprints"}}
  local bp = tabs.add{type = "flow", name = "ai_bot_tab_blueprints", direction = "vertical"}
  bp.add{
    type = "textfield",
    name = "ai_bot_bp_search",
    text = store.bp_filter or "",
    lose_focus_on_confirm = true
  }
  local bp_actions = bp.add{type = "flow", direction = "horizontal"}
  bp_actions.add{type = "button", name = "ai_bot_save_cursor", caption = {"ai-bot.save-cursor"}}
  bp_actions.add{type = "button", name = "ai_bot_stamp", caption = {"ai-bot.stamp-selected"}}
  bp_actions.add{type = "button", name = "ai_bot_delete_bp", caption = {"ai-bot.delete-selected"}}
  local bp_list = bp.add{type = "scroll-pane", name = "ai_bot_bp_list"}
  bp_list.style.maximal_height = 260
  tabs.add_tab(tab_bp, bp)

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
    name = "ai_bot_set_autostart",
    caption = {"ai-bot.settings-autostart"},
    state = util.player_setting(player, "ai-bot-auto-start", false)
  }
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
    player.print({"ai-bot.bot-assigned", tostring(entity.unit_number)})
    gui.refresh(player)
    return true
  end
  return false
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
  player_settings["ai-bot-auto-start"] = {value = setf.ai_bot_set_autostart.state}
  player_settings["ai-bot-force-build"] = {value = setf.ai_bot_set_force.state}
  player_settings["ai-bot-take-from-network"] = {value = setf.ai_bot_set_network.state}
  player_settings["ai-bot-take-from-player"] = {value = setf.ai_bot_set_player.state}
  player.print({"ai-bot.settings-saved"})
end

function gui.begin_stamp(player, blueprint_id)
  local store = player_store(player)
  local entry = store.blueprints[blueprint_id or store.selected_bp]
  if not entry then
    player.print({"ai-bot.no-blueprint"})
    return
  end
  store.selected_bp = entry.id
  store.stamp = {
    blueprint_id = entry.id,
    export = entry.export,
    name = entry.name
  }
  if blueprint.put_on_cursor(player, entry.export) then
    player.print({"ai-bot.stamp-ready", entry.name})
  else
    store.stamp = nil
    player.print({"ai-bot.no-cursor-blueprint"})
  end
end

function gui.cancel_stamp(player)
  local store = player_store(player)
  if not store.stamp then
    return
  end
  store.stamp = nil
  local cursor = player.cursor_stack
  if cursor and cursor.valid_for_read and cursor.is_blueprint then
    player.clear_cursor()
  end
  player.print({"ai-bot.stamp-cancelled"})
end

function gui.is_stamping(player)
  return player_store(player).stamp ~= nil
end

function gui.enqueue_blueprint(player, blueprint_id, position, direction, flip)
  local store = player_store(player)
  local entry = store.blueprints[blueprint_id or store.selected_bp]
  if not entry then
    player.print({"ai-bot.no-blueprint"})
    return nil
  end
  local job, duplicated = jobs.enqueue(player, entry, position, direction, flip)
  if not duplicated then
    player.print({
      "ai-bot.blueprint-enqueued",
      entry.name,
      tostring(math.floor(position.x)),
      tostring(math.floor(position.y))
    })
  end
  gui.refresh(player)
  return job
end

function gui.save_cursor_blueprint(player)
  local store = player_store(player)
  local saved, err = blueprint.save_from_player(player, store)
  if not saved then
    player.print({"ai-bot." .. (err or "no-cursor-blueprint")})
    return
  end
  store.selected_bp = saved[1].id
  player.print({"ai-bot.blueprint-saved", saved[1].name})
  if util.player_setting(player, "ai-bot-auto-start", false) then
    gui.begin_stamp(player, saved[1].id)
  end
  gui.refresh(player)
end

function gui.delete_selected(player)
  local store = player_store(player)
  if store.selected_bp then
    store.blueprints[store.selected_bp] = nil
    store.selected_bp = nil
    gui.refresh(player)
  end
end

function gui.cancel_current_job(player)
  local store = player_store(player)
  local job = store.queue[1]
  if not job then
    return
  end
  for _, ghost in pairs(job.ghosts or {}) do
    if ghost.valid then
      ghost.destroy()
    end
  end
  inventory.clear_bot_requests(gui.get_assigned_bot(player))
  table.remove(store.queue, 1)
  store.last_status = #store.queue > 0 and "queued" or "idle"
  player.print({"ai-bot.job-cancelled", job.name})
  gui.refresh(player)
end

function gui.skip_current_job(player)
  local store = player_store(player)
  local job = store.queue[1]
  if not job then
    return
  end
  for _, ghost in pairs(job.ghosts or {}) do
    if ghost.valid then
      ghost.destroy()
    end
  end
  inventory.clear_bot_requests(gui.get_assigned_bot(player))
  job.placed = false
  job.ghosts = {}
  job.status = "queued"
  job.wait_started = nil
  job.waiting_announced = nil
  table.remove(store.queue, 1)
  table.insert(store.queue, job)
  player.print({"ai-bot.job-skipped", job.name})
  gui.refresh(player)
end

return gui
