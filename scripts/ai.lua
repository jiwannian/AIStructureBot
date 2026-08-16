-- AI 主循环：认领盖章幽灵、收集货舱、说明缺料原因、到场建造。
local util = require("scripts.util")
local blueprint = require("scripts.blueprint")
local inventory = require("scripts.inventory")
local resources = require("scripts.resources")
local builder = require("scripts.builder")
local gui = require("scripts.gui")
local craft = require("scripts.craft")

local ai = {}

local function warn_job_stock(player, store, have_map, need_map)
  local threshold = util.player_setting(player, "ai-bot-warn-threshold", 20)
  store.warnings = {}
  if threshold <= 0 or not need_map then
    return
  end
  for _, need in pairs(need_map) do
    local have = have_map[util.item_key(need.name, need.quality)]
    local count = have and have.count or 0
    if count <= threshold then
      table.insert(store.warnings, {"ai-bot.warning-low", need.name, tostring(count)})
    end
  end
end

local function auto_assign_bot(player)
  local bot = gui.get_assigned_bot(player)
  if bot then
    return bot
  end
  local bots = player.surface.find_entities_filtered{
    name = "ai-structure-bot",
    force = player.force
  }
  if bots[1] then
    gui.assign_bot(player, bots[1])
    return bots[1]
  end
  return nil
end

local function finish_job(player, store, job, status_key)
  inventory.clear_bot_requests(gui.get_assigned_bot(player))
  job.status = status_key
  store.last_status = status_key
  store.last_wait_reasons = {}
  table.remove(store.queue, 1)
end

local function announce_wait(player, store, bot, job, missing)
  local reasons = inventory.describe_wait(player, bot, missing)
  store.last_wait_reasons = reasons
  if job.waiting_announced then
    return
  end
  job.waiting_announced = true
  player.print({"ai-bot.job-waiting"})
  for _, reason in ipairs(reasons) do
    player.print(reason)
  end
end

