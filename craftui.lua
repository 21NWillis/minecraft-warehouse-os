-- craftui: the order terminal for the crafting fleet. Live recipe search,
-- click/keyboard selection, a quantity field and one big ORDER button.
-- Planning + dispatch are NOT done here: ordering shells out to craftd's
-- one-shot mode, which owns storage and prints its own progress.
--
-- Runs on an ADVANCED computer attached to the same machine as craftd
-- (color + mouse); degrades to plain black/white on a basic computer.
-- Optional craftui.cfg gives up to 6 one-click favorites:
--   { { label = "Sail", id = "dysoncubeproject:solar_sail", count = 64 } }
-- run: craftui
local db = require("recipedb")

local FAV_FILE = "craftui.cfg"
-- db.search walks every recipe output, so a keystroke costs one full scan;
-- 12 hits is the sweet spot between "found it" and staying inside the tick.
local RESULT_LIMIT = 12
local MAX_FAVS = 6
local MAX_QTY = 99999

local isColor = (term.isColor and term.isColor()) and true or false

local THEME = {
  [colors.black] = 0x10131f,
  [colors.gray] = 0x1d2233,
  [colors.lightGray] = 0x707894,
  [colors.white] = 0xe8eaf2,
  [colors.cyan] = 0x4cc9f0,
  [colors.blue] = 0x2b3a67,
  [colors.green] = 0x51cf66,
  [colors.orange] = 0xffa94d,
  [colors.red] = 0xff6b6b,
  [colors.yellow] = 0xffd43b,
}

local function applyTheme()
  if not (isColor and term.setPaletteColour) then return end
  for c, rgb in pairs(THEME) do pcall(term.setPaletteColour, c, rgb) end
end

local function restoreTheme()
  if not (isColor and term.setPaletteColour and term.nativePaletteColour) then return end
  for c in pairs(THEME) do
    local ok, r, g, b = pcall(term.nativePaletteColour, c)
    if ok then pcall(term.setPaletteColour, c, r, g, b) end
  end
end

-- ------------------------------------------------------------------ drawing
-- a basic computer rejects every non-grayscale color, so ALL color changes go
-- through here: real colors on advanced, invert-or-plain on basic.
local function paint(f, b, inverse)
  if isColor then
    term.setTextColor(f or colors.white)
    term.setBackgroundColor(b or colors.black)
  elseif inverse then
    term.setTextColor(colors.black)
    term.setBackgroundColor(colors.white)
  else
    term.setTextColor(colors.white)
    term.setBackgroundColor(colors.black)
  end
end

