-- AI 主循环：认领盖章幽灵、收集货舱、说明缺料原因、到场建造。
local util = require("scripts.util")
local blueprint = require("scripts.blueprint")
local inventory = require("scripts.inventory")
local resources = require("scripts.resources")
local builder = require("scripts.builder")
local gui = require("scripts.gui")
local craft = require("scripts.craft")
local plan = require("scripts.plan")
local maintain = require("scripts.maintain")

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
  local bots = maintain.list_bots(player)
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

  -- 幽灵/拆除列表由 tick_player 每拍刷新一次，这里只按当前列表计料。
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
  -- 与复活逻辑同一套计数：只看名字，不管品质字段，避免有货却判成不能建。
  local can_build_now = false
  for _, ghost in pairs(job.ghosts or {}) do
    if ghost.valid then
      local item_name = util.item_place_name(ghost.ghost_prototype) or ghost.ghost_name
      if item_name then
        if util.get_count(have, item_name, "normal") > 0 then
          can_build_now = true
          break
        end
      end
    end
  end

  local going_to_mine = false
  -- 有红图拆除时先拆，拆下来的材料可能正好补建造缺口。
  -- 缺料就去采/合成。不要因为手里还能摆几件就整拍站着。
  if next(missing) and not (job.marked and #job.marked > 0) then
    -- 每只 Bot 自己锁矿点，避免多机抢同一格。
    local bot_state = maintain.get_bot_state(bot.unit_number)
    local locked = bot_state.mine_target or job.mine_target
    local locked_ok = locked and locked.valid
    if locked_ok and locked.type == "resource" then
      local ok, amount = pcall(function()
        return locked.amount
      end)
      locked_ok = ok and (amount or 0) > 0
    end
    if locked_ok then
      job.status = "search"
      store.last_status = "search"
      builder.move_bot(bot, locked.position)
      going_to_mine = util.distance(bot.position, locked.position) > 6
      if not going_to_mine then
        bot_state.mine_target = nil
        job.mine_target = nil
      end
    end
    if not going_to_mine then
      local result = craft.try_fulfill(player, bot, missing, bot.position)
      if result.action == "move" and result.target then
        job.status = "search"
        store.last_status = "search"
        bot_state.mine_target = result.ore or bot_state.mine_target
        builder.move_bot(bot, result.target)
        going_to_mine = true
        if not job.craft_announced then
          job.craft_announced = true
          announce_wait(player, store, bot, job, missing)
          craft.announce(player, result)
        end
      elseif result.produced then
        bot_state.mine_target = nil
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
    end
  else
    maintain.get_bot_state(bot.unit_number).mine_target = nil
  end

  -- 正在去矿时本拍只赶路，不要改去幽灵点，否则蜘蛛原地来回。
  if going_to_mine then
    return
  end

  local site = builder.nearest_work_position(job, bot.position)
  if site and not builder.bot_in_range(bot, site, range) then
    job.status = "moving"
    store.last_status = "moving"
    builder.move_bot(bot, site)
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

  if not builder.job_has_work(job) then
    if job.export then
      local placed = builder.place_job_ghosts(player, job)
      if placed == 0 then
        player.print({"ai-bot.job-blocked", job.name})
        finish_job(player, store, job, "blocked")
        return
      end
    else
      -- 规划幽灵和红图拆除都已清空，才收尾。
      finish_job(player, store, job, "done")
      return
    end
  end

  job.status = "build"
  store.last_status = "build"
  local batch = util.global_setting("ai-bot-build-batch", 8)
  if job.marked and #job.marked > 0 then
    builder.deconstruct_batch(player, bot, job, batch)
    local next_mark = job.marked[1]
    if next_mark and next_mark.valid then
      builder.move_bot(bot, next_mark.position)
    end
  end
  local revived, remain = builder.revive_batch(player, bot, job, batch)
  remain = #(job.ghosts or {})
  local marked_left = job.marked and #job.marked or 0
  if remain == 0 and marked_left == 0 then
    player.print({
      "ai-bot.job-finished",
      job.name,
      tostring(job.entity_built or 0),
      tostring(job.tile_built or 0),
      tostring(job.deconstructed or 0)
    })
    finish_job(player, store, job, "done")
    return
  end
  if job.status == "search" then
    return
  end
  local next_site = builder.nearest_work_position(job, bot.position)
  if next_site and not builder.bot_in_range(bot, next_site, range) then
    job.status = "moving"
    store.last_status = "moving"
    builder.move_bot(bot, next_site)
  end
end

function ai.tick_player(player)
  if not player or not player.valid or not player.connected then
    return
  end
  local store = gui.player_store(player)
  -- 召回只赶被召回的那几只，其他 Bot 继续干活。
  plan.tick_recall(player)
  if store.planning then
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
  local maintain_bots = {}
  local build_bots = {}
  for _, worker in ipairs(maintain.list_bots(player)) do
    if worker.valid then
      local worker_state = maintain.get_bot_state(worker.unit_number)
      if not worker_state.paused and not worker_state.recalling then
        if worker_state.mode == "maintain" then
          table.insert(maintain_bots, worker)
        elseif worker_state.mode == "build" then
          table.insert(build_bots, worker)
        end
      end
    end
  end

  -- 建造和维护同一拍都跑。先建造，避免维护全图扫描把建造挤掉。
  if store.queue and #store.queue > 0 and #build_bots > 0 then
    local job = store.queue[1]
    builder.refresh_job_ghosts(player, job)
    builder.refresh_marked(player, job)
    store.last_status = "build"
    for _, worker in ipairs(build_bots) do
      if maintain.get_bot_state(worker.unit_number).mode ~= "maintain" then
        if not store.queue[1] or store.queue[1] ~= job then
          break
        end
        local ok, err = pcall(process_job, player, store, worker, job)
        if not ok then
          job.status = "failed"
          store.last_status = "failed"
          job.fail_count = (job.fail_count or 0) + 1
          if job.fail_count <= 2 then
            player.print(err)
          end
          if job.fail_count >= 3 then
            finish_job(player, store, job, "failed")
            break
          end
        end
      end
    end
  elseif #maintain_bots > 0 then
    store.last_status = "maintain"
  elseif store.last_status ~= "idle" and store.last_status ~= "done" then
    store.last_status = "idle"
  end

  if #maintain_bots > 0 then
    for _, worker in ipairs(maintain_bots) do
      local ok, err = pcall(maintain.tick, player, worker, maintain_bots)
      if not ok then
        player.print(err)
      end
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
