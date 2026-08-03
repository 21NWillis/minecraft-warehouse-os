-- surveyd: nightly survey daemon. Parks a dedicated turtle at a wing's
-- survey station and rescans on a timer, forever. Survives server restarts
-- if launched from startup:
--   startup.lua:  shell.run("surveyd", "16", "16", "8", "warehouse")
-- (a restart just triggers an immediate rescan, then the cycle resumes)
--
-- USAGE:  surveyd <width> <length> <height> <label> [hours=24]
local tArgs = { ... }
if #tArgs < 4 then
  print("usage: surveyd <width> <length> <height> <label> [hours]")
  return
end
local hours = tonumber(tArgs[5] or "24")

while true do
  shell.run("survey", tArgs[1], tArgs[2], tArgs[3], tArgs[4])
  print(("surveyd: sleeping %sh until next scan"):format(hours))
  os.sleep(hours * 3600)
end
