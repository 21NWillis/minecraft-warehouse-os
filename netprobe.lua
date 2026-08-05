-- netprobe: hard evidence for the wired-network bug. Run on any
-- computer. For every attached modem it prints: side, wired/wireless,
-- this machine's name on that network, and every remote peripheral the
-- modem claims to see. If a wired modem shows zero remotes while a
-- cable run visibly connects it to an activated modem, node linking is
-- broken - that output IS the bug report.
local sides = { "left", "right", "top", "bottom", "front", "back" }
local found = false
for _, side in ipairs(sides) do
  if peripheral.getType(side) == "modem" then
    found = true
    local m = peripheral.wrap(side)
    local wireless = m.isWireless and m.isWireless()
    print(("%s: %s modem"):format(side, wireless and "wireless" or "WIRED"))
    if not wireless then
      local okL, localName = pcall(m.getNameLocal)
      print(("  my name on this net: %s"):format(okL and tostring(localName) or "?"))
      local okR, remotes = pcall(m.getNamesRemote)
      if okR and type(remotes) == "table" then
        print(("  remote peripherals: %d"):format(#remotes))
        for _, r in ipairs(remotes) do
          print("    " .. r)
        end
      else
        print("  getNamesRemote failed: " .. tostring(remotes))
      end
    end
  end
end
if not found then print("no modems attached to this computer") end
