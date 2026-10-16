--[[
	pixie - Player Bonding, Loyalty Tiers & Guardian Angel Persistence
	Manages companion loyalty progression, session disconnect safety restoration,
	and the sacrificial Guardian Angel last stand.
]]

local S = core.get_translator("pixie")
local mod_storage = pixie.storage

---@class PixieBondingSubsystem
---@field active_player_pixies table<string, PixieEntity>
---@field get_loyalty_tier fun(bond_time: number): integer
---@field get_tier_title fun(tier: integer|number): string
---@field format_bond_time fun(sec: number): string
---@field save_bonded_pixie fun(player: ObjectRef, pixie: table)
---@field load_bonded_pixie fun(player: ObjectRef): table|nil
---@field clear_bonded_pixie fun(player: ObjectRef)
---@field untame_pixie fun(ent: table)
---@field stow_bonded_pixie fun(player: ObjectRef, pixie_ent: table, player_name: string)
---@field release_companion fun(player: ObjectRef, notify?: boolean, target_ent?: table): boolean
---@field restore_companion fun(player: ObjectRef): boolean
---@field recall_companion fun(player: ObjectRef, notify?: boolean): boolean, string, table|nil
---@field signal_combat fun(player_or_name: ObjectRef|string, duration?: number, threat_pos?: Vector): boolean
local bonding = {}

-- Active bonded following companions map [player_name] = PixieEntity
local active_player_pixies = {}
bonding.active_player_pixies = active_player_pixies

local DEFAULT_TIER2_TIME = 1200
local DEFAULT_TIER3_TIME = 3600
local tier2_thresh = (pixie.config and pixie.config.loyalty_tier2_time) or DEFAULT_TIER2_TIME
local tier3_thresh = (pixie.config and pixie.config.loyalty_tier3_time) or DEFAULT_TIER3_TIME

local DEFAULT_COMBAT_DURATION = 8.0
local combat_retreat_duration = (pixie.config and pixie.config.combat_retreat_duration) or DEFAULT_COMBAT_DURATION

---Gets the loyalty tier (1, 2, or 3) from total bond survival time in seconds.
---@param bond_time number Total seconds bonded
---@return integer tier 1 = Fledgling, 2 = Loyal, 3 = Guardian
function bonding.get_loyalty_tier(bond_time)
	bond_time = tonumber(bond_time) or 0
	if bond_time >= tier3_thresh then
		return 3
	elseif bond_time >= tier2_thresh then
		return 2
	else
		return 1
	end
end

---Gets the localized title for a loyalty tier.
---@param tier integer|number Tier number or bond time
---@return string title
function bonding.get_tier_title(tier)
	local tier_num = (type(tier) == "number" and tier > 10) and bonding.get_loyalty_tier(tier) or tier
	if tier_num == 3 then
		return S("Ancient Guardian")
	elseif tier_num == 2 then
		return S("Loyal Companion")
	else
		return S("Fledgling")
	end
end

---Formats bond survival time in seconds into a concise readable string (e.g. "45s", "25m", "2h 15m").
---@param sec number
---@return string
function bonding.format_bond_time(sec)
	sec = math.max(0, math.floor(tonumber(sec) or 0))
	if sec < 60 then
		return sec .. "s"
	elseif sec < 3600 then
		return math.floor(sec / 60) .. "m"
	else
		local hrs = math.floor(sec / 3600)
		local mins = math.floor((sec % 3600) / 60)
		return hrs .. "h " .. mins .. "m"
	end
end

---Checks whether an entity is a bonded pixie belonging to a player.
---@param ent table Lua entity instance
---@param pname string Player username
---@return boolean
local function is_player_bonded_pixie(ent, pname)
	return ent ~= nil and ent.name == "pixie:pixie" and ent.owner_name == pname
end

---Safely invalidates, cleans up lights/particles, and removes a duplicate or stale companion entity.
---@param ent table Entity instance
function bonding.prune_companion_entity(ent)
	if not ent then return end
	ent._invalidated = true
	ent.is_dead = true
	ent._removed = true
	if ent._sparkle_spawner_id then
		core.delete_particlespawner(ent._sparkle_spawner_id)
		ent._sparkle_spawner_id = nil
	end
	pixie.dynamic_light.clear(ent)
	if ent.object and ent.object:is_valid() then
		ent.object:remove()
	end
end

