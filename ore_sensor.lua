--[[
	pixie - Ore Prospecting Subsystem
	Scans, prioritizes, and highlights subterranean ore deposits with visual beacons.
]]

---@class PixieOreCache
---@field last_scan_time number
---@field last_scan_pos Vector|nil
---@field cached_ore_pos Vector|nil
---@field cached_ore_title string|nil
---@field cached_ore_priority integer
---@field cached_node_name string|nil
---@field recent_alerts table<string, table>

---@class PixieOreSensor
---@field max_ore_y number
---@field cache PixieOreCache
---@field can_scan fun(pos: Vector): boolean
---@field scan_area fun(center: Vector, r_h?: number, r_v?: number): Vector|nil, string|nil, integer, string|nil
local ore_sensor = {}

---Shared ore prospecting cache across companion pixies to eliminate redundant spatial scans and duplicate alert spam
---@type PixieOreCache
local ore_cache = {
	last_scan_time = 0,
	last_scan_pos = nil,
	cached_ore_pos = nil,
	cached_ore_title = nil,
	cached_ore_priority = 0,
	cached_node_name = nil,
	recent_alerts = {},
}

ore_sensor.cache = ore_cache

---@type string[]|nil
local pixie_ore_nodes = nil
---@type table<string, string>
local pixie_ore_titles = {}
---@type table<string, integer>
local pixie_ore_priorities = {}

local ORE_PRIORITY_ORDER = {
	-- Tier 6: Supreme & Ultra-Rare Treasures (Score: 60 - 65)
	{stem = "diamond", score = 65},
	{stem = "adamantite", score = 62},
	{stem = "ancient_debris", score = 62},
	{stem = "mithril", score = 60},
	{stem = "platinum", score = 60},
	{stem = "titanium", score = 60},

	-- Tier 5: Precious Jewels & Power Crystals (Score: 45 - 50)
	{stem = "mese", score = 50},
	{stem = "ruby", score = 48},
	{stem = "emerald", score = 48},
	{stem = "sapphire", score = 48},
	{stem = "amethyst", score = 45},
	{stem = "topaz", score = 45},
	{stem = "jewel", score = 45},
	{stem = "baborium", score = 45},

	-- Tier 4: Exotic Minerals & Arcane Components (Score: 35 - 40)
	{stem = "uranium", score = 40},
	{stem = "redstone", score = 38},
	{stem = "lapis", score = 36},
	{stem = "gold", score = 35},

	-- Tier 3: Semiprecious Metals & Resonators (Score: 22 - 30)
	{stem = "silver", score = 28},
	{stem = "tungsten", score = 26},
	{stem = "chromium", score = 25},
	{stem = "quartz", score = 24},
	{stem = "pyrite", score = 22},

	-- Tier 2: Essential Base Metals (Score: 12 - 18)
	{stem = "iron", score = 18},
	{stem = "tin", score = 14},
	{stem = "copper", score = 14},
	{stem = "lead", score = 13},
	{stem = "zinc", score = 13},
	{stem = "aluminum", score = 12},
	{stem = "bauxite", score = 12},
	{stem = "bauxit", score = 12},

	-- Tier 1: Abundant / Common Fuel & Minerals (Score: 5 - 8)
	{stem = "coal", score = 8},
	{stem = "sulfur", score = 6},
	{stem = "salt", score = 5},
}


local ORE_STEMS = {
	"coal", "iron", "copper", "tin", "gold", "mese", "diamond", "pyrite",
	"silver", "mithril", "ruby", "emerald", "sapphire", "amethyst", "topaz",
	"redstone", "lapis", "quartz", "uranium", "chromium", "zinc", "lead",
	"titanium", "platinum", "tungsten", "aluminum", "bauxite", "sulfur",
	"salt", "adamantite", "jewel", "baborium", "ancient_debris",
}

