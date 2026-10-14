--[[
	pixie - Particle Systems
	Starlight, Healing Hearts, Guidance Beacons, Taming Bursts, and Death Dissolve.
]]

---Builds a modern Luanti texpool array from compact frame definitions.
---@param blend string Blend mode ("screen" or "alpha")
---@param frames table[] Array of {col, row, s0, s1, a0, a1, a_start}
---@return table[]
local function build_texpool(blend, frames)
	local pool = {}
	for i = 1, #frames do
		local f = frames[i]
		pool[i] = {
			name = string.format("pixie_particles.png^[sheet:8x8:%d,%d", f[1], f[2]),
			blend = blend,
			scale_tween = {f[3], f[4]},
			alpha_tween = {f[5], f[6], start = f[7]},
		}
	end
	return pool
end

local PIXIE_SPARKLE_TEXPOOL = build_texpool("screen", {
	{1, 0, 1.2, 1.8, 0.80, 0.20, 0.5},
	{2, 0, 1.4, 2.2, 1.00, 0.30, 0.4},
	{3, 0, 1.0, 1.5, 0.90, 0.10, 0.6},
	{4, 0, 1.1, 1.7, 0.85, 0.25, 0.5},
	{5, 0, 0.9, 1.4, 0.75, 0.15, 0.7},
	{6, 0, 1.3, 2.0, 0.95, 0.35, 0.3},
})

local PIXIE_GLIMMER_TEXPOOL = build_texpool("screen", {
	{0, 1, 1.2, 2.0, 1.00, 0.00, 0.3},
	{1, 1, 1.5, 2.4, 1.00, 0.10, 0.4},
	{2, 1, 1.1, 1.8, 0.90, 0.00, 0.5},
	{3, 1, 1.3, 2.2, 0.95, 0.05, 0.3},
})

local PIXIE_HEART_TEXPOOL = build_texpool("alpha", {
	{0, 2, 1.0, 1.8, 1.00, 0.00, 0.4},
	{1, 2, 1.2, 2.2, 1.00, 0.10, 0.3},
	{2, 2, 1.4, 2.6, 1.00, 0.00, 0.5},
	{3, 2, 1.1, 2.0, 0.90, 0.00, 0.4},
})

local PIXIE_BURST_TEXPOOL = build_texpool("screen", {
	{1, 3, 1.5, 3.2, 1.00, 0.00, 0.2},
	{2, 3, 1.8, 3.6, 1.00, 0.00, 0.2},
	{2, 0, 1.2, 2.5, 0.90, 0.10, 0.4},
	{0, 3, 2.0, 4.0, 1.00, 0.00, 0.1},
})

local PIXIE_WING_TEXPOOL = build_texpool("screen", {
	{0, 6, 1.2, 0.4, 0.90, 0.00, 0.5},
	{1, 6, 1.4, 0.5, 1.00, 0.00, 0.4},
	{2, 6, 1.0, 0.3, 0.80, 0.00, 0.6},
	{3, 6, 1.3, 0.4, 0.90, 0.00, 0.5},
	{4, 6, 1.1, 0.3, 0.85, 0.00, 0.5},
})

local PIXIE_TAME_STAR_TEXPOOL = build_texpool("screen", {
	{2, 6, 1.5, 3.0, 1.00, 0.00, 0.3},
	{3, 6, 1.2, 2.5, 0.90, 0.00, 0.4},
	{1, 6, 1.8, 3.5, 1.00, 0.00, 0.2},
})

---Dispatches a particle spawner optionally scoped to a single player.
---@param spec table ParticleSpawner definition
---@param playername? string Optional player recipient
---@return integer|nil spawner_id
local function emit_spawner(spec, playername)
	if playername and playername ~= "" then
		spec.playername = playername
	end
	return core.add_particlespawner(spec)
end

