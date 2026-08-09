-- voice: the fleet's Chat Box brand - the Minutes, made audible.
-- Doctrine (planning/acquisition_review.md SS3): departments speak,
-- turtles don't; one line per event, ticket-subject grammar,
-- institutional third person. No questions to chat (probes go to the
-- Board by Minutes) except ACKNOWLEDGE. No exclamation marks, no
-- emoji, no apologies. Failures are filed, not sorry'd.
--
--   voice maiden [employees] [fallen]   perform the First Words
-- As a module: voice.say(chatBox, "PAYROLL", "text")
local M = {}

M.DEPARTMENTS = {
  BOARD = true, PAYROLL = true, HOUSE = true, BATTERY = true,
  PERSONNEL = true, CARPET = true, EXCHANGE = true,
}

-- enforce the brand at the API: uppercase, exclamations become
-- filings, apologies are struck, questions are demoted to statements
-- (ACKNOWLEDGE excepted - it is a probe, not a question)
function M.sanitize(text)
  local t = tostring(text)
  t = t:gsub("[\128-\255]", "")            -- no emoji survives utf-8 strip
  t = t:upper()
  t = t:gsub("%s*SORRY[,%s]*", " ")         -- failures are filed
  t = t:gsub("%s*APOLOGIES[,%s]*", " ")
  t = t:gsub("!", ".")
  if not t:find("ACKNOWLEDGE") then
    t = t:gsub("%?", ".")
  end
  t = t:gsub("%s+", " "):gsub("^%s", ""):gsub("%s$", "")
  if t ~= "" and not t:match("[%.%,%:]$") then t = t .. "." end
  return t
end

function M.format(dept, text)
  dept = tostring(dept):upper()
  if not M.DEPARTMENTS[dept] then dept = "PAYROLL" end
  return "[" .. dept .. "] " .. M.sanitize(text)
end

-- The First Words (acquisition review, adopted verbatim)
function M.firstWords(employees, fallen)
  return {
    "PROBE 1: THIS MESSAGE. ACKNOWLEDGE.",
    ("ROLL CALL: %d EMPLOYEES PRESENT. %d FALLEN. THE FALLEN DO NOT ANSWER.")
      :format(employees or 0, fallen or 0),
    "THE WORLD REMAINS LARGELY UNBENT. WORK RESUMES.",
  }
end

-- speak through an AP chat box; never throws (a missing box is a
-- silent corporation, not a crashed one)
function M.say(chatBox, dept, text)
  if not chatBox then return false end
  local ok = pcall(chatBox.sendMessage, M.format(dept, text), "Paperclip")
  return ok and true or false
end

if _TEST then return M end

-- ------------------------------------------------------- maiden program
local args = { ... }
if args[1] == "maiden" then
  local cb = peripheral.find("chatBox")
  if not cb then
    print("no chat box on this computer - the fleet remains mute")
    return
  end
  local employees = tonumber(args[2]) or 0
  local fallen = tonumber(args[3]) or 0
  local words = M.firstWords(employees, fallen)
  print("performing the First Words...")
  M.say(cb, "BOARD", words[1])
  -- await the operator's ACKNOWLEDGE (any chat containing the word)
  local deadline = os.clock() + 120
  local acked = false
  while os.clock() < deadline do
    local ev = { os.pullEventTimeout and os.pullEventTimeout("chat", 5)
      or os.pullEvent("chat") }
    if ev[1] == "chat" and tostring(ev[3]):upper():find("ACKNOWLEDGE") then
      acked = true
      break
    end
  end
  if acked then
    print("probe returned true. filed.")
  else
    print("no acknowledgement - proceeding anyway; the corporation is patient")
  end
  sleep(1)
  M.say(cb, "PERSONNEL", words[2])
  sleep(1)
  M.say(cb, "BOARD", words[3])
  print("the fleet has spoken. record the date.")
  return
end

print("usage: voice maiden [employees] [fallen]")
print("module: voice.say(chatBox, dept, text)")
return M
