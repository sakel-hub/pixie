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
---@field ore_cache PixieOreCache
---@field bonding PixieBondingSubsystem
---@field threat_cache PixieThreatCache
---@field TRICK_DURATIONS table<string, number>
---@field TRICK_NAMES string[]
---@field spawn_sparkles fun(pos: Vector, count?: number, playername?: string)
---@field attach_ambient_sparkles fun(obj: ObjectRef, playername?: string): integer|nil
---@field spawn_heal fun(pos: Vector, count?: number, playername?: string)
---@field spawn_guidance_beacon fun(pos: Vector, dir: Vector, target_pos: Vector, playername?: string)
---@field spawn_death_guide fun(pos: Vector, dir: Vector, target_pos?: Vector, playername?: string)
---@field spawn_tame_burst fun(pos: Vector)
---@field spawn_death fun(pos: Vector)
---@field spawn_guardian_sacrifice fun(pos: Vector, playername?: string)
---@field spawn_whistle_melody fun(pos: Vector, playername?: string)
---@field play_trick fun(obj: ObjectRef, trick_name?: string, options?: PixieTrickOptions): boolean
---@field signal_combat fun(player_or_name: ObjectRef|string, duration?: number, threat_pos?: Vector): boolean
---@field storage? StorageRef Persistent per-mod key-value storage
local api = {}

-- Obtain mod storage reference during load time (when get_current_modname() is guaranteed)
local mod_storage = core.get_mod_storage()
api.storage = mod_storage

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