-- Helper to find active or nearby companion entity for a player
local function get_companion_entity(player_name, search_radius)
	local ent = active_player_pixies[player_name]
	if ent and ent.object and ent.object:is_valid() then
		return ent
	end
	local player = core.get_player_by_name(player_name)
	if player and player:is_valid() then
		local ppos = player:get_pos()
		if ppos then
			local nearby = core.get_objects_inside_radius(ppos, search_radius or 16.0)
			for i = 1, #nearby do
				local o = nearby[i]
				if o and not o:is_player() then
					local le = o:get_luaentity()
					if is_player_bonded_pixie(le, player_name) then
						return le
					end
				end
			end
		end
	end
	return nil
end

---Saves bonded companion state into player metadata.
---@param player ObjectRef
---@param pixie table Pixie entity instance
function bonding.save_bonded_pixie(player, pixie)
	if not player or not player:is_valid() then return end
	local player_name = player:get_player_name()
	if not player_name or player_name == "" then return end

	local cur_hp = pixie.hp
	if not cur_hp and pixie.object and pixie.object:is_valid() then
		cur_hp = pixie.object:get_hp()
	end
	local tex_no = pixie.texture_no or 1
	local b_time = pixie.bond_time or 0
	local l_tier = pixie.loyalty_tier or bonding.get_loyalty_tier(b_time)

	local g_pos = pixie.guard_pos
	if (pixie.mode == "stay" or pixie.mode == "guard") and not g_pos and pixie.object and pixie.object:is_valid() then
		local pos = pixie.object:get_pos()
		if pos then
			g_pos = vector.round(pos)
			pixie.guard_pos = g_pos
		end
	end

	local comp_id = pixie._companion_id
	if not comp_id or comp_id == "" then
		comp_id = x_mob_core.generate_uuid()
		pixie._companion_id = comp_id
	end

	local cur_gen = pixie._recall_gen or 0

	local save_data = {
		owner_name = player_name,
		mode = pixie.mode or "follow",
		guard_pos = g_pos,
		bond_time = b_time,
		loyalty_tier = l_tier,
		texture_no = tex_no,
		hp = cur_hp or 30,
		custom_name = pixie.custom_name,
		pixie_name = pixie.pixie_name or S("Mystical Pixie"),
		show_nametag = (pixie.show_nametag ~= false),
		persistent = true,
		recall_gen = cur_gen,
		companion_id = comp_id,
	}
	player:get_meta():set_string("pixie:bonded", core.serialize(save_data))

	if mod_storage then
		mod_storage:set_string("pixie:" .. player_name .. ":companion_id", comp_id)
		mod_storage:set_int("pixie:" .. player_name .. ":recall_gen", cur_gen)
		mod_storage:set_string("pixie:" .. player_name .. ":mode", pixie.mode or "follow")
	end
end

---Loads bonded companion state from player metadata.
---@param player ObjectRef
---@return table|nil
function bonding.load_bonded_pixie(player)
	if not player or not player:is_valid() then return nil end
	local meta = player:get_meta()
	local raw = meta:get_string("pixie:bonded")
	if not raw or raw == "" then return nil end
	local data = core.deserialize(raw)
	return type(data) == "table" and data or nil
end

---Clears bonded companion state from player metadata and mod storage.
---@param player ObjectRef
function bonding.clear_bonded_pixie(player)
	if not player or not player:is_valid() then return end
	local player_name = player:get_player_name()
	local meta = player:get_meta()
	meta:set_string("pixie:bonded", "")
	if mod_storage and player_name and player_name ~= "" then
		mod_storage:set_string("pixie:" .. player_name .. ":companion_id", "")
		mod_storage:set_int("pixie:" .. player_name .. ":recall_gen", 0)
		mod_storage:set_string("pixie:" .. player_name .. ":mode", "")
	end
end

