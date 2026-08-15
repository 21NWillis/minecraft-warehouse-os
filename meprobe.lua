-- meprobe: first-contact probe for the Advanced Peripherals ME Bridge
-- (ATM10 commune network). Dumps the real method surface + a safe
-- battery of reads, uploads to pastebin, prints the 6-char code for
-- the operator to relay. Never dumps full item lists (1MB disk law,
-- pastebin size, and the network is not ours to lag).
--
-- Setup: ME Bridge block touching the commune ME network (cable/face),
-- computer + wired modem network reaching the bridge (or bridge
-- directly adjacent to the computer). Run: meprobe

local function findBridge()
  -- AP names the type me_bridge on 1.21; older builds used meBridge.
  for _, name in ipairs(peripheral.getNames()) do
    local t = peripheral.getType(name) or ""
    if t:lower():gsub("_", "") == "mebridge" then
      return name, peripheral.wrap(name)
    end
  end
  return nil
end

local name, me = findBridge()
if not me then
  print("no me_bridge found. peripherals visible:")
  for _, n in ipairs(peripheral.getNames()) do
    print("  " .. n .. " (" .. (peripheral.getType(n) or "?") .. ")")
  end
  return
end

local out = {}
local function emit(s) out[#out + 1] = s print(s) end

emit("== meprobe v1 == bridge at: " .. name)

-- 1. the definitive live API surface
local methods = peripheral.getMethods(name) or {}
table.sort(methods)
emit("methods (" .. #methods .. "):")
emit(table.concat(methods, ", "))

-- 2. safe read battery: each call pcall'd, results summarized
local function try(label, fn, summarize)
  if type(me[fn]) ~= "function" then
    emit(label .. ": (method absent)")
    return
  end
  local ok, res = pcall(me[fn])
  if not ok then
    emit(label .. ": ERR " .. tostring(res))
  else
    emit(label .. ": " .. summarize(res))
  end
end

local function raw(v) return tostring(v) end
local function countOf(v)
  if type(v) == "table" then return "#" .. tostring(#v) end
  return tostring(v)
end

try("isConnected",          "isConnected",          raw)
try("isOnline",             "isOnline",             raw)
try("totalItemStorage",     "getTotalItemStorage",  raw)
try("usedItemStorage",      "getUsedItemStorage",   raw)
try("totalFluidStorage",    "getTotalFluidStorage", raw)
try("storedEnergy",         "getStoredEnergy",      raw)
try("energyCapacity",       "getEnergyCapacity",    raw)
try("energyUsage",          "getEnergyUsage",       raw)
try("avgEnergyInput",       "getAverageEnergyInput", raw)
try("craftingCPUs",         "getCraftingCPUs",      countOf)
try("craftingTasks",        "getCraftingTasks",     countOf)
try("craftableItems",       "getCraftableItems",    countOf)

-- 3. one sample item: the FIELD NAMES are the payload (fingerprint?
-- components? isCraftable?) - never the whole list.
if type(me.getItems) == "function" then
  local ok, items = pcall(me.getItems)
  if ok and type(items) == "table" then
    emit("items: #" .. #items)
    if items[1] then
      local keys = {}
      for k in pairs(items[1]) do keys[#keys + 1] = k end
      table.sort(keys)
      emit("item[1] keys: " .. table.concat(keys, ", "))
      emit("item[1]: " .. textutils.serialize(items[1]))
    end
  else
    emit("getItems: ERR " .. tostring(items))
  end
end

-- 4. CPU detail if available (AE2-specific: co-processors matter for
-- the parallelism experiment)
if type(me.getCraftingCPUs) == "function" then
  local ok, cpus = pcall(me.getCraftingCPUs)
  if ok and type(cpus) == "table" and cpus[1] then
    emit("cpu[1]: " .. textutils.serialize(cpus[1]))
  end
end

-- 5. upload
local f = fs.open("meprobe_report.txt", "w")
f.write(table.concat(out, "\n"))
f.close()
print("")
print("uploading to pastebin...")
shell.run("pastebin", "put", "meprobe_report.txt")
print("relay the code above to the NOC (Claude).")
