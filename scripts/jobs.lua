-- 任务入队与幽灵认领：接受原版蓝图落下，不再删了重放。
local jobs = {}

local function store_of(player)
  storage.players = storage.players or {}
  storage.players[player.index] = storage.players[player.index] or {}
  local store = storage.players[player.index]
  store.queue = store.queue or {}
  return store
end

function jobs.current(player)
  local store = store_of(player)
  return store.queue[1]
end

function jobs.claim_window(player)
  return store_of(player).claim
end

function jobs.begin_claim(player, job)
  store_of(player).claim = {
    job = job,
    tick = game.tick,
    position = job.position
  }
end

function jobs.end_claim(player)
  store_of(player).claim = nil
end

function jobs.enqueue(player, entry, position, direction, flip)
  local store = store_of(player)
  local last = store.queue[#store.queue]
  if last and last.export == entry.export and last.tick and game.tick - last.tick < 10 then
    if math.abs((last.position.x or 0) - (position.x or 0)) < 1.5
      and math.abs((last.position.y or 0) - (position.y or 0)) < 1.5 then
      return last, true
    end
  end
  local job = {
    id = entry.id,
    name = entry.name,
    export = entry.export,
    cost = entry.cost,
    position = {x = position.x, y = position.y},
    direction = direction or defines.direction.north,
    flip_horizontal = flip and flip.horizontal or false,
    flip_vertical = flip and flip.vertical or false,
    mirror = flip and flip.mirror or false,
    status = "queued",
    placed = false,
    ghosts = {},
    built_count = 0,
    entity_built = 0,
    tile_built = 0,
    tick = game.tick
  }
  table.insert(store.queue, job)
  return job, false
end

local function matches_job(job, entity)
  if not job or not entity or not entity.valid then
    return false
  end
  if entity.type ~= "entity-ghost" and entity.type ~= "tile-ghost" then
    return false
  end
  local dx = entity.position.x - job.position.x
  local dy = entity.position.y - job.position.y
  return (dx * dx + dy * dy) <= (64 * 64)
end

function jobs.attach_ghost(player, entity)
  local store = store_of(player)
  local claim = store.claim
  local job = claim and claim.job
  if not job then
    job = store.queue[#store.queue]
    if job and job.tick and game.tick - job.tick > 2 then
      return false
    end
  end
  if not matches_job(job, entity) then
    return false
  end
  job.ghosts = job.ghosts or {}
  table.insert(job.ghosts, entity)
  job.placed = true
  job.expected_count = (job.expected_count or 0) + 1
  if entity.cancel_deconstruction then
    entity.cancel_deconstruction(entity.force)
  end
  return true
end

return jobs
