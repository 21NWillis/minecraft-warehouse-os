-- menu: PaperclipOS launcher. A themed boot menu that lists the installed
-- Paperclip tools (only the ones actually present) and launches them. Saves
-- remembering script names; makes the base feel like it runs an OS.
-- `menu install` writes startup.lua so it greets you on every boot.
local menu = {}

menu.programs = {
  { script = "warehouse",  desc = "storage + autocrafting terminal" },
  { script = "exchange",   desc = "Paperclip Exchange (EMC stock ticker)" },
  { script = "attract",    desc = "attract-mode screensaver" },
  { script = "melink",     desc = "server-wide ME network map (hub)" },
  { script = "remote",     desc = "pocket network console" },
  { script = "pa",         desc = "PA announcer" },
  { script = "oracle",     desc = "the AI Oracle" },
  { script = "vault",      desc = "secure access terminal" },
  { script = "conway",     desc = "Game of Life" },
  { script = "recipes",    desc = "recipe lookup" },
  { script = "transmute",  desc = "Equivalent Exchange" },
  { script = "reactor",    desc = "fission reactor controller" },
  { script = "profiler",   desc = "tick-lag + peripheral latency profiler" },
  { script = "bridge",     desc = "cross-layer comms (snapshot/run)" },
  { script = "seed",       desc = "bootstrap seed puller" },
}

if not _TEST then
  if ({ ... })[1] == "install" then
    local f = fs.open("startup.lua", "w"); f.write('shell.run("menu")'); f.close()
    print("startup.lua written; PaperclipOS boots on start")
    return
  end

  -- only offer programs that are actually deployed here
  local available = {}
  for _, p in ipairs(menu.programs) do
    if fs.exists(p.script .. ".lua") then available[#available + 1] = p end
  end

  local sel = 1
  local function draw()
    term.setBackgroundColor(colors.black); term.clear()
    term.setCursorPos(1, 1); term.setTextColor(colors.cyan)
    print("  P A P E R C L I P   O S")
    term.setTextColor(colors.gray); print("  the factory is listening\n")
    for i, p in ipairs(available) do
      term.setCursorPos(1, i + 3)
      if i == sel then
        term.setBackgroundColor(colors.cyan); term.setTextColor(colors.black)
      else
        term.setBackgroundColor(colors.black); term.setTextColor(colors.white)
      end
      term.write((" %-10s %s"):format(p.script, p.desc))
      term.setBackgroundColor(colors.black)
    end
    local _, h = term.getSize()
    term.setCursorPos(1, h); term.setTextColor(colors.lightGray)
    term.write(" up/down + enter to launch, q to quit")
  end

  if #available == 0 then print("no Paperclip programs installed here (run update)") return end
  draw()
  while true do
    local ev, a = os.pullEvent()
    if ev == "key" then
      if a == keys.up then sel = (sel - 2) % #available + 1; draw()
      elseif a == keys.down then sel = sel % #available + 1; draw()
      elseif a == keys.enter then
        term.setBackgroundColor(colors.black); term.clear(); term.setCursorPos(1, 1)
        shell.run(available[sel].script)
        draw()
      elseif a == keys.q then break end
    end
  end
  term.setBackgroundColor(colors.black); term.clear(); term.setCursorPos(1, 1)
end

return menu
