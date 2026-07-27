-- bridge_commands.lua: Claude writes commands here; `bridge run` fetches and
-- executes this against the world, capturing output. This starter just reports
-- what it can see. Claude edits + commits this to issue real actions.
print("bridge online on computer #" .. os.getComputerID())
print("peripherals:")
for _, n in ipairs(peripheral.getNames()) do
  print("  " .. n .. " [" .. peripheral.getType(n) .. "]")
end