---Spawns ambient fairy stardust and sparkling wing motes around a pixie.
---@param pos Vector Origin position
---@param count? number Particle count (default: 4)
---@param playername? string Optional recipient playername to conserve network bandwidth
function pixie.spawn_sparkles(pos, count, playername)
	emit_spawner({
		amount = count or 4,
		time = 0.15,
		pos = {
			min = {x = pos.x - 0.25, y = pos.y - 0.15, z = pos.z - 0.25},
			max = {x = pos.x + 0.25, y = pos.y + 0.35, z = pos.z + 0.25},
		},
		vel = {
			min = {x = -0.3, y = -0.1, z = -0.3},
			max = {x = 0.3, y = 0.4, z = 0.3},
		},
		acc = {min = {x = 0, y = 0.1, z = 0}, max = {x = 0, y = 0.3, z = 0}},
		drag = {min = {x = 0.5, y = 0.2, z = 0.5}, max = {x = 1.0, y = 0.5, z = 1.0}},
		jitter = {min = {x = -0.2, y = -0.2, z = -0.2}, max = {x = 0.2, y = 0.2, z = 0.2}},
		size = {min = 1.0, max = 2.2},
		exptime = {min = 0.8, max = 1.6},
		glow = 14,
		texpool = PIXIE_SPARKLE_TEXPOOL,
	}, playername)
end

---Attaches a persistent ambient stardust spawner directly to the pixie entity object.
---Eliminates per-step network packets and targets the spawner to the companion owner if specified.
---@param obj ObjectRef Pixie entity ObjectRef
---@param playername? string Optional companion owner playername
---@return integer|nil spawner_id Particle spawner identifier
function pixie.attach_ambient_sparkles(obj, playername)
	return emit_spawner({
		amount = 2.0,
		time = 0,
		attached = obj,
		pos = {
			min = {x = -0.25, y = -0.15, z = -0.25},
			max = {x = 0.25, y = 0.35, z = 0.25},
		},
		vel = {
			min = {x = -0.25, y = -0.1, z = -0.25},
			max = {x = 0.25, y = 0.3, z = 0.25},
		},
		acc = {min = {x = 0, y = 0.05, z = 0}, max = {x = 0, y = 0.2, z = 0}},
		drag = {min = {x = 0.5, y = 0.2, z = 0.5}, max = {x = 1.0, y = 0.5, z = 1.0}},
		jitter = {min = {x = -0.15, y = -0.15, z = -0.15}, max = {x = 0.15, y = 0.15, z = 0.15}},
		size = {min = 1.0, max = 2.0},
		exptime = {min = 0.8, max = 1.5},
		glow = 14,
		texpool = PIXIE_SPARKLE_TEXPOOL,
	}, playername)
end

---Spawns gentle healing starlight and floating heart motes toward a player.
---@param pos Vector Target player origin
---@param count? number Particle count (default: 12)
---@param playername? string Optional player recipient to reduce bandwidth
function pixie.spawn_heal(pos, count, playername)
	emit_spawner({
		amount = count or 12,
		time = 0.35,
		pos = {
			min = {x = pos.x - 0.35, y = pos.y + 0.2, z = pos.z - 0.35},
			max = {x = pos.x + 0.35, y = pos.y + 1.2, z = pos.z + 0.35},
		},
		vel = {
			min = {x = -0.4, y = 0.6, z = -0.4},
			max = {x = 0.4, y = 1.4, z = 0.4},
		},
		acc = {min = {x = 0, y = 0.2, z = 0}, max = {x = 0, y = 0.5, z = 0}},
		drag = {min = {x = 0.3, y = 0.1, z = 0.3}, max = {x = 0.6, y = 0.3, z = 0.6}},
		jitter = {min = {x = -0.15, y = -0.1, z = -0.15}, max = {x = 0.15, y = 0.1, z = 0.15}},
		size = {min = 1.8, max = 3.4},
		exptime = {min = 1.2, max = 2.0},
		glow = 14,
		texpool = PIXIE_HEART_TEXPOOL,
	}, playername)
end

