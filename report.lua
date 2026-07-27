-- report <program> [args...]: run a program, capture screen output, upload to pastebin
-- then read me the short code it prints
local args = { ... }
if #args == 0 then
  print("usage: report <program> [args...]")
  return
end

local parent = term.current()
local w, h = parent.getSize()
local win = window.create(parent, 1, 1, w, h, true)
local old = term.redirect(win)
local ok, err = pcall(shell.run, table.unpack(args))
term.redirect(old)

local lines = {}
for y = 1, h do
  local text = win.getLine(y)
  lines[#lines + 1] = text:gsub("%s+$", "")
end
while #lines > 0 and lines[#lines] == "" do table.remove(lines) end
if not ok then lines[#lines + 1] = "ERROR: " .. tostring(err) end

local f = fs.open(".report.txt", "w")
f.write(table.concat(lines, "\n"))
f.close()
shell.run("pastebin", "put", ".report.txt")