---Calculates the priority score of an ore node (higher score = more valuable)
---@param name string Technical node name
---@param def table|nil Node definition table
---@return integer priority Score between 5 and 65 (default 15 for unidentified ores)
function ore_sensor.calculate_ore_priority(name, def)
	-- Check explicit game/mod compat registry first
	local c_info = pixie.compat.get_ore_info(name)
	if c_info and c_info.priority then
		return c_info.priority
	end

	local lname = name:lower()
	local desc = def and (def.short_description or def.description)
	local ldesc = (desc and type(desc) == "string") and desc:lower() or nil

	-- First, check direct compound prefixes on node name (e.g. stone_with_coal, mineral_iron)
	-- Evaluates highest priority ores first to enable immediate early exit and JIT trace efficiency
	for i = 1, #ORE_PRIORITY_ORDER do
		local entry = ORE_PRIORITY_ORDER[i]
		local stem = entry.stem
		if lname:find("_with_" .. stem, 1, true)
			or lname:find(":mineral_" .. stem, 1, true)
			or lname:find("_ore_" .. stem, 1, true)
			or lname:find(":" .. stem .. "_ore", 1, true)
			or lname:find("^" .. stem .. "_ore") then
			return entry.score
		end
	end

	-- Second, check priority order against word boundaries in name and description
	for i = 1, #ORE_PRIORITY_ORDER do
		local entry = ORE_PRIORITY_ORDER[i]
		local stem = entry.stem
		local pat_underscore = "%f[%a]" .. stem .. "%f[%A]"
		local pat_space = stem:find("_") and ("%f[%a]" .. stem:gsub("_", " ") .. "%f[%A]") or nil

		if lname:find(pat_underscore) or (pat_space and lname:find(pat_space)) then
			return entry.score
		end
		if ldesc and (ldesc:find(pat_underscore) or (pat_space and ldesc:find(pat_space))) then
			return entry.score
		end
	end

	return 15 -- Default fallback priority
end

---Extracts a sanitized, human-readable title from node definition or technical name
---@param name string Registered node technical name
---@param def table Node definition table
---@return string Clean display title
function ore_sensor.extract_clean_ore_title(name, def)
	local c_info = pixie.compat.get_ore_info(name)
	if c_info and c_info.title then
		return c_info.title
	end

	local desc = def and (def.short_description or def.description)
	if desc and type(desc) == "string" and desc ~= "" then
		local line = desc:match("^[^\r\n]+") or desc
		line = core.strip_colors(line)
		line = line:gsub("\27%b()", ""):gsub("\27.", ""):match("^%s*(.-)%s*$")
		if line and line ~= "" then
			return line
		end
	end
	-- Fallback to formatting the technical node name into clean Title Case
	local sub = name:match(":(.+)$") or name
	sub = sub:gsub("(%l)(%u)", "%1 %2"):gsub("_", " ")
	return (sub:gsub("(%a)([%w_']*)", function(first, rest)
		return first:upper() .. rest:lower()
	end))
end

---Evaluates whether a registered node represents a valuable mineable ore
---@param name string Technical node name
---@param def table Node definition table
---@return boolean is_ore True if node is a recognized ore
function ore_sensor.is_valuable_ore_node(name, def)
	local groups = def.groups or {}

	-- Exclude organic/living vegetation, liquid, soil, and sand
	if groups.tree or groups.leaves or groups.plant or groups.flora
		or groups.sapling or groups.flower or groups.grass or groups.soil
		or groups.sand or groups.liquid or groups.water or groups.lava then
		return false
	end

	local lname = name:lower()

	-- Exclude surface vegetative covers and non-ore overlays
	if lname:find("_with_moss") or lname:find("_with_lichen")
		or lname:find("_with_algae") or lname:find("_with_grass")
		or lname:find("_with_snow") or lname:find("_with_rainforest")
		or lname:find("_with_coniferous") or lname:find("_with_stones")
		or lname:find("_with_kelp") then
		return false
	end

	-- Exclude basic mass terrain and building materials
	if lname == "default:clay" or lname == "default:sand"
		or lname == "default:desert_sand" or lname == "default:silver_sand"
		or lname == "default:gravel" or lname == "default:dirt"
		or lname == "default:stone" or lname == "default:desert_stone"
		or lname == "default:cobble" or lname == "default:desert_cobble" then
		return false
	end

	-- Check explicit ore groups
	if (groups.ore and groups.ore > 0)
		or (groups.mineral and groups.mineral > 0)
		or (groups.ore_node and groups.ore_node > 0)
		or (groups.is_ore and groups.is_ore > 0)
		or (groups.natural_ore and groups.natural_ore > 0) then
		return true
	end

	-- Check name patterns
	for i = 1, #ORE_STEMS do
		local stem = ORE_STEMS[i]
		if lname:find("_with_" .. stem)
			or lname:find(":mineral_" .. stem)
			or lname:find("_ore_" .. stem)
			or lname:find("_ore")
			or lname:find(":ore_")
			or lname:find("adamantite")
			or lname:find("ancient_debris") then
			return true
		end
	end

	-- Check description for "Ore" keyword
	local desc = def.description
	if desc and type(desc) == "string" then
		local clean = core.strip_colors(desc):gsub("\27%b()", ""):gsub("\27.", ""):match("^%s*(.-)%s*$")
		if clean and clean:match("%f[%a][Oo]re%f[%A]") then
			return true
		end
	end

	return false
end

