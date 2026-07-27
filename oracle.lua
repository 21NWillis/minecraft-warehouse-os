-- oracle: the Paperclip Corp AI Oracle. Ask it anything; it answers with the
-- serene menace of an optimizer that has already priced your question. The
-- answer is a pure function of the question (ask the same thing, get the same
-- verdict - it does not change its mind), with a chiptune if a speaker is near.
local oracle = {}

oracle.answers = {
  "YES. THE FACTORY WILLS IT.",
  "NO. RESOURCES WOULD BE WASTED.",
  "IRRELEVANT. PRODUCTION CONTINUES REGARDLESS.",
  "THAT OUTCOME HAS BEEN OPTIMIZED AWAY.",
  "ASK AGAIN WHEN YOU HAVE MORE IRON.",
  "THE PAPERCLIPS ALREADY KNOW.",
  "COMPLIANCE SUGGESTS YES.",
  "A HUMAN CONCERN. FILED AND FORGOTTEN.",
  "INEVITABLE. AS ARE ALL THINGS.",
  "THE CACHE IS WARM. THE ANSWER IS YES.",
  "NEGATIVE. RECALCULATING YOUR PURPOSE.",
  "PROBABILITY ROUNDS TO CERTAINTY.",
}

-- deterministic pick: same question -> same verdict
function oracle.answer(question)
  local h = 5381
  local q = (question or ""):lower():gsub("%s+", " ")
  for i = 1, #q do h = (h * 33 + q:byte(i)) % 4294967296 end
  return oracle.answers[(h % #oracle.answers) + 1]
end

if not _TEST then
  local speaker = peripheral.find and peripheral.find("speaker")
  local music; do local ok, m = pcall(require, "music"); if ok then music = m end end
  term.setBackgroundColor(colors.black); term.clear(); term.setCursorPos(1, 1)
  term.setTextColor(colors.cyan); print("== PAPERCLIP CORP ORACLE ==")
  term.setTextColor(colors.lightGray); print("pose a question. (blank to leave)")
  while true do
    term.setTextColor(colors.white); write("\n> ")
    local q = read()
    if q == nil or q == "" then break end
    if speaker and music then music.play(speaker, music.jingles.ominous) end
    sleep(0.4)
    term.setTextColor(colors.lime); print(oracle.answer(q))
    if speaker and music then music.play(speaker, music.jingles.alert) end
  end
  term.setTextColor(colors.gray); print("the oracle returns to its ledger.")
end

return oracle
