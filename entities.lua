--[[
	pixie - Entity Definition & AI Steering
	Enchanted glowing fairy companion with dynamic lighting, ore detection,
	hostile threat radar, and triage healing.
]]

local S = core.get_translator("pixie")
local mod_storage = pixie.storage

local avoid_solid_nodes = x_mob_core.avoid_solid_nodes
local get_headroom = x_mob_core.get_headroom
local get_ground_y = x_mob_core.get_ground_y
local is_walkable_node = x_mob_core.utils.is_walkable_node
local is_passable_node = x_mob_core.utils.is_passable_node
local atan2 = math.atan2 or math.atan

---If entity is in or immediately touching liquid, scans upward to find the liquid surface elevation.
---@param pos Vector Entity position
---@return number|nil surface_y Top elevation of liquid column, or nil
local function get_water_surface_y(pos)
	local nx = math.floor(pos.x + 0.5)
	local ny = math.floor(pos.y + 0.5)
	local nz = math.floor(pos.z + 0.5)
	local start_y = ny
	local n0 = core.get_node_or_nil({x = nx, y = start_y, z = nz})
	local d0 = n0 and core.registered_nodes[n0.name]
	if not (d0 and d0.liquidtype and d0.liquidtype ~= "none") then
		start_y = ny - 1
		local n_under = core.get_node_or_nil({x = nx, y = start_y, z = nz})
		local d_under = n_under and core.registered_nodes[n_under.name]
		if not (d_under and d_under.liquidtype and d_under.liquidtype ~= "none") then
			return nil
		end
	end

	for cy = start_y, start_y + 16 do
		local node = core.get_node_or_nil({x = nx, y = cy, z = nz})
		if not node then break end
		local def = core.registered_nodes[node.name]
		if not def or not (def.liquidtype and def.liquidtype ~= "none") then
			return cy - 0.5
		end
	end
	return nil
end

---Shared threat radar cache across companion pixies to eliminate redundant spatial queries in multiplayer
---@class PixieThreatCache
pixie.threat_cache = {
	recent_alerts = {},
	player_scans = {},
}

local pixie_phenotypes = {
	{ name = "Starlight", tex = "pixie.png" },
	{ name = "Sunbeam",   tex = "pixie.png^[hsl:38:35:15" },
	{ name = "Arcane",    tex = "pixie.png^[hsl:275:30:12" },
	{ name = "Verdant",   tex = "pixie.png^[hsl:122:25:8" },
	{ name = "Glacial",   tex = "pixie.png^[hsl:195:35:20" },
	{ name = "Ember",     tex = "pixie.png^[hsl:8:45:15" },
	{ name = "Astral",    tex = "pixie.png^[hsl:225:-40:30" },
	{ name = "Mese",      tex = "pixie.png^[hsl:56:50:22" },
}

local pixie_textures = {}
for i = 1, #pixie_phenotypes do
	pixie_textures[i] = { pixie_phenotypes[i].tex }
end

---Checks whether an item is a valid taming offering or food
---@param item_name string Item technical name
---@return boolean
local function is_taming_food(item_name)
	if not item_name or item_name == "" then return false end
	if item_name == "farming:honey" or item_name == "default:mese_crystal_fragment" then
		return true
	end
	return pixie.compat.is_flora(item_name)
end

