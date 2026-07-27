-- display capability probe: run and paste the output back
local function report(t, label)
  local w, h = t.getSize()
  print(label .. ": " .. w .. "x" .. h .. " cells")
  print("  color: " .. tostring(t.isColor and t.isColor()))
  print("  palette: " .. tostring(t.setPaletteColour ~= nil))
  print("  pixelmode: " .. tostring(t.setGraphicsMode ~= nil))
end

report(term, "terminal")

local m = peripheral.find("monitor")
if m then
  m.setTextScale(0.5)
  report(m, "monitor@0.5")
else
  print("no monitor found")
end

local p = pocket and "THIS IS A POCKET" or "not a pocket"
print(p)
