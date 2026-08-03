-- peripherals: list everything this computer can actually see - names,
-- types, and method counts. The ground-truth tool for "why can't the
-- warehouse find the controller". Pairs with `report peripherals`.
local names = peripheral.getNames()
if #names == 0 then
  print("NO peripherals visible at all.")
  print("If a wired modem should be attached: is it the FULL-BLOCK kind,")
  print("and is it directly adjacent to this computer?")
  return
end
print(#names .. " peripheral(s):")
for _, name in ipairs(names) do
  local types = { peripheral.getType(name) }
  local methods = peripheral.getMethods(name) or {}
  print(("%s [%s] %d methods"):format(name, table.concat(types, ","), #methods))
  local line = "  "
  for i, mth in ipairs(methods) do
    if #line + #mth > 48 then print(line) line = "  " end
    line = line .. mth .. " "
    if i >= 24 then line = line .. "..." break end
  end
  if line ~= "  " then print(line) end
end