---Untames a pixie entity, returning it freely to the wild and clearing all nametags.
---@param ent table Pixie entity instance
function bonding.untame_pixie(ent)
	if not ent then return end
	ent.owner_name = nil
	ent.custom_name = nil
	ent.pixie_name = nil
	ent.show_nametag = false
	ent.mode = "wild"
	ent.guard_pos = nil
	ent.bond_time = 0
	ent.loyalty_tier = 1
	ent._persistent = false
	ent._companion_id = nil
	ent._recall_gen = 0

	-- Reset factions to wild state: remove players alliance so released pixies can be attacked/killed
	ent.factions = {pixie = true, fairy = true, neutral = true}
	ent.faction_list = {"pixie", "fairy", "neutral"}

	-- Ensure health and mortal mob properties
	ent.hp = ent.hp or 30
	if ent.hp <= 0 then ent.hp = 30 end
	ent.is_dead = false
	ent.state = "idle"
	ent.action_timer = 0

	pixie.dynamic_light.clear(ent)

	if ent.object and ent.object:is_valid() then
		local pos = ent.object:get_pos()
		if pos then
			ent._home_pos = {x = pos.x, y = pos.y, z = pos.z}
			pixie.spawn_sparkles(pos, 8)
			x_mob_core.play_sound(ent, "chime", {pos = pos, pitch = 0.85})
		end
		-- Immediately wipe 3D in-world nametag billboard from engine object
		ent.object:set_properties({
			nametag = "",
			nametag_color = {r = 0, g = 0, b = 0, a = 0},
			nametag_bgcolor = false,
			pointable = true,
		})
		-- Ensure armor groups are standard mortal damage groups
		ent.object:set_armor_groups({ fleshy = 100 })
		ent:_update_properties()
		x_mob_core.play_animation(ent.object, "idle", {speed = 1.0, loop = true, force = true})
	end
end

---Stows active bonded companion into player's persistent storage upon disconnect or shutdown
---@param player ObjectRef
---@param pixie_ent table PixieEntity
---@param player_name string
function bonding.stow_bonded_pixie(player, pixie_ent, player_name)
	if pixie_ent and pixie_ent.object and pixie_ent.object:is_valid() then
		bonding.save_bonded_pixie(player, pixie_ent)
		if pixie_ent.mode == "follow" then
			pixie.dynamic_light.clear(pixie_ent)
			pixie_ent.object:remove()
		end
	end
	active_player_pixies[player_name] = nil
end

---Releases any existing bonded pixie companion belonging to a player.
---@param player ObjectRef Connected player
---@param notify? boolean Whether to send a chat notification to the player
---@param target_ent? table Optional specific pixie entity instance to untame
---@return boolean released True if an existing companion was released
function bonding.release_companion(player, notify, target_ent)
	if not player or not player:is_valid() then return false end
	local pname = player:get_player_name()
	local had_bonded = false

	if target_ent then
		bonding.untame_pixie(target_ent)
		had_bonded = true
	end

	local active = active_player_pixies[pname]
	if active then
		bonding.untame_pixie(active)
		active_player_pixies[pname] = nil
		had_bonded = true
	end

	-- Check nearby radius around player for any companions belonging to this player
	local ppos = player:get_pos()
	if ppos then
		local nearby = core.get_objects_inside_radius(ppos, 32.0)
		for i = 1, #nearby do
			local o = nearby[i]
			if o and o:is_valid() and not o:is_player() then
				local le = o:get_luaentity()
				if is_player_bonded_pixie(le, pname) then
					bonding.untame_pixie(le)
					had_bonded = true
				end
			end
		end
	end

	-- Also untame any stray loaded entities belonging to this player across active blocks
	for _, ent in pairs(core.luaentities) do
		if is_player_bonded_pixie(ent, pname) then
			bonding.untame_pixie(ent)
			had_bonded = true
		end
	end

	-- Clear player metadata
	local saved = bonding.load_bonded_pixie(player)
	if saved and saved.owner_name then
		had_bonded = true
	end
	bonding.clear_bonded_pixie(player)

	if had_bonded and notify then
		core.chat_send_player(pname, core.colorize("#ffff88",
			S("You cut the magical bond loose. Your pixie companion returns freely to the wild!")))
	end

	return had_bonded
end

