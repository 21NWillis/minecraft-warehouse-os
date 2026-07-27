-- vault: a Paperclip Corp access terminal. Password-gated redstone door with a
-- salted hash (no plaintext on disk), masked entry, lockout after repeated
-- failures, an attempt log, and chiptune grant/deny stingers if a speaker is
-- attached. Pure CC/Lua. Run on a computer whose redstone output drives a door
-- (piston/iron door); first run sets the password.
local vault = {}

-- small non-crypto string hash (djb2) - plenty for a Minecraft door
function vault.hash(salt, pw)
  local h = 5381
  local s = tostring(salt) .. ":" .. tostring(pw)
  for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
  return string.format("%08x", h)
end

if not _TEST then
  local CFG = "vault.cfg"
  local SIDE = "back"          -- redstone side that drives the door
  local OPEN_SECONDS = 4
  local MAX_FAILS = 3

  local speaker = peripheral.find and peripheral.find("speaker")
  local music
  do local ok, m = pcall(require, "music"); if ok then music = m end end
  local function jingle(name)
    if speaker and music then music.play(speaker, music.jingles[name] or {}) end
  end

  local function loadCfg()
    if not fs.exists(CFG) then return nil end
    local f = fs.open(CFG, "r"); local salt = f.readLine(); local hash = f.readLine(); f.close()
    return salt, hash
  end
  local function saveCfg(salt, hash)
    local f = fs.open(CFG, "w"); f.write(salt .. "\n" .. hash .. "\n"); f.close()
  end
  local function logAttempt(ok)
    local f = fs.open("vault.log", "a"); if not f then return end
    f.write(("%s %s\n"):format(textutils.formatTime(os.time("local"), true), ok and "GRANTED" or "DENIED"))
    f.close()
  end

  local salt, hash = loadCfg()
  if not hash then
    term.clear(); term.setCursorPos(1, 1)
    print("PAPERCLIP VAULT - first-time setup")
    write("set access code: ")
    local pw = read("*")
    salt = tostring((os.epoch and os.epoch("utc") or os.clock()) % 100000)
    hash = vault.hash(salt, pw)
    saveCfg(salt, hash)
    print("code set. reboot to arm the vault.")
    return
  end

  local fails = 0
  while true do
    term.setBackgroundColor(colors.black); term.clear(); term.setCursorPos(1, 1)
    term.setTextColor(colors.cyan); print("== PAPERCLIP CORP VAULT ==")
    term.setTextColor(colors.white); write("access code: ")
    local pw = read("*")
    if vault.hash(salt, pw) == hash then
      fails = 0
      logAttempt(true)
      term.setTextColor(colors.lime); print("ACCESS GRANTED"); jingle("success")
      redstone.setOutput(SIDE, true)
      sleep(OPEN_SECONDS)
      redstone.setOutput(SIDE, false)
    else
      fails = fails + 1
      logAttempt(false)
      term.setTextColor(colors.red); print("ACCESS DENIED"); jingle("error")
      if fails >= MAX_FAILS then
        term.setTextColor(colors.orange); print("LOCKED OUT - COMPLIANCE REVIEW PENDING")
        jingle("alert"); sleep(30); fails = 0
      else
        sleep(1.5)
      end
    end
  end
end

return vault
