--[[
	pixie - Fairy Whistle Tool & Crafting
	Enchanted musical instrument used to recall distant guarding companions
	and command playful acrobatic tricks when accompanied.
]]

local S = core.get_translator("pixie")

local DEFAULT_WHISTLE_DURABILITY = 30
local setting_durability = tonumber(core.settings:get("pixie_whistle_durability"))
local WHISTLE_DURABILITY = (setting_durability and setting_durability > 0)
	and setting_durability or DEFAULT_WHISTLE_DURABILITY
local WEAR_PER_USE = math.floor(65535 / WHISTLE_DURABILITY)

local function handle_whistle(itemstack, user, pointed_thing)
	if not user or not user:is_player() or not user:is_valid() then
		return itemstack
	end
	local player_name = user:get_player_name()
	if not player_name or player_name == "" then
		return itemstack
	end

	local ppos = user:get_pos()
	if not ppos then return itemstack end

	-- Sneak + Right-Click: Instant companion status and location radar check
	if user:get_player_control().sneak then
		if core.chatcommands["pixie"] and core.chatcommands["pixie"].func then
			local _, msg = core.chatcommands["pixie"].func(player_name, "status")
			if msg then
				core.chat_send_player(player_name, core.colorize("#ffff88", msg))
				x_mob_core.play_sound(user, "pixie_chime", {pos = ppos, gain = 0.5, pitch = 1.25})
			end
		end
		return itemstack
	end

	-- If right-clicking a node that has its own on_rightclick (chest, door, etc.), pass through
	if pointed_thing and pointed_thing.type == "node" then
		local node = core.get_node_or_nil(pointed_thing.under)
		local def = node and core.registered_nodes[node.name]
		if def and def.on_rightclick then
			return def.on_rightclick(pointed_thing.under, node, user, itemstack, pointed_thing)
		end
	end

	-- If right-clicking directly on a pixie entity, let the entity's on_rightclick handle it
	if pointed_thing and pointed_thing.type == "object" then
		local obj = pointed_thing.ref
		if obj and obj:is_valid() then
			local ent = obj:get_luaentity()
			if ent and ent.name == "pixie:pixie" and ent.on_rightclick then
				return ent:on_rightclick(user) or itemstack
			end
		end
	end

	-- Musical whistle audio and visual starlight sparkles
	core.sound_play("pixie_whistle", {
		pos = ppos,
		gain = 0.85,
		pitch = 1.0,
		max_hear_distance = 24.0,
	})
	pixie.spawn_whistle_melody(ppos, player_name)

	local success = pixie.recall_companion(user, true)
	if success then
		-- Apply tool wear on successful recall or trick command
		itemstack:add_wear(WEAR_PER_USE)
		if itemstack:get_count() == 0 or itemstack:is_empty() then
			x_mob_core.play_sound(user, "pixie_hurt", {pos = ppos, gain = 0.6, pitch = 1.6})
			core.chat_send_player(player_name, core.colorize("#ffaa88",
				S("✦ Your Fairy Whistle has dissolved into delicate fairy dust! ✦")))
		end
	end

	return itemstack
end

-- Register the Fairy Whistle Tool
core.register_tool("pixie:whistle", {
	description = S("Fairy Whistle") .. "\n" ..
		core.colorize("#aaeebb", S("Right-click to call your guarding pixie companion back to follow you.")) .. "\n" ..
		core.colorize("#dddddd", S("Plays a cheerful melody that commands tricks when following.")) .. "\n" ..
		core.colorize("#88ccff", S("Sneak + Right-click to check companion status and distance.")),
	inventory_image = "pixie_whistle.png",
	wield_image = "pixie_whistle.png",
	stack_max = 1,
	groups = {tool = 1},

	on_place = handle_whistle,
	on_secondary_use = handle_whistle,
})

-- Crafting Recipes
-- 1. Standard Luanti Game (default)
if core.get_modpath("default") then
	-- Gold Ingot + Flower + Stick
	core.register_craft({
		output = "pixie:whistle",
		recipe = {
			{"group:flower", "default:gold_ingot"},
			{"", "group:stick"},
		},
	})
	-- Mese Crystal Fragment + Flower + Stick
	core.register_craft({
		output = "pixie:whistle",
		recipe = {
			{"group:flower", "default:mese_crystal_fragment"},
			{"", "group:stick"},
		},
	})
end

-- 2. Voxelibre / Mineclonia (mcl_core)
if core.get_modpath("mcl_core") then
	core.register_craft({
		output = "pixie:whistle",
		recipe = {
			{"group:flower", "mcl_core:gold_ingot"},
			{"", "mcl_core:stick"},
		},
	})
end

-- 3. Generic Group Fallback for standalone games
if not core.get_modpath("default") and not core.get_modpath("mcl_core") then
	core.register_craft({
		output = "pixie:whistle",
		recipe = {
			{"group:flower", "group:wood"},
			{"", "group:stick"},
		},
	})
end
