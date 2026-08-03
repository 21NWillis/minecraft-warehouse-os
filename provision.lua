-- provision: the flash-drive installer. Copy onto a floppy as its startup:
--   1. craft a disk drive + floppy disk
--   2. put the floppy in a drive attached to any ALREADY-installed computer
--   3. on that computer:  copy provision.lua disk/startup.lua
--   4. leave the floppy in the drive; place fresh turtles/computers next to
--      the drive - they boot the floppy, self-install PaperclipOS, reboot,
--      and drop to a ready shell. Fuel + pickaxe are still your job.
if not os.getComputerLabel() then
  os.setComputerLabel(("clip-%d"):format(os.getComputerID()))
  print("[provision] labelled " .. os.getComputerLabel())
end

if fs.exists("/menu.lua") then
  print("[provision] PaperclipOS already installed; shell is yours")
  return
end

local BASE = "https://raw.githubusercontent.com/21NWillis/minecraft-warehouse-os/main/"
print("[provision] installing PaperclipOS from " .. BASE)
local r, err = http.get(BASE .. "update.lua")
if not r then
  printError("[provision] cannot reach GitHub: " .. tostring(err))
  return
end
local f = fs.open("/update.lua", "w")
f.write(r.readAll())
r.close()
f.close()
shell.run("/update.lua", BASE)
print("[provision] installed; rebooting into a ready turtle")
sleep(1)
os.reboot()
