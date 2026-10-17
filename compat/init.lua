--[[
	pixie - Compatibility Layer Subsystem
	Modular cross-game and cross-mod integration registry for Luanti.
	Supports Voxelibre / Mineclonia, Everness, Ethereal, Farming, and standard environments.
]]

---@class PixieCompat
local compat = {
	flora_patterns = {},
	flora_items = {},
	ores = {},
	hostiles = {},
	hostile_factions = {
		undead = true,
		skeleton = true,
		spider = true,
		fallen = true,
		cultist = true,
		monster = true,
		monsters = true,
		hostile = true,
		enemy = true,
		boss = true,
	},
	spawn_nodes = {},
	drop_entries = {},
}

---Registers a flower or floral item/pattern for wild pixie attraction, taming, and healing.
---@param item_or_pattern string
function compat.register_flora(item_or_pattern)
	if not item_or_pattern or item_or_pattern == "" then return end
	if item_or_pattern:find("[%^%*%$]") then
		compat.flora_patterns[item_or_pattern] = true
	else
		compat.flora_items[item_or_pattern] = true
	end
end

---Checks whether an item name is recognized as flora.
---@param item_name string
---@return boolean
function compat.is_flora(item_name)
	if not item_name or item_name == "" then return false end
	if compat.flora_items[item_name] then return true end

	local def = core.registered_items[item_name]
	if def and def.groups then
		local fg = def.groups.flower
		local flg = def.groups.flora
		if (fg and fg > 0) or (flg and flg > 0) then
			return true
		end
	end

	for pattern in pairs(compat.flora_patterns) do
		if item_name:find(pattern) then
			return true
		end
	end

	return false
end

---Registers an ore node classification with priority score and title.
---@param node_name string
---@param title string
---@param priority integer
function compat.register_ore(node_name, title, priority)
	compat.ores[node_name] = {
		title = title,
		priority = priority,
	}
end

---Returns classification for an ore node name if registered.
---@param node_name string
---@return table|nil
function compat.get_ore_info(node_name)
	return compat.ores[node_name]
end

---Returns all registered ore node names.
---@return table<string, {title: string, priority: integer}>
function compat.get_all_ores()
	return compat.ores
end

---Registers a known hostile mob technical name.
---@param entity_name string
---@param display_title string
function compat.register_hostile(entity_name, display_title)
	compat.hostiles[entity_name] = display_title
end

---Registers a hostile faction name.
---@param faction string
function compat.register_hostile_faction(faction)
	compat.hostile_factions[faction:lower()] = true
end

---Formats a technical entity name into a human-readable Title Case string.
---@param ent_name string
---@return string
local function format_entity_title(ent_name)
	local sub = ent_name:match(":(.+)$") or ent_name
	return (sub:gsub("_", " "):gsub("(%a)([%w_']*)", function(first, rest)
		return first:upper() .. rest:lower()
	end))
end

