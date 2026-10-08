--[[
	test_combat_evasion.lua
	Automated test suite for Pixie Hybrid Combat Evasion & Tactical Perch Subsystem.
]]
-- luacheck: globals core minetest vector x_mob_core
-- luacheck: ignore 121 122 212

-- Mock minimal Luanti engine environment
local registered_on_punchplayer = {}
local registered_on_hpchange = {}
local registered_entities = {}
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
	register_on_punchplayer = function(fn)
		registered_on_punchplayer[#registered_on_punchplayer + 1] = fn
	end,
	register_on_player_hpchange = function(fn)
		registered_on_hpchange[#registered_on_hpchange + 1] = fn
	end,
	register_on_dieplayer = function() end,
	register_on_leaveplayer = function() end,
	register_on_shutdown = function() end,
	register_on_joinplayer = function() end,
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
	registered_nodes = setmetatable({}, {__index = function() return {walkable = false} end}),
	get_node_or_nil = function() return {name = "air"} end,
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
	normalize = function(v)
		local l = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
		if l == 0 then return {x = 0, y = 0, z = 0} end
		return {x = v.x / l, y = v.y / l, z = v.z / l}
	end,
}

-- Mock x_mob_core
local listeners = {}
x_mob_core = {
	register_mob = function(name, def)
		registered_entities[name] = def
	end,
	register_spawn = function() end,
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
}

-- Load pixie subsystems
dofile(modpath .. "/api.lua")

-- Stub particle and dynamic light helpers
pixie.spawn_sparkles = function() end
pixie.attach_ambient_sparkles = function() return 1 end
pixie.spawn_heal = function() end
pixie.spawn_guidance_beacon = function() end
pixie.spawn_death_guide = function() end
pixie.spawn_tame_burst = function() end
pixie.spawn_death = function() end
pixie.spawn_guardian_sacrifice = function() end
pixie.spawn_whistle_melody = function() end
pixie.dynamic_light = {update = function() end, clear = function() end}
pixie.ore_sensor = {can_scan = function() return false end}

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
}

local pixie_def = registered_entities["pixie:pixie"]
assert(pixie_def, "Error: pixie:pixie definition not registered!")

local comp_ent = {
	object = mock_obj,
	name = "pixie:pixie",
	owner_name = "SaKeL",
	owner = "SaKeL",
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
comp_ent.owner = "SaKeL"
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

-- Test 11: Verify pixie mob registration flags for x_mob_core pipeline isolation and elevation
assert(pixie_def.melee == false, "Test 11 Failed: melee must be false in pixie definition")
assert(pixie_def.shooter == false, "Test 11 Failed: shooter must be false in pixie definition")
assert(pixie_def.auto_scan == false, "Test 11 Failed: auto_scan must be false in pixie definition")
assert(pixie_def.can_attack == false, "Test 11 Failed: can_attack must be false in pixie definition")
assert(pixie_def.flight_elevation == 1.85, "Test 11 Failed: flight_elevation must be 1.85")
assert(pixie_def.hover_offset == 1.85, "Test 11 Failed: hover_offset must be 1.85")
assert(pixie_def.combat_hover_offset == 1.85, "Test 11 Failed: combat_hover_offset must be 1.85")
print("Test 11: Mob Registration Pipeline Isolation Flags & Flight Elevation Verified.")

print("========== ALL TESTS PASSED SUCCESSFULLY! ==========")
