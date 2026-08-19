-- 库存扫描：玩家背包、Bot 货舱、物流网络（可关，且保留安全库存）。
local util = require("scripts.util")

local inventory = {}

local function add_player_inventories(player, map)
  util.count_inventory(player.get_main_inventory(), map)
  if player.character and player.character.valid then
    util.count_inventory(player.get_inventory(defines.inventory.character_trash), map)
  end
end

local function add_bot_inventories(bot, map)
  if not util.valid_entity(bot) then
    return
  end
  util.count_inventory(bot.get_inventory(defines.inventory.spider_trunk), map)
  util.count_inventory(bot.get_inventory(defines.inventory.spider_trash), map)
end

function inventory.invalidate_scan()
  storage.scan_cache = nil
end

function inventory.list_force_bots(player)
  if not player or not player.valid then
    return {}
  end
  storage.fleet_cache = storage.fleet_cache or {}
  local key = player.force.index or player.force.name
  local cache = storage.fleet_cache[key]
  if cache and cache.tick == game.tick then
    return cache.bots
  end
  local bots = {}
  for _, surface in pairs(game.surfaces) do
    for _, bot in pairs(surface.find_entities_filtered{
      name = "ai-structure-bot",
      force = player.force
    }) do
      if bot.valid then
        table.insert(bots, bot)
      end
    end
  end
  storage.fleet_cache[key] = {tick = game.tick, bots = bots}
  return bots
end

local function add_fleet_inventories(player, map)
  for _, bot in ipairs(inventory.list_force_bots(player)) do
    add_bot_inventories(bot, map)
  end
end

local function each_network(force, surface, handler)
  local grouped = force.logistic_networks
  local networks = grouped and grouped[surface.name]
  if not networks then
    return
  end
  for _, network in pairs(networks) do
    if network.valid then
      handler(network)
    end
  end
end

local function add_logistic_networks(force, surface, map)
  each_network(force, surface, function(network)
    for _, stack in pairs(network.get_contents() or {}) do
      util.add_count(map, stack.name, stack.quality, stack.count)
    end
  end)
end

function inventory.scan_available(player, bot, include_network, include_player)
  storage.scan_cache = storage.scan_cache or {}
  local key = tostring(player.index) .. "|" .. tostring(include_network and true or false) .. "|" .. tostring(include_player and true or false)
  local cache = storage.scan_cache[key]
  if cache and cache.tick == game.tick then
    return cache.map
  end
  local map = {}
  if include_player then
    add_player_inventories(player, map)
  end
  add_fleet_inventories(player, map)
  if include_network then
    add_logistic_networks(player.force, player.surface, map)
  end
  storage.scan_cache[key] = {tick = game.tick, map = map}
  return map
end

function inventory.scan_sources(player, bot)
  local player_map, bot_map, net_map = {}, {}, {}
  add_player_inventories(player, player_map)
  add_fleet_inventories(player, bot_map)
  add_logistic_networks(player.force, player.surface, net_map)
  local all = {}
  util.merge_counts(all, bot_map)
  if util.player_setting(player, "ai-bot-take-from-player", true) then
    util.merge_counts(all, player_map)
  end
  if util.player_setting(player, "ai-bot-take-from-network", false) then
    util.merge_counts(all, net_map)
  end
  return {
    player = player_map,
    bot = bot_map,
    network = net_map,
    total = all
  }
end

function inventory.diff(need_map, have_map)
  local missing = {}
  for key, need in pairs(need_map) do
    local have_count = util.get_count(have_map, need.name, need.quality)
    if have_count < need.count then
      missing[key] = {
        name = need.name,
        quality = need.quality,
        count = need.count - have_count,
        need = need.count,
        have = have_count
      }
    end
  end
  return missing
end

function inventory.try_remove_from_player(player, name, quality, count)
  if count <= 0 then
    return 0
  end
  return player.remove_item({name = name, count = count, quality = quality}) or 0
end

function inventory.try_remove_from_bot(bot, name, quality, count)
  if not util.valid_entity(bot) or count <= 0 then
    return 0
  end
  inventory.invalidate_scan()
  local left = count
  local trunk = bot.get_inventory(defines.inventory.spider_trunk)
  if trunk then
    left = left - (trunk.remove({name = name, count = left, quality = quality}) or 0)
  end
  if left > 0 then
    local trash = bot.get_inventory(defines.inventory.spider_trash)
    if trash then
      left = left - (trash.remove({name = name, count = left, quality = quality}) or 0)
    end
  end
  return count - left
end

function inventory.try_remove_from_fleet(player, name, quality, count, prefer_bot)
  if count <= 0 then
    return 0
  end
  local left = count
  if prefer_bot and prefer_bot.valid then
    left = left - inventory.try_remove_from_bot(prefer_bot, name, quality, left)
  end
  if left <= 0 then
    return count
  end
  for _, bot in ipairs(inventory.list_force_bots(player)) do
    if not prefer_bot or bot.unit_number ~= prefer_bot.unit_number then
      left = left - inventory.try_remove_from_bot(bot, name, quality, left)
      if left <= 0 then
        break
      end
    end
  end
  return count - left
