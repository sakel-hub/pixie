--[[
	pixie - Particle Systems
	Starlight, Healing Hearts, Guidance Beacons, Taming Bursts, and Death Dissolve.
]]

local PIXIE_SPARKLE_TEXPOOL = {
	{
		name = "pixie_particles.png^[sheet:8x8:1,0",
		blend = "screen",
		scale_tween = {1.2, 1.8},
		alpha_tween = {0.8, 0.2, start = 0.5},
	},
	{
		name = "pixie_particles.png^[sheet:8x8:2,0",
		blend = "screen",
		scale_tween = {1.4, 2.2},
		alpha_tween = {1.0, 0.3, start = 0.4},
	},
	{
		name = "pixie_particles.png^[sheet:8x8:3,0",
		blend = "screen",
		scale_tween = {1.0, 1.5},
		alpha_tween = {0.9, 0.1, start = 0.6},
	},
	{
		name = "pixie_particles.png^[sheet:8x8:4,0",
		blend = "screen",
		scale_tween = {1.1, 1.7},
		alpha_tween = {0.85, 0.25, start = 0.5},
	},
	{
		name = "pixie_particles.png^[sheet:8x8:5,0",
		blend = "screen",
		scale_tween = {0.9, 1.4},
		alpha_tween = {0.75, 0.15, start = 0.7},
	},
	{
		name = "pixie_particles.png^[sheet:8x8:6,0",
		blend = "screen",
		scale_tween = {1.3, 2.0},
		alpha_tween = {0.95, 0.35, start = 0.3},
	},
}

local PIXIE_GLIMMER_TEXPOOL = {
	{
		name = "pixie_particles.png^[sheet:8x8:0,1",
		blend = "screen",
		scale_tween = {1.2, 2.0},
		alpha_tween = {1.0, 0.0, start = 0.3},
	},
	{
		name = "pixie_particles.png^[sheet:8x8:1,1",
		blend = "screen",
		scale_tween = {1.5, 2.4},
		alpha_tween = {1.0, 0.1, start = 0.4},
	},
	{
		name = "pixie_particles.png^[sheet:8x8:2,1",
		blend = "screen",
		scale_tween = {1.1, 1.8},
		alpha_tween = {0.9, 0.0, start = 0.5},
	},
	{
		name = "pixie_particles.png^[sheet:8x8:3,1",
		blend = "screen",
		scale_tween = {1.3, 2.2},
		alpha_tween = {0.95, 0.05, start = 0.3},
	},
}

local PIXIE_HEART_TEXPOOL = {
	{
		name = "pixie_particles.png^[sheet:8x8:0,2",
		blend = "alpha",
		scale_tween = {1.0, 1.8},
		alpha_tween = {1.0, 0.0, start = 0.4},
	},
	{
		name = "pixie_particles.png^[sheet:8x8:1,2",
		blend = "alpha",
		scale_tween = {1.2, 2.2},
		alpha_tween = {1.0, 0.1, start = 0.3},
	},
	{
		name = "pixie_particles.png^[sheet:8x8:2,2",
		blend = "alpha",
		scale_tween = {1.4, 2.6},
		alpha_tween = {1.0, 0.0, start = 0.5},
	},
	{
		name = "pixie_particles.png^[sheet:8x8:3,2",
		blend = "alpha",
		scale_tween = {1.1, 2.0},
		alpha_tween = {0.9, 0.0, start = 0.4},
	},
}

local PIXIE_BURST_TEXPOOL = {
	{
		name = "pixie_particles.png^[sheet:8x8:1,3",
		blend = "screen",
		scale_tween = {1.5, 3.2},
		alpha_tween = {1.0, 0.0, start = 0.2},
	},
	{
		name = "pixie_particles.png^[sheet:8x8:2,3",
		blend = "screen",
		scale_tween = {1.8, 3.6},
		alpha_tween = {1.0, 0.0, start = 0.2},
	},
	{
		name = "pixie_particles.png^[sheet:8x8:2,0",
		blend = "screen",
		scale_tween = {1.2, 2.5},
		alpha_tween = {0.9, 0.1, start = 0.4},
	},
	{
		name = "pixie_particles.png^[sheet:8x8:0,3",
		blend = "screen",
		scale_tween = {2.0, 4.0},
		alpha_tween = {1.0, 0.0, start = 0.1},
	},
}