---Internal helper to spawn and hydrate a following companion entity at `spawn_pos`.
---@param player ObjectRef
---@param player_name string
---@param data table
---@param spawn_pos Vector
---@param trick_name string
---@param sparkles integer
---@param chime_pitch number
---@return table|nil ent
local function spawn_companion_entity(player, player_name, data, spawn_pos, trick_name, sparkles, chime_pitch)
	local tex_no = data.texture_no or 1
	local b_time = data.bond_time or 0
	local l_tier = data.loyalty_tier or bonding.get_loyalty_tier(b_time)
	local comp_id = data.companion_id or x_mob_core.generate_uuid()
	local cur_gen = data.recall_gen or 0

	local static_str = core.serialize({
		owner_name = player_name,
		mode = "follow",
		guard_pos = nil,
		bond_time = b_time,
		loyalty_tier = l_tier,
		texture_no = tex_no,
		hp = data.hp or 30,
		custom_name = data.custom_name,
		pixie_name = data.pixie_name,
		show_nametag = (data.show_nametag ~= false),
		persistent = true,
		recall_gen = cur_gen,
		companion_id = comp_id,
	})
	local obj, ent = x_mob_core.spawn_mob(spawn_pos, "pixie:pixie", static_str)
	if not obj or not obj:is_valid() then
		return nil
	end
	if ent then
		ent._persistent = true
		ent.texture_no = tex_no
		ent.owner_name = player_name
		ent.mode = "follow"
		ent.guard_pos = nil
		ent._recall_gen = cur_gen
		ent._companion_id = comp_id
		ent.bond_time = b_time
		ent.loyalty_tier = l_tier
		ent.custom_name = data.custom_name
		ent.pixie_name = data.pixie_name
		ent.show_nametag = (data.show_nametag ~= false)
		ent.hp = data.hp or 30
		ent:_update_properties()
		active_player_pixies[player_name] = ent
		bonding.save_bonded_pixie(player, ent)
	end
	pixie.spawn_tame_burst(spawn_pos)
	x_mob_core.play_sound(obj, "chime", {pos = spawn_pos, pitch = chime_pitch})
	pixie.play_trick(obj, trick_name, {speed = 1.2, sparkles = sparkles, force = true})
	return ent
end

---Restores a player's bonded companion if missing from world (e.g. after /clearobjects, restart, or join)
---@param player ObjectRef Connected player
---@return boolean restored True if an entity was respawned
function bonding.restore_companion(player)
	if not player or not player:is_player() or not player:is_valid() then return false end
	local player_name = player:get_player_name()
	if not player_name or player_name == "" then return false end

	local existing = active_player_pixies[player_name]
	if existing and existing.object and existing.object:is_valid() then
		return false
	end

	-- Fast check: if player has no bonded pixie saved in metadata, skip immediately
	-- without running expensive core.luaentities iterations
	local data = bonding.load_bonded_pixie(player)
	if not data or data.owner_name ~= player_name then return false end
	if data.mode ~= "follow" then
		-- Guarding companions persist directly in their mapblocks as static objects.
		-- Never spawn an extra entity for guarding companions on player join.
		return false
	end

	-- Check core.luaentities for any companion already loaded in world (follow OR stay)
	for _, ent in pairs(core.luaentities) do
		if is_player_bonded_pixie(ent, player_name) then
			if not existing then
				existing = ent
				active_player_pixies[player_name] = ent
			else
				bonding.prune_companion_entity(ent)
			end
		end
	end

	if existing and existing.object and existing.object:is_valid() then
		return false
	end

	local ppos = player:get_pos()
	if not ppos then return false end

	local spawn_pos = x_mob_core.avoid_solid_nodes({x = ppos.x, y = ppos.y + 1.2, z = ppos.z}, ppos)
	local trick_name = (math.random() < 0.5) and "spin_around" or "flip_front"
	local ent = spawn_companion_entity(player, player_name, data, spawn_pos, trick_name, 4, 1.2)
	return ent ~= nil
end