---Spawns a guidance starlight beam pointing toward an ore deposit or point of interest.
---@param pos Vector Origin position (e.g. pixie world coordinate)
---@param dir Vector Direction unit vector towards target
---@param target_pos Vector Target point of interest
---@param playername? string Optional player recipient to reduce bandwidth
function pixie.spawn_guidance_beacon(pos, dir, target_pos, playername)
	emit_spawner({
		amount = 12,
		time = 0.4,
		pos = {
			min = {x = pos.x - 0.1, y = pos.y - 0.1, z = pos.z - 0.1},
			max = {x = pos.x + 0.1, y = pos.y + 0.1, z = pos.z + 0.1},
		},
		vel = {
			min = {x = dir.x * 3.5 - 0.2, y = dir.y * 3.5 - 0.2, z = dir.z * 3.5 - 0.2},
			max = {x = dir.x * 5.0 + 0.2, y = dir.y * 5.0 + 0.2, z = dir.z * 5.0 + 0.2},
		},
		acc = {min = {x = 0, y = 0.05, z = 0}, max = {x = 0, y = 0.15, z = 0}},
		drag = {min = {x = 0.2, y = 0.2, z = 0.2}, max = {x = 0.5, y = 0.5, z = 0.5}},
		size = {min = 1.4, max = 2.8},
		exptime = {min = 0.8, max = 1.4},
		glow = 14,
		texpool = PIXIE_GLIMMER_TEXPOOL,
	}, playername)

	-- Highlight target position
	emit_spawner({
		amount = 14,
		time = 0.5,
		pos = {
			min = {x = target_pos.x - 0.4, y = target_pos.y - 0.4, z = target_pos.z - 0.4},
			max = {x = target_pos.x + 0.4, y = target_pos.y + 0.4, z = target_pos.z + 0.4},
		},
		vel = {min = {x = -0.3, y = -0.2, z = -0.3}, max = {x = 0.3, y = 0.5, z = 0.3}},
		acc = {min = {x = 0, y = 0.1, z = 0}, max = {x = 0, y = 0.2, z = 0}},
		drag = {min = {x = 0.4, y = 0.3, z = 0.4}, max = {x = 0.8, y = 0.6, z = 0.8}},
		size = {min = 1.6, max = 3.0},
		exptime = {min = 1.0, max = 1.8},
		glow = 14,
		texpool = PIXIE_BURST_TEXPOOL,
	}, playername)
end

---Spawns brilliant taming heart and fairy firework burst upon bonding.
---@param pos Vector Origin position
function pixie.spawn_tame_burst(pos)
	emit_spawner({
		amount = 28,
		time = 0.25,
		pos = {
			min = {x = pos.x - 0.3, y = pos.y, z = pos.z - 0.3},
			max = {x = pos.x + 0.3, y = pos.y + 0.6, z = pos.z + 0.3},
		},
		vel = {
			min = {x = -2.2, y = 0.5, z = -2.2},
			max = {x = 2.2, y = 3.2, z = 2.2},
		},
		acc = {min = {x = 0, y = -1.5, z = 0}, max = {x = 0, y = -0.5, z = 0}},
		drag = {min = {x = 0.6, y = 0.4, z = 0.6}, max = {x = 1.2, y = 0.8, z = 1.2}},
		bounce = {min = 0.2, max = 0.5},
		size = {min = 2.2, max = 4.5},
		exptime = {min = 1.4, max = 2.5},
		glow = 14,
		texpool = PIXIE_TAME_STAR_TEXPOOL,
	})
end

