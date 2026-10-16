--[[
	pixie - Dynamic Light Subsystem
	Transient node-based dynamic lighting radiating from the pixie companion.
	Includes an auto-decay node timer to guarantee zero ghost lights across crashes/restarts.
]]

local S = core.get_translator("pixie")

---@class PixieLightSubsystem
---@field natural_light_threshold number
---@field clear fun(self: table)
---@field update fun(self: table, pos: Vector)
local dynamic_light = {}

-- Transient airlike light node providing real world illumination.
core.register_node("pixie:light", {
	description = S("Pixie Dynamic Aura Light"),
	drawtype = "airlike",
	paramtype = "light",
	light_source = 13,
	sunlight_propagates = true,
	walkable = false,
	pointable = false,
	diggable = false,
	buildable_to = true,
	air_equivalent = true,
	floodable = true,
	drop = "",
	groups = {not_in_creative_inventory = 1},
	on_blast = function() end,
	on_timer = function(pos)
		local objs = core.get_objects_inside_radius(pos, 4.5)
		for i = 1, #objs do
			local obj = objs[i]
			if obj and obj:is_valid() and not obj:is_player() then
				local ent = obj:get_luaentity()
				if ent and ent.name == "pixie:pixie" then
					return true
				end
			end
		end
		core.swap_node(pos, {name = "air"})
		return false
	end,
})

-- Pre-allocated static offset tables to avoid LuaJIT GC pressure in step loops
local CARDINAL_LIGHT_OFFSETS = {
	{x = 0, y = 1, z = 0},
	{x = 0, y = -1, z = 0},
	{x = 1, y = 0, z = 0},
	{x = -1, y = 0, z = 0},
	{x = 0, y = 0, z = 1},
	{x = 0, y = 0, z = -1},
}

local light_probe = {x = 0, y = 0, z = 0}

local DEFAULT_NATURAL_THRESHOLD = 12
dynamic_light.natural_light_threshold = (pixie.config and pixie.config.light_natural_threshold)
	or DEFAULT_NATURAL_THRESHOLD

-- Minimum displacement squared (2.0 blocks) before relocating an active light node
local MIN_LIGHT_MOVE_DIST_SQ = 4.0

-- In-memory registry of active companion light positions with weak keys to prevent leaks
---@type table<table, Vector>
dynamic_light.active_lights = setmetatable({}, {__mode = "k"})

---Safely clears dynamic light node from previous coordinate
---@param self table Mob entity instance
function dynamic_light.clear(self)
	dynamic_light.active_lights[self] = nil
	if self._last_light_pos then
		local node = core.get_node_or_nil(self._last_light_pos)
		if node and node.name == "pixie:light" then
			core.swap_node(self._last_light_pos, {name = "air"})
		end
		self._last_light_pos = nil
	end
end

---Updates dynamic voxel light source around the moving pixie with flicker-free adjacent air fallback
---@param self table Mob entity instance
---@param pos Vector Mob world position
function dynamic_light.update(self, pos)
	local rounded = vector.round(pos)
	local target_light_pos = nil

	-- Prefer node the pixie is directly occupying if it's air or already our light
	local cur_node = core.get_node_or_nil(rounded)
	if cur_node and (cur_node.name == "air" or cur_node.name == "pixie:light") then
		target_light_pos = rounded
	else
		-- Pos is inside or grazing a solid block; search cardinal neighbors for clear air
		for i = 1, #CARDINAL_LIGHT_OFFSETS do
			local off = CARDINAL_LIGHT_OFFSETS[i]
			light_probe.x = rounded.x + off.x
			light_probe.y = rounded.y + off.y
			light_probe.z = rounded.z + off.z
			local n = core.get_node_or_nil(light_probe)
			if n and (n.name == "air" or n.name == "pixie:light") then
				target_light_pos = {x = light_probe.x, y = light_probe.y, z = light_probe.z}
				break
			end
		end
	end

	-- If no clear air was found anywhere nearby, extinguish previous light
	if not target_light_pos then
		dynamic_light.clear(self)
		return
	end

	-- Natural ambient sunlight shutoff: in broad daylight (>= threshold), dynamic lighting adds
	-- zero visual benefit and needlessly incurs C++ lighting recalculations and network packets.
	local nat_thresh = dynamic_light.natural_light_threshold or DEFAULT_NATURAL_THRESHOLD
	local nat_light = core.get_natural_light(target_light_pos)
	if nat_light and nat_light >= nat_thresh then
		dynamic_light.clear(self)
		return
	end

	-- Proximity light sharing among party members / nearby pixies:
	-- If another companion's light is already radiating within 4.0 blocks (dist_sq <= 16.0),
	-- borrow that light source and avoid creating a redundant light node.
	for other_self, other_pos in pairs(dynamic_light.active_lights) do
		if other_self ~= self and other_pos then
			if pixie.utils.dist_sq(other_pos, target_light_pos) <= 16.0 then
				local other_node = core.get_node_or_nil(other_pos)
				if other_node and other_node.name == "pixie:light" then
					dynamic_light.clear(self)
					return
				end
			end
		end
	end

	-- Displacement threshold optimization:
	-- A light source with radius 13 illuminates virtually the identical volume within 2.0 blocks.
	-- Skip swapping if displacement from existing active light is < 2.0 blocks (dist_sq < 4.0).
	if self._last_light_pos then
		local dist_sq = pixie.utils.dist_sq(self._last_light_pos, target_light_pos)

		if dist_sq < MIN_LIGHT_MOVE_DIST_SQ then
			-- Verify existing light node is still intact in the world
			local existing = core.get_node_or_nil(self._last_light_pos)
			if existing and existing.name == "pixie:light" then
				core.get_node_timer(self._last_light_pos):start(4.0)
				dynamic_light.active_lights[self] = self._last_light_pos
				return
			end
		end
	end

	local old_pos = self._last_light_pos
	local placed_new = false

	local target_node = core.get_node_or_nil(target_light_pos)
	if target_node and target_node.name == "air" then
		core.swap_node(target_light_pos, {name = "pixie:light"})
		core.get_node_timer(target_light_pos):start(4.0)
		self._last_light_pos = target_light_pos
		placed_new = true
	elseif target_node and target_node.name == "pixie:light" then
		core.get_node_timer(target_light_pos):start(4.0)
		self._last_light_pos = target_light_pos
		placed_new = true
	end

	-- Seamless hand-off: remove the previous light only AFTER the new light is active and radiating
	-- This eliminates momentary blackout flickers by maintaining continuous voxel illumination
	if placed_new then
		dynamic_light.active_lights[self] = target_light_pos
		if old_pos and not vector.equals(old_pos, target_light_pos) then
			local old_node = core.get_node_or_nil(old_pos)
			if old_node and old_node.name == "pixie:light" then
				core.swap_node(old_pos, {name = "air"})
			end
		end
	else
		-- Target could not be illuminated; clean up previous light
		dynamic_light.clear(self)
	end
end

pixie.dynamic_light = dynamic_light
return dynamic_light