-- Pre-allocated neighbor offsets for de-penetration safeguard
local NEIGHBOR_OFFSETS_26 = {}
for dx = -1, 1 do
	for dy = -1, 1 do
		for dz = -1, 1 do
			if not (dx == 0 and dy == 0 and dz == 0) then
				NEIGHBOR_OFFSETS_26[#NEIGHBOR_OFFSETS_26 + 1] = {x = dx, y = dy, z = dz}
			end
		end
	end
end

local avoid_round = {x = 0, y = 0, z = 0}

-- Pre-allocated probe vectors for tight-space and shoulder clearance checks
local probe_tight_l = {x = 0, y = 0, z = 0}
local probe_tight_r = {x = 0, y = 0, z = 0}
local probe_tight_f = {x = 0, y = 0, z = 0}
local probe_sh_r = {x = 0, y = 0, z = 0}
local probe_sh_l = {x = 0, y = 0, z = 0}

-- Pre-allocated probe vectors for flight steering, climb assist, repulsion & buoyancy
local probe_climb_0 = {x = 0, y = 0, z = 0}
local probe_climb_1 = {x = 0, y = 0, z = 0}
local probe_climb_2 = {x = 0, y = 0, z = 0}
local probe_repulse = {x = 0, y = 0, z = 0}
local probe_repulse_x = {x = 0, y = 0, z = 0}
local probe_repulse_y = {x = 0, y = 0, z = 0}
local probe_repulse_z = {x = 0, y = 0, z = 0}
local probe_buoy_cur = {x = 0, y = 0, z = 0}
local probe_buoy_under = {x = 0, y = 0, z = 0}
local probe_passable = {x = 0, y = 0, z = 0}

-- Pre-allocated static trick action arrays to prevent per-tick GC allocations
local EVASIVE_TRICKS = {"flip_side", "flip_side_left", "flip_back"}
local EVASIVE_TRICKS_COMBAT = {"flip_back", "flip_side", "spin_around"}
local GROUND_TRICKS = {"flip_front", "flip_back", "spin_around", "somersault"}
local TRIAGE_TRICKS = {"somersault", "spin_around", "flip_front"}
local THREAT_REACTIONS = {"flip_back", "flip_side", "flip_side_left", "spin_around"}
local FLIGHT_TRICKS_HIGH = {"flip_side", "flip_side_left", "somersault", "flip_front", "flip_back"}
local FLIGHT_TRICKS_MID = {"flip_side", "flip_side_left", "somersault", "flip_front", "flip_back", "spin_around"}
local JUMP_TRICKS = {"flip_back", "somersault", "flip_front"}
local PAUSE_TRICKS = {"spin_around", "flip_front", "flip_side", "flip_side_left"}
local WILD_FLIGHT_TRICKS = {"flip_side", "flip_side_left", "somersault", "flip_front", "flip_back"}

---Calculates 3D station orbit anchor for guarding or waiting companions
---@param center Vector Origin anchor point
---@param orbit_t number Angular progression
---@param radius number Horizontal orbital radius
---@param height_offset number Base elevation offset
---@param bob_amp? number Harmonic vertical oscillation amplitude
---@param bob_freq? number Harmonic vertical oscillation frequency
---@return Vector anchor_pos
local function calculate_station_orbit(center, orbit_t, radius, height_offset, bob_amp, bob_freq)
	return avoid_solid_nodes({
		x = center.x + math.cos(orbit_t) * radius,
		y = center.y + height_offset + math.sin(orbit_t * (bob_freq or 1.2)) * (bob_amp or 0.25),
		z = center.z + math.sin(orbit_t) * radius,
	}, center)
end

---Retrieves nearby companion positions for shoulder coordination without per-tick closure allocations
---@param self table Pixie entity instance
---@param ppos Vector Player world position
---@return Vector[]
local function get_nearby_companion_positions(self, ppos)
	if self._cached_companion_positions then
		return self._cached_companion_positions
	end
	local comps = {}
	if self.owner_name then
		local nearby = core.get_objects_inside_radius(ppos, 3.5)
		for i = 1, #nearby do
			local nobj = nearby[i]
			if nobj and nobj ~= self.object and not nobj:is_player() then
				local nent = nobj:get_luaentity()
				if nent and not nent.is_dead and nent.name == self.name and nent.owner_name == self.owner_name then
					local npos = nobj:get_pos()
					if npos then
						comps[#comps + 1] = npos
					end
				end
			end
		end
	end
	self._cached_companion_positions = comps
	return comps
end

---Selects an active 3D aerial wander waypoint, balancing low ground cruising and flower foraging
---@param pos Vector Current world position
---@param home_pos Vector Anchor territory origin
---@param cur_yaw? number Current orientation in radians
---@return Vector
local function pick_flight_waypoint(pos, home_pos, cur_yaw)
	-- 35% chance to seek a nearby flower to flutter towards
	if math.random() < 0.35 then
		local minp = {
			x = math.floor(pos.x - 9),
			y = math.floor(pos.y - 3),
			z = math.floor(pos.z - 9),
		}
		local maxp = {
			x = math.floor(pos.x + 9),
			y = math.floor(pos.y + 3),
			z = math.floor(pos.z + 9),
		}
		local flowers = core.find_nodes_in_area(minp, maxp, {"group:flower", "group:flora"})
		if flowers and #flowers > 0 then
			local filtered = {}
			for i = 1, #flowers do
				local f = flowers[i]
				local d = (f.x - pos.x) * (f.x - pos.x) + (f.z - pos.z) * (f.z - pos.z)
				if d > 4.0 then
					filtered[#filtered + 1] = f
				end
			end
			local pick = (#filtered > 0 and filtered[math.random(#filtered)]) or flowers[math.random(#flowers)]
			local f_target = {x = pick.x, y = pick.y + 1.35, z = pick.z}
			if is_passable_node(vector.round(f_target), true) then
				return f_target
			end
		end
	end

	-- Forward-biased exploration angle
	local base_angle = (cur_yaw and (-cur_yaw + math.pi * 0.5)) or (math.random() * math.pi * 2)
	for _ = 1, 8 do
		local angle = base_angle + ((math.random() - 0.5) * math.pi * 1.2)
		local dist = 3.5 + math.random() * 4.5
		local cand_x = pos.x + math.cos(angle) * dist
		local cand_z = pos.z + math.sin(angle) * dist

		-- Maintain generous 28-block territory boundary
		local odx = cand_x - home_pos.x
		local odz = cand_z - home_pos.z
		if (odx * odx + odz * odz) > 784 then
			local back_angle = atan2(home_pos.z - pos.z, home_pos.x - pos.x)
			cand_x = pos.x + math.cos(back_angle) * (5.0 + math.random() * 3.5)
			cand_z = pos.z + math.sin(back_angle) * (5.0 + math.random() * 3.5)
		end

		-- Terrain surface sampling (both solid ground and water surfaces)
		local sy = get_ground_y({x = cand_x, y = pos.y, z = cand_z}, 36, 6, false)
		local cand_y
		if sy then
			-- Cruise close to the ground or water surface, matching low hovering heights (1.3 to 1.8 nodes)
			cand_y = sy + 1.4 + math.random() * 0.4
		else
			-- If no surface detected within 36 blocks, steer downwards to return to terra firma
			cand_y = pos.y - 3.5
		end

		local candidate = {x = cand_x, y = cand_y, z = cand_z}
		if is_passable_node(vector.round(candidate), true) then
			return candidate
		end
	end

	-- Guaranteed offset fallback at low cruising elevation
	local fallback_ang = math.random() * math.pi * 2
	local f_cand_x = pos.x + math.cos(fallback_ang) * 6.0
	local f_cand_z = pos.z + math.sin(fallback_ang) * 6.0
	local f_sy = get_ground_y({x = f_cand_x, y = pos.y, z = f_cand_z}, 36, 6, false)
	local f_y = f_sy and (f_sy + 1.5) or (pos.y - 2.0)
	local fb_node = core.get_node_or_nil(vector.round({x = f_cand_x, y = f_y, z = f_cand_z}))
	local fb_def = fb_node and core.registered_nodes[fb_node.name]
	if fb_def and fb_def.liquidtype and fb_def.liquidtype ~= "none" then
		f_y = (f_sy or pos.y) + 1.6
	end
	return {
		x = f_cand_x,
		y = f_y,
		z = f_cand_z,
	}
end

---Phase 1: Instant De-penetration Safeguard & Liquid Immersion Buoyancy
---@param self table Mob entity instance
---@param dtime number Step delta time
---@param pos Vector Current world position
---@return Vector|nil pos Updated safe position
local function step_depenetration_and_buoyancy(self, dtime, pos)
	avoid_round.x = math.floor(pos.x + 0.5)
	avoid_round.y = math.floor(pos.y + 0.5)
	avoid_round.z = math.floor(pos.z + 0.5)
	if is_walkable_node(avoid_round) then
		local best_air_x, best_air_y, best_air_z = nil, nil, nil
		local best_score = 999
		local rx = avoid_round.x
		local ry = avoid_round.y
		local rz = avoid_round.z

		for i = 1, #NEIGHBOR_OFFSETS_26 do
			local off = NEIGHBOR_OFFSETS_26[i]
			avoid_round.x = rx + off.x
			avoid_round.y = ry + off.y
			avoid_round.z = rz + off.z
			if is_passable_node(avoid_round, true) then
				local dy_bonus = (off.y > 0) and -0.6 or ((off.y < 0) and 0.8 or 0.0)
				local dist_sq = (avoid_round.x - pos.x)^2 + (avoid_round.y - pos.y)^2 + (avoid_round.z - pos.z)^2 + dy_bonus
				if dist_sq < best_score then
					best_score = dist_sq
					best_air_x = avoid_round.x
					best_air_y = avoid_round.y
					best_air_z = avoid_round.z
				end
			end
		end

		if not best_air_x then
			probe_passable.x = rx
			probe_passable.z = rz
			for dy = 1, 8 do
				probe_passable.y = ry + dy
				if is_passable_node(probe_passable, true) then
					best_air_x = rx
					best_air_y = probe_passable.y
					best_air_z = rz
					break
				end
			end
		end

		if best_air_x then
			local best_air = {x = best_air_x, y = best_air_y + 0.1, z = best_air_z}
			self.object:set_pos(best_air)
			self.object:set_velocity({x = 0, y = 1.2, z = 0})
			pos = best_air
		elseif self.owner_name then
			local owner = core.get_player_by_name(self.owner_name)
			if owner and owner:is_valid() then
				local ppos = owner:get_pos()
				local safe_pop = avoid_solid_nodes({x = ppos.x, y = ppos.y + 1.2, z = ppos.z}, ppos)
				self.object:set_pos(safe_pop)
				self.object:set_velocity({x = 0, y = 1.0, z = 0})
				pos = safe_pop
			end
		end
	end

	-- Liquid Immersion & Buoyancy Protection
	local p_floor_x = math.floor(pos.x + 0.5)
	local p_floor_y = math.floor(pos.y + 0.5)
	local p_floor_z = math.floor(pos.z + 0.5)
	probe_buoy_cur.x = p_floor_x
	probe_buoy_cur.y = p_floor_y
	probe_buoy_cur.z = p_floor_z
	local cur_node = core.get_node_or_nil(probe_buoy_cur)
	local cur_def = cur_node and core.registered_nodes[cur_node.name]
	local in_liquid = cur_def and cur_def.liquidtype and cur_def.liquidtype ~= "none"

	probe_buoy_under.x = p_floor_x
	probe_buoy_under.y = math.floor(pos.y - 0.25 + 0.5)
	probe_buoy_under.z = p_floor_z
	local under_node = core.get_node_or_nil(probe_buoy_under)
	local under_def = under_node and core.registered_nodes[under_node.name]
	local touching_liquid = under_def and under_def.liquidtype and under_def.liquidtype ~= "none"

	if in_liquid or touching_liquid then
		local cur_vel = self.object:get_velocity() or {x = 0, y = 0, z = 0}
		local water_surf_y = get_water_surface_y(pos) or (pos.y + 1.2)

		if in_liquid then
			local escape_vy = math.max(cur_vel.y + 14.0 * dtime, 3.2)
			self.object:set_velocity({
				x = cur_vel.x * 0.85,
				y = escape_vy,
				z = cur_vel.z * 0.85,
			})
			x_mob_core.play_animation(self.object, "fly", {speed = 1.6, loop = true})
			if math.random() < dtime * 6.0 then
				pixie.spawn_sparkles(pos, 2, self.owner_name)
			end
		else
			if cur_vel.y < 0.6 then
				self.object:set_velocity({
					x = cur_vel.x,
					y = math.max(cur_vel.y + 8.0 * dtime, 1.4),
					z = cur_vel.z,
				})
			end
		end

		if self._wander_target and self._wander_target.y < (water_surf_y + 1.0) then
			self._wander_target = nil
			self._wander_timer = 0
		end
	end

	return pos
end

---Phase 2: Timers, Cooldowns & Spontaneous Ground Acrobatics
---@param self table Mob entity instance
---@param dtime number Step delta time
local function step_timers_and_tricks(self, dtime)
	if self._combat_timer and self._combat_timer > 0 then
		self._combat_timer = self._combat_timer - dtime
		if self._combat_timer <= 0 then
			self._combat_timer = 0
			self._combat_threat_pos = nil
			self:_update_properties()
		end
	end

	if self._anim_lock and self._anim_lock > 0 then
		self._anim_lock = self._anim_lock - dtime
	end

	if self._interact_cooldown and self._interact_cooldown > 0 then
		self._interact_cooldown = self._interact_cooldown - dtime
	end

	if self._evasive_trick_queued and (self._anim_lock or 0) <= 0 then
		self._evasive_trick_queued = nil
		local chosen_evasive = EVASIVE_TRICKS[math.random(1, #EVASIVE_TRICKS)]
		pixie.play_trick(self.object, chosen_evasive, {speed = 1.25, sparkles = 4})
	end

	if (self._anim_lock or 0) <= 0 then
		local cur_track = self._current_track
		if cur_track == "walk" or cur_track == "run" then
			self._ground_trick_timer = (self._ground_trick_timer or math.random(15, 30)) - dtime
			if self._ground_trick_timer <= 0 then
				self._ground_trick_timer = math.random(18, 38)
				local chosen_ground = GROUND_TRICKS[math.random(1, #GROUND_TRICKS)]
				pixie.play_trick(self.object, chosen_ground, {speed = 1.2, sparkles = 4})
			end
		end
	end
end

---Phase 3: Companion Perks (Dynamic Lighting, Bond Tier, Survival Triage, Threat Radar, Ore Sensing)
---@param self table Mob entity instance
---@param dtime number Step delta time
---@param pos Vector Mob world position
---@param owner_player ObjectRef|nil Connected owner player ObjectRef
local function step_companion_perks(self, dtime, pos, owner_player)
	-- Throttled Dynamic Voxel Lighting (100ms interval)
	self.light_timer = (self.light_timer or 0) + dtime
	if self.light_timer >= 0.1 then
		self.light_timer = 0
		pixie.dynamic_light.update(self, pos)
	end

	-- Accumulate companion bond survival time if tamed
	if self.owner_name and not self.is_dead then
		self.bond_time = (self.bond_time or 0) + dtime
		local old_tier = self.loyalty_tier or 1
		local cur_tier = pixie.bonding.get_loyalty_tier(self.bond_time)
		if cur_tier ~= old_tier then
			self.loyalty_tier = cur_tier
			self:_update_properties()
			local comp_name = self.custom_name or self.pixie_name or S("Pixie")
			if cur_tier == 2 then
				local msg = S("✦ Your companion @1 has grown into a Loyal Companion!"
					.. " Threat radar and triage healing unlocked. ✦", comp_name)
				core.chat_send_player(self.owner_name, core.colorize("#aaffaa", msg))
				pixie.spawn_tame_burst(pos)
				x_mob_core.play_sound(self, "chime", {pos = pos, pitch = 1.4, distance = 18.0})
				pixie.play_trick(self.object, "somersault", {speed = 1.15, sparkles = 8, force = true})
			elseif cur_tier == 3 then
				local msg = S("✦ Your companion @1 has ascended to an Ancient Guardian!"
					.. " Subterranean ore sensing unlocked. ✦", comp_name)
				core.chat_send_player(self.owner_name, core.colorize("#ffdd44", msg))
				pixie.spawn_tame_burst(pos)
				x_mob_core.play_sound(self, "chime", {pos = pos, pitch = 1.6, distance = 20.0})
				pixie.play_trick(self.object, "spin_around", {speed = 1.2, sparkles = 10, force = true})
			end
		else
			self.loyalty_tier = cur_tier
		end
	end

	if not (owner_player and owner_player:is_valid()) then return end
	local ppos = owner_player:get_pos()
	local dist = vector.distance(pos, ppos)
	local loyalty = self.loyalty_tier or 1

	-- Survival Triage: +2 HP every 8 seconds when damaged (Requires Tier 2)
	if loyalty >= 2 then
		self.heal_timer = (self.heal_timer or 0) + dtime
		if self.heal_timer >= 8.0 then
			self.heal_timer = 0
			local player_hp = owner_player:get_hp()
			if player_hp < 20 and player_hp > 0 then
				owner_player:set_hp(math.min(20, player_hp + 2))
				self._swoop_heal_timer = 1.0
				pixie.spawn_heal(ppos, 16, self.owner_name)
				x_mob_core.play_sound(self, "chime", {pos = pos, pitch = 1.0})
				local chosen_triage = TRIAGE_TRICKS[math.random(1, #TRIAGE_TRICKS)]
				pixie.play_trick(self.object, chosen_triage, {speed = 1.25, sparkles = 8, force = true})
			end
		end
	end

	-- Hostile Mob Radar: Proactive Combat Evasion (ALL tiers) & Early Warning Alerts (Tier 2+)
	self._threat_cooldown = (self._threat_cooldown or 0) - dtime
	self._threat_scan_timer = (self._threat_scan_timer or 1.5) - dtime
	if self._threat_scan_timer <= 0 and dist < 14.0 then
		self._threat_scan_timer = 1.5
		local now = core.get_gametime()
		local cache = pixie.threat_cache
		local closest_threat_pos = nil
		local closest_threat_dist_sq = 196.0 -- 14^2
		local closest_threat_name = nil
		local closest_threat_obj = nil

		-- Periodic threat alert expiration pruning every 10 seconds
		if now - (cache._last_prune or 0) > 10.0 then
			cache._last_prune = now
			for k, expire_time in pairs(cache.recent_alerts) do
				if now >= expire_time then
					cache.recent_alerts[k] = nil
				end
			end
		end

		local can_reuse_cache = false
		cache.player_scans = cache.player_scans or {}
		local p_scan = cache.player_scans[self.owner_name]
		if p_scan and (now - p_scan.time < 1.2) then
			can_reuse_cache = (pixie.utils.dist_sq(ppos, p_scan.pos) <= 36.0)
		end

		local candidate_threats = {}
		if can_reuse_cache and p_scan then
			candidate_threats = p_scan.threats
		else
			local nearby_objs = core.get_objects_inside_radius(ppos, 14.0)
			for i = 1, #nearby_objs do
				local cand_obj = nearby_objs[i]
				if cand_obj and cand_obj ~= self.object and cand_obj ~= owner_player then
					local is_threat, tname = pixie.compat.is_hostile(cand_obj, owner_player)
					if is_threat then
						local tp = cand_obj:get_pos()
						if tp then
							candidate_threats[#candidate_threats + 1] = {
								obj = cand_obj,
								pos = tp,
								name = tname,
							}
						end
					end
				end
			end
			cache.player_scans[self.owner_name] = {
				time = now,
				pos = {x = ppos.x, y = ppos.y, z = ppos.z},
				threats = candidate_threats,
			}
		end

		for i = 1, #candidate_threats do
			local t = candidate_threats[i]
			local tp = t.pos
			local td_sq = pixie.utils.dist_sq(tp, ppos)
			if td_sq < closest_threat_dist_sq then
				closest_threat_dist_sq = td_sq
				closest_threat_pos = tp
				closest_threat_name = t.name
				closest_threat_obj = t.obj
			end
		end

		if closest_threat_pos and closest_threat_name then
			local alert_key = tostring(closest_threat_obj)
			local already_alerted = cache.recent_alerts[alert_key] and (now < cache.recent_alerts[alert_key])

			if closest_threat_dist_sq <= 144.0 then
				self._threat_dart_timer = 0
				pixie.signal_combat(self.owner_name, 8.0, closest_threat_pos)
			else
				self._threat_target_pos = {
					x = closest_threat_pos.x,
					y = closest_threat_pos.y,
					z = closest_threat_pos.z,
				}
				self._threat_dart_timer = 1.8
			end

			if loyalty >= 2 and (self._threat_cooldown or 0) <= 0 and not already_alerted then
				self._threat_cooldown = 18.0
				cache.recent_alerts[alert_key] = now + 12.0
				x_mob_core.play_sound(self, "alert", {pos = pos, pitch = 1.35, distance = 18.0})
				local to_threat = vector.direction(pos, closest_threat_pos)
				pixie.spawn_guidance_beacon(pos, to_threat, closest_threat_pos, self.owner_name)
				core.chat_send_player(self.owner_name,
					S("⚠ Pixie alerts: hostile @1 lurking nearby! ⚠", closest_threat_name))
				local chosen_reaction = THREAT_REACTIONS[math.random(1, #THREAT_REACTIONS)]
				pixie.play_trick(self.object, chosen_reaction, {speed = 1.25, sparkles = 6, force = true})
			end
		end
	end

	-- Ore Sensing & Mining Alert Radar (Requires Tier 3)
	if loyalty >= 3 then
		self._ore_cooldown = (self._ore_cooldown or 0) - dtime
		self._ore_scan_timer = (self._ore_scan_timer or 1.5) - dtime
		if self._ore_scan_timer <= 0 and dist < 10.0 then
			self._ore_scan_timer = 2.0
			if pixie.ore_sensor.can_scan(ppos) then
				local best_ore_pos, ore_name, best_priority = pixie.ore_sensor.scan_area(ppos, 6, 3)
				if best_ore_pos and best_priority and best_priority > 0 then
					local is_high_tier = best_priority >= 45
					local cooldown_ready = (self._ore_cooldown or 0) <= 0
					local last_ore = self._last_alerted_ore
					local priority_breakthrough = is_high_tier
						and ((last_ore and last_ore.priority or 0) < 35)
						and not (last_ore and vector.equals(best_ore_pos, last_ore.pos))

					if cooldown_ready or priority_breakthrough then
						self._last_alerted_ore = {
							pos = best_ore_pos,
							priority = best_priority,
						}
						self._ore_cooldown = 24.0

						local now = core.get_gametime()
						local ore_cache = pixie.ore_sensor.cache
						local ore_key = core.hash_node_position(best_ore_pos)
						local alert_entry = ore_cache and ore_cache.recent_alerts and ore_cache.recent_alerts[ore_key]
						local is_global_alert_active = alert_entry and (now < alert_entry.expire)

						if ore_cache and ore_cache.recent_alerts and (now - (ore_cache._last_prune or 0) > 10.0) then
							ore_cache._last_prune = now
							for k, entry in pairs(ore_cache.recent_alerts) do
								if entry.expire and now >= entry.expire then
									ore_cache.recent_alerts[k] = nil
								end
							end
						end

						if not is_global_alert_active or priority_breakthrough then
							local chime_pitch = is_high_tier and 1.65 or 1.45
							x_mob_core.play_sound(self, "chime", {pos = pos, pitch = chime_pitch})
						end

						local to_ore = vector.direction(pos, best_ore_pos)
						pixie.spawn_guidance_beacon(pos, to_ore, best_ore_pos, self.owner_name)
						pixie.spawn_sparkles(pos, 4, self.owner_name)

						local owner_notified = alert_entry and alert_entry.players and alert_entry.players[self.owner_name]
						if not is_global_alert_active or priority_breakthrough or not owner_notified then
							if is_high_tier then
								core.chat_send_player(self.owner_name, S("✦ Pixie excitedly senses rare @1 hidden nearby! ✦", ore_name))
							else
								core.chat_send_player(self.owner_name, S("✦ Pixie senses @1 hidden nearby! ✦", ore_name))
							end
						end

						if ore_cache and ore_cache.recent_alerts then
							if not is_global_alert_active or priority_breakthrough then
								ore_cache.recent_alerts[ore_key] = {
									expire = now + 24.0,
									players = {[self.owner_name] = true},
								}
							elseif alert_entry and alert_entry.players then
								alert_entry.players[self.owner_name] = true
							end
						end

						local ore_trick
						if is_high_tier then
							ore_trick = (math.random() < 0.5) and "somersault" or "spin_around"
						else
							local candidate_tricks = {"flip_front", "spin_around", "flip_side", "flip_side_left"}
							ore_trick = candidate_tricks[math.random(1, #candidate_tricks)]
						end
						pixie.play_trick(self.object, ore_trick, {speed = 1.25, sparkles = 6, force = true})
					end
				end
			end
		end
	end
end

---Phase 4: Follow Mode (Flight Kinematics, Elevation Preservation, Mining Illumination, Steering Target)
---@param self table Mob entity instance
---@param dtime number Step delta time
---@param pos Vector Mob world position
---@param owner_player ObjectRef Connected owner player ObjectRef
---@return Vector anchor_pos
---@return boolean is_moving_fast
---@return Vector custom_desired_vel
---@return number custom_steer_rate
---@return number custom_target_yaw
local function step_follow_mode(self, dtime, pos, owner_player)
	local ppos = owner_player:get_pos()
	local dist = vector.distance(pos, ppos)

	local look_dir = owner_player:get_look_dir() or {x = 0, y = 0, z = 1}
	local look_hlen = math.sqrt(look_dir.x * look_dir.x + look_dir.z * look_dir.z)
	local lhx, lhz
	if look_hlen > 0.08 then
		lhx = look_dir.x / look_hlen
		lhz = look_dir.z / look_hlen
	else
		local pyaw = owner_player:get_look_horizontal() or 0
		lhx = -math.sin(pyaw)
		lhz = math.cos(pyaw)
	end
	local perp_x = -lhz
	local perp_z = lhx

	local headroom = get_headroom(ppos, 3.5)
	local is_low_ceiling = headroom < 2.4

	-- Tight-Space Environment Detection (Caves, 1x2 tunnels, narrow mining corridors, or facing rock walls)
	local probe_y = math.floor(ppos.y + 1.2 + 0.5)

	probe_tight_l.x = math.floor(ppos.x - perp_x * 1.05 + 0.5)
	probe_tight_l.y = probe_y
	probe_tight_l.z = math.floor(ppos.z - perp_z * 1.05 + 0.5)

	probe_tight_r.x = math.floor(ppos.x + perp_x * 1.05 + 0.5)
	probe_tight_r.y = probe_y
	probe_tight_r.z = math.floor(ppos.z + perp_z * 1.05 + 0.5)

	local is_corridor = is_walkable_node(probe_tight_l) and is_walkable_node(probe_tight_r)

	probe_tight_f.x = math.floor(ppos.x + lhx * 1.4 + 0.5)
	probe_tight_f.y = probe_y
	probe_tight_f.z = math.floor(ppos.z + lhz * 1.4 + 0.5)
	local is_facing_wall = is_walkable_node(probe_tight_f)

	local in_tight_space = is_low_ceiling or is_corridor or is_facing_wall

	-- Smooth Hysteresis: rapid tuck behind shoulder (0.25s), graceful release to open flight (0.6s)
	self._tight_space_factor = self._tight_space_factor or 0.0
	if in_tight_space then
		self._tight_space_factor = math.min(1.0, self._tight_space_factor + dtime * 4.0)
	else
		self._tight_space_factor = math.max(0.0, self._tight_space_factor - dtime * 1.6)
	end
	local tight_f = self._tight_space_factor

	-- Instant Player Teleport Catch-up (e.g. /home, /base, /spawn, warps, elevators)
	local player_teleported = false
	if self._last_ppos then
		local p_disp = vector.distance(ppos, self._last_ppos)
		if p_disp > 12.0 then
			player_teleported = true
		end
	end

	-- Line-of-sight and separation monitor
	local pixie_eye = {x = pos.x, y = pos.y + 0.2, z = pos.z}
	local p_eye = {x = ppos.x, y = ppos.y + 1.2, z = ppos.z}
	local has_los = core.line_of_sight(pixie_eye, p_eye)

	if dist > 14.0 and not has_los then
		self._los_lost_timer = (self._los_lost_timer or 0) + dtime
	else
		self._los_lost_timer = math.max(0, (self._los_lost_timer or 0) - dtime * 2.0)
	end

	local los_timeout = (self._los_lost_timer or 0) >= 6.0

	if player_teleported or los_timeout or dist > 32.0 then
		self._los_lost_timer = 0
		local target_y = in_tight_space and (ppos.y + 1.65) or (ppos.y + 1.85)
		local arrive_raw
		if in_tight_space then
			local side = self._shoulder_side or 1
			arrive_raw = {
				x = ppos.x - lhx * 0.38 + perp_x * (side * 0.42),
				y = target_y,
				z = ppos.z - lhz * 0.38 + perp_z * (side * 0.42),
			}
		else
			arrive_raw = {
				x = ppos.x + lhx * 1.5 + perp_x * 0.8,
				y = target_y,
				z = ppos.z + lhz * 1.5 + perp_z * 0.8,
			}
		end
		local arrive_pos = avoid_solid_nodes(arrive_raw, ppos, look_dir)

		pixie.spawn_sparkles(pos, 6, self.owner_name)
		self.object:set_pos(arrive_pos)
		local p_vel = owner_player:get_velocity() or {x = 0, y = 0, z = 0}
		self.object:set_velocity(p_vel)
		pixie.spawn_tame_burst(arrive_pos)
		if player_teleported or dist > 20.0 then
			x_mob_core.play_sound(self, "chime", {pos = arrive_pos, pitch = 1.3})
			local arrival_trick = (math.random() < 0.5) and "spin_around" or "flip_front"
			pixie.play_trick(self.object, arrival_trick, {speed = 1.25, sparkles = 4})
		end

		self._last_ppos = {x = ppos.x, y = ppos.y, z = ppos.z}
		self._player_vel = {x = p_vel.x, y = p_vel.y, z = p_vel.z}
		self._follow_factor = 0.5
		pixie.dynamic_light.update(self, arrive_pos)
		return arrive_pos, false, p_vel, 12.0, self.object:get_yaw()
	end

	-- Measure player velocity accurately via engine velocity and displacement tracking
	local pvel = owner_player:get_velocity() or {x = 0, y = 0, z = 0}
	local measured_vx, measured_vy, measured_vz = 0, 0, 0
	if self._last_ppos and dtime > 0.0001 and vector.distance(ppos, self._last_ppos) < 15.0 then
		measured_vx = (ppos.x - self._last_ppos.x) / dtime
		measured_vy = (ppos.y - self._last_ppos.y) / dtime
		measured_vz = (ppos.z - self._last_ppos.z) / dtime
	end
	if self._last_ppos then
		self._last_ppos.x = ppos.x
		self._last_ppos.y = ppos.y
		self._last_ppos.z = ppos.z
	else
		self._last_ppos = {x = ppos.x, y = ppos.y, z = ppos.z}
	end

	local m_spd_sq = measured_vx * measured_vx + measured_vy * measured_vy + measured_vz * measured_vz
	local p_spd_sq = pvel.x * pvel.x + pvel.y * pvel.y + pvel.z * pvel.z
	local use_engine_vel = (p_spd_sq >= m_spd_sq * 0.49 and p_spd_sq > 0.01)
	local raw_vx = use_engine_vel and pvel.x or measured_vx
	local raw_vy = use_engine_vel and pvel.y or measured_vy
	local raw_vz = use_engine_vel and pvel.z or measured_vz

	-- Filter velocity smoothly to eliminate single-packet jitter
	local vel_smooth = math.min(1.0, dtime * 12.0)
	if self._player_vel then
		self._player_vel.x = self._player_vel.x + (raw_vx - self._player_vel.x) * vel_smooth
		self._player_vel.y = self._player_vel.y + (raw_vy - self._player_vel.y) * vel_smooth
		self._player_vel.z = self._player_vel.z + (raw_vz - self._player_vel.z) * vel_smooth
	else
		self._player_vel = {x = raw_vx, y = raw_vy, z = raw_vz}
	end
	local p_speed = vector.length(self._player_vel)

	-- Throttled companion flock coordination (2Hz instead of 20Hz)
	self._flock_coord_timer = (self._flock_coord_timer or 0) - dtime
	if self._flock_coord_timer <= 0 then
		self._flock_coord_timer = 0.5
		self._cached_companion_positions = nil
	end

	-- Follow Factor: 0.0 = player is resting/stationary, 1.0 = player is actively moving
	self._follow_factor = self._follow_factor or 0.0
	if p_speed > 0.6 or dist > 5.5 then
		self._follow_factor = math.min(1.0, self._follow_factor + dtime * 2.5)
	else
		self._follow_factor = math.max(0.0, self._follow_factor - dtime * 1.5)
	end

	-- Active 3D Flight & Organic Orbit
	self._orbit_dir = self._orbit_dir or 1
	self._orbit_dir_timer = (self._orbit_dir_timer or 6.0) - dtime
	if self._orbit_dir_timer <= 0 then
		self._orbit_dir_timer = 5.0 + math.random() * 6.0
		if math.random() < 0.65 then
			self._orbit_dir = -self._orbit_dir
		end
	end

	local target_orbit_vel = self._orbit_dir * (1.3 + math.min(1.2, p_speed * 0.18))
	self._orbit_vel = self._orbit_vel or (self._orbit_dir * 1.4)
	self._orbit_vel = self._orbit_vel + (target_orbit_vel - self._orbit_vel) * math.min(1.0, dtime * 2.2)
	self.orbit_t = (self.orbit_t or 0) + dtime * self._orbit_vel

	-- Shoulder Perch Kinematics
	local preferred_side = self._shoulder_side or 1
	local sh_dist = 0.42
	local sh_y = ppos.y + 1.65

	probe_sh_r.x = math.floor(ppos.x + perp_x * sh_dist + 0.5)
	probe_sh_r.y = math.floor(sh_y + 0.5)
	probe_sh_r.z = math.floor(ppos.z + perp_z * sh_dist + 0.5)

	probe_sh_l.x = math.floor(ppos.x - perp_x * sh_dist + 0.5)
	probe_sh_l.y = math.floor(sh_y + 0.5)
	probe_sh_l.z = math.floor(ppos.z - perp_z * sh_dist + 0.5)

	local r_blocked = is_walkable_node(probe_sh_r)
	local l_blocked = is_walkable_node(probe_sh_l)

	if r_blocked and not l_blocked then
		preferred_side = -1
	elseif l_blocked and not r_blocked then
		preferred_side = 1
	elseif not r_blocked and not l_blocked and self.owner_name then
		local nearby_comps = get_nearby_companion_positions(self, ppos)
		for i = 1, #nearby_comps do
			local npos = nearby_comps[i]
			local side_dot = (npos.x - ppos.x) * perp_x + (npos.z - ppos.z) * perp_z
			if side_dot > 0.15 and preferred_side == 1 then
				preferred_side = -1
			elseif side_dot < -0.15 and preferred_side == -1 then
				preferred_side = 1
			end
		end
	end
	self._shoulder_side = preferred_side

	local eff_sh_dist = (r_blocked and l_blocked) and 0.20 or sh_dist
	local shoulder_bob = math.sin(self.orbit_t * 2.2) * 0.04
	local sh_fwd_offset = -0.38

	local shoulder_anchor = {
		x = ppos.x + perp_x * (eff_sh_dist * preferred_side) + lhx * sh_fwd_offset,
		y = sh_y + shoulder_bob,
		z = ppos.z + perp_z * (eff_sh_dist * preferred_side) + lhz * sh_fwd_offset,
	}

	-- Forward Lantern Lead & Arc Flight
	local eff_ox, eff_oz
	local v_rel_x, v_rel_z
	if is_low_ceiling then
		local lead_dist = 1.6 + math.sin(self.orbit_t * 0.8) * 0.25
		local sway_amt = math.sin(self.orbit_t * 1.2) * 0.3
		eff_ox = lhx * lead_dist + perp_x * sway_amt
		eff_oz = lhz * lead_dist + perp_z * sway_amt

		local d_lead = (0.8 * math.cos(self.orbit_t * 0.8) * 0.25) * self._orbit_vel
		local d_sway = (1.2 * math.cos(self.orbit_t * 1.2) * 0.3) * self._orbit_vel
		v_rel_x = lhx * d_lead + perp_x * d_sway
		v_rel_z = lhz * d_lead + perp_z * d_sway
	else
		local forward_lead = 3.9 + math.sin(self.orbit_t * 0.7) * 0.65
		local lateral_sway = math.sin(self.orbit_t * 1.1) * 1.6 + math.cos(self.orbit_t * 0.45) * 0.40
		eff_ox = lhx * forward_lead + perp_x * lateral_sway
		eff_oz = lhz * forward_lead + perp_z * lateral_sway

		local d_lead = (0.7 * math.cos(self.orbit_t * 0.7) * 0.65) * self._orbit_vel
		local d_sway = (1.1 * math.cos(self.orbit_t * 1.1) * 1.6
			- 0.45 * math.sin(self.orbit_t * 0.45) * 0.40) * self._orbit_vel
		v_rel_x = lhx * d_lead + perp_x * d_sway
		v_rel_z = lhz * d_lead + perp_z * d_sway
	end

	local elevation_wave = math.sin(self.orbit_t * 0.8 + 1.2) * 0.45 + math.cos(self.orbit_t * 1.4) * 0.22
	local pitch_lift = math.max(0.0, look_dir.y * (is_low_ceiling and 0.2 or 0.45))
	local follow_y = is_low_ceiling
		and (ppos.y + 1.25 + math.sin(self.orbit_t * 1.6) * 0.08 + pitch_lift)
		or (ppos.y + 2.05 + elevation_wave + pitch_lift)

	local follow_raw_anchor = {
		x = ppos.x + eff_ox,
		y = follow_y,
		z = ppos.z + eff_oz,
	}

	local follow_anchor_vel = {
		x = self._player_vel.x + v_rel_x,
		y = self._player_vel.y,
		z = self._player_vel.z + v_rel_z,
	}

	-- Custom Elevation Preservation: track while moving, preserve when stationary
	local base_flight_elevation = self.flight_elevation
		or (self._def and self._def.flight_elevation)
		or self.hover_offset
		or 1.85
	local effective_base_elevation = is_low_ceiling
		and math.min(base_flight_elevation, 1.35)
		or base_flight_elevation

	if self._follow_factor > 0.35 or p_speed > 0.5 then
		local cruising_y = follow_y - ppos.y
		self._preserved_flight_elevation = math.max(
			is_low_ceiling and 1.25 or (effective_base_elevation - 0.20),
			math.min(is_low_ceiling and 1.85 or (effective_base_elevation + 0.40), cruising_y)
		)
	else
		self._preserved_flight_elevation = self._preserved_flight_elevation or effective_base_elevation
	end

	local target_flight_elevation = self._preserved_flight_elevation or effective_base_elevation
	if is_low_ceiling then
		target_flight_elevation = math.min(target_flight_elevation, math.max(1.15, headroom - 0.35))
	end

	-- Idle Lantern Float & Mining Illumination System (Used when stationary)
	self._hover_phase = (self._hover_phase or 0) + dtime * 1.8
	self._idle_timer = (self._idle_timer or 0) - dtime
	self._idle_state = self._idle_state or "perch"

	if self._idle_timer <= 0 then
		local roll = math.random()
		if roll < 0.15 then
			-- Nearby decorative flower inspection (keeps eye-level elevation without diving into dirt)
			local minp = {
				x = math.floor(ppos.x - 4),
				y = math.floor(ppos.y - 1),
				z = math.floor(ppos.z - 4),
			}
			local maxp = {
				x = math.floor(ppos.x + 4),
				y = math.floor(ppos.y + 2),
				z = math.floor(ppos.z + 4),
			}
			local flowers = core.find_nodes_in_area(minp, maxp, {"group:flower"})
			if flowers and #flowers > 0 then
				local fl = flowers[math.random(#flowers)]
				self._idle_state = "flower"
				local flower_hover_y = ppos.y + target_flight_elevation
				self._idle_target_pos = {x = fl.x, y = flower_hover_y, z = fl.z}
				self._idle_timer = 2.5 + math.random() * 2.0
			else
				self._idle_state = "perch"
				self._idle_timer = 3.5 + math.random() * 3.0
			end
		elseif roll < 0.65 then
			self._idle_state = "perch"
			self._idle_flank_side = (math.random() < 0.5) and 1 or -1
			self._idle_flank_fwd = 1.35 + math.random() * 0.45
			self._idle_flank_dist = 0.95 + math.random() * 0.35
			self._idle_flank_height = target_flight_elevation
			self._idle_timer = 3.5 + math.random() * 3.0
		else
			self._idle_state = "swoop"
			self._idle_swoop_t = (math.random() - 0.5) * 1.5
			self._idle_swoop_dir = (math.random() < 0.5) and 1 or -1
			self._idle_swoop_radius = 1.6 + math.random() * 0.4
			self._idle_timer = 3.0 + math.random() * 2.0
		end
	end

	local idle_raw_anchor
	local idle_anchor_vel = {x = 0, y = 0, z = 0}

	if self._idle_state == "flower" and self._idle_target_pos then
		self._idle_target_pos.y = math.max(ppos.y + target_flight_elevation, self._idle_target_pos.y)
		local bob = math.sin(self._hover_phase * 2.0) * 0.12
		local fl_y = self._idle_target_pos.y + bob
		idle_raw_anchor = {
			x = self._idle_target_pos.x,
			y = fl_y,
			z = self._idle_target_pos.z,
		}
		if math.random() < dtime * 1.8 then
			pixie.spawn_sparkles(pos, 1, self.owner_name)
		end
	elseif self._idle_state == "swoop" then
		self._idle_swoop_t = (self._idle_swoop_t or 0) + dtime * 0.85 * (self._idle_swoop_dir or 1)
		local sweep_angle = math.sin(self._idle_swoop_t) * 0.8
		local r = is_low_ceiling and 1.3 or (self._idle_swoop_radius or 1.6)
		local sw_fwd = math.cos(sweep_angle) * r
		local sw_side = math.sin(sweep_angle) * r
		local bob = math.sin(self._hover_phase * 1.8) * 0.14
		local sy = ppos.y + target_flight_elevation + bob + pitch_lift
		idle_raw_anchor = {
			x = ppos.x + lhx * sw_fwd + perp_x * sw_side,
			y = sy,
			z = ppos.z + lhz * sw_fwd + perp_z * sw_side,
		}
		local d_sweep = (math.cos(self._idle_swoop_t) * 0.8) * 0.85 * (self._idle_swoop_dir or 1)
		local d_fwd = -math.sin(sweep_angle) * d_sweep * r
		local d_side = math.cos(sweep_angle) * d_sweep * r
		idle_anchor_vel = {
			x = lhx * d_fwd + perp_x * d_side,
			y = 0,
			z = lhz * d_fwd + perp_z * d_side,
		}
	else
		local side = self._idle_flank_side or 1
		local fwd_amt = is_low_ceiling and 1.15 or (self._idle_flank_fwd or 1.4)
		local side_amt = side * (is_low_ceiling and 0.7 or (self._idle_flank_dist or 1.05))
		local flank_x = lhx * fwd_amt + perp_x * side_amt
		local flank_z = lhz * fwd_amt + perp_z * side_amt
		local bob = math.sin(self._hover_phase * 2.0) * (is_low_ceiling and 0.08 or 0.14)
		local perch_y = ppos.y + target_flight_elevation + bob + pitch_lift
		idle_raw_anchor = {
			x = ppos.x + flank_x,
			y = perch_y,
			z = ppos.z + flank_z,
		}
	end

	-- Maintain flight elevation floor
	local min_idle_y = ppos.y + target_flight_elevation - 0.15
	if idle_raw_anchor.y < min_idle_y then
		idle_raw_anchor.y = min_idle_y + math.sin(self._hover_phase * 1.8) * 0.08
	end

	-- Blend into shoulder anchor when in tight spaces
	if tight_f > 0 then
		follow_raw_anchor = {
			x = follow_raw_anchor.x + (shoulder_anchor.x - follow_raw_anchor.x) * tight_f,
			y = follow_raw_anchor.y + (shoulder_anchor.y - follow_raw_anchor.y) * tight_f,
			z = follow_raw_anchor.z + (shoulder_anchor.z - follow_raw_anchor.z) * tight_f,
		}
		idle_raw_anchor = {
			x = idle_raw_anchor.x + (shoulder_anchor.x - idle_raw_anchor.x) * tight_f,
			y = idle_raw_anchor.y + (shoulder_anchor.y - idle_raw_anchor.y) * tight_f,
			z = idle_raw_anchor.z + (shoulder_anchor.z - idle_raw_anchor.z) * tight_f,
		}
	end

	local raw_anchor
	local v_anchor

	if self._combat_timer and self._combat_timer > 0 then
		local retreat_dist = is_low_ceiling and 0.45 or 1.2
		local perch_y = is_low_ceiling and (ppos.y + 1.65) or (ppos.y + 2.75)
		local shoulder_side = self._shoulder_side or 1
		raw_anchor = {
			x = ppos.x - lhx * retreat_dist + perp_x * 0.45 * shoulder_side,
			y = perch_y + math.sin(self.orbit_t * 2.2) * 0.15,
			z = ppos.z - lhz * retreat_dist + perp_z * 0.45 * shoulder_side,
		}
		v_anchor = {x = self._player_vel.x, y = self._player_vel.y, z = self._player_vel.z}
	elseif self._threat_dart_timer and self._threat_dart_timer > 0 and self._threat_target_pos then
		self._threat_dart_timer = self._threat_dart_timer - dtime
		local to_threat_h = {
			x = self._threat_target_pos.x - ppos.x,
			y = 0,
			z = self._threat_target_pos.z - ppos.z,
		}
		local th_dist = math.sqrt(to_threat_h.x * to_threat_h.x + to_threat_h.z * to_threat_h.z)
		local dart_fwd = (th_dist > 0.1) and math.min(2.8, th_dist * 0.45) or 2.0
		local dart_dir_x = (th_dist > 0.1) and (to_threat_h.x / th_dist) or lhx
		local dart_dir_z = (th_dist > 0.1) and (to_threat_h.z / th_dist) or lhz

		raw_anchor = {
			x = ppos.x + dart_dir_x * dart_fwd,
			y = ppos.y + (is_low_ceiling and 1.3 or 1.9) + math.sin(self.orbit_t * 3.0) * 0.2,
			z = ppos.z + dart_dir_z * dart_fwd,
		}
		v_anchor = {x = 0, y = 0, z = 0}
	elseif self._swoop_heal_timer and self._swoop_heal_timer > 0 then
		self._swoop_heal_timer = self._swoop_heal_timer - dtime
		local swoop_side = perp_x * 0.4
		local swoop_side_z = perp_z * 0.4
		raw_anchor = {
			x = ppos.x + lhx * 0.6 + swoop_side,
			y = ppos.y + (is_low_ceiling and 1.05 or 1.2) + math.sin(self.orbit_t * 2.5) * 0.1,
			z = ppos.z + lhz * 0.6 + swoop_side_z,
		}
		v_anchor = {x = self._player_vel.x, y = self._player_vel.y, z = self._player_vel.z}
	else
		raw_anchor = {
			x = idle_raw_anchor.x + (follow_raw_anchor.x - idle_raw_anchor.x) * self._follow_factor,
			y = idle_raw_anchor.y + (follow_raw_anchor.y - idle_raw_anchor.y) * self._follow_factor,
			z = idle_raw_anchor.z + (follow_raw_anchor.z - idle_raw_anchor.z) * self._follow_factor,
		}
		v_anchor = {
			x = idle_anchor_vel.x + (follow_anchor_vel.x - idle_anchor_vel.x) * self._follow_factor,
			y = idle_anchor_vel.y + (follow_anchor_vel.y - idle_anchor_vel.y) * self._follow_factor,
			z = idle_anchor_vel.z + (follow_anchor_vel.z - idle_anchor_vel.z) * self._follow_factor,
		}
	end

	-- Flight elevation minimum clearance
	local min_clearance_y = ppos.y + (is_low_ceiling and 1.15 or (target_flight_elevation - 0.20))
	if raw_anchor.y < min_clearance_y then
		raw_anchor.y = min_clearance_y
	end

	-- Crosshair cone obstruction avoidance
	local eye_pos = {x = ppos.x, y = ppos.y + 1.625, z = ppos.z}
	local to_anchor = vector.subtract(raw_anchor, eye_pos)
	local dist_to_anchor = vector.length(to_anchor)
	if dist_to_anchor > 0.2 then
		local dir_to_anchor = vector.multiply(to_anchor, 1 / dist_to_anchor)
		local dot_3d = vector.dot(dir_to_anchor, look_dir)
		if dot_3d > 0.70 then
			local evasion = (dot_3d - 0.70) / 0.30
			local lift = is_low_ceiling and (evasion * 0.2) or (evasion * 0.85)
			raw_anchor.y = raw_anchor.y + lift
			local side_sign = ((raw_anchor.x - ppos.x) * perp_x + (raw_anchor.z - ppos.z) * perp_z >= 0) and 1 or -1
			raw_anchor.x = raw_anchor.x + perp_x * side_sign * (evasion * 0.95)
			raw_anchor.z = raw_anchor.z + perp_z * side_sign * (evasion * 0.95)
		end
	end

	local safe_elevated_origin = {
		x = ppos.x,
		y = ppos.y + target_flight_elevation,
		z = ppos.z,
	}
	local anchor_pos = avoid_solid_nodes(raw_anchor, safe_elevated_origin, look_dir)

	local surf_under_anchor = get_ground_y(anchor_pos, 24, 6, true)
	if surf_under_anchor and anchor_pos.y < (surf_under_anchor + 1.4) then
		anchor_pos.y = surf_under_anchor + 1.4
	end

	-- Desired velocity and steering rates
	local delta = vector.subtract(anchor_pos, pos)
	local dist_err = vector.length(delta)

	local catchup_gain = 1.4 + (self._follow_factor * 3.1) + ((dist_err > 2.5) and 2.0 or 0.0)
	local v_correction = vector.multiply(delta, catchup_gain)
	local desired_vel = vector.add(v_anchor, v_correction)

	local idle_max_spd = 1.5
	local follow_max_spd = math.min(36.0, math.max(14.0, (p_speed * 1.5) + 8.0))
	local max_pixie_speed = idle_max_spd + (follow_max_spd - idle_max_spd) * self._follow_factor

	-- Clamp horizontal desired velocity to max_pixie_speed
	local h_desired_spd = math.sqrt(desired_vel.x * desired_vel.x + desired_vel.z * desired_vel.z)
	if h_desired_spd > max_pixie_speed then
		local h_scale = max_pixie_speed / h_desired_spd
		desired_vel.x = desired_vel.x * h_scale
		desired_vel.z = desired_vel.z * h_scale
	end

	-- Vertical velocity authority: assertive upward climb when below target flight elevation
	local min_flight_y = ppos.y + target_flight_elevation
	local y_deficit = min_flight_y - pos.y
	if y_deficit > 0.05 then
		-- Below target elevation: apply assertive vertical restorative climb velocity
		local climb_boost = math.min(3.5, y_deficit * 3.0 + 0.6)
		desired_vel.y = math.max(desired_vel.y, climb_boost)
	else
		-- Above target elevation or hovering: clamp within reasonable vertical range
		desired_vel.y = math.max(-max_pixie_speed, math.min(max_pixie_speed, desired_vel.y))
	end

	if self._follow_factor < 0.25 and p_speed <= 0.25 and dist_err < 0.35 then
		local y_err = anchor_pos.y - pos.y
		local hover_flutter = math.sin(self._hover_phase * 2.2) * 0.06
		if math.abs(y_err) < 0.25 then
			desired_vel.y = hover_flutter + y_err * 1.6
		end
	end

	local steer_rate = 3.5 + (self._follow_factor * 8.5) + ((dist_err > 2.5) and 4.0 or 0.0)
	if y_deficit > 0.15 then
		steer_rate = math.max(steer_rate, 8.0)
	end
	local cur_vel = self.object:get_velocity() or {x = 0, y = 0, z = 0}
	local cur_spd = vector.length(cur_vel)

	local target_yaw
	if self._combat_timer and self._combat_timer > 0 and self._combat_threat_pos then
		local to_threat = vector.subtract(self._combat_threat_pos, pos)
		target_yaw = core.dir_to_yaw({x = to_threat.x, y = 0, z = to_threat.z})
	elseif self._threat_dart_timer and self._threat_dart_timer > 0 and self._threat_target_pos then
		local to_threat = vector.subtract(self._threat_target_pos, pos)
		target_yaw = core.dir_to_yaw({x = to_threat.x, y = 0, z = to_threat.z})
	elseif tight_f > 0.4 then
		target_yaw = owner_player:get_look_horizontal() or core.dir_to_yaw({x = lhx, y = 0, z = lhz})
	elseif self._follow_factor > 0.35 and cur_spd > 0.8 then
		target_yaw = core.dir_to_yaw({x = cur_vel.x, y = 0, z = cur_vel.z})
	elseif self._idle_state == "flower" and self._idle_target_pos then
		local to_flower = vector.subtract(self._idle_target_pos, pos)
		target_yaw = core.dir_to_yaw({x = to_flower.x, y = 0, z = to_flower.z})
	else
		local to_player = vector.subtract(ppos, pos)
		target_yaw = core.dir_to_yaw({x = to_player.x, y = 0, z = to_player.z})
	end

	local is_moving_fast = false
	if (self._anim_lock or 0) <= 0 then
		if self._follow_factor > 0.3 and (p_speed > 1.2 or cur_spd > 3.0 or dist_err > 2.0) then
			is_moving_fast = true
			self._flight_trick_timer = (self._flight_trick_timer or math.random(15, 35)) - dtime
			if self._flight_trick_timer <= 0 and headroom >= 2.2 and tight_f < 0.35 and not is_low_ceiling then
				self._flight_trick_timer = math.random(20, 45)
				local chosen = FLIGHT_TRICKS_HIGH[math.random(1, #FLIGHT_TRICKS_HIGH)]
				pixie.play_trick(self.object, chosen, {speed = 1.25, sparkles = 4})
			else
				x_mob_core.play_animation(self.object, "fly", {speed = 1.5, loop = true})
			end
		elseif cur_spd > 0.6 then
			self._flight_trick_timer = (self._flight_trick_timer or math.random(18, 40)) - dtime
			if self._flight_trick_timer <= 0 and headroom >= 2.0 and tight_f < 0.35 and not is_low_ceiling then
				self._flight_trick_timer = math.random(25, 50)
				local chosen = FLIGHT_TRICKS_MID[math.random(1, #FLIGHT_TRICKS_MID)]
				pixie.play_trick(self.object, chosen, {speed = 1.2, sparkles = 4})
			else
				x_mob_core.play_animation(self.object, "fly", {speed = 1.15, loop = true})
			end
		else
			local p_v = owner_player:get_velocity() or {x = 0, y = 0, z = 0}
			self._jump_reaction_cd = (self._jump_reaction_cd or 0) - dtime
			if p_v.y > 3.2 and dist < 5.0 and self._jump_reaction_cd <= 0 and headroom >= 2.2 then
				self._jump_reaction_cd = 10.0
				local chosen_jump = JUMP_TRICKS[math.random(1, #JUMP_TRICKS)]
				pixie.play_trick(self.object, chosen_jump, {speed = 1.2, sparkles = 5, sound = true})
			else
				self._playful_trick_timer = (self._playful_trick_timer or math.random(18, 35)) - dtime
				if self._playful_trick_timer <= 0 and dist < 6.0 and cur_spd < 0.4 then
					self._playful_trick_timer = math.random(22, 45)
					local chosen = pixie.TRICK_NAMES[math.random(1, #pixie.TRICK_NAMES)]
					pixie.play_trick(self.object, chosen, {speed = 1.15, sparkles = 4, sound = (math.random() < 0.5)})
				else
					x_mob_core.play_animation(self.object, "idle", {speed = 0.95, loop = true})
				end
			end
		end
	end

	return anchor_pos, is_moving_fast, desired_vel, steer_rate, target_yaw
end

---Phase 4: Guard / Stay Mode
---@param self table Mob entity instance
---@param dtime number Step delta time
---@param pos Vector Mob world position
---@return Vector anchor_pos
---@return boolean is_moving_fast
local function step_guard_mode(self, dtime, pos)
	self.guard_pos = self.guard_pos or vector.round(pos)
	self.orbit_t = self.orbit_t + dtime * 0.5
	local anchor_pos = calculate_station_orbit(self.guard_pos, self.orbit_t, 1.5, 1.2, 0.25, 1.2)
	if (self._anim_lock or 0) <= 0 then
		self._guard_trick_timer = (self._guard_trick_timer or math.random(20, 45)) - dtime
		if self._guard_trick_timer <= 0 then
			self._guard_trick_timer = math.random(25, 55)
			local tricks = pixie.TRICK_NAMES
			local chosen = tricks[math.random(1, #tricks)]
			pixie.play_trick(self.object, chosen, {speed = 1.15, sparkles = 4, sound = (math.random() < 0.4)})
		else
			x_mob_core.play_animation(self.object, "idle", {speed = 0.9, loop = true})
		end
	end
	return anchor_pos, false, nil, nil, nil
end

---Phase 4: Offline Owner Wait Mode
---@param self table Mob entity instance
---@param dtime number Step delta time
---@param pos Vector Mob world position
---@return Vector anchor_pos
---@return boolean is_moving_fast
local function step_wait_mode(self, dtime, pos)
	self.orbit_t = self.orbit_t + dtime * 0.5
	self._wait_pos = self._wait_pos or vector.round(pos)
	local anchor_pos = calculate_station_orbit(self._wait_pos, self.orbit_t, 0.8, 0, 0.2, 1.2)
	if (self._anim_lock or 0) <= 0 then
		self._wait_trick_timer = (self._wait_trick_timer or math.random(25, 50)) - dtime
		if self._wait_trick_timer <= 0 then
			self._wait_trick_timer = math.random(30, 60)
			local tricks = pixie.TRICK_NAMES
			local chosen = tricks[math.random(1, #tricks)]
			pixie.play_trick(self.object, chosen, {speed = 1.15, sparkles = 3})
		else
			x_mob_core.play_animation(self.object, "idle", {speed = 0.9, loop = true})
		end
	end
	return anchor_pos, false, nil, nil, nil
end

---Phase 4: Wild Roaming Mode
---@param self table Mob entity instance
---@param dtime number Step delta time
---@param pos Vector Mob world position
---@return Vector anchor_pos
---@return boolean is_moving_fast
local function step_wild_mode(self, dtime, pos)
	self.orbit_t = self.orbit_t + dtime * 1.2
	self._wander_timer = (self._wander_timer or 0) - dtime
	self._wander_pause = (self._wander_pause or 0) - dtime

	local is_moving_fast = false
	local anchor_pos = nil

	-- Check if any nearby player is holding a treat (flower, honey, mese fragment)
	local enticed_player = nil
	local enticed_dist_sq = 64.0
	local enticed_dist = 8.0
	local players = core.get_connected_players()
	for i = 1, #players do
		local p = players[i]
		if p and p:is_valid() then
			local pp = p:get_pos()
			if pp then
				local pd_sq = pixie.utils.dist_sq(pos, pp)
				if pd_sq <= enticed_dist_sq then
					local wielded = p.get_wielded_item and p:get_wielded_item()
					local item = (wielded and wielded.get_name and wielded:get_name()) or ""
					if is_taming_food(item) then
						enticed_player = p
						enticed_dist_sq = pd_sq
						enticed_dist = math.sqrt(pd_sq)
					end
				end
			end
		end
	end

	local custom_target_yaw = nil
	if enticed_player then
		local pp = enticed_player:get_pos()
		local pdir = enticed_player:get_look_dir() or {x = 0, y = 0, z = 1}
		local raw_anchor = {
			x = pp.x + pdir.x * 2.2,
			y = pp.y + 1.4 + math.sin(self.orbit_t * 2.5) * 0.25,
			z = pp.z + pdir.z * 2.2,
		}
		anchor_pos = avoid_solid_nodes(raw_anchor, pp)
		custom_target_yaw = core.dir_to_yaw({x = pp.x - pos.x, y = 0, z = pp.z - pos.z})
		self._entice_chime_timer = (self._entice_chime_timer or 0) - dtime
		if enticed_dist <= 3.5 and self._entice_chime_timer <= 0 then
			self._entice_chime_timer = 3.5 + math.random() * 2.0
			x_mob_core.play_sound(self, "chime", {pos = pos, pitch = 1.25})
		end
		if (self._anim_lock or 0) <= 0 then
			if enticed_dist > 3.0 then
				is_moving_fast = true
				x_mob_core.play_animation(self.object, "fly", {speed = 1.3, loop = true})
			else
				x_mob_core.play_animation(self.object, "idle", {speed = 1.0, loop = true})
			end
		end
		if math.random() < dtime * 2.5 then
			pixie.spawn_sparkles(pos, 1)
		end
	elseif self._wander_pause and self._wander_pause > 0 then
		local sy = get_ground_y(pos, 36, 4, true)
		local target_y = sy and (sy + 1.4) or pos.y
		local bob = math.sin(self.orbit_t * 2.0) * 0.15
		anchor_pos = {x = pos.x, y = target_y + bob, z = pos.z}
		if (self._anim_lock or 0) <= 0 then
			if not self._pause_trick_done and math.random() < 0.45 then
				self._pause_trick_done = true
				local chosen = PAUSE_TRICKS[math.random(1, #PAUSE_TRICKS)]
				pixie.play_trick(self.object, chosen, {speed = 1.15, sparkles = 3})
			else
				x_mob_core.play_animation(self.object, "idle", {speed = 1.0, loop = true})
			end
		end
		if math.random() < dtime * 2.0 then
			pixie.spawn_sparkles(pos, 1)
		end
	else
		local dist_to_target = self._wander_target and vector.distance(pos, self._wander_target) or 999
		local cur_vel = self.object:get_velocity() or {x = 0, y = 0, z = 0}
		local cur_spd_sq = cur_vel.x * cur_vel.x + cur_vel.z * cur_vel.z
		if dist_to_target > 2.0 and cur_spd_sq < 0.1 then
			self._stuck_timer = (self._stuck_timer or 0) + dtime
			if self._stuck_timer > 0.8 then
				self._stuck_timer = 0
				self._wander_target = nil
				self._wander_timer = 0
			end
		else
			self._stuck_timer = 0
		end

		if not self._wander_target or self._wander_timer <= 0 or dist_to_target < 1.4 then
			self._pause_trick_done = false
			if self._wander_target and dist_to_target < 1.4 and math.random() < 0.25 then
				self._wander_pause = 1.6
				self._wander_target = nil
				self._wander_timer = 0
			else
				self._wander_target = pick_flight_waypoint(pos, self._home_pos, self.object:get_yaw())
				self._wander_timer = 5.5 + math.random() * 3.0
			end
		end

		if self._wander_target then
			local bob = math.sin(self.orbit_t * 2.8) * 0.25
			local raw_anchor = {
				x = self._wander_target.x,
				y = self._wander_target.y + bob,
				z = self._wander_target.z,
			}
			anchor_pos = avoid_solid_nodes(raw_anchor, self._home_pos)

			local local_sy = get_ground_y(pos, 36, 4, true)
			if local_sy then
				if pos.y > (local_sy + 2.2) then
					anchor_pos.y = local_sy + 1.4
					if cur_vel.y > 0.3 then
						self.object:set_velocity({x = cur_vel.x, y = cur_vel.y * 0.5 - 0.5, z = cur_vel.z})
					end
				elseif anchor_pos.y < (local_sy + 1.2) then
					anchor_pos.y = local_sy + 1.4
				end
			end

			if (self._anim_lock or 0) <= 0 then
				self._wild_flight_trick_timer = (self._wild_flight_trick_timer or math.random(20, 45)) - dtime
				if self._wild_flight_trick_timer <= 0 and get_headroom(pos, 2.5) >= 2.0 then
					self._wild_flight_trick_timer = math.random(25, 55)
					local chosen = WILD_FLIGHT_TRICKS[math.random(1, #WILD_FLIGHT_TRICKS)]
					pixie.play_trick(self.object, chosen, {speed = 1.2, sparkles = 3})
				else
					x_mob_core.play_animation(self.object, "fly", {speed = 1.25, loop = true})
				end
			end
		end
	end

	return anchor_pos, is_moving_fast, nil, nil, custom_target_yaw
end

---Phase 5: Flight Steering, Obstacle Climbing, Inter-Pixie Repulsion & Yaw Integration
---@param self table Mob entity instance
---@param dtime number Step delta time
---@param pos Vector Mob world position
---@param anchor_pos Vector Target anchor world position
---@param is_moving_fast boolean High-speed flight flag
---@param custom_desired_vel? Vector Pre-calculated desired velocity
---@param custom_steer_rate? number Pre-calculated steering rate
---@param custom_target_yaw? number Pre-calculated target yaw
local function step_flight_steering(self, dtime, pos, anchor_pos, is_moving_fast,
	custom_desired_vel, custom_steer_rate, custom_target_yaw)
	if not anchor_pos then return end

	local surf_under_anchor = get_ground_y(anchor_pos, 24, 6, true)
	if surf_under_anchor and anchor_pos.y < (surf_under_anchor + 1.4) then
		anchor_pos.y = surf_under_anchor + 1.4
	end

	local delta = vector.subtract(anchor_pos, pos)
	local dist = vector.length(delta)

	local desired_vel
	local steer_rate
	local target_yaw

	if custom_desired_vel then
		desired_vel = custom_desired_vel
		steer_rate = custom_steer_rate or 12.0
		target_yaw = custom_target_yaw
		if surf_under_anchor and pos.y < (surf_under_anchor + 1.4) and desired_vel.y < 0.8 then
			desired_vel.y = math.max(desired_vel.y, 1.8)
		end
	else
		target_yaw = custom_target_yaw
		if dist > 0.08 then
			local max_spd = is_moving_fast and 5.5 or 1.6
			local target_speed = math.min(max_spd, math.max(0.7, dist * 1.2))
			local fly_dir = vector.normalize(delta)
			desired_vel = vector.multiply(fly_dir, target_speed)

			local headroom_here = get_headroom(pos, 3.0)
			local bob_amp = (headroom_here < 2.3) and 0.08 or 0.18
			desired_vel.y = desired_vel.y + math.sin(self.orbit_t * 2.4) * bob_amp
			steer_rate = is_moving_fast and 8.0 or 4.0

			local h_dist_sq = delta.x * delta.x + delta.z * delta.z
			if not target_yaw and h_dist_sq > 0.04 then
				target_yaw = core.dir_to_yaw({x = delta.x, y = 0, z = delta.z})
			end
		else
			local cur_vel = self.object:get_velocity() or {x = 0, y = 0, z = 0}
			desired_vel = {
				x = cur_vel.x * 0.4,
				y = math.sin(self.orbit_t * 2.0) * 0.15,
				z = cur_vel.z * 0.4,
			}
			steer_rate = 4.0
		end
	end

	-- Forward Shore Bank & Ledge Climb Assist
	local h_spd_sq = desired_vel.x * desired_vel.x + desired_vel.z * desired_vel.z
	if h_spd_sq > 0.04 then
		local h_spd = math.sqrt(h_spd_sq)
		local f_dir_x = desired_vel.x / h_spd
		local f_dir_z = desired_vel.z / h_spd
		local f_probe_dist = math.min(1.4, math.max(0.7, h_spd * 0.35))

		local f_nx = math.floor(pos.x + f_dir_x * f_probe_dist + 0.5)
		local f_ny = math.floor(pos.y + 0.5)
		local f_nz = math.floor(pos.z + f_dir_z * f_probe_dist + 0.5)

		probe_climb_0.x = f_nx
		probe_climb_0.y = f_ny
		probe_climb_0.z = f_nz

		if is_walkable_node(probe_climb_0) then
			probe_climb_1.x = f_nx
			probe_climb_1.y = f_ny + 1
			probe_climb_1.z = f_nz
			if is_passable_node(probe_climb_1, true) then
				desired_vel.y = math.max(desired_vel.y, 2.4)
				steer_rate = math.max(steer_rate, 8.0)
			else
				probe_climb_2.x = f_nx
				probe_climb_2.y = f_ny + 2
				probe_climb_2.z = f_nz
				if is_passable_node(probe_climb_2, true) then
					desired_vel.y = math.max(desired_vel.y, 3.2)
					steer_rate = math.max(steer_rate, 9.0)
				end
			end
		end
	end

	-- 3D Inter-Pixie Repulsion & Flocking Separation (x_mob_core API)
	self._jitter_timer = (self._jitter_timer or 0) + dtime
	local sep_x, sep_y, sep_z = x_mob_core.calculate_repulsion(self, pos, 1.35, 3.2, true)

	if sep_x ~= 0 or sep_y ~= 0 or sep_z ~= 0 then
		probe_repulse.x = math.floor(pos.x + sep_x * 0.25 + 0.5)
		probe_repulse.y = math.floor(pos.y + sep_y * 0.25 + 0.5)
		probe_repulse.z = math.floor(pos.z + sep_z * 0.25 + 0.5)

		if is_walkable_node(probe_repulse) then
			local floor_py = math.floor(pos.y + 0.5)
			local floor_px = math.floor(pos.x + 0.5)
			local floor_pz = math.floor(pos.z + 0.5)

			probe_repulse_x.x = probe_repulse.x
			probe_repulse_x.y = floor_py
			probe_repulse_x.z = floor_pz
			if is_walkable_node(probe_repulse_x) then
				sep_x = 0
			end

			probe_repulse_z.x = floor_px
			probe_repulse_z.y = floor_py
			probe_repulse_z.z = probe_repulse.z
			if is_walkable_node(probe_repulse_z) then
				sep_z = 0
			end

			probe_repulse_y.x = floor_px
			probe_repulse_y.y = probe_repulse.y
			probe_repulse_y.z = floor_pz
			if is_walkable_node(probe_repulse_y) then
				sep_y = 0
			end
		end

		desired_vel.x = desired_vel.x + sep_x
		desired_vel.y = desired_vel.y + sep_y
		desired_vel.z = desired_vel.z + sep_z
	end

	local cur_vel = self.object:get_velocity() or {x = 0, y = 0, z = 0}
	local steer_x = (desired_vel.x - cur_vel.x) * steer_rate
	local steer_y = (desired_vel.y - cur_vel.y) * steer_rate
	local steer_z = (desired_vel.z - cur_vel.z) * steer_rate

	self.object:set_velocity({
		x = cur_vel.x + steer_x * dtime,
		y = cur_vel.y + steer_y * dtime,
		z = cur_vel.z + steer_z * dtime,
	})

	if target_yaw then
		local cur_yaw = self.object:get_yaw() or target_yaw
		local diff = (target_yaw - cur_yaw) % (math.pi * 2)
		if diff > math.pi then
			diff = diff - math.pi * 2
		end
		self.object:set_yaw(cur_yaw + diff * math.min(1.0, dtime * 8.0))
	end
end

x_mob_core.register_mob("pixie:pixie", {
	initial_properties = {
		hp_max = 30,
		physical = true,
		collide_with_objects = false,
		collisionbox = {-0.2, 0.0, -0.2, 0.2, 0.4, 0.2},
		selectionbox = {-0.18, 0.0, -0.18, 0.18, 0.38, 0.18},
		mesh = "pixie.glb",
		visual_size = {x = 16.41, y = 16.41, z = 16.41},
		backface_culling = false,
		use_texture_alpha = true,
		glow = 14,
	},

	textures = pixie_textures,
	phenotypes = pixie_phenotypes,

	factions = {"pixie", "fairy", "neutral"},
	armor_groups = {fleshy = 100},
	immunities = {suffocation = true, block_suffocation = true},
	is_floating = true,
	flight_elevation = 1.85,
	hover_offset = 1.85,
	combat_hover_offset = 1.85,
	melee = false,
	shooter = false,
	auto_scan = false,
	can_attack = false,
	walk_speed = 3.2,
	pursuit_speed = 6.4,
	wander_speed = 2.4,
	death_duration = 1.67,
	can_flinch = false,
	friendly_fire = false,
	health_regen = {
		rate = 0.5,
		passive = true,
		can_flee = false,
		flee_threshold = 0,
	},
	drops = pixie.compat.get_drops(),
	drop_options = {
		particle_color = "#ffff88",
		particles = true,
		trails = true,
		sound = "pixie_chime",
	},
	damage_effect = { type = "none" },

	sounds = {
		distance = 16.0,
		chime = {name = "pixie_chime", gain = 0.7, pitch = 1.0},
		alert = {name = "pixie_chime", gain = 0.8, pitch = 1.35},
		attack = {name = "pixie_chime", gain = 0.7, pitch = 1.0},
		hurt = {name = "pixie_hurt", gain = 0.8, pitch = 1.0},
		death = {name = "pixie_death", gain = 0.85, pitch = 1.0},
	},

	animations = {
		idle           = {track = "idle",           speed = 1.0,  loop = true},
		walk           = {track = "walk",           speed = 1.1,  loop = true},
		run            = {track = "run",            speed = 1.3,  loop = true},
		fly            = {track = "fly",            speed = 1.25, loop = true},
		attack         = {track = "attack",         speed = 1.2,  loop = false},
		hurt           = {track = "hurt",           speed = 1.0,  loop = false},
		death          = {track = "death",          speed = 1.0,  loop = false},
		flip_back      = {track = "flip_back",      speed = 1.1,  loop = false},
		flip_front     = {track = "flip_front",     speed = 1.1,  loop = false},
		flip_side      = {track = "flip_side",      speed = 1.15, loop = false},
		flip_side_left = {track = "flip_side_left", speed = 1.15, loop = false},
		spin_around    = {track = "spin_around",    speed = 1.2,  loop = false},
		somersault     = {track = "somersault",     speed = 1.1,  loop = false},
	},

	_update_properties = function(self)
		if not self.object or not self.object:is_valid() then return end
		local pheno_list = self.phenotypes or pixie_phenotypes
		local tex_no = self.texture_no or 1
		local pheno = pheno_list[tex_no] or pheno_list[1]
		local label
		local nametag_text = ""
		local show_nametag = (self.show_nametag ~= false)
		if pixie.config and pixie.config.show_nametags == false then
			show_nametag = false
		end

		if self.owner_name then
			local comp_name = self.custom_name or self.pixie_name or (pheno.name .. " Pixie")
			local mode_str
			if self.mode == "stay" then
				local gpos = self.guard_pos or (self.object and self.object:is_valid() and vector.round(self.object:get_pos()))
				if gpos then
					mode_str = S("Guarding at (@1, @2, @3)", gpos.x, gpos.y, gpos.z)
				else
					mode_str = S("Guarding")
				end
			else
				mode_str = S("Following")
			end
			local cur_hp = tostring(self.hp or 30)
			local tier = pixie.bonding.get_loyalty_tier(self.bond_time or 0)
			local tier_title = pixie.bonding.get_tier_title(tier)
			local bond_str = pixie.bonding.format_bond_time(self.bond_time or 0)

			label = S("@1 [@2] (Bonded to @3)\nStatus: @4 | Health: @5/30 | Bond: @6",
				comp_name, tier_title, self.owner_name, mode_str, cur_hp, bond_str)

			if show_nametag then
				nametag_text = comp_name .. " [" .. tier_title .. "]"
			end
		else
			label = pheno.name .. " Pixie (" .. S("Wild") .. ")"
		end

		local n_color = {r = 255, g = 255, b = 255, a = 255}
		if pheno and pheno.name then
			if pheno.name == "Sunbeam" then
				n_color = {r = 255, g = 224, b = 130, a = 255}
			elseif pheno.name == "Arcane" then
				n_color = {r = 209, g = 179, b = 255, a = 255}
			elseif pheno.name == "Verdant" then
				n_color = {r = 165, g = 243, b = 165, a = 255}
			elseif pheno.name == "Glacial" then
				n_color = {r = 179, g = 229, b = 252, a = 255}
			elseif pheno.name == "Ember" then
				n_color = {r = 255, g = 171, b = 145, a = 255}
			elseif pheno.name == "Astral" then
				n_color = {r = 225, g = 190, b = 231, a = 255}
			elseif pheno.name == "Mese" then
				n_color = {r = 255, g = 255, b = 141, a = 255}
			end
		end

		local is_combat = (self._combat_timer and self._combat_timer > 0)
		local is_pointable = not (self.owner_name and is_combat)

		self.object:set_properties({
			visual_size = {x = 16.41, y = 16.41, z = 16.41},
			collide_with_objects = false,
			pointable = is_pointable,
			collisionbox = {-0.2, 0.0, -0.2, 0.2, 0.4, 0.2},
			selectionbox = is_pointable and {-0.18, 0.0, -0.18, 0.18, 0.38, 0.18} or {0, 0, 0, 0, 0, 0},
			textures = { pheno.tex },
			infotext = label,
			nametag = nametag_text,
			nametag_color = (nametag_text ~= "") and n_color or {r = 0, g = 0, b = 0, a = 0},
			nametag_bgcolor = false,
		})
	end,

	on_activate = function(self, data, _dtime_s)
		data = (type(data) == "table" and data) or {}

		self.orbit_t = math.random() * 10.0
		self.heal_timer = 0
		self.light_timer = 0
		self._anim_lock = 0
		self._wander_timer = 0
		self._wander_pause = 0
		self._orbit_dir = (math.random() < 0.5) and 1 or -1
		self._orbit_dir_timer = 5.0 + math.random() * 6.0
		self._orbit_vel = self._orbit_dir * 1.5
		self._hover_phase = math.random() * 10.0
		self._follow_factor = 0.0
		self._idle_timer = 0
		self._idle_state = "perch"
		self._idle_flank_side = (math.random() < 0.5) and 1 or -1
		self._idle_flank_fwd = 1.4
		self._idle_flank_dist = 1.05
		self._idle_flank_height = 1.7
		self._shoulder_side = (math.random() < 0.5) and 1 or -1
		self.pack_id = self.pack_id or "pixie_flock"
		self.follower_index = self.follower_index or math.random(1, 6)
		self._jitter_timer = math.random() * 10.0
		self._los_lost_timer = 0
		self._ore_scan_timer = 0.5 + math.random() * 1.5
		self._ore_cooldown = 0
		self._last_alerted_ore = nil
		self._threat_scan_timer = 0.4 + math.random() * 1.1
		self._threat_cooldown = 0
		self._threat_dart_timer = 0
		self._threat_target_pos = nil
		self._combat_timer = 0
		self._combat_threat_pos = nil
		self._swoop_heal_timer = 0

		if data.hp then
			self.hp = data.hp
		end

		if data.owner_name then
			self.owner_name = data.owner_name
			self.mode = data.mode or "follow"
			self._persistent = true
			self.custom_name = data.custom_name
			self.pixie_name = data.pixie_name
			self.show_nametag = (data.show_nametag ~= false)
			self.bond_time = data.bond_time or 0
			self.loyalty_tier = data.loyalty_tier or pixie.bonding.get_loyalty_tier(self.bond_time)
			self._recall_gen = data.recall_gen or 0
			self._companion_id = data.companion_id

			-- Multi-tier stale companion invalidation across unloaded chunks
			local is_stale = false

			-- Check 1: In-memory live active companion check
			local existing = pixie.bonding.active_player_pixies[self.owner_name]
			if existing and existing.object and existing.object:is_valid() and existing ~= self then
				is_stale = true
			end

			-- Check 2: Mod storage active companion ID & recall generation check
			if not is_stale and mod_storage then
				local active_id = mod_storage:get_string("pixie:" .. self.owner_name .. ":companion_id")
				local active_gen = mod_storage:get_int("pixie:" .. self.owner_name .. ":recall_gen")
				if active_id and active_id ~= "" and self._companion_id and self._companion_id ~= "" then
					if self._companion_id ~= active_id then
						is_stale = true
					end
				elseif active_gen > 0 and self._recall_gen < active_gen then
					is_stale = true
				end
			end

			-- Check 3: Connected player metadata check (single source of truth for online players)
			if not is_stale then
				local owner_player = core.get_player_by_name(self.owner_name)
				if owner_player and owner_player:is_valid() then
					local bdata = pixie.bonding.load_bonded_pixie(owner_player)
					if bdata then
						if bdata.companion_id and bdata.companion_id ~= "" and self._companion_id and self._companion_id ~= "" then
							if self._companion_id ~= bdata.companion_id then
								is_stale = true
							end
						elseif (bdata.recall_gen or 0) > self._recall_gen then
							is_stale = true
						elseif bdata.mode == "follow" and self.mode == "stay" then
							is_stale = true
						end
					end
				end
			end

			if is_stale then
				pixie.bonding.prune_companion_entity(self)
				return
			end

			pixie.bonding.active_player_pixies[self.owner_name] = self
		else
			self.owner_name = nil
			self.custom_name = nil
			self.pixie_name = nil
			self.show_nametag = false
			self.mode = "wild"
			self.bond_time = 0
			self.loyalty_tier = 1
			self._persistent = (data.persistent == true)
			self.factions = {pixie = true, fairy = true, neutral = true}
			self.faction_list = {"pixie", "fairy", "neutral"}
		end

		if data.guard_pos then
			self.guard_pos = data.guard_pos
		end
		if data.texture_no then
			self.texture_no = data.texture_no
		elseif not self.texture_no then
			self.texture_no = math.random(#(self.phenotypes or pixie_phenotypes))
		end
		if self.set_texture then
			self:set_texture(self.texture_no)
		end
		if data.home_pos then
			self._home_pos = data.home_pos
		end

		self:_update_properties()

		-- Wild pixies immediately take flight on spawn
		if self.mode == "wild" and self.object then
			local pos = self.object:get_pos()
			if pos then
				self._home_pos = self._home_pos or vector.round(pos)
				local init_target = pick_flight_waypoint(pos, self._home_pos, nil)
				self._wander_target = init_target
				self._wander_timer = 5.0
				local delta = vector.subtract(init_target, pos)
				local init_dir = vector.normalize(delta)
				self.object:set_velocity({
					x = init_dir.x * 1.4,
					y = 0.4,
					z = init_dir.z * 1.4,
				})
				local target_yaw = core.dir_to_yaw({x = delta.x, y = 0, z = delta.z})
				self.object:set_yaw(target_yaw)
				x_mob_core.play_animation(self.object, "fly", {speed = 1.25, loop = true, force = true})
			else
				x_mob_core.play_animation(self.object, "idle", {speed = 1.0, loop = true, force = true})
			end
		else
			x_mob_core.play_animation(self.object, "idle", {speed = 1.0, loop = true, force = true})
		end

		if self.object then
			self._sparkle_spawner_id = pixie.attach_ambient_sparkles(self.object, self.owner_name)
		end
	end,

	get_staticdata = function(self)
		if self._invalidated or self._removed or self.is_dead then
			return ""
		end
		local cur_hp = self.hp
		if not cur_hp and self.object and self.object:is_valid() then
			cur_hp = self.object:get_hp()
		end
		local tex_no = self.texture_no or 1
		local b_time = self.bond_time or 0
		local l_tier = self.loyalty_tier or pixie.bonding.get_loyalty_tier(b_time)

		return {
			owner_name = self.owner_name,
			mode = self.mode,
			guard_pos = self.guard_pos,
			bond_time = b_time,
			loyalty_tier = l_tier,
			texture_no = tex_no,
			home_pos = self._home_pos,
			hp = cur_hp or 30,
			custom_name = self.custom_name,
			pixie_name = self.pixie_name,
			show_nametag = (self.show_nametag ~= false),
			persistent = self._persistent or (self.owner_name ~= nil),
			recall_gen = self._recall_gen or 0,
			companion_id = self._companion_id,
		}
	end,

	on_punch = function(self, puncher, _time_from_last_punch, _tool_capabilities, _dir, _damage)
		if puncher and puncher:is_player() and self.owner_name then
			return true
		end

		if self.owner_name and puncher and puncher ~= self.object then
			local puncher_pos = (puncher and puncher:is_valid()) and puncher:get_pos() or nil
			pixie.signal_combat(self.owner_name, 10.0, puncher_pos)

			-- Acrobatic aerial evasion: 85% chance to dodge damage from mob melee swings
			if math.random() < 0.85 then
				local cur_v = self.object:get_velocity() or {x = 0, y = 0, z = 0}
				self.object:set_velocity({x = cur_v.x * 0.5, y = 3.5, z = cur_v.z * 0.5})
				local chosen = EVASIVE_TRICKS_COMBAT[math.random(1, #EVASIVE_TRICKS_COMBAT)]
				pixie.play_trick(self.object, chosen, {speed = 1.3, sparkles = 6, force = true})
				return true
			end
		end

		if not self.owner_name and self.factions and self.factions["players"] then
			self.factions["players"] = nil
		end

		return false
	end,

	on_hurt = function(self, puncher, _dmg)
		x_mob_core.play_animation(self.object, "hurt", {speed = 1.2, loop = false, force = true})
		self._anim_lock = 0.58
		if math.random() < 0.40 then
			self._evasive_trick_queued = true
		end

		-- Flee away from attacker if wild, staying anchored close to ground or water surface
		if not self.owner_name and puncher and puncher:is_valid() then
			local puncher_pos = puncher:get_pos()
			local pos = self.object:get_pos()
			if pos and puncher_pos then
				local flee_dir = vector.direction(puncher_pos, pos)
				local target_x = pos.x + flee_dir.x * 7.0
				local target_z = pos.z + flee_dir.z * 7.0
				local sy = get_ground_y({x = target_x, y = pos.y, z = target_z}, 30, 4, true)
				local target_y = sy and (sy + 1.5) or pos.y
				self._wander_target = {
					x = target_x,
					y = target_y,
					z = target_z,
				}
				self._wander_timer = 4.0
				self._wander_pause = 0
			end
		end
	end,

	on_death = function(self, _killer)
		-- Multiplayer Pet Griefing & Farming Defense: Tamed pixies never drop loot.
		-- Also respects server admin setting pixie_enable_drops.
		local enable_drops = (pixie.config and pixie.config.enable_drops) ~= false
		if self.owner_name or not enable_drops then
			self._drops_spawned = true
		end

		if self.owner_name then
			pixie.bonding.active_player_pixies[self.owner_name] = nil
			local owner = core.get_player_by_name(self.owner_name)
			if owner and owner:is_valid() then
				pixie.bonding.clear_bonded_pixie(owner)
			end
		end
		if self._sparkle_spawner_id then
			core.delete_particlespawner(self._sparkle_spawner_id)
			self._sparkle_spawner_id = nil
		end
		pixie.dynamic_light.clear(self)
		local pos = self.object:get_pos()
		if pos then
			pixie.spawn_death(pos)
		end
	end,

	on_deactivate = function(self, removal)
		if self._sparkle_spawner_id then
			core.delete_particlespawner(self._sparkle_spawner_id)
			self._sparkle_spawner_id = nil
		end
		pixie.dynamic_light.clear(self)
		if removal and self.owner_name and not self._invalidated and not self._removed and not self.is_dead then
			local owner = core.get_player_by_name(self.owner_name)
			if owner and owner:is_valid() then
				pixie.bonding.save_bonded_pixie(owner, self)
			end
		end
	end,

	on_rightclick = function(self, clicker)
		if not clicker or not clicker:is_player() then return end
		if (self._interact_cooldown or 0) > 0 then return end
		self._interact_cooldown = 0.35

		local player_name = clicker:get_player_name()
		local itemstack = clicker:get_wielded_item()
		local item_name = itemstack:get_name()
		local pheno_list = self.phenotypes or pixie_phenotypes
		local pheno = pheno_list[self.texture_no or 1] or pheno_list[1]
		local pos = self.object:get_pos()
		if not pos then return end

		-- Wild Taming Offering
		if not self.owner_name then
			if is_taming_food(item_name) then
				if not core.is_creative_enabled(player_name) then
					itemstack:take_item()
					clicker:set_wielded_item(itemstack)
				end

				pixie.bonding.release_companion(clicker, false)

				self.owner_name = player_name
				self.mode = "follow"
				self._persistent = true
				self.hp = 30
				self.custom_name = nil
				self.pixie_name = pheno.name .. " Pixie"
				self.show_nametag = true
				self._companion_id = x_mob_core.generate_uuid()
				self._recall_gen = 0
				pixie.bonding.active_player_pixies[player_name] = self
				self.factions = self.factions or {}
				self.factions["players"] = true

				self:_update_properties()
				pixie.bonding.save_bonded_pixie(clicker, self)

				if self._sparkle_spawner_id then
					core.delete_particlespawner(self._sparkle_spawner_id)
				end
				self._sparkle_spawner_id = pixie.attach_ambient_sparkles(self.object, self.owner_name)

				pixie.spawn_tame_burst(pos)
				x_mob_core.play_sound(self, "chime", {pos = pos})
				core.chat_send_player(player_name, S("@1 Pixie is now bonded to you!", pheno.name))
			else
				core.chat_send_player(player_name,
					S("The Pixie gazes at you timidly. Offer it a flower, honey, or mese crystal fragment!"))
			end
			return
		end

		-- Owner Interaction & Mode Cycling
		if self.owner_name == player_name then
			local ctrl = clicker:get_player_control()
			if ctrl and ctrl.sneak and not is_taming_food(item_name) then
				pixie.bonding.release_companion(clicker, true, self)
				return
			end

			-- Feeding flower to heal companion
			if is_taming_food(item_name) then
				local max_hp = 30
				local cur_hp = self.hp or max_hp
				if cur_hp < max_hp then
					local new_hp = math.min(max_hp, cur_hp + 10)
					self.hp = new_hp
					if not core.is_creative_enabled(player_name) then
						itemstack:take_item()
						clicker:set_wielded_item(itemstack)
					end
					pixie.spawn_heal(pos, 12, player_name)
					x_mob_core.play_sound(self, "chime", {pos = pos, pitch = 1.25})

					pixie.play_trick(self.object, nil, {speed = 1.2, sparkles = 6, force = true})

					core.chat_send_player(player_name, core.colorize("#88ff88",
						S("You feed a fresh treat to @1. Vitality restored to @2/@3 HP!",
							self.custom_name or self.pixie_name or (pheno.name .. " Pixie"),
							tostring(new_hp), tostring(max_hp))))
					pixie.bonding.save_bonded_pixie(clicker, self)
					self:_update_properties()
					return
				else
					pixie.play_trick(self.object, nil, {speed = 1.2, sparkles = 6, sound = true, force = true})

					core.chat_send_player(player_name, core.colorize("#ffff88",
						S("@1 happily performs a joyful trick for you! (Vitality: @2/@3 HP)",
							self.custom_name or self.pixie_name or (pheno.name .. " Pixie"),
							tostring(cur_hp), tostring(max_hp))))
					return
				end
			end

			-- Mode Cycling: follow <-> stay
			if self.mode == "follow" then
				self.mode = "stay"
				local gpos = vector.round(pos)
				self.guard_pos = gpos
				pixie.bonding.active_player_pixies[player_name] = self
				pixie.bonding.save_bonded_pixie(clicker, self)
				core.chat_send_player(player_name, core.colorize("#aaeebb",
					S("✦ Pixie will now guard at (@1, @2, @3). ✦", gpos.x, gpos.y, gpos.z)))
			else
				self.mode = "follow"
				self.guard_pos = nil
				pixie.bonding.active_player_pixies[player_name] = self
				pixie.bonding.save_bonded_pixie(clicker, self)
				core.chat_send_player(player_name, core.colorize("#aaeebb",
					S("✦ Pixie is now following you! ✦")))
			end

			self:_update_properties()
			pixie.spawn_tame_burst(pos)
			x_mob_core.play_sound(self, "chime", {pos = pos, pitch = 1.1})
		end
	end,

	on_step = function(self, dtime)
		if self._invalidated or self._removed or self.is_dead or self.state == "dying" then return end
		local pos = self.object:get_pos()
		if not pos then return end

		-- Phase 1: Solid Node De-penetration & Liquid Buoyancy
		pos = step_depenetration_and_buoyancy(self, dtime, pos)
		if not pos then return end

		self._home_pos = self._home_pos or vector.round(pos)

		-- Ensure released/wild pixies in world never retain player alliance
		if not self.owner_name and self.factions and self.factions["players"] then
			self.factions["players"] = nil
		end

		-- Prune any duplicate runtime entities for this owner immediately
		if self.owner_name then
			local canonical = pixie.bonding.active_player_pixies[self.owner_name]
			if not canonical or not canonical.object or not canonical.object:is_valid() then
				pixie.bonding.active_player_pixies[self.owner_name] = self
			elseif canonical ~= self then
				pixie.bonding.prune_companion_entity(self)
				return
			end
		end

		-- Phase 2: Timers, Cooldowns & Spontaneous Ground Acrobatics
		step_timers_and_tricks(self, dtime)

		-- Phase 3: Persistent Ambient Sparkles Attachment
		if not self._sparkle_spawner_id and self.object then
			self._sparkle_spawner_id = pixie.attach_ambient_sparkles(self.object, self.owner_name)
		end

		local owner_player = self.owner_name and core.get_player_by_name(self.owner_name)

		-- Phase 4: Companion Perks (Dynamic Light, Bond Time, Triage, Threat Radar, Ore Sensing)
		step_companion_perks(self, dtime, pos, owner_player)

		-- Phase 5: Mode Steering Target Resolution
		local anchor_pos, is_moving_fast, custom_desired_vel, custom_steer_rate, custom_target_yaw
		if self.mode == "follow" and owner_player and owner_player:is_valid() then
			anchor_pos, is_moving_fast, custom_desired_vel, custom_steer_rate, custom_target_yaw =
				step_follow_mode(self, dtime, pos, owner_player)
		elseif self.mode == "stay" then
			anchor_pos, is_moving_fast, custom_desired_vel, custom_steer_rate, custom_target_yaw =
				step_guard_mode(self, dtime, pos)
		elseif self.owner_name and (not owner_player or not owner_player:is_valid()) then
			anchor_pos, is_moving_fast, custom_desired_vel, custom_steer_rate, custom_target_yaw =
				step_wait_mode(self, dtime, pos)
		else
			anchor_pos, is_moving_fast, custom_desired_vel, custom_steer_rate, custom_target_yaw =
				step_wild_mode(self, dtime, pos)
		end

		-- Phase 6: Steering Physics, Shore Bank Climb Assist, Repulsion & Yaw Smoothing
		step_flight_steering(self, dtime, pos, anchor_pos, is_moving_fast,
			custom_desired_vel, custom_steer_rate, custom_target_yaw)
	end,
})

-- Solitary Worldwide Spawn Registration
local setting_spawn_chance = (pixie.config and pixie.config.spawn_chance) or 4200
local setting_active_count = (pixie.config and pixie.config.spawn_active_max) or 2
local setting_min_elev = (pixie.config and pixie.config.spawn_min_elevation) or 1

x_mob_core.register_spawn("pixie:pixie", {
	nodes = pixie.compat.get_spawn_nodes(),
	chance = setting_spawn_chance,
	active_object_count = setting_active_count,
	group_min = 1,
	group_max = 1,
	min_light = 5,
	max_light = 15,
	min_elevation = setting_min_elev,
	max_elevation = 31000,
})
