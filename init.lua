--[[
	pixie - Mystical Pixie Companion Mod
	Modular, lightweight, and DRY companion framework relying directly on x_mob_core.
]]

local modpath = core.get_modpath("pixie")

-- Load primary API table first
dofile(modpath .. "/api.lua")

-- Load subsystems in order
dofile(modpath .. "/compat/init.lua")
dofile(modpath .. "/particles.lua")
dofile(modpath .. "/dynamic_light.lua")
dofile(modpath .. "/ore_sensor.lua")
dofile(modpath .. "/bonding.lua")
dofile(modpath .. "/entities.lua")
dofile(modpath .. "/whistle.lua")

core.log("action", "[pixie] Mystical Pixie Companion loaded successfully.")
