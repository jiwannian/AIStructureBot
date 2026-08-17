-- 批量建造：先盖章放幽灵，Bot 到场后再分拍复活。
local util = require("scripts.util")
local blueprint = require("scripts.blueprint")
local inventory = require("scripts.inventory")

local builder = {}

local function ghost_item_name(ghost)
  return util.item_place_name(ghost.ghost_prototype) or ghost.ghost_name
end

function builder.remaining_cost(job)
  local cost = {}
  local kept = {}
  for _, ghost in pairs(job.ghosts or {}) do
    if ghost.valid then
      table.insert(kept, ghost)
      local name = ghost_item_name(ghost)
      if name then
        util.add_count(cost, name, util.quality_name(ghost.quality), 1)
      end
    end
  end
  job.ghosts = kept
  return cost
end

-- 每拍重扫本任务的剩余幽灵，只认规划区域（避免把全图幽灵拖进来）。
function builder.refresh_job_ghosts(player, job)
  local kept = {}
  local seen = {}
  local function keep(ghost)
    if ghost and ghost.valid and not seen[ghost.unit_number or ghost] then
      seen[ghost.unit_number or ghost] = true
      table.insert(kept, ghost)
    end
  end
  -- 先保住派工时认领的幽灵，区域扫描漏了也不要整单变空。
  for _, ghost in pairs(job.ghosts or {}) do
    keep(ghost)
  end
  local found
  if job.area then
    found = player.surface.find_entities_filtered{
      force = player.force,
      area = job.area,
      type = {"entity-ghost", "tile-ghost"}
    }
  elseif job.position then
    found = player.surface.find_entities_filtered{
      force = player.force,
      position = job.position,
      radius = 96,
      type = {"entity-ghost", "tile-ghost"}
    }
  end
  for _, ghost in pairs(found or {}) do
    keep(ghost)
  end
  job.ghosts = kept
  job.placed = #kept > 0
  return #kept
end

function builder.place_job_ghosts(player, job)
  -- 优先认领盖章时原版落下的幽灵，避免删了重放。
  local claimed = 0
  local kept = {}
  for _, ghost in pairs(job.ghosts or {}) do
    if ghost.valid then
      table.insert(kept, ghost)
      claimed = claimed + 1
    end
  end
  if claimed > 0 then
    job.ghosts = kept
    job.placed = true
    job.expected_count = claimed
    return claimed
  end
  local force_build = util.player_setting(player, "ai-bot-force-build", false)
  local ghosts = blueprint.build_ghosts(
    player,
    job.export,
    job.position,
    force_build,
    job.direction,
    job
  )
  job.ghosts = {}
  job.expected_count = 0
  for _, ghost in pairs(ghosts) do
    if ghost.valid then
      table.insert(job.ghosts, ghost)
      job.expected_count = job.expected_count + 1
    end
  end
  job.placed = true
  job.tile_built = job.tile_built or 0
  job.entity_built = job.entity_built or 0
  return #job.ghosts
end

local function still_marked(entity, force)
  if not entity or not entity.valid then
    return false
  end
  if entity.name == "ai-structure-bot" then
    return false
  end
  if entity.type == "entity-ghost" or entity.type == "tile-ghost" then
    return false
  end
  if not entity.to_be_deconstructed then
    return false
  end
  local ok, marked = pcall(function()
    return entity.to_be_deconstructed(force)
  end)
  if ok then
    return marked and true or false
  end
  ok, marked = pcall(function()
    return entity.to_be_deconstructed()
  end)
  return ok and marked
end

function builder.job_has_work(job)
  if not job then
    return false
  end
  for _, ghost in pairs(job.ghosts or {}) do
    if ghost.valid then
      return true
    end
  end
  for _, entity in pairs(job.marked or {}) do
    if entity.valid then
      return true
    end
  end
  return false
end

function builder.refresh_marked(player, job)
  local marked = {}
  local filter = {to_be_deconstructed = true}
  if job.area then
    filter.area = job.area
  end
  local candidates = player.surface.find_entities_filtered(filter)
  for _, entity in pairs(candidates) do
    if still_marked(entity, player.force) then
      table.insert(marked, entity)
    end
  end
  job.marked = marked
  return #marked
end

local function insert_mine_products(bot, player, entity)
  local proto = entity.prototype
  local props = proto and proto.mineable_properties
  local products = props and props.products
  if not products then
    return
  end
  for _, product in pairs(products) do
    if product.type == "item" and product.name then
      local amount = product.amount or product.amount_max or 1
      inventory.insert_or_refund(player, bot, product.name, util.quality_name(entity.quality), amount)
    end
  end
end

local function mine_marked_entity(player, bot, entity)
  local trunk = util.valid_entity(bot) and bot.get_inventory(defines.inventory.spider_trunk) or nil
  local ok, mined = pcall(function()
    return entity.mine{
      inventory = trunk,
      force = true,
      raise_destroyed = true,
      ignore_minable = true
    }
  end)
  if ok and (mined or not entity.valid) then
    return not entity.valid
  end
  if not entity.valid then
    return true
  end
  insert_mine_products(bot, player, entity)
  local destroyed = pcall(function()
    entity.destroy({raise_destroy = true})
  end)
  return destroyed and (not entity.valid)