---Recalls a player's bonded companion from afar (or triggers an acrobatic trick if already following).
---@param player ObjectRef Connected player
---@param notify? boolean Whether to send chat notifications (default: true)
---@return boolean success
---@return string action "recalled" | "trick" | "no_pixie" | "error"
---@return table|nil ent PixieEntity instance
function bonding.recall_companion(player, notify)
	if not player or not player:is_player() or not player:is_valid() then
		return false, "error", nil
	end
	local player_name = player:get_player_name()
	if not player_name or player_name == "" then
		return false, "error", nil
	end

	local data = bonding.load_bonded_pixie(player)
	if not data or not data.owner_name then
		if notify ~= false then
			core.chat_send_player(player_name, core.colorize("#ffff88",
				S("The Fairy Whistle plays a clear, ethereal tune, but no companion answers.")))
		end
		return false, "no_pixie", nil
	end

	local ppos = player:get_pos()
	if not ppos then
		return false, "error", nil
	end

	local comp = get_companion_entity(player_name)
	local comp_name = data.custom_name or data.pixie_name or S("Mystical Pixie")

	-- If companion is actively following nearby (within 24m), whistle commands an acrobatic trick
	if data.mode == "follow" and comp and comp.object and comp.object:is_valid() then
		local cpos = comp.object:get_pos()
		if cpos and vector.distance(ppos, cpos) <= 24.0 then
			pixie.play_trick(comp.object, nil, {speed = 1.25, sparkles = 6, sound = true, force = true})
			if notify ~= false then
				core.chat_send_player(player_name, core.colorize("#ffff88",
					S("✦ You play a cheerful melody. @1 happily performs an aerial trick for you! ✦", comp_name)))
			end
			return true, "trick", comp
		end
	end

	-- Determine previous guard anchor if companion was stationed in guard mode
	local prev_guard_pos = (data.mode == "stay" and data.guard_pos)
		or (comp and comp.mode == "stay" and comp.guard_pos)
		or (comp and comp.mode == "stay" and comp.object and comp.object:is_valid() and vector.round(comp.object:get_pos()))

	-- Recall procedure: transition from guard ("stay") or lost follow state to following at player's side
	-- 1. Invalidate any in-memory active entity for this player
	if comp and comp.object and comp.object:is_valid() then
		local old_pos = comp.object:get_pos()
		bonding.prune_companion_entity(comp)
		if old_pos then
			pixie.spawn_sparkles(old_pos, 8)
		end
		active_player_pixies[player_name] = nil
	end

	-- Also mark & remove any duplicate entities in loaded memory
	for _, ent in pairs(core.luaentities) do
		if is_player_bonded_pixie(ent, player_name) then
			bonding.prune_companion_entity(ent)
		end
	end

	-- 2. Generate a fresh, globally unique companion instance UUID and advance generation token
	local new_gen = (data.recall_gen or 0) + 1
	local new_id = x_mob_core.generate_uuid()
	data.mode = "follow"
	data.guard_pos = nil
	data.recall_gen = new_gen
	data.companion_id = new_id
	player:get_meta():set_string("pixie:bonded", core.serialize(data))
	if mod_storage then
		mod_storage:set_string("pixie:" .. player_name .. ":companion_id", new_id)
		mod_storage:set_int("pixie:" .. player_name .. ":recall_gen", new_gen)
		mod_storage:set_string("pixie:" .. player_name .. ":mode", "follow")
	end

	-- 3. If previous guard position was in an unloaded chunk, schedule proactive asynchronous chunk purge
	if prev_guard_pos and core.emerge_area then
		core.emerge_area(prev_guard_pos, prev_guard_pos, function(_, action, calls_remaining)
			if calls_remaining == 0 and action ~= core.EMERGE_CANCELLED and action ~= core.EMERGE_ERRORED then
				local nearby = core.get_objects_inside_radius(prev_guard_pos, 16.0)
				for i = 1, #nearby do
					local o = nearby[i]
					if o and not o:is_player() and o:is_valid() then
						local le = o:get_luaentity()
						if is_player_bonded_pixie(le, player_name) and le._companion_id ~= new_id then
							bonding.prune_companion_entity(le)
						end
					end
				end
			end
		end)
	end

	-- 4. Spawn companion safely at player's side
	local spawn_pos = x_mob_core.avoid_solid_nodes({x = ppos.x, y = ppos.y + 1.2, z = ppos.z}, ppos)
	local ent = spawn_companion_entity(player, player_name, data, spawn_pos, "somersault", 6, 1.3)
	if ent then
		if notify ~= false then
			if prev_guard_pos and ppos then
				local dist = math.floor(vector.distance(ppos, prev_guard_pos) + 0.5)
				core.chat_send_player(player_name, core.colorize("#ffff88",
					S("✦ @1 heard the sweet call of your Fairy Whistle from (@2, @3, @4) (@5m away) and rushed to your side! ✦",
						comp_name, prev_guard_pos.x, prev_guard_pos.y, prev_guard_pos.z, dist)))
			else
				core.chat_send_player(player_name, core.colorize("#ffff88",
					S("✦ @1 heard the sweet call of your Fairy Whistle and rushed to your side! ✦", comp_name)))
			end
		end

		return true, "recalled", ent
	end

	return false, "error", nil
end

