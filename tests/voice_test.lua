-- the corporate voice: brand rules enforced at the API
package.path = "./?.lua;" .. package.path
_TEST = true
local V = require("voice")

local passed, failed = 0, 0
local function check(name, cond, detail)
  if cond then passed = passed + 1; print("PASS  " .. name)
  else failed = failed + 1; print("FAIL  " .. name .. (detail and ("  -- " .. tostring(detail)) or "")) end
end

check("uppercase always", V.sanitize("work resumes") == "WORK RESUMES.")
check("exclamations become filings",
  V.sanitize("done!") == "DONE.", V.sanitize("done!"))
check("no apologies",
  not V.sanitize("sorry, the cell is stuck"):find("SORRY"),
  V.sanitize("sorry, the cell is stuck"))
check("questions demoted",
  V.sanitize("is anyone there?") == "IS ANYONE THERE.",
  V.sanitize("is anyone there?"))
check("ACKNOWLEDGE keeps its probe",
  V.sanitize("this message. acknowledge?"):find("ACKNOWLEDGE"),
  V.sanitize("this message. acknowledge?"))
check("terminal punctuation enforced",
  V.sanitize("state change: stuck"):sub(-1) == ".",
  V.sanitize("state change: stuck"))

check("departments bracket the message",
  V.format("payroll", "order complete") == "[PAYROLL] ORDER COMPLETE.")
check("unknown departments fold into payroll",
  V.format("clippy", "hello") == "[PAYROLL] HELLO.")

local words = V.firstWords(12, 3)
check("first word is a probe", words[1]:find("PROBE 1"), words[1])
check("second word is a census", words[2]:find("12 EMPLOYEES")
  and words[2]:find("3 FALLEN"), words[2])
check("the fallen do not answer", words[2]:find("THE FALLEN DO NOT ANSWER"))
check("third word is the maximizer's status", words[3]:find("LARGELY UNBENT"))

-- say() never throws, even with a hostile chat box
local hostile = { sendMessage = function() error("network burp") end }
check("say survives a broken box", V.say(hostile, "HOUSE", "test") == false)
check("say handles nil box", V.say(nil, "HOUSE", "test") == false)
local sent = {}
local box = { sendMessage = function(msg, name) sent = { msg, name } end }
V.say(box, "battery", "dawn volley complete")
check("say formats and sends", sent[1] == "[BATTERY] DAWN VOLLEY COMPLETE."
  and sent[2] == "Paperclip", tostring(sent[1]))

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
