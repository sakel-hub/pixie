--[[
	pixie - Compatibility Adaptor: Default / Luanti Game & Standard Mobs
]]

local compat = pixie.compat

-- Flora
compat.register_flora("^flowers:")
compat.register_flora(":flower")
compat.register_flora(":flora")
compat.register_flora("default:junglegrass")

-- Ores
compat.register_ore("default:stone_with_diamond", "Diamond Ore", 100)
compat.register_ore("default:stone_with_mese", "Mese Ore", 90)
compat.register_ore("default:stone_with_gold", "Gold Ore", 75)
compat.register_ore("default:stone_with_iron", "Iron Ore", 50)
compat.register_ore("default:stone_with_copper", "Copper Ore", 45)
compat.register_ore("default:stone_with_tin", "Tin Ore", 42)
compat.register_ore("default:stone_with_coal", "Coal Ore", 30)

-- Known Hostile Entities
compat.register_hostile("x_mobs:spider", "Spider")
compat.register_hostile("x_mobs:skull_archer", "Skull Archer")
compat.register_hostile("x_mobs:skull_lancer", "Skull Lancer")
compat.register_hostile("x_mobs:skull_king", "Skull King")
compat.register_hostile("x_mobs:fallen_shaman", "Fallen Shaman")
compat.register_hostile("x_mobs:fallen_minion", "Fallen Minion")
compat.register_hostile("x_mobs:crystal_guardian", "Crystal Guardian")
compat.register_hostile("pale_watcher:pale_watcher", "Pale Watcher")
compat.register_hostile("mobs_monster:dungeon_master", "Dungeon Master")
compat.register_hostile("mobs_monster:oerkki", "Oerkki")
compat.register_hostile("mobs_monster:stone_monster", "Stone Monster")
compat.register_hostile("mobs_monster:sand_monster", "Sand Monster")
compat.register_hostile("mobs_monster:tree_monster", "Tree Monster")
compat.register_hostile("mobs_monster:spider", "Spider")
compat.register_hostile("dmobs:dragon", "Dragon")
compat.register_hostile("dmobs:orc", "Orc")
compat.register_hostile("dmobs:treeman", "Treeman")

-- Spawning surfaces (walkable ground in meadows, forests, and snowy highlands)
compat.register_spawn_node("default:dirt_with_grass")
compat.register_spawn_node("default:dirt_with_coniferous_litter")
compat.register_spawn_node("default:dirt_with_rainforest_litter")
compat.register_spawn_node("default:dry_dirt_with_dry_grass")
compat.register_spawn_node("default:dirt_with_snow")
compat.register_spawn_node("group:soil")

-- Loot drops on defeat (via x_mob_core: botanical traces & glowing stardust; no diamonds)
compat.register_drop({ name = "flowers:rose", min = 1, max = 1, chance = 0.80 })
compat.register_drop({ name = "default:mese_crystal_fragment", min = 1, max = 1, chance = 0.40 })
