--[[
	pixie - Compatibility Adaptor: Everness
]]

local compat = pixie.compat

-- Flora
compat.register_flora("^everness:.*flower")
compat.register_flora("^everness:coral_flower")
compat.register_flora("^everness:crystal_flower")
compat.register_flora("^everness:glow_flower")
compat.register_flora("^everness:azure_flower")

-- Ores
compat.register_ore("everness:crystal_ore_azure", "Azure Crystal Ore", 85)
compat.register_ore("everness:crystal_ore_amber", "Amber Crystal Ore", 80)
compat.register_ore("everness:crystal_ore_emerald", "Emerald Crystal Ore", 80)
compat.register_ore("everness:crystal_ore_ruby", "Ruby Crystal Ore", 85)
compat.register_ore("everness:crystal_ore_amethyst", "Amethyst Crystal Ore", 85)
compat.register_ore("everness:mineral_quartz", "Everness Quartz Ore", 70)

-- Spawning surfaces
compat.register_spawn_node("everness:crystal_grass")
compat.register_spawn_node("everness:coral_grass")
compat.register_spawn_node("everness:crystal_forest_leaves")

-- Loot drops on defeat (via x_mob_core)
compat.register_drop({ name = "everness:quartz_crystal", min = 1, max = 2, chance = 0.40 })
compat.register_drop({ name = "everness:crystal_emerald", min = 1, max = 1, chance = 0.20 })