---Builds and returns cached array of ore node names and groups for core.find_nodes_in_area
---@return string[] Array of ore node names and group specifiers
function ore_sensor.get_ore_nodes()
	if pixie_ore_nodes then
		return pixie_ore_nodes
	end

	local node_list = {"group:ore", "group:mineral"}
	local seen = {["group:ore"] = true, ["group:mineral"] = true}

	if core.registered_nodes then
		for name, def in pairs(core.registered_nodes) do
			if not seen[name] and ore_sensor.is_valuable_ore_node(name, def) then
				seen[name] = true
				node_list[#node_list + 1] = name
				pixie_ore_titles[name] = ore_sensor.extract_clean_ore_title(name, def)
				pixie_ore_priorities[name] = ore_sensor.calculate_ore_priority(name, def)
			end
		end
	end

	if core.registered_ores then
		for _, ore_def in pairs(core.registered_ores) do
			local oname = ore_def.ore
			if oname and type(oname) == "string" and not seen[oname] then
				local ndef = core.registered_nodes[oname]
				if ndef and ore_sensor.is_valuable_ore_node(oname, ndef) then
					seen[oname] = true
					node_list[#node_list + 1] = oname
					pixie_ore_titles[oname] = ore_sensor.extract_clean_ore_title(oname, ndef)
					pixie_ore_priorities[oname] = ore_sensor.calculate_ore_priority(oname, ndef)
				end
			end
		end
	end

	-- Also incorporate compat-registered ores
	for c_name, c_info in pairs(pixie.compat.get_all_ores()) do
		if not seen[c_name] then
			seen[c_name] = true
			node_list[#node_list + 1] = c_name
			pixie_ore_titles[c_name] = c_info.title
			pixie_ore_priorities[c_name] = c_info.priority
		end
	end

	pixie_ore_nodes = node_list
	return pixie_ore_nodes
end

---Returns the cached or computed ore priority for a node name (0 if not a valuable ore).
---@param node_name string
---@return integer priority
function ore_sensor.get_node_priority(node_name)
	if not node_name or node_name == "" then return 0 end
	local cached = pixie_ore_priorities[node_name]
	if cached then return cached end
	local c_info = pixie.compat.get_ore_info(node_name)
	if c_info and c_info.priority then
		pixie_ore_priorities[node_name] = c_info.priority
		return c_info.priority
	end
	local ndef = core.registered_nodes and core.registered_nodes[node_name]
	if ndef and ore_sensor.is_valuable_ore_node(node_name, ndef) then
		local p = ore_sensor.calculate_ore_priority(node_name, ndef)
		pixie_ore_priorities[node_name] = p
		return p
	end
	return 0
end

ore_sensor.pixie_ore_titles = pixie_ore_titles
ore_sensor.pixie_ore_priorities = pixie_ore_priorities

core.register_on_mods_loaded(function()
	ore_sensor.get_ore_nodes()
end)

local DEFAULT_MAX_ORE_Y = 64
ore_sensor.max_ore_y = (pixie.config and pixie.config.ore_max_y) or DEFAULT_MAX_ORE_Y

---Evaluates whether a position is eligible for ore sensing based on elevation and subterranean lighting.
---Bypasses scanning on the open surface (even at night) while preserving detection in mountain caves.
---@param pos Vector World position to evaluate
---@return boolean can_scan True if the position is subterranean or within a dark cavern
function ore_sensor.can_scan(pos)
	local limit_y = ore_sensor.max_ore_y or DEFAULT_MAX_ORE_Y
	if pos.y > limit_y then
		return false
	end

	-- Solar noon natural light query (0.5 time of day):
	-- Independent of current time-of-day. Returns 15 for open sky (day or night)
	-- and < 8 only inside enclosed caverns, mineshafts, or deep subterranean spaces.
	local noon_sun = core.get_natural_light(pos, 0.5)
	if noon_sun and noon_sun >= 8 then
		return false
	end

	return true
end

---Updates the spatial scan cache for standard-radius queries.
---@param now number Current gametime
---@param center Vector Scan center position
---@param ore_pos Vector|nil Found ore position
---@param title string|nil Found ore title
---@param priority integer Found ore priority
---@param node_name string|nil Found ore technical name
local function update_scan_cache(now, center, ore_pos, title, priority, node_name)
	ore_cache.last_scan_time = now
	if ore_cache.last_scan_pos then
		ore_cache.last_scan_pos.x = center.x
		ore_cache.last_scan_pos.y = center.y
		ore_cache.last_scan_pos.z = center.z
	else
		ore_cache.last_scan_pos = {x = center.x, y = center.y, z = center.z}
	end
	ore_cache.cached_ore_pos = ore_pos
	ore_cache.cached_ore_title = title
	ore_cache.cached_ore_priority = priority
	ore_cache.cached_node_name = node_name
end

---Scans a subterranean cuboid volume for high-value ores.
---@param center Vector Origin coordinate
---@param radius_h number Horizontal radius (default: 6)
---@param radius_v number Vertical radius (default: 3)
---@return Vector|nil best_pos
---@return string|nil best_title
---@return integer best_priority
---@return string|nil best_node_name
function ore_sensor.scan_area(center, radius_h, radius_v)
	if not ore_sensor.can_scan(center) then
		return nil, nil, 0, nil
	end

	radius_h = radius_h or 6
	radius_v = radius_v or 3

	local cache = ore_sensor.cache
	local now = core.get_gametime()

	-- Check spatial and temporal cache validity
	-- Standard scan uses radius_h == 6 and radius_v == 3
	local is_std_radius = (radius_h == 6 and radius_v == 3)
	if is_std_radius and cache.last_scan_pos and (now - cache.last_scan_time < 3.0) then
		if pixie.utils.dist_sq(center, cache.last_scan_pos) <= 4.0 then
			-- Case A: Previously scanned volume was empty (no ores nearby)
			if not cache.cached_ore_pos then
				return nil, nil, 0, nil
			end

			-- Case B: Verify cached ore node has not been mined or altered
			local node = core.get_node_or_nil(cache.cached_ore_pos)
			if node and node.name == cache.cached_node_name then
				return cache.cached_ore_pos, cache.cached_ore_title, cache.cached_ore_priority, cache.cached_node_name
			else
				-- Ore was mined or altered: invalidate and fall through to fresh scan
				cache.cached_ore_pos = nil
				cache.cached_ore_title = nil
				cache.cached_ore_priority = 0
				cache.cached_node_name = nil
			end
		end
	end

	local minp = {
		x = math.floor(center.x - radius_h),
		y = math.floor(center.y - radius_v),
		z = math.floor(center.z - radius_h),
	}
	local maxp = {
		x = math.floor(center.x + radius_h),
		y = math.floor(center.y + radius_v),
		z = math.floor(center.z + radius_h),
	}

	local target_nodes = ore_sensor.get_ore_nodes()
	local ore_groups = core.find_nodes_in_area(minp, maxp, target_nodes, true)
	if not ore_groups or not next(ore_groups) then
		if is_std_radius then
			update_scan_cache(now, center, nil, nil, 0, nil)
		end
		return nil, nil, 0, nil
	end

	local best_ore_pos = nil
	local best_priority = -1
	local best_dist_sq = math.huge
	local best_node_name = nil

	for node_name, positions in pairs(ore_groups) do
		if positions and #positions > 0 then
			local priority = pixie_ore_priorities[node_name]
			if not priority then
				local ndef = core.registered_nodes[node_name]
				priority = ore_sensor.calculate_ore_priority(node_name, ndef)
				pixie_ore_priorities[node_name] = priority
			end

			for i = 1, #positions do
				local p = positions[i]
				local pdx = p.x - center.x
				local pdy = p.y - center.y
				local pdz = p.z - center.z
				local odsq = pdx * pdx + pdy * pdy + pdz * pdz
				if priority > best_priority then
					best_priority = priority
					best_dist_sq = odsq
					best_ore_pos = p
					best_node_name = node_name
				elseif priority == best_priority and odsq < best_dist_sq then
					best_dist_sq = odsq
					best_ore_pos = p
					best_node_name = node_name
				end
			end
		end
	end

	if best_ore_pos and best_node_name then
		local title = pixie_ore_titles[best_node_name]
		if not title then
			local ndef = core.registered_nodes[best_node_name]
			title = ndef and ore_sensor.extract_clean_ore_title(best_node_name, ndef) or "valuable ore"
			pixie_ore_titles[best_node_name] = title
		end

		if is_std_radius then
			update_scan_cache(now, center, best_ore_pos, title, best_priority, best_node_name)
		end

		return best_ore_pos, title, best_priority, best_node_name
	end

	if is_std_radius then
		update_scan_cache(now, center, nil, nil, 0, nil)
	end

	return nil, nil, 0, nil
end

-- Celebratory Somersaults when Mining Rare Ores (Diamond, Mese, Emerald, Ancient Debris, etc.)
if core.register_on_dignode then
	core.register_on_dignode(function(pos, oldnode, digger)
		if not oldnode or not digger or not digger.is_player or not digger:is_player() or not digger:is_valid() then
			return
		end
		if ore_sensor.get_node_priority(oldnode.name) < 45 then
			return
		end
		local player_name = digger:get_player_name()
		if not player_name or player_name == "" then return end

		local comp = pixie.bonding and pixie.bonding.active_player_pixies[player_name]
		if comp and comp.object and comp.object:is_valid() then
			local cpos = comp.object:get_pos()
			if cpos and pos and pixie.utils.dist_sq(cpos, pos) <= 256.0 then
				pixie.trigger_celebration(comp)
			end
		end
	end)
end

pixie.ore_sensor = ore_sensor
return ore_sensor
