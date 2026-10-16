--[[
	pixie - Public API & Core Interface
	Exported namespace and reusable API methods for the Mystical Pixie Companion.
]]

---@class PixieTrickOptions
---@field speed? number Animation playback speed multiplier (default 1.15)
---@field sparkles? number Number of fairy dust sparkles to emit (default 4)
---@field sound? string|boolean Sound name to play, or true for default pixie chime
---@field impulse? Vector Physical velocity impulse applied to entity
---@field force? boolean Force playback even if another animation is running (default true)

---@class PixieMod
---@field compat PixieCompat
---@field dynamic_light PixieLightSubsystem
---@field ore_sensor PixieOreSensor
---@field bonding PixieBondingSubsystem
---@field threat_cache PixieThreatCache
---@field config PixieConfig
---@field utils PixieUtils
---@field TRICK_DURATIONS table<string, number>
---@field TRICK_NAMES string[]
---@field spawn_sparkles fun(pos: Vector, count?: number, playername?: string)
---@field attach_ambient_sparkles fun(obj: ObjectRef, playername?: string): integer|nil
---@field spawn_heal fun(pos: Vector, count?: number, playername?: string)
---@field spawn_guidance_beacon fun(pos: Vector, dir: Vector, target_pos: Vector, playername?: string)
---@field spawn_tame_burst fun(pos: Vector)
---@field spawn_death fun(pos: Vector)
---@field spawn_guardian_sacrifice fun(pos: Vector, playername?: string)
---@field spawn_whistle_melody fun(pos: Vector, playername?: string)
---@field play_trick fun(obj: ObjectRef, trick_name?: string, options?: PixieTrickOptions): boolean
---@field trigger_celebration fun(ent: table): boolean
---@field signal_combat fun(player_or_name: ObjectRef|string, duration?: number, threat_pos?: Vector): boolean
---@field storage? StorageRef Persistent per-mod key-value storage
local api = {}

-- Obtain mod storage reference during load time (when get_current_modname() is guaranteed)
local mod_storage = core.get_mod_storage()
api.storage = mod_storage

---@class PixieConfig
---@field show_nametags boolean
---@field light_natural_threshold integer
---@field ore_max_y integer
---@field loyalty_tier2_time integer
---@field loyalty_tier3_time integer
---@field whistle_durability integer
---@field combat_retreat_duration number
---@field spawn_chance integer
---@field spawn_active_max integer
---@field spawn_min_elevation integer
---@field enable_drops boolean
api.config = {
	show_nametags = core.settings:get_bool("pixie_show_nametags", true),
	light_natural_threshold = tonumber(core.settings:get("pixie_light_natural_threshold")) or 12,
	ore_max_y = tonumber(core.settings:get("pixie_ore_max_y")) or 64,
	loyalty_tier2_time = tonumber(core.settings:get("pixie_loyalty_tier2_time")) or 1200,
	loyalty_tier3_time = tonumber(core.settings:get("pixie_loyalty_tier3_time")) or 3600,
	whistle_durability = tonumber(core.settings:get("pixie_whistle_durability")) or 30,
	combat_retreat_duration = tonumber(core.settings:get("pixie_combat_retreat_duration")) or 8.0,
	spawn_chance = tonumber(core.settings:get("pixie_spawn_chance")) or 4200,
	spawn_active_max = tonumber(core.settings:get("pixie_spawn_active_max")) or 2,
	spawn_min_elevation = tonumber(core.settings:get("pixie_spawn_min_elevation")) or 1,
	enable_drops = core.settings:get_bool("pixie_enable_drops", true),
}

---@class PixieUtils
api.utils = {
	dist_sq = function(a, b)
		local dx = a.x - b.x
		local dy = a.y - b.y
		local dz = a.z - b.z
		return dx * dx + dy * dy + dz * dz
	end,
	is_valid_obj = function(obj)
		return obj ~= nil and obj.is_valid and obj:is_valid()
	end,
	floor_vector = function(v)
		return {x = math.floor(v.x), y = math.floor(v.y), z = math.floor(v.z)}
	end,
}

