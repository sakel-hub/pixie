--[[
	test_combat_evasion.lua
	Automated test suite for Pixie Hybrid Combat Evasion & Tactical Perch Subsystem.
]]
-- luacheck: globals core minetest vector x_mob_core
-- luacheck: ignore 121 122 212

-- Mock minimal Luanti engine environment
local registered_on_punchplayer = {}
local registered_on_hpchange = {}
local registered_on_leaveplayer = {}
local registered_entities = {}
local registered_nodes = setmetatable({}, {__index = function() return {walkable = false} end})
local chat_messages = {}
local played_sounds = {}
local mock_player
-- Dynamic mod path resolution for portability and CI environments
local script_source = debug.getinfo(1, "S").source:sub(2)
local script_dir = script_source:match("(.*[/\\])") or "./"
local modpath = script_dir .. ".."

core = {
	settings = {
		get = function(_, key)
			if key == "pixie_combat_retreat_duration" then return "8.0" end
			return nil
		end,
		get_bool = function(_, _, default) return default end,
	},
	get_current_modname = function() return "pixie" end,
	get_modpath = function(name)
		if name == "pixie" then
			return modpath
		end
		return nil
	end,
	get_mod_storage = function()
		local store = {}
		return {
			get_string = function(_, k) return store[k] or "" end,
			set_string = function(_, k, v) store[k] = v end,
			get_int = function(_, k) return tonumber(store[k]) or 0 end,
			set_int = function(_, k, v) store[k] = v end,
		}
	end,
	register_entity = function(name, def)
		registered_entities[name] = def
	end,
	registered_entities = registered_entities,
	register_node = function(name, def)
		registered_nodes[name] = def
	end,
	swap_node = function() end,
	get_node_timer = function()
		return {
			start = function() end,
			stop = function() end,
			is_started = function() return true end,
		}
	end,
	register_on_punchplayer = function(fn)
		registered_on_punchplayer[#registered_on_punchplayer + 1] = fn
	end,
	register_on_player_hpchange = function(fn)
		registered_on_hpchange[#registered_on_hpchange + 1] = fn
	end,
	register_on_dieplayer = function() end,
	register_on_leaveplayer = function(fn)
		registered_on_leaveplayer[#registered_on_leaveplayer + 1] = fn
	end,
	register_on_shutdown = function() end,
	register_on_joinplayer = function() end,
	register_on_mods_loaded = function() end,
	register_globalstep = function() end,
	chat_send_player = function(target, msg)
		chat_messages[#chat_messages + 1] = {target = target, msg = msg}
	end,
	dir_to_yaw = function(dir)
		local atan = math.atan2 or math.atan
		return atan(-dir.x, dir.z)
	end,
	get_translator = function() return function(s) return s end end,
	colorize = function(_, text) return text end,
	register_chatcommand = function() end,
	find_nodes_in_area = function() return {} end,
	registered_nodes = registered_nodes,
	get_node_or_nil = function() return {name = "air"} end,
	get_natural_light = function() return 0 end,
	get_objects_inside_radius = function() return {} end,
	get_gametime = function() return 100 end,
	get_player_by_name = function(name)
		if mock_player and mock_player:get_player_name() == name then return mock_player end
		return nil
	end,
	get_connected_players = function() return mock_player and {mock_player} or {} end,
	line_of_sight = function() return true end,
	serialize = function() return "" end,
	deserialize = function() return {} end,
	log = function() end,
}
minetest = core

vector = {
	distance = function(a, b)
		local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
		return math.sqrt(dx * dx + dy * dy + dz * dz)
	end,
	subtract = function(a, b)
		return {x = a.x - b.x, y = a.y - b.y, z = a.z - b.z}
	end,
	add = function(a, b)
		return {x = a.x + b.x, y = a.y + b.y, z = a.z + b.z}
	end,
	multiply = function(a, s)
		return {x = a.x * s, y = a.y * s, z = a.z * s}
	end,
	length = function(a)
		return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
	end,
	direction = function(from, to)
		local d = {x = to.x - from.x, y = to.y - from.y, z = to.z - from.z}
		local len = math.sqrt(d.x * d.x + d.y * d.y + d.z * d.z)
		if len == 0 then return {x = 0, y = 0, z = 0} end
		return {x = d.x / len, y = d.y / len, z = d.z / len}
	end,
	dot = function(a, b)
		return a.x * b.x + a.y * b.y + a.z * b.z
	end,
	round = function(v)
		return {x = math.floor(v.x + 0.5), y = math.floor(v.y + 0.5), z = math.floor(v.z + 0.5)}
	end,
	equals = function(a, b)
		return a and b and a.x == b.x and a.y == b.y and a.z == b.z
	end,
	normalize = function(v)
		local l = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
		if l == 0 then return {x = 0, y = 0, z = 0} end
		return {x = v.x / l, y = v.y / l, z = v.z / l}
	end,
}

-- Mock x_mob_core
local listeners = {}
local registered_spawns = {}
x_mob_core = {
	register_mob = function(name, def)
		registered_entities[name] = def
	end,
	register_spawn = function(name, def)
		registered_spawns[name] = def
	end,
	listen = function(event, fn)
		listeners[event] = listeners[event] or {}
		table.insert(listeners[event], fn)
	end,
	emit = function(event, ...)
		if listeners[event] then
			for _, fn in ipairs(listeners[event]) do
				fn(...)
			end
		end
	end,
	play_sound = function(_, name, params)
		played_sounds[#played_sounds + 1] = {name = name, params = params}
	end,
	play_animation = function() end,
	avoid_solid_nodes = function(pos) return pos end,
	handle_punch = function() return false end,
	get_ground_y = function(pos) return pos.y - 1 end,
	get_headroom = function() return 4.0 end,
	calculate_repulsion = function() return 0, 0, 0 end,
	generate_uuid = function() return "mock-uuid-1234" end,
	spawn_mob = function() return nil, nil end,
	utils = {
		is_walkable_node = function() return false end,
		is_passable_node = function() return true end,
	},
}

-- Load pixie subsystems
dofile(modpath .. "/api.lua")

-- Stub particle and dynamic light helpers
pixie.spawn_sparkles = function() end
pixie.attach_ambient_sparkles = function() return 1 end
pixie.spawn_heal = function() end
pixie.spawn_guidance_beacon = function() end
pixie.spawn_tame_burst = function() end
pixie.spawn_death = function() end
pixie.spawn_guardian_sacrifice = function() end
pixie.spawn_whistle_melody = function() end
dofile(modpath .. "/dynamic_light.lua")
pixie.ore_sensor = {can_scan = function() return false end, cache = {recent_alerts = {}}}

dofile(modpath .. "/compat/init.lua")
dofile(modpath .. "/bonding.lua")
dofile(modpath .. "/entities.lua")

print("========== RUNNING PIXIE COMBAT EVASION TEST SUITE ==========")

-- Create mock player
local player_pos = {x = 100, y = 10, z = 100}
mock_player = {
	is_player = function() return true end,
	is_valid = function() return true end,
	get_player_name = function() return "SaKeL" end,
	get_pos = function() return {x = player_pos.x, y = player_pos.y, z = player_pos.z} end,
	get_hp = function() return 20 end,
	set_hp = function() end,
	get_velocity = function() return {x = 0, y = 0, z = 0} end,
	get_look_dir = function() return {x = 0, y = 0, z = 1} end, -- Looking North (+Z)
	get_look_horizontal = function() return 0 end,
	get_wielded_item = function()
		return {
			get_name = function() return "" end,
			is_empty = function() return true end,
		}
	end,
	get_meta = function()
		return {
			set_string = function() end,
			get_string = function() return "" end,
		}
	end,
}

-- Create mock companion ObjectRef and LuaEntity
local companion_props = {}
local comp_pos = {x = 100, y = 11.5, z = 99}
local comp_vel = {x = 0, y = 0, z = 0}
local mock_obj = {
	is_player = function() return false end,
	is_valid = function() return true end,
	get_pos = function() return {x = comp_pos.x, y = comp_pos.y, z = comp_pos.z} end,
	set_pos = function(_, p) comp_pos = p end,
	get_velocity = function() return comp_vel end,
	set_velocity = function(_, v) comp_vel = v end,
	set_properties = function(_, props)
		for k, v in pairs(props) do
			companion_props[k] = v
		end
	end,
	set_yaw = function() end,
	get_yaw = function() return 0 end,
	get_luaentity = function(self) return self.ent end,
	remove = function() end,
}

local pixie_def = registered_entities["pixie:pixie"]
assert(pixie_def, "Error: pixie:pixie definition not registered!")

local comp_ent = {
	object = mock_obj,
	name = "pixie:pixie",
	owner_name = "SaKeL",
	mode = "follow",
	bond_time = 2000,
	loyalty_tier = 2,
	hp = 30,
	orbit_t = 0,
	_follow_factor = 0.0,
	_shoulder_side = 1,
}
mock_obj.ent = comp_ent
setmetatable(comp_ent, {__index = pixie_def})
comp_ent:on_activate({owner_name = "SaKeL", mode = "follow", hp = 30}, 0)
comp_ent.owner_name = "SaKeL"
pixie.bonding.active_player_pixies["SaKeL"] = comp_ent

-- Test 1: Baseline peaceful state
assert(comp_ent._combat_timer == 0, "Test 1 Failed: Combat timer should be 0 initially")
comp_ent:_update_properties()
assert(companion_props.pointable == true, "Test 1 Failed: Companion should be pointable in peaceful state")

-- Test 2: Signal combat directly via API
local signaled = pixie.signal_combat("SaKeL", 8.0, {x = 100, y = 10, z = 110})
assert(signaled == true, "Test 2 Failed: pixie.signal_combat should return true")
assert(comp_ent._combat_timer == 8.0, "Test 2 Failed: _combat_timer should be 8.0")
assert(comp_ent._combat_threat_pos and comp_ent._combat_threat_pos.z == 110, "Test 2 Failed: threat pos not recorded")

comp_ent:_update_properties()
assert(companion_props.pointable == false, "Test 2 Failed: Companion should NOT be pointable in combat state!")
assert(companion_props.selectionbox[1] == 0 and companion_props.selectionbox[4] == 0,
	"Test 2 Failed: Selectionbox should be zeroed out in combat to prevent attack blocking")

-- Test 3: Engine punch hook (core.register_on_punchplayer)
comp_ent._combat_timer = 0
assert(#registered_on_punchplayer > 0, "Test 3 Failed: on_punchplayer hook not registered")
local mock_mob_obj = {
	is_valid = function() return true end,
	is_player = function() return false end,
	get_pos = function() return {x = 100, y = 10, z = 108} end,
}
registered_on_punchplayer[1](mock_player, mock_mob_obj)
assert(comp_ent._combat_timer == 8.0, "Test 3 Failed: on_punchplayer should trigger combat timer")

-- Test 4: Verify passive target scan (on_mob_target) does not trigger for distant mobs (>12m),
-- but triggers for close threats (<=12m)
comp_ent._combat_timer = 0
local mock_distant_mob_obj = {
	is_valid = function() return true end,
	is_player = function() return false end,
	get_pos = function() return {x = 100, y = 10, z = 125} end, -- 25m away (>12m)
}
x_mob_core.emit("on_mob_target", {object = mock_distant_mob_obj}, mock_player)
assert(comp_ent._combat_timer == 0, "Test 4 Failed: distant on_mob_target should not trigger combat timer")

x_mob_core.emit("on_mob_target", {object = mock_mob_obj}, mock_player) -- 8m away (<=12m)
assert(comp_ent._combat_timer == 8.0, "Test 4 Failed: close on_mob_target should trigger combat timer")
comp_ent._combat_timer = 0

-- Test 5: x_mob_core Pub-Sub on_mob_hurt hook (player strikes mob)
comp_ent._combat_timer = 0
x_mob_core.emit("on_mob_hurt", {object = mock_mob_obj}, mock_player, 5)
assert(comp_ent._combat_timer == 8.0, "Test 5 Failed: on_mob_hurt should trigger combat timer")

-- Test 6: Companion self-defense evasion on mob hit
local mob_punched = comp_ent:on_punch(mock_mob_obj, 1.0, {}, {x = 0, y = 0, z = 1}, 5)
assert(comp_ent._combat_timer >= 8.0, "Test 6 Failed: on_punch by mob should refresh combat timer")
print(string.format("Test 6: Mob punched pixie -> combat timer active (%.1fs), dodge result: %s",
	comp_ent._combat_timer, tostring(mob_punched)))

-- Test 7: Tactical Combat Anchor Geometry (Rear High Perch)
comp_ent._combat_timer = 8.0
comp_ent._follow_factor = 0.0

local look_dir = mock_player:get_look_dir()
local lhx, lhz = look_dir.x, look_dir.z
local perp_x, perp_z = -lhz, lhx
local retreat_dist = 1.2
local perch_y = player_pos.y + 2.75
local shoulder_side = comp_ent._shoulder_side or 1
local raw_anchor = {
	x = player_pos.x - lhx * retreat_dist + perp_x * 0.45 * shoulder_side,
	y = perch_y,
	z = player_pos.z - lhz * retreat_dist + perp_z * 0.45 * shoulder_side,
}

local to_anchor_h = {x = raw_anchor.x - player_pos.x, y = 0, z = raw_anchor.z - player_pos.z}
local dot_with_look = to_anchor_h.x * look_dir.x + to_anchor_h.z * look_dir.z

assert(dot_with_look < -1.0, "Test 7 Failed: Anchor must be strictly BEHIND the player! dot=" .. dot_with_look)
assert(raw_anchor.y >= player_pos.y + 2.5, "Test 7 Failed: Anchor must be elevated above 2.5m! y=" .. raw_anchor.y)
print(string.format("Test 7: Anchor Geometry Verified: Anchor is at (%.2f, %.2f, %.2f) behind player facing North.",
	raw_anchor.x, raw_anchor.y, raw_anchor.z))

-- Test 8: Combat timer decay and peaceful restore
comp_ent._combat_timer = 0.1
comp_ent:on_step(0.2)
assert(comp_ent._combat_timer == 0, "Test 8 Failed: Combat timer should expire to 0")
comp_ent:_update_properties()
assert(companion_props.pointable == true, "Test 8 Failed: Peaceful companion should become pointable again")

-- Test 9: Custom Elevation Preservation when player stops
-- Simulate active follow flight first
comp_ent._combat_timer = 0
comp_ent._follow_factor = 1.0
comp_ent:on_step(0.1)
comp_pos.x = comp_pos.x + comp_vel.x * 0.1
comp_pos.y = comp_pos.y + comp_vel.y * 0.1
comp_pos.z = comp_pos.z + comp_vel.z * 0.1
assert(comp_ent._preserved_flight_elevation >= 1.65, "Test 9 Failed: Preserved flight elevation must be >= 1.65m while following")

-- Player now stops moving (simulate 20 physics steps with stationary player)
comp_ent._follow_factor = 0.0
for _ = 1, 20 do
	comp_ent:on_step(0.05)
	comp_pos.x = comp_pos.x + comp_vel.x * 0.05
	comp_pos.y = comp_pos.y + comp_vel.y * 0.05
	comp_pos.z = comp_pos.z + comp_vel.z * 0.05
end
assert(comp_pos.y >= player_pos.y + 1.65, string.format("Test 9 Failed: Pixie must keep elevation when player stops! Got y=%.2f, player_pos.y=%.2f", comp_pos.y, player_pos.y))
print(string.format("Test 9: Stationary Elevation Preservation Verified: Pixie position is at y=%.2f (>= %.2f).", comp_pos.y, player_pos.y + 1.65))

-- Test 9b: Assertive Vertical Restitution when dropped near ground
comp_pos = {x = player_pos.x, y = player_pos.y + 0.2, z = player_pos.z - 1.0}
comp_vel = {x = 0, y = 0, z = 0}
for _ = 1, 25 do
	comp_ent:on_step(0.05)
	comp_pos.x = comp_pos.x + comp_vel.x * 0.05
	comp_pos.y = comp_pos.y + comp_vel.y * 0.05
	comp_pos.z = comp_pos.z + comp_vel.z * 0.05
end
assert(comp_pos.y >= player_pos.y + 1.65, string.format("Test 9b Failed: Pixie must actively climb from ground to elevation! Got y=%.2f", comp_pos.y))
print(string.format("Test 9b: Restorative Ground Climb Verified: Ascended from ground to y=%.2f.", comp_pos.y))

-- Test 10: Flower inspection idle state maintains elevation floor
comp_ent._idle_timer = 2.0
comp_ent._idle_state = "flower"
comp_ent._idle_target_pos = {x = player_pos.x + 2, y = player_pos.y, z = player_pos.z + 2} -- ground flora at player feet
comp_ent:on_step(0.1)
assert(comp_ent._idle_target_pos.y >= player_pos.y + 1.65, "Test 10 Failed: Flower idle elevation must not sink below player elevation!")
print(string.format("Test 10: Flower Inspection Elevation Floor Verified: Target y=%.2f.", comp_ent._idle_target_pos.y))

-- Test 11: Verify pixie mob registration flags for x_mob_core pipeline isolation, elevation, and health_regen
assert(pixie_def.melee == false, "Test 11 Failed: melee must be false in pixie definition")
assert(pixie_def.shooter == false, "Test 11 Failed: shooter must be false in pixie definition")
assert(pixie_def.auto_scan == false, "Test 11 Failed: auto_scan must be false in pixie definition")
assert(pixie_def.can_attack == false, "Test 11 Failed: can_attack must be false in pixie definition")
assert(pixie_def.flight_elevation == 1.85, "Test 11 Failed: flight_elevation must be 1.85")
assert(pixie_def.hover_offset == 1.85, "Test 11 Failed: hover_offset must be 1.85")
assert(pixie_def.combat_hover_offset == 1.85, "Test 11 Failed: combat_hover_offset must be 1.85")
assert(pixie_def.health_regen and pixie_def.health_regen.rate == 0.5 and pixie_def.health_regen.passive == true,
	"Test 11 Failed: passive health_regen must be configured")
assert(pixie_def.health_regen.can_flee == false, "Test 11 Failed: health_regen.can_flee must be false")
print("Test 11: Mob Registration Pipeline Isolation Flags, Flight Elevation & Health Regen Verified.")

-- Test 12: Wild Pixie single-punch delegation (on_punch returns false) & on_hurt flee behavior
local wild_ent = {
	object = mock_obj,
	name = "pixie:pixie",
	mode = "wild",
	hp = 30,
	factions = {pixie = true, fairy = true, neutral = true, players = true},
}
setmetatable(wild_ent, {__index = pixie_def})
local punch_handled = wild_ent:on_punch(mock_player, 1.0, {}, {x = 0, y = 0, z = 1}, 5)
assert(punch_handled == false, "Test 12 Failed: Wild pixie on_punch must return false to delegate to x_mob_core")
assert(wild_ent.factions["players"] == nil, "Test 12 Failed: Wild pixie must strip players faction on punch")
wild_ent:on_hurt(mock_player, 5)
assert(wild_ent._anim_lock == 0.58, "Test 12 Failed: on_hurt must set _anim_lock = 0.58")
assert(wild_ent._wander_target ~= nil and wild_ent._wander_timer == 4.0, "Test 12 Failed: Wild pixie must flee on_hurt")
print("Test 12: Wild Pixie Single-Punch Delegation & on_hurt Flee Verified.")

-- Test 13: Celebration API trigger
local celebrated = pixie.trigger_celebration(comp_ent)
assert(celebrated == true, "Test 13 Failed: pixie.trigger_celebration must return true for valid companion")
print("Test 13: Mining Celebration Trigger API Verified.")

-- Test 14: Spawning Configuration & Multi-Game Walkable Surfaces
local spawn_def = registered_spawns["pixie:pixie"]
assert(spawn_def ~= nil, "Test 14 Failed: pixie:pixie must be registered for natural spawning")
assert(spawn_def.chance == 4200, "Test 14 Failed: default spawn chance must be 4200")
assert(spawn_def.active_object_count == 2, "Test 14 Failed: active_object_count must be 2")
assert(spawn_def.min_elevation == 1, "Test 14 Failed: min_elevation must be 1")
assert(spawn_def.max_elevation == 31000, "Test 14 Failed: max_elevation must be 31000")
assert(spawn_def.min_light == 5 and spawn_def.max_light == 15, "Test 14 Failed: light bounds must be 5 to 15")

local spawn_nodes = pixie.compat.get_spawn_nodes()
local node_set = {}
for _, n in ipairs(spawn_nodes) do
	node_set[n] = true
end
assert(node_set["default:dirt_with_grass"] == true, "Test 14 Failed: MTG dirt_with_grass missing")
assert(node_set["ethereal:green_dirt"] == true, "Test 14 Failed: Ethereal green_dirt missing")
assert(node_set["mcl_core:dirt_with_grass"] == true, "Test 14 Failed: MCL dirt_with_grass missing")
assert(node_set["mcl_core:podzol"] == true, "Test 14 Failed: MCL podzol missing")
assert(node_set["everness:crystal_grass"] == true, "Test 14 Failed: Everness crystal_grass missing")
assert(node_set["group:flora"] == nil, "Test 14 Failed: non-walkable group:flora must be excluded from spawn nodes")
assert(node_set["mcl_flowers:poppy"] == nil, "Test 14 Failed: non-walkable mcl_flowers:poppy must be excluded from spawn nodes")
print("Test 14: Spawning Configuration & Multi-Game Walkable Surfaces Verified.")

-- Test 15: Balanced Drops & Tamed Pet Drop Suppression
local drops = pixie.compat.get_drops()
for _, drop in ipairs(drops) do
	assert(drop.name ~= "default:diamond", "Test 15 Failed: Diamonds must not drop from pixies")
	assert(drop.name ~= "mcl_core:diamond", "Test 15 Failed: Diamonds must not drop from pixies")
	assert(drop.name ~= "everness:crystal_emerald", "Test 15 Failed: Emeralds must not drop from pixies")
end

-- Tamed companion death must set _drops_spawned = true to suppress drops
local tamed_death_ent = {
	object = mock_obj,
	name = "pixie:pixie",
	owner_name = "TestPlayer",
	mode = "follow",
	hp = 0,
}
setmetatable(tamed_death_ent, {__index = pixie_def})
tamed_death_ent:on_death(mock_player)
assert(tamed_death_ent._drops_spawned == true, "Test 15 Failed: Tamed companion must suppress drops on death")

-- Wild pixie death must NOT suppress drops by default
local wild_death_ent = {
	object = mock_obj,
	name = "pixie:pixie",
	owner_name = nil,
	mode = "wild",
	hp = 0,
}
setmetatable(wild_death_ent, {__index = pixie_def})
wild_death_ent:on_death(mock_player)
assert(wild_death_ent._drops_spawned == nil, "Test 15 Failed: Wild pixie must not suppress drops on death")

print("Test 15: Balanced Drops & Tamed Pet Drop Suppression Verified.")

-- Test 16: Threat Cache Pruning & Player Leave Cleanup
local now = core.get_gametime()
pixie.threat_cache.recent_alerts["expired_threat"] = now - 5
pixie.threat_cache.recent_alerts["active_threat"] = now + 15
pixie.threat_cache._last_prune = now - 20

local perk_ent = {
	object = mock_obj,
	name = "pixie:pixie",
	owner_name = "SaKeL",
	mode = "follow",
	bond_time = 2000,
	loyalty_tier = 2,
	_threat_scan_timer = 0,
	_threat_cooldown = 0,
}
setmetatable(perk_ent, {__index = pixie_def})
mock_obj.ent = perk_ent
pixie.bonding.active_player_pixies["SaKeL"] = perk_ent
perk_ent:on_step(0.1)

assert(pixie.threat_cache.recent_alerts["expired_threat"] == nil, "Test 16 Failed: expired threat alert must be pruned")
assert(pixie.threat_cache.recent_alerts["active_threat"] ~= nil, "Test 16 Failed: active threat alert must remain")

pixie.threat_cache.player_scans["LeavingPlayer"] = {
	time = now,
	pos = {x = 10, y = 5, z = 10},
	threats = {},
}
local mock_leaving_player = {
	is_player = function() return true end,
	is_valid = function() return true end,
	get_player_name = function() return "LeavingPlayer" end,
}
for _, fn in ipairs(registered_on_leaveplayer) do
	fn(mock_leaving_player)
end
assert(pixie.threat_cache.player_scans["LeavingPlayer"] == nil, "Test 16 Failed: player_scans must be cleared on leaveplayer")
print("Test 16: Threat Cache Pruning & Player Leave Cleanup Verified.")

-- Test 17: Dynamic Light Timer Defensive Object Handling
local light_node = registered_nodes["pixie:light"]
assert(light_node ~= nil, "Test 17 Failed: pixie:light must be registered")
assert(type(light_node.on_timer) == "function", "Test 17 Failed: pixie:light must have on_timer handler")

local timer_res1 = light_node.on_timer({x = 0, y = 0, z = 0})
assert(timer_res1 == false, "Test 17 Failed: on_timer must return false when no pixie is nearby")

local old_get_objs = core.get_objects_inside_radius
core.get_objects_inside_radius = function()
	return {
		mock_player,
		{ is_valid = function() return false end },
		{ is_valid = function() return true end, is_player = function() return false end, get_luaentity = function() return nil end },
	}
end
local timer_res2 = light_node.on_timer({x = 0, y = 0, z = 0})
assert(timer_res2 == false, "Test 17 Failed: on_timer must safely handle players and invalid objects without error")

core.get_objects_inside_radius = function()
	return {
		{
			is_valid = function() return true end,
			is_player = function() return false end,
			get_luaentity = function() return { name = "pixie:pixie" } end,
		}
	}
end
local timer_res3 = light_node.on_timer({x = 0, y = 0, z = 0})
assert(timer_res3 == true, "Test 17 Failed: on_timer must return true when valid pixie is inside radius")
core.get_objects_inside_radius = old_get_objs
print("Test 17: Dynamic Light Timer Defensive Object Handling Verified.")

-- Test 18: Integer Coordinates in Area Queries & Utils
assert(pixie.utils.floor_vector({x = 10.74, y = 5.22, z = -14.88}).x == 10, "Test 18 Failed: floor_vector x mismatch")
assert(pixie.utils.floor_vector({x = 10.74, y = 5.22, z = -14.88}).y == 5, "Test 18 Failed: floor_vector y mismatch")
assert(pixie.utils.floor_vector({x = 10.74, y = 5.22, z = -14.88}).z == -15, "Test 18 Failed: floor_vector z mismatch")

local recorded_minp, recorded_maxp
local old_find_nodes = core.find_nodes_in_area
core.find_nodes_in_area = function(minp, maxp)
	recorded_minp = minp
	recorded_maxp = maxp
	return {}
end

local wild_waypoint_ent = {
	object = mock_obj,
	name = "pixie:pixie",
	mode = "wild",
	_home_pos = {x = 10.5, y = 5.5, z = 10.5},
	_wander_timer = 0,
	orbit_t = 0,
}
setmetatable(wild_waypoint_ent, {__index = pixie_def})
for _ = 1, 30 do
	wild_waypoint_ent:on_step(0.1)
	if recorded_minp then
		break
	end
end
if recorded_minp and recorded_maxp then
	assert(recorded_minp.x == math.floor(recorded_minp.x), "Test 18 Failed: minp.x must be integer")
	assert(recorded_minp.y == math.floor(recorded_minp.y), "Test 18 Failed: minp.y must be integer")
	assert(recorded_minp.z == math.floor(recorded_minp.z), "Test 18 Failed: minp.z must be integer")
	assert(recorded_maxp.x == math.floor(recorded_maxp.x), "Test 18 Failed: maxp.x must be integer")
	assert(recorded_maxp.y == math.floor(recorded_maxp.y), "Test 18 Failed: maxp.y must be integer")
	assert(recorded_maxp.z == math.floor(recorded_maxp.z), "Test 18 Failed: maxp.z must be integer")
end
core.find_nodes_in_area = old_find_nodes
print("Test 18: Integer Coordinates in Area Queries & Utils Verified.")

-- Test 19: Centralized Configuration Registry & Hostile State Detection
assert(type(pixie.config) == "table", "Test 19 Failed: pixie.config must exist")
assert(pixie.config.loyalty_tier2_time == 1200, "Test 19 Failed: default tier2 time mismatch")
assert(pixie.config.loyalty_tier3_time == 3600, "Test 19 Failed: default tier3 time mismatch")
assert(pixie.config.whistle_durability == 30, "Test 19 Failed: default whistle durability mismatch")
assert(pixie.config.combat_retreat_duration == 8.0, "Test 19 Failed: default combat retreat duration mismatch")
assert(pixie.config.spawn_chance == 4200, "Test 19 Failed: default spawn chance mismatch")
assert(pixie.config.spawn_active_max == 2, "Test 19 Failed: default spawn active max mismatch")
assert(pixie.config.spawn_min_elevation == 1, "Test 19 Failed: default spawn min elevation mismatch")
assert(pixie.config.show_nametags == true, "Test 19 Failed: default show_nametags mismatch")
assert(pixie.config.enable_drops == true, "Test 19 Failed: default enable_drops mismatch")

assert(pixie.utils.dist_sq({x = 1, y = 2, z = 3}, {x = 4, y = 2, z = 7}) == 25, "Test 19 Failed: dist_sq mismatch")

local dying_mob_obj = {
	is_valid = function() return true end,
	is_player = function() return false end,
	get_hp = function() return 10 end,
	get_luaentity = function()
		return {
			name = "mobs_monster:dungeon_master",
			hp = 10,
			state = "dying",
			type = "monster",
		}
	end,
}
local is_threat1, _ = pixie.compat.is_hostile(dying_mob_obj, mock_player)
assert(is_threat1 == false, "Test 19 Failed: Dying mob must not be flagged as active hostile threat")

local dead_flag_mob_obj = {
	is_valid = function() return true end,
	is_player = function() return false end,
	get_hp = function() return 10 end,
	get_luaentity = function()
		return {
			name = "mobs_monster:dungeon_master",
			hp = 10,
			is_dead = true,
			type = "monster",
		}
	end,
}
local is_threat2, _ = pixie.compat.is_hostile(dead_flag_mob_obj, mock_player)
assert(is_threat2 == false, "Test 19 Failed: Mob with is_dead == true must not be flagged as active hostile threat")
print("Test 19: Centralized Configuration Registry & Hostile State Detection Verified.")

-- Test 20: Comprehensive False Positive Prevention & Mob Validation
-- 1. Status Effect Envelop (x_mob_core:envelop) targeting player
local envelop_obj = {
	is_valid = function() return true end,
	is_player = function() return false end,
	get_hp = function() return 1 end,
	get_attach = function() return mock_player end,
	get_luaentity = function()
		return {
			name = "x_mob_core:envelop",
			_is_envelop = true,
			target = mock_player,
			effects = { test_freeze = { timer = 5.0 } },
		}
	end,
}
local env_threat, _ = pixie.compat.is_hostile(envelop_obj, mock_player)
assert(env_threat == false, "Test 20 Failed: Envelop attached to player must not be flagged as hostile")

-- Detached / mob-attached envelop
local detached_envelop = {
	is_valid = function() return true end,
	is_player = function() return false end,
	get_hp = function() return 1 end,
	get_attach = function() return nil end,
	get_luaentity = function()
		return {
			name = "x_mob_core:envelop",
			_is_envelop = true,
			target = mock_player,
		}
	end,
}
local env_threat2, _ = pixie.compat.is_hostile(detached_envelop, mock_player)
assert(env_threat2 == false, "Test 20 Failed: Detached envelop entity targeting player must not be flagged as hostile")

-- 2. 3D Health Bar entity
local health_bar_obj = {
	is_valid = function() return true end,
	is_player = function() return false end,
	get_hp = function() return 1 end,
	get_attach = function() return nil end,
	get_luaentity = function()
		return {
			name = "x_mob_core:health_bar",
			_is_visual = true,
			_is_health_bar = true,
		}
	end,
}
local hb_threat, _ = pixie.compat.is_hostile(health_bar_obj, mock_player)
assert(hb_threat == false, "Test 20 Failed: Health bar entity must not be flagged as hostile")

-- 3. Projectiles carrying hostile mob factions (e.g. Suture Golem Bile, Frost Shard)
local projectile_obj = {
	is_valid = function() return true end,
	is_player = function() return false end,
	get_hp = function() return 1 end,
	get_attach = function() return nil end,
	get_luaentity = function()
		return {
			name = "x_mobs:suture_golem_bile",
			_is_projectile = true,
			_is_arrow = true,
			factions = { "undead", "golem", "subterranean" },
		}
	end,
}
local proj_threat, _ = pixie.compat.is_hostile(projectile_obj, mock_player)
assert(proj_threat == false, "Test 20 Failed: Projectile with hostile factions must not be flagged as hostile mob")

-- 4. Visual proxy, armor mesh, wielditem, and corpses
local armor_corpse_obj = {
	is_valid = function() return true end,
	is_player = function() return false end,
	get_hp = function() return 1 end,
	get_attach = function() return nil end,
	get_luaentity = function()
		return {
			name = "x_player_armor:corpse",
			_is_corpse = true,
			_is_x_player_armor = true,
			_is_visual = true,
		}
	end,
}
local corpse_threat, _ = pixie.compat.is_hostile(armor_corpse_obj, mock_player)
assert(corpse_threat == false, "Test 20 Failed: Armor corpse entity must not be flagged as hostile mob")

-- 5. Dropped item and falling node
local item_obj = {
	is_valid = function() return true end,
	is_player = function() return false end,
	get_hp = function() return 1 end,
	get_attach = function() return nil end,
	get_luaentity = function()
		return {
			name = "__builtin:item",
			itemstring = "default:apple",
		}
	end,
}
local item_threat, _ = pixie.compat.is_hostile(item_obj, mock_player)
assert(item_threat == false, "Test 20 Failed: Builtin dropped item must not be flagged as hostile mob")

-- 6. Generic object attached to player
local attached_gear_obj = {
	is_valid = function() return true end,
	is_player = function() return false end,
	get_hp = function() return 1 end,
	get_attach = function() return mock_player end,
	get_luaentity = function()
		return {
			name = "custom_mod:backpack",
		}
	end,
}
local gear_threat, _ = pixie.compat.is_hostile(attached_gear_obj, mock_player)
assert(gear_threat == false, "Test 20 Failed: Object attached to owner_player must not be flagged as hostile mob")

-- 7. Neutral / retaliatory farm animals (Cow, Panda, Kitten)
local cow_obj = {
	is_valid = function() return true end,
	is_player = function() return false end,
	get_hp = function() return 20 end,
	get_attach = function() return nil end,
	get_luaentity = function()
		return {
			name = "mobs_animal:cow",
			type = "animal",
			passive = false,
			attack_type = "dogfight",
		}
	end,
}
local cow_threat, _ = pixie.compat.is_hostile(cow_obj, mock_player)
assert(cow_threat == false, "Test 20 Failed: Peaceful unprovoked cow must not be flagged as hostile mob")

local kitten_obj = {
	is_valid = function() return true end,
	is_player = function() return false end,
	get_hp = function() return 10 end,
	get_attach = function() return nil end,
	get_luaentity = function()
		return {
			name = "mobs_animal:kitten",
			type = "animal",
			passive = false,
			attack_players = false,
			attack_type = "dogfight",
		}
	end,
}
local kitten_threat, _ = pixie.compat.is_hostile(kitten_obj, mock_player)
assert(kitten_threat == false, "Test 20 Failed: Kitten must not be flagged as hostile mob")

-- 8. Provoked animal actively attacking player
local provoked_cow_obj = {
	is_valid = function() return true end,
	is_player = function() return false end,
	get_hp = function() return 20 end,
	get_attach = function() return nil end,
	get_luaentity = function()
		return {
			name = "mobs_animal:cow",
			type = "animal",
			passive = false,
			attack_type = "dogfight",
			attack = mock_player,
		}
	end,
}
local prov_threat, prov_name = pixie.compat.is_hostile(provoked_cow_obj, mock_player)
assert(prov_threat == true, "Test 20 Failed: Provoked cow attacking player must be flagged as threat")
assert(prov_name == "Cow", "Test 20 Failed: Provoked cow title mismatch")

-- 9. Player's tamed pet
local pet_obj = {
	is_valid = function() return true end,
	is_player = function() return false end,
	get_hp = function() return 25 end,
	get_attach = function() return nil end,
	get_luaentity = function()
		return {
			name = "animalia:wolf",
			owner = mock_player:get_player_name(),
			tamed = true,
		}
	end,
}
local pet_threat, _ = pixie.compat.is_hostile(pet_obj, mock_player)
assert(pet_threat == false, "Test 20 Failed: Player's tamed pet must not be flagged as hostile threat")

-- 10. Legitimate Hostile Monsters from x_mobs and mobs_monster
local suture_golem_obj = {
	is_valid = function() return true end,
	is_player = function() return false end,
	get_hp = function() return 120 end,
	get_attach = function() return nil end,
	get_luaentity = function()
		return {
			name = "x_mobs:suture_golem",
			factions = { "undead", "golem", "subterranean" },
		}
	end,
}
local golem_threat, golem_title = pixie.compat.is_hostile(suture_golem_obj, mock_player)
assert(golem_threat == true, "Test 20 Failed: Suture Golem must be flagged as hostile monster")
assert(golem_title == "Suture Golem", "Test 20 Failed: Suture Golem title mismatch, got: " .. tostring(golem_title))

local dm_obj = {
	is_valid = function() return true end,
	is_player = function() return false end,
	get_hp = function() return 40 end,
	get_attach = function() return nil end,
	get_luaentity = function()
		return {
			name = "mobs_monster:dungeon_master",
			type = "monster",
			attack_type = "dogfight",
		}
	end,
}
local dm_threat, dm_title = pixie.compat.is_hostile(dm_obj, mock_player)
assert(dm_threat == true, "Test 20 Failed: Dungeon Master must be flagged as hostile monster")
assert(dm_title == "Dungeon Master", "Test 20 Failed: Dungeon Master title mismatch")
print("Test 20: Comprehensive False Positive Prevention & Mob Validation Verified.")

print("========== ALL TESTS PASSED SUCCESSFULLY! ==========")