local function process_job(player, store, bot, job)
  if job.status == "queued" then
    player.print({"ai-bot.job-started", job.name})
    job.status = "scan"
    job.wait_started = nil
  end

  -- 只按还没建完的幽灵计料，避免建完一座又按整单去挖矿。
  local need = builder.remaining_cost(job)
  if (not next(need)) and job.export then
    need = job.cost or blueprint.item_cost_from_export(job.export)
  end
  job.cost = need
  store.last_need = need
  local include_net = util.player_setting(player, "ai-bot-take-from-network", false)
  local include_player = util.player_setting(player, "ai-bot-take-from-player", true)
  local have = inventory.scan_available(player, bot, include_net, include_player)
  warn_job_stock(player, store, have, need)
  inventory.collect_items(player, bot, need)
  have = inventory.scan_available(player, bot, include_net, include_player)
  local missing = inventory.diff(need, have)
  store.last_missing = missing

  local range = util.player_setting(player, "ai-bot-work-range", 24)
  local can_build_now = false
  for _, ghost in pairs(job.ghosts or {}) do
    if ghost.valid then
      local item_name = util.item_place_name(ghost.ghost_prototype) or ghost.ghost_name
      if item_name and util.get_count(have, item_name, ghost.quality) > 0 then
        can_build_now = true
        break
      end
    end
  end

  if next(missing) and not can_build_now then
    local result = craft.try_fulfill(player, bot, missing)
    if result.action == "move" and result.target then
      job.status = "search"
      store.last_status = "search"
      builder.move_bot(bot, result.target)
      if not job.craft_announced then
        job.craft_announced = true
        announce_wait(player, store, bot, job, missing)
        craft.announce(player, result)
      end
      return
    end
    if result.produced then
      have = inventory.scan_available(player, bot, include_net, include_player)
      missing = inventory.diff(need, have)
      store.last_missing = missing
      if not job.last_craft_tick or game.tick - job.last_craft_tick > 60 then
        craft.announce(player, result)
        job.last_craft_tick = game.tick
      end
    elseif not job.craft_announced then
      job.craft_announced = true
      announce_wait(player, store, bot, job, missing)
      craft.announce(player, result)
    end
    have = inventory.scan_available(player, bot, include_net, include_player)
    for _, ghost in pairs(job.ghosts or {}) do
      if ghost.valid then
        local item_name = util.item_place_name(ghost.ghost_prototype) or ghost.ghost_name
        if item_name and util.get_count(have, item_name, ghost.quality) > 0 then
          can_build_now = true
          break
        end
      end
    end
    if next(missing) and not can_build_now then
      job.status = "search"
      store.last_status = "search"
      return
    end
  end

  local site = builder.nearest_ghost_position(job, bot.position)
  if site and not builder.ghosts_in_range(bot, job, range) then
    job.status = "moving"
    store.last_status = "moving"
    builder.move_bot(bot, site)
    return
  end

  if next(missing) then
    store.last_wait_reasons = inventory.describe_wait(player, bot, missing)
    inventory.set_bot_requests(bot, missing)
    if not job.waiting_announced then
      announce_wait(player, store, bot, job, missing)
    end
  else
    inventory.clear_bot_requests(bot)
    store.last_wait_reasons = {}
  end

  if not job.placed or not job.ghosts or #job.ghosts == 0 then
    local placed = builder.place_job_ghosts(player, job)
    if placed == 0 then
      player.print({"ai-bot.job-blocked", job.name})
      finish_job(player, store, job, "blocked")
      return
    end
  end

  job.status = "build"
  store.last_status = "build"
  local batch = util.global_setting("ai-bot-build-batch", 8)
  local revived, remain = builder.revive_batch(player, bot, job, batch)
  if remain == 0 then
    if (job.built_count or 0) == 0 then
      player.print({"ai-bot.job-blocked", job.name})
      finish_job(player, store, job, "blocked")
      return
    end
    player.print({
      "ai-bot.job-finished",
      job.name,
      tostring(job.entity_built or 0),
      tostring(job.tile_built or 0)
    })
    finish_job(player, store, job, "done")
  elseif revived == 0 then
    local next_site = builder.nearest_ghost_position(job, bot.position)
    if next_site and not builder.bot_in_range(bot, next_site, range) then
      job.status = "moving"
      store.last_status = "moving"
      builder.move_bot(bot, next_site)
    elseif next(missing) then
      job.status = "search"
      store.last_status = "search"
    end
  end
end

function ai.tick_player(player)
  if not player or not player.valid or not player.connected then
    return
  end
  local store = gui.player_store(player)
  if store.planning then
    return
  end
  if not store.enabled then
    store.last_status = "disabled"
    return
  end
  if not store.queue or #store.queue == 0 then
    if store.last_status ~= "idle" and store.last_status ~= "done" then
      store.last_status = "idle"
    end
    return
  end
  local bot = auto_assign_bot(player)
  if not bot then
    store.last_status = "failed"
    if not store.no_bot_announced then
      player.print({"ai-bot.no-bot"})
      store.no_bot_announced = true
    end
    return
  end
  store.no_bot_announced = false
  local job = store.queue[1]
  local ok, err = pcall(process_job, player, store, bot, job)
  if not ok then
    job.status = "failed"
    store.last_status = "failed"
    job.fail_count = (job.fail_count or 0) + 1
    if job.fail_count <= 2 then
      player.print(err)
    end
    if job.fail_count >= 3 then
      finish_job(player, store, job, "failed")
    end
  end
end

function ai.on_tick(event)
  local interval = util.global_setting("ai-bot-tick-interval", 30)
  if event.tick % interval ~= 0 then
    return
  end
  for _, player in pairs(game.connected_players) do
    ai.tick_player(player)
    if event.tick % (interval * 4) == 0 then
      gui.refresh(player)
    end
  end
end

return ai
