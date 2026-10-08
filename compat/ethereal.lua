--[[
	pixie - Compatibility Adaptor: Ethereal NG
]]

local compat = pixie.compat

-- Flora
compat.register_flora("ethereal:fire_flower")
compat.register_flora("ethereal:illumishroom")
compat.register_flora("ethereal:crystalgrass")
compat.register_flora("ethereal:snowflower")
compat.register_flora("ethereal:sponge_mushroom")

-- Ores / Minerals
compat.register_ore("ethereal:crystal_spike", "Crystal Spike", 80)
compat.register_ore("ethereal:illumishroom_ore", "Illumishroom Deposit", 65)

-- Spawning surfaces
compat.register_spawn_node("ethereal:crystal_dirt")
compat.register_spawn_node("ethereal:prairie_dirt")
compat.register_spawn_node("ethereal:grove_dirt")

-- Loot drops on defeat (via x_mob_core)
compat.register_drop({ name = "ethereal:crystal_spike", min = 1, max = 2, chance = 0.35 })
compat.register_drop({ name = "ethereal:fire_flower", min = 1, max = 1, chance = 0.50 })
