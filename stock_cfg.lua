-- stock_cfg: minimum-held watermarks for stockd (ATM10 commune ME).
-- stockd sweeps every 30s and fires ME autocrafts for anything below
-- its number. Every item here NEEDS an encoded AE2 pattern or stockd
-- will report it unstockable and skip.
-- Edit via repo + `update` (config-as-code), or `edit stock_cfg.lua`
-- in-game for quick tweaks (update will overwrite local edits!).
-- IDs are Mekanism defaults - if the pack unified an item under a
-- different id, check it in ME with advanced tooltips (F3+H) and fix.

return {
  -- metals & alloys (the parts-rage tier)
  ["mekanism:ingot_steel"]            = 512,
  ["mekanism:alloy_infused"]          = 256,
  ["mekanism:alloy_reinforced"]       = 128,
  ["mekanism:alloy_atomic"]           = 64,

  -- circuits
  ["mekanism:basic_control_circuit"]    = 128,
  ["mekanism:advanced_control_circuit"] = 64,
  ["mekanism:elite_control_circuit"]    = 32,
  ["mekanism:ultimate_control_circuit"] = 16,

  -- structural staples
  ["mekanism:steel_casing"]           = 32,

  -- enriched infusion feedstock (processing patterns: enrichment chamber)
  ["mekanism:enriched_carbon"]        = 256,
  ["mekanism:enriched_redstone"]      = 128,
  ["mekanism:enriched_diamond"]       = 64,
  ["mekanism:enriched_obsidian"]      = 32,
}
