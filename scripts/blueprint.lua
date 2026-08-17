-- 蓝图解析：保存字符串、统计实体/地砖物品、展开蓝图书。
local util = require("scripts.util")

local blueprint = {}

local function new_storage_id(player_store)
  player_store.next_id = (player_store.next_id or 0) + 1
  return player_store.next_id
end

local function with_temp_stack(handler)
  local inventory = game.create_inventory(1)
  local ok, result = pcall(handler, inventory[1], inventory)
  inventory.destroy()
  if not ok then
    error(result)
  end
  return result
end

local function add_place_item(map, proto, quality)
  local item_name = util.item_place_name(proto)
  if item_name then
    util.add_count(map, item_name, quality, 1)
  end
end

function blueprint.item_cost_from_export(export_string)
  return with_temp_stack(function(stack)
    local code = stack.import_stack(export_string)
    if code == 1 or not stack.valid_for_read or not stack.is_blueprint or not stack.is_blueprint_setup() then
      return {}
    end
    local map = {}
    for _, entity in pairs(stack.get_blueprint_entities() or {}) do
      local proto = prototypes.entity[entity.name]
      add_place_item(map, proto, entity.quality)
      for _, request in pairs(entity.items or {}) do
        local item = request.id or request
        local name = item.name or request.name
        local quality = item.quality or request.quality
        local count = request.count or (request.items and request.items.in_inventory and 1) or 1
        if name then
          util.add_count(map, name, quality, count)
        end
      end
    end
    for _, tile in pairs(stack.get_blueprint_tiles() or {}) do
      local proto = prototypes.tile[tile.name]
      add_place_item(map, proto, nil)
    end
    return map
  end)
end

function blueprint.decode_export(export_string)
  return with_temp_stack(function(stack)
    local code = stack.import_stack(export_string)
    if code == 1 or not stack.valid_for_read then
      return nil
    end
    local entities = (stack.is_blueprint and stack.is_blueprint_setup()) and (stack.get_blueprint_entities() or {}) or {}
    local tiles = (stack.is_blueprint and stack.is_blueprint_setup()) and (stack.get_blueprint_tiles() or {}) or {}
    return {
      label = stack.label or stack.name,
      is_book = stack.is_blueprint_book,
      is_blueprint = stack.is_blueprint,
      setup = stack.is_blueprint and stack.is_blueprint_setup() or false,
      entities = entities,
      tiles = tiles
    }
  end)
end

function blueprint.list_book_exports(export_string)
  return with_temp_stack(function(stack)
    local code = stack.import_stack(export_string)
    if code == 1 or not stack.valid_for_read then
      return {}
    end
    if stack.is_blueprint and stack.is_blueprint_setup() then
      return {{
        label = stack.label or "blueprint",
        export = stack.export_stack()
      }}
    end
    if not stack.is_blueprint_book then
      return {}
    end
    local book = stack.get_inventory(defines.inventory.item_main)
    local result = {}
    if not book then
      return result
    end
    for i = 1, #book do
      local inner = book[i]
      if inner.valid_for_read then
        if inner.is_blueprint and inner.is_blueprint_setup() then
          table.insert(result, {
            label = inner.label or ("blueprint-" .. i),
            export = inner.export_stack()
          })
        elseif inner.is_blueprint_book then
          local nested = blueprint.list_book_exports(inner.export_stack())
          for _, item in pairs(nested) do
            table.insert(result, item)
          end
        end
      end
    end
    return result
  end)
end

local function save_pages(player_store, pages)
  if not pages or #pages == 0 then
    return nil, "no-cursor-blueprint"
  end
  local saved = {}
  for _, page in pairs(pages) do
    local id = new_storage_id(player_store)
    local decoded = blueprint.decode_export(page.export)
    local cost = blueprint.item_cost_from_export(page.export)
    local entry = {
      id = id,
      name = page.label or (decoded and decoded.label) or ("BP-" .. id),
      export = page.export,
      entity_count = decoded and #(decoded.entities or {}) or 0,
      tile_count = decoded and #(decoded.tiles or {}) or 0,
      cost = cost,
      created_tick = game.tick
    }
    player_store.blueprints[id] = entry
    table.insert(saved, entry)
  end
  return saved