---Determines whether an ObjectRef is a hostile threat to the player.
---@param obj ObjectRef
---@param owner_player? ObjectRef
---@return boolean is_threat
---@return string display_title
function compat.is_hostile(obj, owner_player)
	if not obj or not obj:is_valid() then return false, "" end
	if obj:is_player() then return false, "" end

	-- Exclude anything directly attached to the player (armor meshes, wield items, visual sleeves, HUDs)
	if obj.get_attach and owner_player and owner_player:is_valid() then
		local parent = obj:get_attach()
		if parent == owner_player then
			return false, ""
		end
	end

	local ent = obj:get_luaentity()
	if not ent or ent.name == "pixie:pixie" then
		return false, ""
	end

	-- Exclude status visual sleeves / envelops, health bars, visual proxies, armor entities, items, corpses
	if ent._is_envelop or ent._is_health_bar or ent._is_visual
		or ent._is_visual_proxy or ent._is_wielditem or ent._is_x_player_armor
		or ent._is_item or ent._is_hologram or ent._csm_ignore
		or ent._is_corpse
		or ent.name == "x_mob_core:envelop" or ent.name == "x_mob_core:health_bar"
		or ent.name == "__builtin:item" or ent.name == "__builtin:falling_node"
		or ent.name:find(":envelop") or ent.name:find("trophy_hologram") then
		return false, ""
	end

	-- Exclude projectiles, ammunition, spells, and arrows
	if ent._is_projectile or ent._is_arrow or ent._is_bullet
		or ent._is_fireball or ent._is_spell
		or ent.name:find(":arrow") or ent.name:find("_arrow$")
		or ent.name:find("_projectile$")
		or (ent.velocity and (ent.hit_player or ent.hit_node or ent.hit_mob)) then
		return false, ""
	end

	-- Exclude dead, dying, or corpse entities
	if ent.is_dead or ent.dead or ent._dead
		or ent.state == "dying" or ent.state == "die" or ent.state == "dead" then
		return false, ""
	end

	local hp = ent.hp or obj:get_hp()
	if hp and hp <= 0 then
		return false, ""
	end

	-- Do not alert on the player's own tamed companions, mounts, or pets
	local owner_name = owner_player and owner_player:is_valid() and owner_player:get_player_name()
	if owner_name and owner_name ~= "" then
		if ent.owner_name == owner_name or ent.owner == owner_name or ent._owner == owner_name then
			return false, ""
		end
		if ent.tamed == true and (not ent.owner or ent.owner == "" or ent.owner == owner_name or ent.owner_name == owner_name) then
			return false, ""
		end
	end

	-- Check x_mob_core allegiance subsystem if present
	if x_mob_core and x_mob_core.are_allies and owner_player and owner_player:is_valid() then
		if x_mob_core.are_allies(obj, owner_player) then
			return false, ""
		end
	end

	-- Known hostile entities registered in compat registries
	local known_title = compat.hostiles[ent.name]
	if known_title then
		return true, known_title
	end

	-- Entities explicitly configured to never attack players (e.g. kittens, passive critters)
	if ent.attack_players == false or ent.attacks_players == false then
		return false, ""
	end

	-- Passive mobs that do not fight
	if ent.passive == true then
		return false, ""
	end

	-- Mobs Redo / generic monster type or aggressive attack type (excluding neutral animals/NPCs)
	if ent.type == "monster" or ent.type == "hostile"
		or (ent.passive == false and ent.type ~= "animal" and ent.type ~= "npc"
			and (ent.attack_type == "dogfight" or ent.attack_type == "shoot" or ent.attack_type == "dogshoot")) then
		return true, format_entity_title(ent.name)
	end

	-- Creatura / Animalia aggressive predators
	if ent.attacks_players == true or ent.hostile == true then
		return true, format_entity_title(ent.name)
	end

	-- Hostile faction memberships (e.g. undead, skeleton, fallen, cultist, monster, boss)
	if ent.factions and type(ent.factions) == "table" then
		for k, v in pairs(ent.factions) do
			local f = (type(k) == "string" and k) or (type(v) == "string" and v)
			if f and compat.hostile_factions[f:lower()] then
				return true, format_entity_title(ent.name)
			end
		end
	end

	-- Active aggressive lock-on targeting the owner player
	if owner_player and owner_player:is_valid() then
		local has_target_lock = (ent.target == owner_player or ent.attack == owner_player or ent._target == owner_player)
		if has_target_lock then
			return true, format_entity_title(ent.name)
		end
		if type(ent.punch_target) == "userdata" and ent.punch_target == owner_player then
			return true, format_entity_title(ent.name)
		end
	end

	return false, ""
end

---Registers environmental natural spawning surfaces.
---@param node_name string
function compat.register_spawn_node(node_name)
	compat.spawn_nodes[node_name] = true
end

---Returns all valid environmental natural spawning surfaces.
---@return string[]
function compat.get_spawn_nodes()
	local list = {}
	for name in pairs(compat.spawn_nodes) do
		list[#list + 1] = name
	end
	return list
end

---Registers loot drop entries for x_mob_core drop tables.
---@param drop_entry table
function compat.register_drop(drop_entry)
	compat.drop_entries[#compat.drop_entries + 1] = drop_entry
end

---Returns all declarative drop entries for x_mob_core.
---@return table[]
function compat.get_drops()
	return compat.drop_entries
end

pixie.compat = compat

-- Load modular compatibility adaptors
local modpath = core.get_modpath("pixie")
dofile(modpath .. "/compat/default.lua")
dofile(modpath .. "/compat/mcl.lua")
dofile(modpath .. "/compat/everness.lua")
dofile(modpath .. "/compat/ethereal.lua")
dofile(modpath .. "/compat/farming.lua")
dofile(modpath .. "/compat/mobs.lua")

return compat