end

function inventory.count_fleet_item(player, name)
  return util.get_count(inventory.scan_available(player, nil, false, false), name, "normal")
end

function inventory.try_remove_from_network(player, name, quality, count)
  if count <= 0 or not util.player_setting(player, "ai-bot-take-from-network", false) then
    return 0
  end
  local reserve = util.player_setting(player, "ai-bot-reserve-stock", 50)
  local left = count
  each_network(player.force, player.surface, function(network)
    if left <= 0 then
      return
    end
    local available = network.get_item_count({name = name, quality = quality}) or 0
    local take = math.min(left, math.max(0, available - reserve))
    if take > 0 then
      local removed = network.remove_item({name = name, count = take, quality = quality}) or 0
      left = left - removed
    end
  end)
  return count - left
end

function inventory.insert_or_refund(player, bot, name, quality, count)
  if count <= 0 then
    return 0
  end
  local leftover = count
  if util.valid_entity(bot) then
    leftover = leftover - (bot.insert({name = name, count = leftover, quality = quality}) or 0)
  end
  if leftover > 0 then
    leftover = leftover - (player.insert({name = name, count = leftover, quality = quality}) or 0)
  end
  return count - leftover
end

function inventory.collect_items(player, bot, need_map)
  local collected = {}
  for _, need in pairs(need_map) do
    local remain = need.count
    local already_in_bot = 0
    if util.valid_entity(bot) then
      local trunk = bot.get_inventory(defines.inventory.spider_trunk)
      if trunk then
        already_in_bot = util.count_item(trunk, need.name)
        remain = remain - already_in_bot
      end
    end
    local taken_outside = 0
    if remain > 0 then
      local from_others = 0
      for _, other in ipairs(inventory.list_force_bots(player)) do
        if remain > 0 and (not bot or not bot.valid or other.unit_number ~= bot.unit_number) then
          local took = inventory.try_remove_from_bot(other, need.name, need.quality, remain)
          from_others = from_others + took
          remain = remain - took
        end
      end
      if from_others > 0 then
        inventory.insert_or_refund(player, bot, need.name, need.quality, from_others)
        already_in_bot = already_in_bot + from_others
      end
    end
    if remain > 0 and util.player_setting(player, "ai-bot-take-from-player", true) then
      local from_player = inventory.try_remove_from_player(player, need.name, need.quality, remain)
      taken_outside = taken_outside + from_player
      remain = remain - from_player
    end
    if remain > 0 then
      local from_net = inventory.try_remove_from_network(player, need.name, need.quality, remain)
      taken_outside = taken_outside + from_net
      remain = remain - from_net
    end
    if taken_outside > 0 then
      inventory.insert_or_refund(player, bot, need.name, need.quality, taken_outside)
    end
    collected[util.item_key(need.name, need.quality)] = {
      name = need.name,
      quality = need.quality,
      count = already_in_bot + taken_outside,
      remain = remain
    }
  end
  inventory.invalidate_scan()
  return collected
end

local REQUEST_GROUP = "ai-structure-bot"

local function find_or_add_section(bot)
  local sections = bot.get_logistic_sections and bot.get_logistic_sections()
  if not sections then
    return nil
  end
  for _, section in pairs(sections.sections or {}) do
    if section.valid and section.group == REQUEST_GROUP then
      return section
    end
  end
  if sections.add_section then
    return sections.add_section(REQUEST_GROUP)
  end
  return nil
end

function inventory.set_bot_requests(bot, missing)
  if not util.valid_entity(bot) then
    return false
  end
  local section = find_or_add_section(bot)
  if not section then
    return false
  end
  section.active = true
  local filters = {}
  local index = 1
  for _, item in pairs(missing) do
    filters[index] = {
      value = {
        type = "item",
        name = item.name,
        quality = item.quality or "normal",
        comparator = "="
      },
      min = item.count
    }
    index = index + 1
  end
  section.filters = filters
  return true
end

function inventory.clear_bot_requests(bot)
  if not util.valid_entity(bot) then
    return
  end
  local sections = bot.get_logistic_sections and bot.get_logistic_sections()
  if not sections then
    return
  end
  for _, section in pairs(sections.sections or {}) do
    if section.valid and section.group == REQUEST_GROUP then
      section.filters = {}
    end
  end
end

local function item_caption(name, count)
  local proto = prototypes.item[name]
  local label = proto and proto.localised_name or name
  return {"", label, "  x", tostring(count)}
end

function inventory.list_missing(missing)
  local lines = {}
  local rows = {}
  for _, item in pairs(missing or {}) do
    table.insert(rows, item)
  end
  table.sort(rows, function(a, b)
    return a.name < b.name
  end)
  for _, item in ipairs(rows) do
    table.insert(lines, item_caption(item.name, item.count))
  end
  return lines
end

function inventory.describe_wait(player, bot, missing)
  local reasons = {}
  table.insert(reasons, {"ai-bot.wait-need-title"})
  for _, line in ipairs(inventory.list_missing(missing)) do
    table.insert(reasons, line)
  end
  return reasons
end

return inventory
