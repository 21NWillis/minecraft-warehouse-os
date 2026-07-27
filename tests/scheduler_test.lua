-- headless scheduler tests: mock workers complete instantly, so we can assert
-- the serving policy (priority preemption, dependency order, pool sharing,
-- failure requeue) without any turtles or rednet.
package.path = "./?.lua;" .. package.path

local scheduler = require("scheduler")

local passed, failed = 0, 0
local function check(name, cond, detail)
  if cond then passed = passed + 1; print("PASS  " .. name)
  else failed = failed + 1; print("FAIL  " .. name .. (detail and ("  -- " .. tostring(detail)) or "")) end
end

local function step(output, times) return { output = output, times = times, recipe = {}, picks = {} } end

-- drive the scheduler to completion with W workers, recording the order in
-- which (jobId, output) batches are dispatched. mock dispatch always succeeds.
local function drive(sched, W, opts)
  opts = opts or {}
  local log = {}
  local rounds = 0
  while sched:pending() and rounds < 1000 do
    rounds = rounds + 1
    local workers = {}
    for i = 1, W do workers[i] = "t" .. i end
    local assigns = sched:assign(workers)
    if #assigns == 0 then break end
    for _, a in ipairs(assigns) do
      log[#log + 1] = { job = a.job.id, out = a.step.spec.output, count = a.count, round = rounds }
      local crafted = a.count
      if opts.failFirst and opts.failFirst[a.step.spec.output] then
        crafted = 0
        opts.failFirst[a.step.spec.output] = nil  -- fail once, then succeed
      end
      sched:complete(a, crafted)
    end
    if opts.inject and opts.inject[rounds] then opts.inject[rounds](sched) end
  end
  return log, rounds
end

-- 1. single job, single step, batches split across workers
do
  local s = scheduler.new()
  s:submit({ id = "j1", priority = 0, steps = { step("stick", 200) } })
  local log = drive(s, 4)
  local total = 0
  for _, e in ipairs(log) do total = total + e.count end
  check("all 200 crafts dispatched", total == 200, total)
  check("batched into ceil(200/64)=4 batches", #log == 4, #log)
  check("first round used all 4 workers", log[4].round == 1, log[4].round)
end

-- 2. dependency order: step 2 never dispatches before step 1 completes
do
  local s = scheduler.new()
  s:submit({ id = "j", priority = 0, steps = { step("planks", 100), step("table", 25) } })
  local log = drive(s, 4)
  local lastPlanks, firstTable
  for i, e in ipairs(log) do
    if e.out == "planks" then lastPlanks = i end
    if e.out == "table" and not firstTable then firstTable = i end
  end
  check("planks all dispatched before first table", lastPlanks < firstTable,
    ("planks@%s table@%s"):format(tostring(lastPlanks), tostring(firstTable)))
end

-- 3. priority preemption: a p0 job injected mid-run grabs the next freed
--    worker ahead of the running p10 stock job (continuous batching)
do
  local s = scheduler.new()
  s:submit({ id = "stock", priority = 10, steps = { step("cobble", 640) } })  -- 10 batches
  local grabbedRound
  local log = drive(s, 1, {
    inject = {
      [3] = function(sched)
        sched:submit({ id = "urgent", priority = 0, steps = { step("pickaxe", 64) } })
      end,
    },
  })
  for _, e in ipairs(log) do
    if e.job == "urgent" then grabbedRound = grabbedRound or e.round end
  end
  -- injected before round 3's completion; must run at round 4, not after all
  -- 10 cobble batches (which would be round 11)
  check("urgent p0 preempts running p10 at next batch", grabbedRound and grabbedRound <= 5,
    "urgent ran at round " .. tostring(grabbedRound))
end

-- 4. pool sharing: with 2 jobs same priority and 4 workers, both get workers
--    in the same round (no head-of-line blocking within a band)
do
  local s = scheduler.new()
  s:submit({ id = "a", priority = 5, steps = { step("x", 64) } })
  s:submit({ id = "b", priority = 5, steps = { step("y", 64) } })
  local assigns = s:assign({ "t1", "t2", "t3", "t4" })
  local jobs = {}
  for _, a in ipairs(assigns) do jobs[a.job.id] = true end
  check("two same-priority jobs share the pool", jobs.a and jobs.b)
end

-- 5. failure requeue: a batch that crafts 0 returns its work to the pool
do
  local s = scheduler.new()
  local doneOk
  s:submit({ id = "j", priority = 0, steps = { step("gear", 64) },
             onDone = function(ok) doneOk = ok end })
  local log = drive(s, 1, { failFirst = { gear = true } })
  local total = 0
  for _, e in ipairs(log) do total = total + e.count end
  check("failed batch retried until 64 crafted", total == 128, total)  -- 64 failed + 64 ok
  check("job completes ok after retry", doneOk == true, tostring(doneOk))
end

-- 6. onDone fires exactly once on completion
do
  local s = scheduler.new()
  local calls = 0
  s:submit({ id = "j", priority = 0, steps = { step("z", 10) },
             onDone = function() calls = calls + 1 end })
  drive(s, 2)
  check("onDone fires exactly once", calls == 1, calls)
  check("scheduler empty after completion", not s:pending())
end

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
