-- pixeltest: verify the CC:Graphics pixel API on the monitor
-- run as: report pixeltest   (then screenshot the monitor too)
local monName
for _, name in ipairs(peripheral.getNames()) do
  if peripheral.getType(name) == "monitor" then monName = name break end
end
if not monName then print("no monitor") return end

local m = peripheral.wrap(monName)
local interesting = {}
for _, method in ipairs(peripheral.getMethods(monName)) do
  local lower = method:lower()
  if lower:find("pixel") or lower:find("graphic") or lower:find("frame") or lower:find("palette") then
    interesting[#interesting + 1] = method
  end
end
table.sort(interesting)
print("gfx methods: " .. table.concat(interesting, ", "))

local ok, err = pcall(function()
  m.setGraphicsMode(1)
  local w, h = m.getSize(1)
  print("pixel canvas: " .. tostring(w) .. "x" .. tostring(h))
  for x = 0, math.min(w - 1, 100) do
    m.setPixel(x, x % (h or 100), colors.cyan)
    m.setPixel(x, 10, colors.red)
  end
  sleep(4)
  m.setGraphicsMode(0)
end)
print("draw test: " .. (ok and "OK" or ("FAILED " .. tostring(err))))
