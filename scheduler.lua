-- scheduler: continuous-batching work scheduler for the turtle pool.
--
-- Policy only - no I/O, no rednet, no peripherals. The warehouse supplies the
-- transport (dispatch a batch to a turtle) and the clock; this module decides
-- WHAT runs WHERE, so it can be tested headless with instant mock workers.
--
-- Model (the inference-serving analogy is exact):
--   job   = a craft request           (an inference request)
--   step  = one recipe in the plan     (a layer; steps run in planner order)
--   batch = <=64 crafts of a step      (a microbatch)
--   turtle= a worker                    (an accelerator)
--   priority: lower number = higher priority (0 = interactive player request,
--             10 = background stock reconcile)
--
-- Continuous batching: turtles are assigned per-batch and re-evaluated every
-- time one frees, so a high-priority job submitted mid-run acquires the next
-- freed worker at the batch boundary WITHOUT draining the queue first. No
-- job holds the whole pool; long low-priority runs never starve interactive
-- requests for more than one batch of latency.
local scheduler = {}
scheduler.__index = scheduler

local BATCH = 64

-- opts.softCap: background (low-priority) work is shed above this queue depth.
-- opts.hardCap: nothing is admitted above this (protects the main thread).
function scheduler.new(opts)
  opts = opts or {}
  return setmetatable({
    jobs = {}, seq = 0,
    softCap = opts.softCap or 16,
    hardCap = opts.hardCap or 64,
  }, scheduler)
end

function scheduler:load()
  return #self.jobs
end

-- admission control: decide BEFORE planning/submitting a job. Player requests
-- (priority 0) are admitted up to hardCap; background reconcile (priority>=10)
-- is shed above softCap so a big restock can't starve interactive requests or
-- pile unbounded work on the shared main thread. Load-shedding by priority.
function scheduler:admit(priority)
  local n = #self.jobs
  if n >= self.hardCap then
    return false, "queue full (" .. n .. "/" .. self.hardCap .. ")"
  end
  if (priority or 0) >= 10 and n >= self.softCap then
    return false, "factory busy, deferring background work (queue " .. n .. ")"
  end
  return true
end

-- steps: ordered list from planner; each { output, recipe, times, picks }
function scheduler:submit(job)
  self.seq = self.seq + 1
  local steps = {}
  for i, s in ipairs(job.steps) do
    steps[i] = { spec = s, toAssign = s.times, done = 0, inflight = 0 }
  end
  local entry = {
    id = job.id,
    priority = job.priority or 10,
    seq = self.seq,          -- FIFO tiebreak within a priority band
    steps = steps,
    cursor = 1,              -- steps before cursor are fully complete
    label = job.label or job.id,
    onDone = job.onDone,
  }
  self.jobs[#self.jobs + 1] = entry
  return entry
end

-- the current step of a job is eligible for assignment iff earlier steps are
-- fully done (dependency order) and it still has crafts left to hand out
local function eligibleStep(job)
  local step = job.steps[job.cursor]
  if not step then return nil end
  if step.toAssign > 0 then return step end
  return nil
end

-- jobs sorted by (priority asc, seq asc): the serving policy
local function ordered(jobs)
  local list = {}
  for _, j in ipairs(jobs) do list[#list + 1] = j end
  table.sort(list, function(a, b)
    if a.priority ~= b.priority then return a.priority < b.priority end
    return a.seq < b.seq
  end)
  return list
end

-- given a list of idle worker handles, return batch assignments for this round.
-- each assignment: { worker, job, step, count }. Greedy by priority; one job
-- can occupy several workers if higher-priority jobs have no eligible work.
function scheduler:assign(idleWorkers)
  local assignments = {}
  local workers = {}
  for _, w in ipairs(idleWorkers) do workers[#workers + 1] = w end

  for _, job in ipairs(ordered(self.jobs)) do
    while #workers > 0 do
      local step = eligibleStep(job)
      if not step then break end
      local count = math.min(BATCH, step.toAssign)
      step.toAssign = step.toAssign - count
      step.inflight = step.inflight + count
      local worker = table.remove(workers, 1)
      assignments[#assignments + 1] =
        { worker = worker, job = job, step = step, count = count }
    end
    if #workers == 0 then break end
  end
  return assignments
end

-- report the outcome of a dispatched batch. crafted may be < count on failure;
-- unfinished crafts return to the assignable pool so another worker retries.
function scheduler:complete(assignment, crafted)
  local step = assignment.step
  local job = assignment.job
  step.inflight = step.inflight - assignment.count
  crafted = math.max(0, math.min(crafted, assignment.count))
  step.done = step.done + crafted
  local shortfall = assignment.count - crafted
  if shortfall > 0 then step.toAssign = step.toAssign + shortfall end

  -- advance the cursor past any now-complete steps
  while job.steps[job.cursor]
        and job.steps[job.cursor].done >= job.steps[job.cursor].spec.times do
    job.cursor = job.cursor + 1
  end

  if job.cursor > #job.steps then
    self:_finish(job, true)
  end
  return step
end

-- a job makes no progress if it has eligible work but every dispatch fails;
-- the warehouse calls this to abandon a job whose current step is stuck.
function scheduler:fail(job, reason)
  self:_finish(job, false, reason)
end

function scheduler:_finish(job, ok, reason)
  for i, j in ipairs(self.jobs) do
    if j == job then table.remove(self.jobs, i) break end
  end
  if job.onDone then job.onDone(ok, reason) end
end

function scheduler:pending()
  return #self.jobs > 0
end

-- diagnostics for the dashboard / stats
function scheduler:snapshot()
  local out = {}
  for _, job in ipairs(ordered(self.jobs)) do
    local total, done = 0, 0
    for _, s in ipairs(job.steps) do
      total = total + s.spec.times
      done = done + s.done
    end
    out[#out + 1] = {
      id = job.id, label = job.label, priority = job.priority,
      step = job.cursor, steps = #job.steps, done = done, total = total,
    }
  end
  return out
end

return scheduler