end

function builder.deconstruct_batch(player, bot, job, batch_size)
  local done = 0
  local still = {}
  for _, entity in pairs(job.marked or {}) do
    if still_marked(entity, player.force) then
      if done < batch_size then
        if mine_marked_entity(player, bot, entity) then
          done = done + 1
          job.deconstructed = (job.deconstructed or 0) + 1
        else
          table.insert(still, entity)
        end
      else
        table.insert(still, entity)
      end
    end
  end
  job.marked = still
  return done, #still
end

function builder.revive_batch(player, bot, job, batch_size)
  if not job.placed then
    return 0, 0
  end
  local revived = 0
  local still = {}
  for _, ghost in pairs(job.ghosts or {}) do
    if ghost.valid then
      if revived < batch_size then
        local item_name = ghost_item_name(ghost)
        local quality = util.quality_name(ghost.quality)
        local have = 0
        if util.valid_entity(bot) then
          local trunk = bot.get_inventory(defines.inventory.spider_trunk)
          if trunk then
            have = util.count_item(trunk, item_name)
          end
        end
        if have < 1 and util.player_setting(player, "ai-bot-take-from-player", true) then
          have = util.count_item(player, item_name)
        end
        if have >= 1 then
          local is_tile = ghost.type == "tile-ghost"
          -- 幽灵复活后会失效，配方必须先读出来。
          local recipe_name
          if ghost.tags and ghost.tags.ai_recipe then
            recipe_name = ghost.tags.ai_recipe
          end
          local ok_rev, revived_entity = pcall(function()
            local _, ent = ghost.silent_revive()
            return ent
          end)
          revived_entity = ok_rev and revived_entity or nil
          local tile_ok = is_tile and (not ghost.valid)
          if revived_entity or tile_ok then
            local taken = 0
            if util.valid_entity(bot) then
              taken = inventory.try_remove_from_bot(bot, item_name, quality, 1)
            end
            if taken < 1 and util.player_setting(player, "ai-bot-take-from-player", true) then
              inventory.try_remove_from_player(player, item_name, quality, 1)
            end
            if revived_entity and revived_entity.valid then
              pcall(function()
                revived_entity.force = player.force
              end)
              if recipe_name then
                pcall(function()
                  revived_entity.set_recipe(recipe_name)
                end)
              end
            end
            revived = revived + 1
            if is_tile then
              job.tile_built = (job.tile_built or 0) + 1
            else
              job.entity_built = (job.entity_built or 0) + 1
            end
          else
            table.insert(still, ghost)
          end
        else
          table.insert(still, ghost)
        end
      else
        table.insert(still, ghost)
      end
    end
  end
  job.ghosts = still
  job.built_count = (job.built_count or 0) + revived
  return revived, #still
end

function builder.wake_bot(bot)
  if not util.valid_entity(bot) then
    return
  end
  bot.active = true
  pcall(function()
    for _, leg in pairs(bot.get_spider_legs() or {}) do
      if leg.valid then
        leg.active = true
      end
    end
  end)
end

function builder.move_bot(bot, position)
  if not util.valid_entity(bot) or not position then
    return
  end
  builder.wake_bot(bot)
  local dest = {
    x = position.x or position[1],
    y = position.y or position[2]
  }
  local current = bot.autopilot_destination
  if current and util.distance(current, dest) < 2 then
    return
  end
  pcall(function()
    bot.follow_target = nil
  end)
  pcall(function()
    bot.stop_spider()
  end)
  bot.autopilot_destination = dest
  if not bot.autopilot_destination then
    pcall(function()
      bot.add_autopilot_destination(dest)
    end)
  end
end

function builder.bot_in_range(bot, target, range)
  if not util.valid_entity(bot) then
    return false
  end
  return util.distance(bot.position, target) <= range
end

function builder.nearest_ghost_position(job, from_position)
  return builder.nearest_work_position(job, from_position, false)
end

function builder.nearest_work_position(job, from_position, include_marked)
  local origin = from_position or job.position
  local best, best_dist
  local function consider(entity)
    if entity and entity.valid then
      local dist = util.distance(origin, entity.position)
      if not best_dist or dist < best_dist then
        best = entity.position
        best_dist = dist
      end
    end
  end
  for _, ghost in pairs(job.ghosts or {}) do
    consider(ghost)
  end
  if include_marked ~= false then
    for _, entity in pairs(job.marked or {}) do
      consider(entity)
    end
  end
  return best
end

function builder.ghosts_in_range(bot, job, range)
  if not util.valid_entity(bot) then
    return false
  end
  for _, ghost in pairs(job.ghosts or {}) do
    if ghost.valid and util.distance(bot.position, ghost.position) <= range then
      return true
    end
  end
  return false
end

return builder
