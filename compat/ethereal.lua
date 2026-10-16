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

-- Spawning surfaces (walkable ground in green plains, enchanted groves, and crystal dirt)
compat.register_spawn_node("ethereal:green_dirt")
compat.register_spawn_node("ethereal:crystal_dirt")
compat.register_spawn_node("ethereal:prairie_dirt")
compat.register_spawn_node("ethereal:grove_dirt")
compat.register_spawn_node("ethereal:bamboo_dirt")
compat.register_spawn_node("ethereal:jungle_dirt")

-- Loot drops on defeat (via x_mob_core: botanical traces & glowing mushroom)
compat.register_drop({ name = "ethereal:fire_flower", min = 1, max = 1, chance = 0.60 })
compat.register_drop({ name = "ethereal:illumishroom", min = 1, max = 1, chance = 0.40 })