---Signals active combat state to a player's bonded pixie companion, triggering safe retreat.
---@param player_or_name ObjectRef|string Player ObjectRef or player name
---@param duration? number Combat stance duration in seconds (defaults to setting/8.0s)
---@param threat_pos? Vector Optional world position of the hostile threat
---@return boolean signaled True if an active companion was signaled
function bonding.signal_combat(player_or_name, duration, threat_pos)
	if not player_or_name then return false end
	local player_name = (type(player_or_name) == "string") and player_or_name
		or (player_or_name.is_player and player_or_name:is_player() and player_or_name:get_player_name())
	if not player_name or player_name == "" then return false end

	local comp = get_companion_entity(player_name)
	if not comp or not comp.object or not comp.object:is_valid() then return false end

	local dur = (duration and duration > 0) and duration or combat_retreat_duration
	local was_peaceful = not comp._combat_timer or comp._combat_timer <= 0
	comp._combat_timer = math.max(comp._combat_timer or 0, dur)

	if threat_pos then
		comp._combat_threat_pos = {x = threat_pos.x, y = threat_pos.y, z = threat_pos.z}
	end

	-- On entering combat mode freshly from peaceful state, play an evasive maneuver & warning chime
	if was_peaceful then
		local pos = comp.object:get_pos()
		if pos then
			x_mob_core.play_sound(comp, "alert", {pos = pos})
			pixie.spawn_sparkles(pos, 4, player_name)
		end
		local evasive_tricks = {"flip_back", "spin_around"}
		local chosen = evasive_tricks[math.random(1, #evasive_tricks)]
		pixie.play_trick(comp.object, chosen, {speed = 1.25, sparkles = 4, force = true})
	end

	return true
end

-- Guardian Angel: Sacrificial Last Stand
-- When a player suffers fatal damage, a Tier 3 (Ancient Guardian) bonded companion sacrifices itself
-- to save the player's life, restoring the player to +5 HP.
-- Strictly NO temporary speed boosts, jumps, or invulnerability frames.
core.register_on_player_hpchange(function(player, hp_change, reason)
	if not player or not player:is_player() or not player:is_valid() then
		return hp_change
	end

	if hp_change >= 0 then
		return hp_change
	end

	if reason and reason.type == "respawn" then
		return hp_change
	end

	local player_name = player:get_player_name()
	if not player_name or player_name == "" then
		return hp_change
	end

	local cur_hp = player:get_hp()
	if cur_hp + hp_change > 0 then
		-- Non-fatal hit: Signal combat retreat if damage source is combat-related
		local r_type = reason and reason.type
		if r_type and (r_type == "punch" or r_type == "mob") then
			local hpos = (reason.object and reason.object:is_valid()) and reason.object:get_pos() or nil
			bonding.signal_combat(player_name, nil, hpos)
		end
		return hp_change
	end

	local comp = get_companion_entity(player_name, 36.0)
	if not comp or not comp.object or not comp.object:is_valid() then
		return hp_change
	end

	local tier = comp.loyalty_tier or bonding.get_loyalty_tier(comp.bond_time or 0)
	if tier < 3 then
		return hp_change
	end

	local ppos = player:get_pos()
	local cpos = comp.object:get_pos()
	if not ppos or not cpos then
		return hp_change
	end

	local dist_sq = pixie.utils.dist_sq(ppos, cpos)
	if comp.mode == "stay" and dist_sq > 256.0 then
		return hp_change
	end
	if dist_sq > 1296.0 then
		return hp_change
	end

	-- Intercept lethal damage: restore player to exactly +5 HP
	local target_hp = 5
	local new_hp_change = target_hp - cur_hp

	-- Sacrificial Starlight Burst and Audio FX
	pixie.spawn_guardian_sacrifice(ppos, player_name)
	pixie.spawn_death(cpos)

	x_mob_core.play_sound(player, "chime", {
		pos = ppos,
		gain = 1.0,
		pitch = 1.5,
		distance = 32.0,
	})

	local comp_name = comp.custom_name or comp.pixie_name or S("Mystical Pixie")
	local tier_title = bonding.get_tier_title(tier)
	core.chat_send_player(player_name, core.colorize("#ffdd44",
		S("✦ Your @1 (@2) sacrificed its life to save you from death! ✦", tier_title, comp_name)))

	bonding.prune_companion_entity(comp)
	active_player_pixies[player_name] = nil
	bonding.clear_bonded_pixie(player)

	return new_hp_change, true
end, true)

-- Universal Player Combat Punch Hook:
-- Detects when ANY mob or entity strikes the player across any mob framework (Mobs Redo, Mineclonia, etc.)
core.register_on_punchplayer(function(player, hitter, _time_from_last_punch, _tool_capabilities, _dir, _damage)
	if not player or not player:is_player() or not player:is_valid() then return end
	local player_name = player:get_player_name()
	local hpos = (hitter and hitter:is_valid()) and hitter:get_pos() or nil
	bonding.signal_combat(player_name, nil, hpos)
end)

-- x_mob_core Pub-Sub Event Bus Listeners (Proactive combat attack detection)
do
	-- Proactive combat detection: x_mob_core mob acquires player target in close proximity
	x_mob_core.listen("on_mob_target", function(mob, target, _old_target)
		if target and target.is_player and target:is_player() and target:is_valid() then
			local player_name = target:get_player_name()
			local mpos = (mob and mob.object and mob.object:is_valid()) and mob.object:get_pos() or nil
			local ppos = target:get_pos()
			if mpos and ppos and pixie.utils.dist_sq(mpos, ppos) <= 144.0 then -- 12m proximity threshold
				bonding.signal_combat(player_name, nil, mpos)
			end
		end
	end)

	-- Combat strike detection: Player attacks mob
	x_mob_core.listen("on_mob_hurt", function(mob, puncher, _dmg)
		if puncher and puncher.is_player and puncher:is_player() and puncher:is_valid() then
			local player_name = puncher:get_player_name()
			local mpos = (mob and mob.object and mob.object:is_valid()) and mob.object:get_pos() or nil
			bonding.signal_combat(player_name, nil, mpos)
		end
	end)
end

-- Player Death Handler:
-- The bond between player and companion breaks upon actual player death.
-- Companions do not persist across death, encouraging players to explore and bond again.
core.register_on_dieplayer(function(player)
	if not player or not player:is_player() then return end
	local name = player:get_player_name()
	if not name or name == "" then return end

	local pixie_ent = active_player_pixies[name]
	if pixie_ent then
		pixie.dynamic_light.clear(pixie_ent)
		if pixie_ent.object and pixie_ent.object:is_valid() then
			local ppos = pixie_ent.object:get_pos()
			if ppos then
				pixie.spawn_death(ppos)
			end
			pixie_ent.object:remove()
		end
		active_player_pixies[name] = nil
	end

	-- Clear persistent metadata on death
	bonding.clear_bonded_pixie(player)
end)

-- Companion Lifecycle & Session Persistence
-- When an owner disconnects or server shuts down, an actively following companion stows safely
-- in the player's persistent metadata and is restored seamlessly when the owner reconnects.
core.register_on_leaveplayer(function(player)
	if not player or not player:is_player() then return end
	local player_name = player:get_player_name()
	if not player_name or player_name == "" then return end

	local pixie_ent = active_player_pixies[player_name]
	if pixie_ent then
		bonding.stow_bonded_pixie(player, pixie_ent, player_name)
	end

	if pixie.threat_cache and pixie.threat_cache.player_scans then
		pixie.threat_cache.player_scans[player_name] = nil
	end
end)

core.register_on_shutdown(function()
	local players = core.get_connected_players()
	for i = 1, #players do
		local player = players[i]
		if player and player:is_valid() then
			local player_name = player:get_player_name()
			local pixie_ent = active_player_pixies[player_name]
			if pixie_ent then
				bonding.stow_bonded_pixie(player, pixie_ent, player_name)
			end
		end
	end
end)

-- Restore bonded companion on player join
core.register_on_joinplayer(function(player)
	core.after(0.2, function()
		bonding.restore_companion(player)
	end)
end)

-- Periodic auto-reunion check: ensures companions return if wiped or missing while player is online
local bonded_check_timer = 0
core.register_globalstep(function(dtime)
	bonded_check_timer = bonded_check_timer + dtime
	if bonded_check_timer < 1.5 then return end
	bonded_check_timer = 0

	local players = core.get_connected_players()
	if #players == 0 then return end
	for i = 1, #players do
		bonding.restore_companion(players[i])
	end
end)


-- Chat command to manage companion bond
core.register_chatcommand("pixie", {
	params = "release | rename <name> | nametag [show|hide|toggle] | status",
	description = S("Manage your bonded pixie companion (status, release, rename, nametag)"),
	func = function(name, param)
		local player = core.get_player_by_name(name)
		if not player or not player:is_valid() then
			return false, S("Player not found.")
		end
		local raw_param = param and param:match("^%s*(.-)%s*$") or ""
		local lower_param = raw_param:lower()
		if lower_param == "release" or lower_param == "untame" or lower_param == "unbond" then
			local released = bonding.release_companion(player, true)
			if released then
				return true, S("Magical bond severed. Your pixie companion has returned to the wild.")
			else
				return false, S("You do not currently have a bonded pixie companion.")
			end
		elseif lower_param == "status" then
			local ent = get_companion_entity(name)
			local data = bonding.load_bonded_pixie(player)
			if (data and data.owner_name) or (ent and ent.owner_name == name) then
				local comp_name = (ent and (ent.custom_name or ent.pixie_name))
					or (data and (data.custom_name or data.pixie_name))
					or S("Mystical Pixie")
				local cur_mode = (ent and ent.mode) or (data and data.mode) or "follow"
				local cur_gpos = (ent and ent.guard_pos) or (data and data.guard_pos)
				if not cur_gpos and ent and ent.object and ent.object:is_valid() and cur_mode == "stay" then
					local epos = ent.object:get_pos()
					if epos then
						cur_gpos = vector.round(epos)
					end
				end
				local cur_hp = (ent and ent.hp) or (data and data.hp) or 30
				local tag_shown = (ent and ent.show_nametag ~= false) or (data and data.show_nametag ~= false)
				local tag_vis = tag_shown and S("Visible") or S("Hidden")
				local b_time = (ent and ent.bond_time) or (data and data.bond_time) or 0
				local ppos = player:get_pos()

				local mode_str
				if cur_mode == "stay" then
					if cur_gpos then
						local dist = ppos and math.floor(vector.distance(ppos, cur_gpos) + 0.5) or 0
						mode_str = S("Guarding at (@1, @2, @3) — @4m away", cur_gpos.x, cur_gpos.y, cur_gpos.z, dist)
					else
						mode_str = S("Guarding")
					end
				else
					mode_str = S("Following")
				end

				local tier = bonding.get_loyalty_tier(b_time)
				local tier_title = bonding.get_tier_title(tier)
				local bond_str = bonding.format_bond_time(b_time)

				return true, S("You are bonded with @1 (Tier: @2 | Bond: @3 | Status: @4 | HP: @5/30 | Nametag: @6).",
					comp_name, tier_title, bond_str, mode_str, tostring(cur_hp), tag_vis)
			else
				return true, S("You do not currently have a bonded pixie companion.")
			end
		elseif lower_param:sub(1, 7) == "nametag" then
			local arg = raw_param:sub(8):match("^%s*(.-)%s*$"):lower()
			local data = bonding.load_bonded_pixie(player)
			if not data or not data.owner_name then
				return false, S("You do not currently have a bonded pixie companion.")
			end

			local cur_vis = (data.show_nametag ~= false)
			local new_vis
			if arg == "hide" or arg == "off" or arg == "false" or arg == "0" then
				new_vis = false
			elseif arg == "show" or arg == "on" or arg == "true" or arg == "1" then
				new_vis = true
			elseif arg == "toggle" or arg == "" then
				new_vis = not cur_vis
			else
				return false, S("Usage: /pixie nametag [show|hide|toggle]")
			end

			data.show_nametag = new_vis
			player:get_meta():set_string("pixie:bonded", core.serialize(data))

			local ent = get_companion_entity(name)
			if ent and ent.object and ent.object:is_valid() then
				ent.show_nametag = new_vis
				ent:_update_properties()
			end

			local comp_name = data.custom_name or data.pixie_name or S("Mystical Pixie")
			if new_vis then
				return true, S("Nametag for @1 is now visible.", comp_name)
			else
				return true, S("Nametag for @1 is now completely hidden.", comp_name)
			end
		elseif lower_param:sub(1, 6) == "rename" then
			local new_name = raw_param:sub(7):match("^%s*(.-)%s*$") or ""
			local data = bonding.load_bonded_pixie(player)
			if not data or not data.owner_name then
				return false, S("You do not currently have a bonded pixie companion.")
			end

			if new_name == "" or new_name:lower() == "clear" or new_name:lower() == "none" or new_name:lower() == "reset" then
				data.custom_name = nil
				player:get_meta():set_string("pixie:bonded", core.serialize(data))

				local ent = get_companion_entity(name)
				if ent and ent.object and ent.object:is_valid() then
					ent.custom_name = nil
					ent:_update_properties()
				end
				return true, S("Custom name cleared. Pixie companion has returned to its default name.")
			end

			if #new_name < 1 or #new_name > 32 then
				return false, S("Please provide a valid name (1-32 characters).")
			end

			data.custom_name = new_name
			player:get_meta():set_string("pixie:bonded", core.serialize(data))

			-- Update active loaded entity
			local ent = get_companion_entity(name)
			if ent and ent.object and ent.object:is_valid() then
				ent.custom_name = new_name
				ent:_update_properties()
			end
			return true, S("Your pixie companion has been renamed to '@1'.", new_name)
		else
			return false, S("Usage: /pixie release, /pixie rename <name>, /pixie nametag [show|hide|toggle], or /pixie status")
		end
	end,
})

pixie.bonding = bonding
return bonding