---Spawns serene dissolve particles upon pixie death.
---@param pos Vector Origin position
function pixie.spawn_death(pos)
	emit_spawner({
		amount = 24,
		time = 0.35,
		pos = {
			min = {x = pos.x - 0.3, y = pos.y + 0.1, z = pos.z - 0.3},
			max = {x = pos.x + 0.3, y = pos.y + 0.6, z = pos.z + 0.3},
		},
		vel = {
			min = {x = -1.2, y = 0.2, z = -1.2},
			max = {x = 1.2, y = 1.8, z = 1.2},
		},
		acc = {min = {x = 0, y = 0.1, z = 0}, max = {x = 0, y = 0.3, z = 0}},
		drag = {min = {x = 0.5, y = 0.2, z = 0.5}, max = {x = 1.0, y = 0.5, z = 1.0}},
		size = {min = 1.5, max = 3.0},
		exptime = {min = 1.2, max = 2.2},
		glow = 12,
		texpool = PIXIE_WING_TEXPOOL,
	})
end

---Spawns a radiant celestial burst when a pixie sacrifices itself to save its bonded owner.
---@param pos Vector Player position
---@param playername? string Optional player recipient
function pixie.spawn_guardian_sacrifice(pos, playername)
	emit_spawner({
		amount = 45,
		time = 0.4,
		pos = {
			min = {x = pos.x - 0.4, y = pos.y + 0.2, z = pos.z - 0.4},
			max = {x = pos.x + 0.4, y = pos.y + 1.6, z = pos.z + 0.4},
		},
		vel = {
			min = {x = -3.5, y = 0.5, z = -3.5},
			max = {x = 3.5, y = 4.5, z = 3.5},
		},
		acc = {min = {x = 0, y = -1.2, z = 0}, max = {x = 0, y = -0.4, z = 0}},
		drag = {min = {x = 0.8, y = 0.5, z = 0.8}, max = {x = 1.4, y = 0.9, z = 1.4}},
		bounce = {min = 0.3, max = 0.6},
		size = {min = 2.8, max = 5.5},
		exptime = {min = 1.6, max = 3.0},
		glow = 14,
		texpool = PIXIE_TAME_STAR_TEXPOOL,
	}, playername)

	emit_spawner({
		amount = 18,
		time = 0.5,
		pos = {
			min = {x = pos.x - 0.3, y = pos.y + 0.8, z = pos.z - 0.3},
			max = {x = pos.x + 0.3, y = pos.y + 1.4, z = pos.z + 0.3},
		},
		vel = {
			min = {x = -0.8, y = 1.2, z = -0.8},
			max = {x = 0.8, y = 2.8, z = 0.8},
		},
		acc = {min = {x = 0, y = 0.2, z = 0}, max = {x = 0, y = 0.6, z = 0}},
		drag = {min = {x = 0.3, y = 0.2, z = 0.3}, max = {x = 0.6, y = 0.4, z = 0.6}},
		size = {min = 2.4, max = 4.6},
		exptime = {min = 1.8, max = 2.8},
		glow = 14,
		texpool = PIXIE_HEART_TEXPOOL,
	}, playername)
end

---Spawns gentle musical starlight swirls when the fairy whistle is blown.
---@param pos Vector Player or whistle origin
---@param playername? string Optional player recipient to reduce bandwidth
function pixie.spawn_whistle_melody(pos, playername)
	emit_spawner({
		amount = 16,
		time = 0.35,
		pos = {
			min = {x = pos.x - 0.45, y = pos.y + 0.6, z = pos.z - 0.45},
			max = {x = pos.x + 0.45, y = pos.y + 1.5, z = pos.z + 0.45},
		},
		vel = {
			min = {x = -0.5, y = 0.4, z = -0.5},
			max = {x = 0.5, y = 1.2, z = 0.5},
		},
		acc = {min = {x = 0, y = 0.15, z = 0}, max = {x = 0, y = 0.4, z = 0}},
		drag = {min = {x = 0.3, y = 0.1, z = 0.3}, max = {x = 0.6, y = 0.3, z = 0.6}},
		jitter = {min = {x = -0.2, y = -0.1, z = -0.2}, max = {x = 0.2, y = 0.1, z = 0.2}},
		size = {min = 1.4, max = 2.6},
		exptime = {min = 0.8, max = 1.6},
		glow = 14,
		texpool = PIXIE_GLIMMER_TEXPOOL,
	}, playername)
end