end

local function collect_record_pages(record, player, out)
  if not record or not record.valid then
    return
  end
  if record.type == "blueprint" then
    local ready = true
    if record.is_blueprint_setup then
      ready = record.is_blueprint_setup()
    end
    if ready then
      local export_string = record.export_record()
      if export_string and export_string ~= "" then
        table.insert(out, {export = export_string})
      end
    end
    return
  end
  if record.type ~= "blueprint-book" then
    return
  end
  local contents = record.contents
  local size = record.contents_size or 0
  local found = false
  if contents and size > 0 then
    for i = 1, size do
      local inner = contents[i]
      if inner then
        local before = #out
        collect_record_pages(inner, player, out)
        if #out > before then
          found = true
        end
      end
    end
  end
  if not found and record.get_selected_record then
    collect_record_pages(record.get_selected_record(player), player, out)
  end
end

function blueprint.save_from_stack(player_store, stack)
  if not stack or not stack.valid_for_read then
    return nil, "no-cursor-blueprint"
  end
  if not (stack.is_blueprint or stack.is_blueprint_book) then
    return nil, "no-cursor-blueprint"
  end
  local export_string = stack.export_stack()
  local pages = blueprint.list_book_exports(export_string)
  if #pages == 0 then
    return nil, "blueprint-empty"
  end
  return save_pages(player_store, pages)
end

function blueprint.save_from_record(player_store, record, player)
  if not record or not record.valid then
    return nil, "no-cursor-blueprint"
  end
  local pages = {}
  collect_record_pages(record, player, pages)
  if #pages == 0 then
    return nil, "blueprint-empty"
  end
  return save_pages(player_store, pages)
end

-- 2.0：蓝图库 / Ctrl+C 复制件在 cursor_record，物品栏蓝图在 cursor_stack。
function blueprint.save_from_player(player, player_store)
  local stack = player.cursor_stack
  if stack and stack.valid_for_read and (stack.is_blueprint or stack.is_blueprint_book) then
    return blueprint.save_from_stack(player_store, stack)
  end
  local record = player.cursor_record
  if record and record.valid and (record.type == "blueprint" or record.type == "blueprint-book") then
    return blueprint.save_from_record(player_store, record, player)
  end
  local setup = player.blueprint_to_setup
  if setup and setup.valid_for_read and setup.is_blueprint then
    return blueprint.save_from_stack(player_store, setup)
  end
  return nil, "no-cursor-blueprint"
end

function blueprint.put_on_cursor(player, export_string)
  if not player.clear_cursor() then
    return false
  end
  local cursor = player.cursor_stack
  if not cursor or not cursor.valid then
    return false
  end
  local code = cursor.import_stack(export_string)
  if code == 1 or not cursor.valid_for_read or not (cursor.is_blueprint or cursor.is_blueprint_book) then
    player.clear_cursor()
    return false
  end
  player.cursor_stack_temporary = true
  return true
end

local function ensure_build_force(player)
  local name = "ai-bot-build-" .. player.force.name
  local force = game.forces[name]
  if not force then
    force = game.create_force(name)
    force.set_friend(player.force, true)
    force.set_cease_fire(player.force, true)
    player.force.set_friend(force, true)
    player.force.set_cease_fire(force, true)
    force.share_chart = true
  end
  return force
end

function blueprint.build_ghosts(player, export_string, position, force_build, direction, job)
  return with_temp_stack(function(stack)
    local code = stack.import_stack(export_string)
    if code == 1 or not stack.valid_for_read or not stack.is_blueprint then
      return {}
    end
    local mode = force_build and defines.build_mode.forced or defines.build_mode.normal
    return stack.build_blueprint{
      surface = player.surface,
      force = player.force,
      position = position,
      direction = direction or defines.direction.north,
      build_mode = mode,
      skip_fog_of_war = false,
      raise_built = false
    } or {}
  end)
end

return blueprint
