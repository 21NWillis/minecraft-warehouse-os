# Factory Plan — Iron Foundry + Starter Datacenter

Recursive bill of materials. Chase the numbers top-down: raw materials
are what you mine/smelt; machine outputs are what you must **automate**.

## Target machines (the datacenter)

- [ ] 2× **Depot** (`create:depot`)
- [ ] 1× **Mechanical Press** (`create:mechanical_press`)
- [ ] 4× **Basic Bin** (`mekanism:basic_bin`)
- [ ] 2× **Basic Energy Cube** (`mekanism:basic_energy_cube`)  ⚠ recipe not found — verify id
- [ ] 16× **Basic Universal Cable** (`mekanism:basic_universal_cable`)
- [ ] 1× **Crusher** (`mekanism:crusher`)
- [ ] 2× **Energized Smelter** (`mekanism:energized_smelter`)
- [ ] 2× **Enrichment Chamber** (`mekanism:enrichment_chamber`)
- [ ] 1× **Metallurgic Infuser** (`mekanism:metallurgic_infuser`)
- [ ] 4× **Steel Casing** (`mekanism:steel_casing`)

## Raw materials to gather / mine  (the shopping list)

- [ ] 40× Steel Ingot (`createmetallurgy:steel_ingot`)
- [ ] 40× Glass (`minecraft:glass`)
- [ ] 36× Cobblestone (`minecraft:cobblestone`)
- [ ] 32× Redstone Dust (`minecraft:redstone`)
- [ ] 24× Osmium Ingot (`mekanism:ingot_osmium`)
- [ ] 17× Iron Ingot (`minecraft:iron_ingot`)
- [ ] 5× Andesite Alloy (`create:andesite_alloy`)
- [ ] 2× Lava Bucket (`minecraft:lava_bucket`)
- [ ] 1× Shaft (`create:shaft`)

## Machine-made intermediates  (build these machines first)

### Manual/Deployer Application
- [ ] 3× Andesite Casing (`create:andesite_casing`)

### Metallurgic Infuser
- [ ] 14× Basic Control Circuit (`mekanism:basic_control_circuit`)

## Chemicals/gases required (Mekanism infrastructure)

These need their own production (electrolyzer, etc.): redstone

## Hand-crafted intermediates

- [ ] 2× Furnace (`minecraft:furnace`)
- [ ] 1× Shaft (`create:shaft`)
- [ ] 1× Block of Iron (`minecraft:iron_block`)
- [ ] 0× Shaft Bundle (`create_compressed:shaft_bundle`)

## ⚠ Unresolved (no grid or machine recipe found — likely raw, or check id)

- 2× Basic Energy Cube (`mekanism:basic_energy_cube`)

## Automation recommendations

- **Bootstrap order**: build these machines first, since other targets depend on their output — Manual/Deployer Application, Metallurgic Infuser.
  Note the chicken-and-egg: the first control circuits / infused alloys are made by hand in the Metallurgic Infuser before you can automate the chain.