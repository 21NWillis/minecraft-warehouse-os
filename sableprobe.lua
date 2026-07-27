-- sableprobe: dump whatever CC:Sable exposes so we can build the orbital
-- cockpit against reality instead of guessing. Run on a computer placed on a
-- Sable / Create Aeronautics ship, then: report sableprobe
local function dump(label, v, depth)
  depth = depth or 0
  local pad = string.rep("  ", depth)
  if type(v) == "table" then
    print(pad .. label .. " = {")
    local n = 0
    for k, val in pairs(v) do
      n = n + 1
      if n > 20 then print(pad .. "  ...more"); break end
      if type(val) == "function" then
        print(pad .. "  " .. tostring(k) .. "()")
      elseif type(val) == "table" and depth < 2 then
        dump(tostring(k), val, depth + 1)
      else
        print(pad .. "  " .. tostring(k) .. " = " .. tostring(val))
      end
    end
    print(pad .. "}")
  else
    print(pad .. label .. " = " .. tostring(v) .. "  (" .. type(v) .. ")")
  end
end

print("== global API candidates ==")
for _, name in ipairs({ "sable", "aero", "aerodynamics", "sublevel", "ship" }) do
  if _G[name] ~= nil then dump(name, _G[name]) else print(name .. " = nil") end
end

print("\n== peripherals ==")
for _, pname in ipairs(peripheral.getNames()) do
  print(pname .. "  [" .. peripheral.getType(pname) .. "]")
  if peripheral.getType(pname):find("sable") or peripheral.getType(pname):find("ship") then
    for _, m in ipairs(peripheral.getMethods(pname)) do print("   ." .. m) end
  end
end

print("\n== likely telemetry probes (pcall'd) ==")
for _, expr in ipairs({
  "sable.getName", "sable.getUniqueId", "sable.getLogicalPose",
  "sable.getPosition", "aero.getAirPressure", "aero.getGravity",
}) do
  local ns, fn = expr:match("^(%w+)%.(%w+)$")
  if _G[ns] and type(_G[ns][fn]) == "function" then
    local ok, res = pcall(_G[ns][fn])
    print(expr .. "() -> " .. (ok and textutils.serialize(res):gsub("%s+", " "):sub(1, 80) or ("error: " .. tostring(res))))
  end
end
