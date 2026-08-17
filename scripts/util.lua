-- 通用工具：距离、库存计数、玩家设置读取。
local util = {}

function util.distance(a, b)
  local dx = (a.x or a[1]) - (b.x or b[1])
  local dy = (a.y or a[2]) - (b.y or b[2])
  return math.sqrt(dx * dx + dy * dy)
end

function util.player_setting(player, name, fallback)
  local settings_map = player.mod_settings
  if settings_map and settings_map[name] then
    return settings_map[name].value
  end
  return fallback
end

function util.global_setting(name, fallback)
  local settings_map = settings.global
  if settings_map and settings_map[name] then
    return settings_map[name].value
  end
  return fallback
end

function util.quality_name(quality)
  if not quality then
    return "normal"
  end
  if type(quality) == "string" then
    return quality
  end
  return quality.name or "normal"
end

function util.item_key(name, quality)
  return name .. "|" .. util.quality_name(quality)
end

function util.add_count(map, name, quality, count)
  if not name or not count or count <= 0 then
    return
  end
  local key = util.item_key(name, quality)
  local entry = map[key]
  if not entry then
    map[key] = {name = name, quality = util.quality_name(quality), count = count}
  else
    entry.count = entry.count + count
  end
end

function util.merge_counts(dst, src)
  for _, entry in pairs(src) do
    util.add_count(dst, entry.name, entry.quality, entry.count)
  end
end

function util.count_inventory(inv, map)
  if not inv or not inv.valid then
    return
  end
  local contents = inv.get_contents()
  for _, stack in pairs(contents) do
    util.add_count(map, stack.name, stack.quality, stack.count)
  end
end

function util.get_count(map, name, quality)
  local entry = map[util.item_key(name, quality)]
  if entry then
    return entry.count
  end
  -- 普通品质：兼容库存里没带 quality 字段的计数。
  if util.quality_name(quality) == "normal" then
    local any = 0
    for _, row in pairs(map) do
      if row.name == name then
        any = any + row.count
      end
    end
    return any
  end
  return 0
end

function util.count_item(owner, name)
  if not owner then
    return 0
  end
  local ok, count = pcall(function()
    return owner.get_item_count(name)
  end)
  return (ok and count) or 0
end

function util.valid_entity(entity)
  return entity and entity.valid
end

function util.safe_destroy(element)
  if element and element.valid then
    element.destroy()
  end
end

function util.item_place_name(proto)
  if not proto then
    return nil
  end
  local items = proto.items_to_place_this
  if items then
    if items[1] and items[1].name then
      return items[1].name
    end
    for _, item in pairs(items) do
      if item and item.name then
        return item.name
      end
    end
  end
  local props = proto.mineable_properties
  if props and props.products then
    for _, product in pairs(props.products) do
      if product.type == "item" and product.name then
        return product.name
      end
    end
  end
  return proto.name
end

function util.next_cardinal(direction)
  local order = {
    defines.direction.north,
    defines.direction.east,
    defines.direction.south,
    defines.direction.west
  }
  for index, value in ipairs(order) do
    if value == (direction or defines.direction.north) then
      return order[(index % #order) + 1]
    end
  end
  return defines.direction.east
end

function util.near(a, b, extra)
  extra = extra or 8
  return util.distance(a, b) <= extra
end

function util.give_temp_tool(player, item_name)
  if not player or not player.clear_cursor then
    return false
  end
  if not player.clear_cursor() then
    return false
  end
  local cursor = player.cursor_stack
  if not cursor or not cursor.valid then
    return false
  end
  return cursor.set_stack({name = item_name, count = 1})
end

return util