local function pad(s, n)
  s = tostring(s or ""):sub(1, n)
  return s .. string.rep(" ", n - #s)
end

-- ------------------------------------------------------------------- state
local W, H = term.getSize()
local LIST_TOP, LIST_ROWS = 4, 1
local FAV_Y, BAR_Y, HELP_Y = nil, H - 1, H

local query = ""
local results = {}
local sel = 0          -- 0 means "nothing selected" (empty result list)
local top = 1          -- first visible result index
local qtyText = "1"
local qtyFocus = false
local qtyFresh = false   -- first digit typed after focusing REPLACES the field
local message = ""
local favs = {}
local widgets = {}     -- rebuilt every draw: { x1, x2, y, action, arg }
local running = true

local function writeAt(x, y, s, f, b, inverse)
  if y < 1 or y > H or x < 1 or x > W then return end
  paint(f, b, inverse)
  term.setCursorPos(x, y)
  term.write(s)
end

local function clickable(x1, x2, y, action, arg)
  widgets[#widgets + 1] = { x1 = x1, x2 = x2, y = y, action = action, arg = arg }
end

-- ------------------------------------------------------------------ layout
local function layout()
  W, H = term.getSize()
  HELP_Y = H
  BAR_Y = H - 1
  FAV_Y = (#favs > 0) and (H - 2) or nil
  LIST_TOP = 4
  local listBottom = (FAV_Y or BAR_Y) - 1
  LIST_ROWS = math.max(0, listBottom - LIST_TOP + 1)
end

local function clampView()
  if #results == 0 then sel = 0; top = 1; return end
  if sel < 1 then sel = 1 elseif sel > #results then sel = #results end
  if LIST_ROWS < 1 then top = 1; return end
  if sel < top then top = sel end
  if sel > top + LIST_ROWS - 1 then top = sel - LIST_ROWS + 1 end
  local maxTop = math.max(1, #results - LIST_ROWS + 1)
  if top > maxTop then top = maxTop end
  if top < 1 then top = 1 end
end

local function runSearch()
  local ok, hits = pcall(db.search, query, math.max(RESULT_LIMIT, LIST_ROWS))
  results = (ok and type(hits) == "table") and hits or {}
  sel = (#results > 0) and 1 or 0
  top = 1
end

-- ---------------------------------------------------------------- quantity
local function setQtyText(t)
  t = t:gsub("^0+(%d)", "%1")
  if #t > 5 then t = t:sub(1, 5) end
  qtyText = t
end

local function orderCount()
  local n = math.floor(tonumber(qtyText) or 1)
  if n < 1 then n = 1 end
  if n > MAX_QTY then n = MAX_QTY end
  return n
end

local function bumpQty(d)
  setQtyText(tostring(math.max(1, math.min(MAX_QTY, orderCount() + d))))
  qtyFresh = false
end

local function typeQtyDigit(ch)
  setQtyText(qtyFresh and ch or (qtyText .. ch))
  qtyFresh = false
end

-- ---------------------------------------------------------------- favorites
local function loadFavs()
  local out = {}
  if not fs.exists(FAV_FILE) then return out end
  local f = fs.open(FAV_FILE, "r")
  if not f then return out end
  local text = f.readAll() or ""
  f.close()
  local ok, data = pcall(textutils.unserialize, text)
  if not ok or type(data) ~= "table" then return out end
  for _, e in ipairs(data) do
    if type(e) == "table" and type(e.id) == "string" then
      out[#out + 1] = {
        id = e.id,
        label = tostring(e.label or db.name(e.id) or e.id):sub(1, 10),
        count = math.max(1, math.floor(tonumber(e.count) or 1)),
      }
      if #out >= MAX_FAVS then break end
    end
  end
  return out
end

-- --------------------------------------------------------------------- draw
local function draw()
  layout()
  widgets = {}
  paint(colors.white, colors.black)
  term.clear()

  -- title bar
  local right = db.recipeCount() .. " recipes "
  local head = pad(" PAPERCLIP CRAFT", W)
  if W > #right + 17 then head = pad(" PAPERCLIP CRAFT", W - #right) .. right end
  writeAt(1, 1, head, colors.yellow, colors.blue, true)

  -- search field (always the default focus)
  local label = " find: "
  local avail = math.max(1, W - #label - 1)
  local shown = query
  if #shown > avail then shown = shown:sub(#shown - avail + 1) end
  writeAt(1, 2, pad(label .. shown, W), colors.white, colors.gray)
  writeAt(1, 2, label, colors.cyan, colors.gray)
  clickable(1, W, 2, "search")

  -- status / hint line
  local info
  if message ~= "" then
    info = message
  elseif query == "" then
    info = "type to search the recipe book"
  elseif #results == 0 then
    info = "no recipes match " .. query
  else
    info = ("%d result%s"):format(#results, #results == 1 and "" or "s")
  end
  writeAt(1, 3, pad(" " .. info, W),
    message ~= "" and colors.orange or colors.lightGray, colors.black)

  -- result list
  clampView()
  local idW = math.min(24, math.max(6, math.floor(W * 0.42)))
  local nameW = math.max(1, W - idW - 3)
  for i = 0, LIST_ROWS - 1 do
    local idx = top + i
    local y = LIST_TOP + i
    local id = results[idx]
    if not id then
      writeAt(1, y, string.rep(" ", W), colors.white, colors.black)
    else
      local picked = (idx == sel)
      local bg = picked and colors.blue or colors.black
      writeAt(1, y, pad((picked and ">" or " ") .. " " .. pad(db.name(id) or id, nameW), W),
        colors.white, bg, picked)
      if W - idW + 1 >= 3 then
        writeAt(W - idW + 1, y, pad(id, idW),
          picked and colors.cyan or colors.lightGray, bg, picked)
      end
      clickable(1, W, y, "pick", idx)
    end
  end

  -- favorites row (hidden entirely when craftui.cfg is absent/empty)
  if FAV_Y then
    writeAt(1, FAV_Y, string.rep(" ", W), colors.white, colors.black)
    local x = 1
    for i, fav in ipairs(favs) do
      local text = ("[%s x%d]"):format(fav.label, fav.count)
      if x + #text - 1 > W then break end
      writeAt(x, FAV_Y, text, colors.black, colors.cyan, true)
      clickable(x, x + #text - 1, FAV_Y, "fav", i)
      x = x + #text + 1
    end
  end

  -- order bar: selected item, quantity field, ORDER button
  local ORDER = "[ORDER]"
  local qtyW = 6
  local orderX = W - #ORDER + 1
  local plusX = orderX - 4
  local qtyX = plusX - qtyW
  local minusX = qtyX - 3
  local wideBar = (minusX >= 12)
  if not wideBar then qtyX = math.max(2, orderX - 1 - qtyW) end
  local nameFieldW = math.max(1, (wideBar and minusX or qtyX) - 2)

  writeAt(1, BAR_Y, string.rep(" ", W), colors.white, colors.gray)
  local selId = results[sel]
  writeAt(2, BAR_Y, pad(selId and (db.name(selId) or selId) or "nothing selected", nameFieldW),
    selId and colors.white or colors.lightGray, colors.gray)

  if wideBar then
    writeAt(minusX, BAR_Y, "[-]", colors.white, colors.blue)
    clickable(minusX, minusX + 2, BAR_Y, "qtyminus")
    writeAt(plusX, BAR_Y, "[+]", colors.white, colors.blue)
    clickable(plusX, plusX + 2, BAR_Y, "qtyplus")
  end
  writeAt(qtyX, BAR_Y, pad(" " .. (qtyText == "" and "_" or qtyText), qtyW),
    qtyFocus and colors.white or colors.cyan,
    qtyFocus and colors.blue or colors.black, qtyFocus)
  clickable(qtyX, qtyX + qtyW - 1, BAR_Y, "qty")

  writeAt(orderX, BAR_Y, ORDER, selId and colors.black or colors.lightGray,
    selId and colors.green or colors.gray, selId ~= nil)
  clickable(orderX, W, BAR_Y, "order")

  writeAt(1, HELP_Y, pad(" enter order  tab qty  arrows pick  esc quit", W),
    colors.lightGray, colors.black)

  -- park the hardware cursor in whichever field has focus
  if qtyFocus then
    paint(colors.white, colors.blue, true)
    term.setCursorPos(math.min(W, qtyX + 1 + #qtyText), BAR_Y)
  else
    paint(colors.white, colors.gray)
    term.setCursorPos(math.min(W, 1 + #label + #shown), 2)
  end
  term.setCursorBlink(true)
end

-- ----------------------------------------------------------------- ordering
-- What you selected is what gets ordered: craftd's id: form bypasses
-- its search entirely (the maiden order picked Cast Iron Ingot when
-- the user chose Iron Ingot - never again).
local function craftdQuery(id)
  return "id:" .. id
end

-- a key press queues a "char" too; swallow the tail so it doesn't land in the
-- search box when we come back from craftd's output
local function drainInput()
  local timer = os.startTimer(0.1)
  while true do
    local e, p = os.pullEvent()
    if e == "timer" and p == timer then return end
  end
end

-- fire-and-forget: append to the orderq file that `craftd serve`
-- (running in another multishell tab: `bg craftd serve`) drains. The
-- UI never blocks; queue multiple orders as fast as you can click.
local function placeOrder(id, count, name)
  local h = fs.open("orderq", fs.exists("orderq") and "a" or "w")
  h.writeLine(count .. "|" .. id)
  h.close()
  message = ("queued %d x %s"):format(count, name)
end

local function orderSelected()
  local id = results[sel]
  if not id then
    message = "pick a recipe first"
    return
  end
  placeOrder(id, orderCount(), db.name(id) or id)
end

local function handleAction(action, arg)
  message = ""
  if action == "pick" then
    sel = arg
    qtyFocus = false
  elseif action == "search" then
    qtyFocus = false
  elseif action == "qty" then
    qtyFocus = true
    qtyFresh = true
  elseif action == "qtyplus" then
    bumpQty(1)
  elseif action == "qtyminus" then
    bumpQty(-1)
  elseif action == "order" then
    orderSelected()
  elseif action == "fav" then
    local f = favs[arg]
    if f then placeOrder(f.id, f.count, f.label) end
  end
end

-- --------------------------------------------------------------- event loop
local function mainLoop()
  while running do
    draw()
    local ev = { os.pullEvent() }   -- terminate raises here and unwinds cleanly
    local e = ev[1]

    if e == "char" then
      local ch = ev[2]
      if ch == "+" then
        bumpQty(1)
      elseif ch == "-" then
        bumpQty(-1)
      elseif qtyFocus then
        if ch:match("%d") then typeQtyDigit(ch) end
      else
        query = query .. ch
        message = ""
        runSearch()
      end

    elseif e == "key" then
      local k = ev[2]
      if k == keys.tab then
        qtyFocus = not qtyFocus
        qtyFresh = qtyFocus
      elseif k == keys.enter or k == keys.numPadEnter then
        orderSelected()
      elseif k == keys.backspace then
        if qtyFocus then
          setQtyText(qtyText:sub(1, #qtyText - 1))
          qtyFresh = false
        else
          query = query:sub(1, #query - 1)
          message = ""
          runSearch()
        end
      elseif k == keys.up then
        if qtyFocus then bumpQty(1) else sel = math.max(1, sel - 1) end
      elseif k == keys.down then
        if qtyFocus then bumpQty(-1) else sel = math.min(#results, sel + 1) end
      elseif k == keys.pageUp then
        sel = math.max(1, sel - math.max(1, LIST_ROWS))
      elseif k == keys.pageDown then
        sel = math.min(#results, sel + math.max(1, LIST_ROWS))
      elseif k == keys.home then
        sel = math.min(#results, 1)
      elseif k == keys["end"] then
        sel = #results
      elseif k == keys.escape then
        running = false
      end

    elseif e == "mouse_click" then
      local mx, my = ev[3], ev[4]
      local hit = false
      for _, wdg in ipairs(widgets) do
        if my == wdg.y and mx >= wdg.x1 and mx <= wdg.x2 then
          handleAction(wdg.action, wdg.arg)
          hit = true
          break
        end
      end
      if not hit then qtyFocus = false end   -- clicking empty space just defocuses

    elseif e == "mouse_scroll" then
      local dir = ev[2]
      if #results > 0 and LIST_ROWS > 0 then
        local maxTop = math.max(1, #results - LIST_ROWS + 1)
        top = math.min(maxTop, math.max(1, top + dir))
        if sel < top then sel = top end
        if sel > top + LIST_ROWS - 1 then sel = top + LIST_ROWS - 1 end
      end
    end
    -- term_resize and anything else: the next draw() re-reads getSize()
  end
end

-- --------------------------------------------------------------------- main
paint(colors.white, colors.black)
term.clear()
term.setCursorPos(1, 1)
paint(colors.cyan, colors.black)
print("loading recipes...")
paint(colors.white, colors.black)

local loaded, err = db.load("data")
if not loaded then
  paint(colors.red, colors.black)
  print("recipedb: " .. tostring(err))
  paint(colors.white, colors.black)
  return
end

favs = loadFavs()
layout()
runSearch()
applyTheme()

local ok, runErr = pcall(mainLoop)

term.setCursorBlink(false)
restoreTheme()
paint(colors.white, colors.black)
term.clear()
term.setCursorPos(1, 1)
if not ok and not tostring(runErr):find("Terminated", 1, true) then
  error(runErr, 0)
end
