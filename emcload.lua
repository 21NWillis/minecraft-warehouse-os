-- emcload: load the EMC value table, from disk if present else streamed from
-- GitHub into RAM (like the recipe DB). emc.txt is ~800KB, which will not fit
-- alongside the scripts on the server's 1MB computer disk, so it must NOT live
-- on disk there - this streams it instead. Returns id -> value (may be empty).
local emcload = {}

local function ingest(handle, emc)
  if not handle then return end
  while true do
    local line = handle.readLine(); if not line then break end
    local id, v = line:match("^(%S+)%s+([%d%.]+)$")
    if id then emc[id] = tonumber(v) end
  end
  handle.close()
end

function emcload.load()
  local emc = {}
  if fs.exists("data/emc.txt") then
    ingest(fs.open("data/emc.txt", "r"), emc)
  elseif http and fs.exists(".updatebase") then
    local f = fs.open(".updatebase", "r"); local base = f.readAll(); f.close()
    if base:sub(-1) ~= "/" then base = base .. "/" end
    ingest((http.get(base .. "data/emc.txt")), emc)
  end
  return emc
end

return emcload