---Calibrated duration locks in seconds for each trick animation
api.TRICK_DURATIONS = {
	flip_back      = 0.78,
	flip_front     = 0.78,
	flip_side      = 0.70,
	flip_side_left = 0.70,
	spin_around    = 0.78,
	somersault     = 0.88,
}

---Canonical array of all acrobatic trick animation names
api.TRICK_NAMES = {
	"flip_back",
	"flip_front",
	"flip_side",
	"flip_side_left",
	"spin_around",
	"somersault",
}

---Plays a playful trick animation on the pixie object with optional sound, impulse, and particles.
---@param obj ObjectRef The pixie ObjectRef
---@param trick_name? string Optional trick: "flip_back", "flip_front", "flip_side", "spin_around", etc.
---@param options? PixieTrickOptions Playback and effect parameters
---@return boolean success
function api.play_trick(obj, trick_name, options)
	if not obj or not obj:is_valid() then return false end
	local ent = obj:get_luaentity()
	if not ent or not ent.name or not ent.name:find("^pixie:") then return false end

	options = options or {}
	local chosen = trick_name
	if not chosen or not api.TRICK_DURATIONS[chosen] then
		chosen = api.TRICK_NAMES[math.random(1, #api.TRICK_NAMES)]
	end

	local base_lock = api.TRICK_DURATIONS[chosen] or 0.8
	local speed = options.speed or 1.15
	local lock_duration = base_lock / (speed / 1.15)

	x_mob_core.play_animation(obj, chosen, {speed = speed, loop = false, force = options.force ~= false})
	ent._anim_lock = lock_duration

	local pos = obj:get_pos()
	if pos then
		if options.impulse then
			local cur_vel = obj:get_velocity() or {x = 0, y = 0, z = 0}
			obj:set_velocity({
				x = cur_vel.x + options.impulse.x,
				y = cur_vel.y + options.impulse.y,
				z = cur_vel.z + options.impulse.z,
			})
		end

		local sparkle_count = options.sparkles ~= nil and options.sparkles or 4
		if sparkle_count > 0 then
			api.spawn_sparkles(pos, sparkle_count, ent.owner_name)
		end

		if options.sound then
			local sname = type(options.sound) == "string" and options.sound or "chime"
			local pitch = 1.25 + math.random() * 0.25
			x_mob_core.play_sound(ent, sname, {pos = pos, pitch = pitch})
		end
	end
	return true
end

---Triggers an ecstatic celebratory somersault or spin on a companion entity (e.g. when mining rare ores).
---@param ent table Pixie entity instance
---@return boolean success
function api.trigger_celebration(ent)
	if not ent or not ent.object or not ent.object:is_valid() then return false end
	local chosen = (math.random() < 0.65) and "somersault" or "spin_around"
	return api.play_trick(ent.object, chosen, {
		speed = 1.25,
		sparkles = 8,
		sound = true,
		force = true,
	})
end

---Recalls a player's bonded companion to follow them, or triggers an acrobatic trick if nearby.
---Delegates directly to bonding subsystem.
---@param player ObjectRef
---@param notify? boolean
---@return boolean success
---@return string action
---@return table|nil ent
function api.recall_companion(player, notify)
	return api.bonding.recall_companion(player, notify)
end

---Signals active combat state to a player's bonded pixie companion.
---Delegates directly to bonding subsystem.
---@param player_or_name ObjectRef|string Player ObjectRef or player name
---@param duration? number Combat stance duration in seconds (default 8.0)
---@param threat_pos? Vector Optional world position of the hostile threat
---@return boolean success True if companion received combat signal
function api.signal_combat(player_or_name, duration, threat_pos)
	return api.bonding.signal_combat(player_or_name, duration, threat_pos)
end

-- Global public namespace
pixie = api

return api
