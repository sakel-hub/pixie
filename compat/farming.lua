--[[
	pixie - Compatibility Adaptor: Farming & x_farming
]]

local compat = pixie.compat

-- Flora & Botanical blossoms
compat.register_flora("^farming:sunflower")
compat.register_flora("^farming:rose")
compat.register_flora("^farming:tulip")
compat.register_flora("^x_farming:sunflower")
compat.register_flora("^x_farming:rose")
compat.register_flora("farming:cotton_wild")

-- Loot drops on defeat (via x_mob_core: botanical seed trace)
compat.register_drop({ name = "farming:seed_cotton", min = 1, max = 1, chance = 0.35 })
