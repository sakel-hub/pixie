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

	local ent = obj:get_luaentity()
	if not ent or ent.name == "pixie:pixie" then
		return false, ""
	end

	if ent.is_dead or ent.state == "dying" or ent.state == "die" then
		return false, ""
	end

	local hp = ent.hp or obj:get_hp()
	if hp and hp <= 0 then
		return false, ""
	end

	-- Do not alert on the player's own tamed companions or pets
	local owner_name = owner_player and owner_player:get_player_name()
	if owner_name then
		if ent.owner_name == owner_name or ent.owner == owner_name then
			return false, ""
		end
	end

	local known_title = compat.hostiles[ent.name]
	if known_title then
		return true, known_title
	end

	-- Mobs Redo / generic monster type or aggressive attack type
	if ent.type == "monster" or ent.type == "hostile"
		or (ent.passive == false and (ent.attack_type == "dogfight" or ent.attack_type == "shoot")) then
		return true, format_entity_title(ent.name)
	end

	-- Creatura / Animalia aggressive predators
	if ent.attacks_players == true or ent.hostile == true then
		return true, format_entity_title(ent.name)
	end

	if ent.factions and type(ent.factions) == "table" then
		for k, v in pairs(ent.factions) do
			local f = (type(k) == "string" and k) or (type(v) == "string" and v)
			if f and compat.hostile_factions[f:lower()] then
				return true, format_entity_title(ent.name)
			end
		end
	end

	if owner_player and owner_player:is_valid() then
		if ent.target == owner_player or ent.attack == owner_player
			or ent._target == owner_player or ent.punch_target == owner_player then
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