local PIXIE_WING_TEXPOOL = {
	{
		name = "pixie_particles.png^[sheet:8x8:0,6",
		blend = "screen",
		scale_tween = {1.2, 0.4},
		alpha_tween = {0.9, 0.0, start = 0.5},
	},
	{
		name = "pixie_particles.png^[sheet:8x8:1,6",
		blend = "screen",
		scale_tween = {1.4, 0.5},
		alpha_tween = {1.0, 0.0, start = 0.4},
	},
	{
		name = "pixie_particles.png^[sheet:8x8:2,6",
		blend = "screen",
		scale_tween = {1.0, 0.3},
		alpha_tween = {0.8, 0.0, start = 0.6},
	},
	{
		name = "pixie_particles.png^[sheet:8x8:3,6",
		blend = "screen",
		scale_tween = {1.3, 0.4},
		alpha_tween = {0.9, 0.0, start = 0.5},
	},
	{
		name = "pixie_particles.png^[sheet:8x8:4,6",
		blend = "screen",
		scale_tween = {1.1, 0.3},
		alpha_tween = {0.85, 0.0, start = 0.5},
	},
}

local PIXIE_TAME_STAR_TEXPOOL = {
	{
		name = "pixie_particles.png^[sheet:8x8:2,6",
		blend = "screen",
		scale_tween = {1.5, 3.0},
		alpha_tween = {1.0, 0.0, start = 0.3},
	},
	{
		name = "pixie_particles.png^[sheet:8x8:3,6",
		blend = "screen",
		scale_tween = {1.2, 2.5},
		alpha_tween = {0.9, 0.0, start = 0.4},
	},
	{
		name = "pixie_particles.png^[sheet:8x8:1,6",
		blend = "screen",
		scale_tween = {1.8, 3.5},
		alpha_tween = {1.0, 0.0, start = 0.2},
	},
}

---Spawns ambient fairy stardust and sparkling wing motes around a pixie.
---@param pos Vector Origin position
---@param count? number Particle count (default: 4)
---@param playername? string Optional recipient playername to conserve network bandwidth
function pixie.spawn_sparkles(pos, count, playername)
	local p_spec = {
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

		minpos = {x = pos.x - 0.25, y = pos.y - 0.15, z = pos.z - 0.25},
		maxpos = {x = pos.x + 0.25, y = pos.y + 0.35, z = pos.z + 0.25},
		minvel = {x = -0.3, y = -0.1, z = -0.3},
		maxvel = {x = 0.3, y = 0.4, z = 0.3},
		minacc = {x = 0, y = 0.1, z = 0},
		maxacc = {x = 0, y = 0.3, z = 0},
		minexptime = 0.8,
		maxexptime = 1.6,
		minsize = 1.0,
		maxsize = 2.2,
		texture = "pixie_particles.png^[sheet:8x8:2,0",
	}
	if playername and playername ~= "" then
		p_spec.playername = playername
	end
	core.add_particlespawner(p_spec)
end

---Attaches a persistent ambient stardust spawner directly to the pixie entity object.
---Eliminates per-step network packets and targets the spawner to the companion owner if specified.
---@param obj ObjectRef Pixie entity ObjectRef
---@param playername? string Optional companion owner playername
---@return integer|nil spawner_id Particle spawner identifier
function pixie.attach_ambient_sparkles(obj, playername)
	local p_spec = {
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

		minpos = {x = -0.25, y = -0.15, z = -0.25},
		maxpos = {x = 0.25, y = 0.35, z = 0.25},
		minvel = {x = -0.25, y = -0.1, z = -0.25},
		maxvel = {x = 0.25, y = 0.3, z = 0.25},
		minacc = {x = 0, y = 0.05, z = 0},
		maxacc = {x = 0, y = 0.2, z = 0},
		minexptime = 0.8,
		maxexptime = 1.5,
		minsize = 1.0,
		maxsize = 2.0,
		texture = "pixie_particles.png^[sheet:8x8:2,0",
	}
	if playername and playername ~= "" then
		p_spec.playername = playername
	end
	return core.add_particlespawner(p_spec)
end

---Spawns gentle healing starlight and floating heart motes toward a player.
---@param pos Vector Target player origin
---@param count? number Particle count (default: 12)
---@param playername? string Optional player recipient to reduce bandwidth
function pixie.spawn_heal(pos, count, playername)
	local p_spec = {
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

		minpos = {x = pos.x - 0.35, y = pos.y + 0.2, z = pos.z - 0.35},
		maxpos = {x = pos.x + 0.35, y = pos.y + 1.2, z = pos.z + 0.35},
		minvel = {x = -0.4, y = 0.6, z = -0.4},
		maxvel = {x = 0.4, y = 1.4, z = 0.4},
		minacc = {x = 0, y = 0.2, z = 0},
		maxacc = {x = 0, y = 0.5, z = 0},
		minexptime = 1.2,
		maxexptime = 2.0,
		minsize = 1.8,
		maxsize = 3.4,
		texture = "pixie_particles.png^[sheet:8x8:1,2",
	}
	if playername then p_spec.playername = playername end
	core.add_particlespawner(p_spec)
