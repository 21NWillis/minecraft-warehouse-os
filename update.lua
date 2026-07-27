-- update [baseurl]: sync all warehouse files from a raw-file host (e.g. GitHub raw)
-- first run: update https://raw.githubusercontent.com/21NWillis/minecraft-warehouse-os/main/
-- after that: update           (base url is remembered)
-- NOTE: this repo's root IS the cc-scripts folder, so the base ends in /main/
--       (NOT /main/cc-scripts/) - manifest.txt and data/ live at the repo root.
local BASE_FILE = ".updatebase"

local args = { ... }
local base = args[1]
if not base and fs.exists(BASE_FILE) then
  local f = fs.open(BASE_FILE, "r")
  base = f.readAll()
  f.close()
end
if not base then
  print("usage: update <baseurl ending in />")
  return
end
if base:sub(-1) ~= "/" then base = base .. "/" end

local res, err = http.get(base .. "manifest.txt")
if not res then
  print("manifest fetch failed: " .. tostring(err))
  return
end
local manifest = res.readAll()
res.close()

local f = fs.open(BASE_FILE, "w")
f.write(base)
f.close()

local okCount, failCount = 0, 0
for path in manifest:gmatch("[^\r\n]+") do
  write(path .. " ... ")
  local r, ferr = http.get(base .. path)
  if not r then
    print("FAILED: " .. tostring(ferr))
    failCount = failCount + 1
  else
    local body = r.readAll()
    r.close()
    local existing = fs.exists(path) and fs.getSize(path) or 0
    local free = fs.getFreeSpace("/") + existing
    if #body + 512 > free then
      print(("FAILED: need %dKB, %dKB free"):format(math.ceil(#body / 1024), math.floor(free / 1024)))
      print("  disk too small - was computer_space_limit raised + server restarted?")
      failCount = failCount + 1
    else
      local dir = fs.getDir(path)
      if dir ~= "" then fs.makeDir(dir) end
      local out = fs.open(path, "w")
      if not out then
        print("FAILED: cannot open for writing")
        failCount = failCount + 1
      else
        out.write(body)
        out.close()
        print(("%d KB"):format(math.ceil(#body / 1024)))
        okCount = okCount + 1
      end
    end
  end
end
print(("updated %d files, %d failed"):format(okCount, failCount))
if failCount == 0 then print("reboot to restart warehouse") end
