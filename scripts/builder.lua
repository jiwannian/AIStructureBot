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

function builder.revive_batch(player, bot, job, batch_size)
  if not job.placed then
    return 0, 0
  end
  local range = util.player_setting(player, "ai-bot-work-range", 24)
  local revived = 0
  local still = {}
  for _, ghost in pairs(job.ghosts or {}) do
    if ghost.valid then
      if revived < batch_size and builder.bot_in_range(bot, ghost.position, range) then
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
          local _, revived_entity = ghost.silent_revive()
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
              revived_entity.force = player.force
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

function builder.move_bot(bot, position)
  if not util.valid_entity(bot) or not position then
    return
  end
  if bot.active == false then
    bot.active = true
  end
  bot.follow_target = nil
  pcall(function()
    bot.stop_spider()
  end)
  bot.autopilot_destination = nil
  bot.add_autopilot_destination(position)
end

function builder.bot_in_range(bot, target, range)
  if not util.valid_entity(bot) then
    return false
  end
  return util.distance(bot.position, target) <= range
end

function builder.nearest_ghost_position(job, from_position)
  local origin = from_position or job.position
  local best, best_dist
  for _, ghost in pairs(job.ghosts or {}) do
    if ghost.valid then
      local dist = util.distance(origin, ghost.position)
      if not best_dist or dist < best_dist then
        best = ghost.position
        best_dist = dist
      end
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