end

---Spawns a guidance starlight beam pointing toward an ore deposit or point of interest.
---@param pos Vector Origin position (e.g. pixie world coordinate)
---@param dir Vector Direction unit vector towards target
---@param target_pos Vector Target point of interest
---@param playername? string Optional player recipient to reduce bandwidth
function pixie.spawn_guidance_beacon(pos, dir, target_pos, playername)
	local beam_spec = {
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

		minpos = {x = pos.x - 0.1, y = pos.y - 0.1, z = pos.z - 0.1},
		maxpos = {x = pos.x + 0.1, y = pos.y + 0.1, z = pos.z + 0.1},
		minvel = {x = dir.x * 3.5 - 0.2, y = dir.y * 3.5 - 0.2, z = dir.z * 3.5 - 0.2},
		maxvel = {x = dir.x * 5.0 + 0.2, y = dir.y * 5.0 + 0.2, z = dir.z * 5.0 + 0.2},
		minacc = {x = 0, y = 0.05, z = 0},
		maxacc = {x = 0, y = 0.15, z = 0},
		minexptime = 0.8,
		maxexptime = 1.4,
		minsize = 1.4,
		maxsize = 2.8,
		texture = "pixie_particles.png^[sheet:8x8:2,0",
	}
	if playername then beam_spec.playername = playername end
	core.add_particlespawner(beam_spec)

	-- Highlight target position
	local mark_spec = {
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

		minpos = {x = target_pos.x - 0.4, y = target_pos.y - 0.4, z = target_pos.z - 0.4},
		maxpos = {x = target_pos.x + 0.4, y = target_pos.y + 0.4, z = target_pos.z + 0.4},
		minvel = {x = -0.3, y = -0.2, z = -0.3},
		maxvel = {x = 0.3, y = 0.5, z = 0.3},
		minacc = {x = 0, y = 0.1, z = 0},
		maxacc = {x = 0, y = 0.2, z = 0},
		minexptime = 1.0,
		maxexptime = 1.8,
		minsize = 1.6,
		maxsize = 3.0,
		texture = "pixie_particles.png^[sheet:8x8:2,0",
	}
	if playername then mark_spec.playername = playername end
	core.add_particlespawner(mark_spec)
end

---Spawns clean directional particles guiding player back towards grave/death coordinates.
---@param pos Vector Origin position (e.g. pixie world coordinate)
---@param dir Vector Direction unit vector towards grave
---@param target_pos Vector Grave world coordinate
---@param playername? string Optional player recipient
function pixie.spawn_death_guide(pos, dir, _target_pos, playername)
	local guide_spec = {
		amount = 14,
		time = 0.4,
		pos = {
			min = {x = pos.x - 0.15, y = pos.y - 0.15, z = pos.z - 0.15},
			max = {x = pos.x + 0.15, y = pos.y + 0.15, z = pos.z + 0.15},
		},
		vel = {
			min = {x = dir.x * 2.8 - 0.25, y = dir.y * 2.8 - 0.2, z = dir.z * 2.8 - 0.25},
			max = {x = dir.x * 4.2 + 0.25, y = dir.y * 4.2 + 0.2, z = dir.z * 4.2 + 0.25},
		},
		acc = {min = {x = 0, y = 0.05, z = 0}, max = {x = 0, y = 0.15, z = 0}},
		drag = {min = {x = 0.2, y = 0.2, z = 0.2}, max = {x = 0.4, y = 0.4, z = 0.4}},
		size = {min = 2.4, max = 4.2},
		exptime = {min = 1.2, max = 2.0},
		glow = 14,
		texpool = PIXIE_TAME_STAR_TEXPOOL,

		minpos = {x = pos.x - 0.15, y = pos.y - 0.15, z = pos.z - 0.15},
		maxpos = {x = pos.x + 0.15, y = pos.y + 0.15, z = pos.z + 0.15},
		minvel = {x = dir.x * 2.8 - 0.25, y = dir.y * 2.8 - 0.2, z = dir.z * 2.8 - 0.25},
		maxvel = {x = dir.x * 4.2 + 0.25, y = dir.y * 4.2 + 0.2, z = dir.z * 4.2 + 0.25},
		minacc = {x = 0, y = 0.05, z = 0},
		maxacc = {x = 0, y = 0.15, z = 0},
		minexptime = 1.2,
		maxexptime = 2.0,
		minsize = 2.4,
		maxsize = 4.2,
		texture = "pixie_particles.png^[sheet:8x8:2,6",
	}
	if playername then guide_spec.playername = playername end
	core.add_particlespawner(guide_spec)
