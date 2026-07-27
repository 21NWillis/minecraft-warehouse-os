-- music: a tiny chiptune player over the CC:Tweaked Speaker peripheral. Pure
-- Lua, no mod. Sequences are lists of { p = pitch(0-24), d = beats, i = instr }.
local music = {}

function music.play(speaker, seq, opts)
  if not speaker then return end
  opts = opts or {}
  local inst = opts.instrument or "harp"
  local vol = opts.volume or 2.0
  local tempo = opts.tempo or 0.14
  for _, n in ipairs(seq) do
    if n.p then pcall(speaker.playNote, n.i or inst, vol, n.p) end
    sleep((n.d or 1) * tempo)
  end
end

-- pitch cheatsheet: 0 = F#3 (lowest), 12 = F#4, 24 = F#5 (highest)
music.jingles = {
  boot     = { { p = 12 }, { p = 16 }, { p = 19 }, { p = 24, d = 2 } },
  success  = { { p = 12 }, { p = 19 }, { p = 24, d = 2 } },
  alert    = { { i = "bit", p = 18 }, { i = "bit", p = 12 }, { i = "bit", p = 18 }, { i = "bit", p = 12 } },
  ominous  = { { i = "bass", p = 5, d = 2 }, { i = "bass", p = 3, d = 2 }, { i = "bass", p = 1, d = 3 } },
  milestone = { { p = 12 }, { p = 14 }, { p = 16 }, { p = 19 }, { p = 24, d = 2 }, { i = "bell", p = 24, d = 3 } },
  error    = { { i = "bass", p = 4 }, { i = "bass", p = 2, d = 2 } },
}

return music