end

---Spawns brilliant taming heart and fairy firework burst upon bonding.
---@param pos Vector Origin position
function pixie.spawn_tame_burst(pos)
	core.add_particlespawner({
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

		minpos = {x = pos.x - 0.3, y = pos.y, z = pos.z - 0.3},
		maxpos = {x = pos.x + 0.3, y = pos.y + 0.6, z = pos.z + 0.3},
		minvel = {x = -2.2, y = 0.5, z = -2.2},
		maxvel = {x = 2.2, y = 3.2, z = 2.2},
		minacc = {x = 0, y = -1.5, z = 0},
		maxacc = {x = 0, y = -0.5, z = 0},
		minexptime = 1.4,
		maxexptime = 2.5,
		minsize = 2.2,
		maxsize = 4.5,
		texture = "pixie_particles.png^[sheet:8x8:2,6",
	})
end

---Spawns serene dissolve particles upon pixie death.
---@param pos Vector Origin position
function pixie.spawn_death(pos)
	core.add_particlespawner({
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

		minpos = {x = pos.x - 0.3, y = pos.y + 0.1, z = pos.z - 0.3},
		maxpos = {x = pos.x + 0.3, y = pos.y + 0.6, z = pos.z + 0.3},
		minvel = {x = -1.2, y = 0.2, z = -1.2},
		maxvel = {x = 1.2, y = 1.8, z = 1.2},
		minacc = {x = 0, y = 0.1, z = 0},
		maxacc = {x = 0, y = 0.3, z = 0},
		minexptime = 1.2,
		maxexptime = 2.2,
		minsize = 1.5,
		maxsize = 3.0,
		texture = "pixie_particles.png^[sheet:8x8:0,1",
	})
end

---Spawns a radiant celestial burst when a pixie sacrifices itself to save its bonded owner.
---@param pos Vector Player position
---@param playername? string Optional player recipient
function pixie.spawn_guardian_sacrifice(pos, playername)
	local star_spec = {
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

		minpos = {x = pos.x - 0.4, y = pos.y + 0.2, z = pos.z - 0.4},
		maxpos = {x = pos.x + 0.4, y = pos.y + 1.6, z = pos.z + 0.4},
		minvel = {x = -3.5, y = 0.5, z = -3.5},
		maxvel = {x = 3.5, y = 4.5, z = 3.5},
		minacc = {x = 0, y = -1.2, z = 0},
		maxacc = {x = 0, y = -0.4, z = 0},
		minexptime = 1.6,
		maxexptime = 3.0,
		minsize = 2.8,
		maxsize = 5.5,
		texture = "pixie_particles.png^[sheet:8x8:2,6",
	}
	if playername then star_spec.playername = playername end
	core.add_particlespawner(star_spec)

	local heart_spec = {
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

		minpos = {x = pos.x - 0.3, y = pos.y + 0.8, z = pos.z - 0.3},
		maxpos = {x = pos.x + 0.3, y = pos.y + 1.4, z = pos.z + 0.3},
		minvel = {x = -0.8, y = 1.2, z = -0.8},
		maxvel = {x = 0.8, y = 2.8, z = 0.8},
		minacc = {x = 0, y = 0.2, z = 0},
		maxacc = {x = 0, y = 0.6, z = 0},
		minexptime = 1.8,
		maxexptime = 2.8,
		minsize = 2.4,
		maxsize = 4.6,
		texture = "pixie_particles.png^[sheet:8x8:0,2",
	}
	if playername then heart_spec.playername = playername end
	core.add_particlespawner(heart_spec)
end

---Spawns gentle musical starlight swirls when the fairy whistle is blown.
---@param pos Vector Player or whistle origin
---@param playername? string Optional player recipient to reduce bandwidth
function pixie.spawn_whistle_melody(pos, playername)
	local melody_spec = {
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

		minpos = {x = pos.x - 0.45, y = pos.y + 0.6, z = pos.z - 0.45},
		maxpos = {x = pos.x + 0.45, y = pos.y + 1.5, z = pos.z + 0.45},
		minvel = {x = -0.5, y = 0.4, z = -0.5},
		maxvel = {x = 0.5, y = 1.2, z = 0.5},
		minacc = {x = 0, y = 0.15, z = 0},
		maxacc = {x = 0, y = 0.4, z = 0},
		minexptime = 0.8,
		maxexptime = 1.6,
		minsize = 1.4,
		maxsize = 2.6,
		texture = "pixie_particles.png^[sheet:8x8:1,1",
	}
	if playername and playername ~= "" then
		melody_spec.playername = playername
	end
	core.add_particlespawner(melody_spec)
end
