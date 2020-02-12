-- support for i18n
local S = armor_i18n.gettext

-- Update methods for supported inventories
local inventory_update
if minetest.global_exists("unified_inventory") then
	inventory_update = function(player)
		local page = unified_inventory.current_page[player:get_player_name()]
		unified_inventory.set_inventory_formspec(player, "armor")
		unified_inventory.get_formspec(player, "armor")
		unified_inventory.set_inventory_formspec(player, page)
	end
elseif minetest.global_exists("sfinv") then
	inventory_update = function(player)
		sfinv.set_player_inventory_formspec(player)
	end
elseif minetest.global_exists("inventory_plus") then
	inventory_update = function(player)
		local name = player:get_player_name()
		local formspec = armor:get_armor_formspec(name, true)
		local page = player:get_inventory_formspec()
		if page:find("detached:"..name.."_armor") then
			inventory_plus.set_inventory_formspec(player, formspec)
		end
	end
else
	inventory_update = function()end
end

-- Shields enabled?
local shield = minetest.get_modpath("shields")

-- Supported armor stand slots
local elements = {"head", "torso", "legs", "feet"}
if shield then
	table.insert(elements, "shield")
end

local armor_stand_formspec = function(playername)
	return "formspec_version[1]" ..
		"size[" .. (shield and 11 or 8) .. ",7]" ..
		default.gui_bg ..
		default.gui_bg_img ..
		default.gui_slots ..
		default.get_hotbar_bg(0,3) ..
		"list[context;armor_head;3,0.5;1,1;]" ..
		"list[context;armor_torso;4,0.5;1,1;]" ..
		"list[context;armor_legs;3,1.5;1,1;]" ..
		"list[context;armor_feet;4,1.5;1,1;]" ..
		(shield and "list[context;armor_shield;5,1.5;1,1;]" or "") ..
		"image[3,0.5;1,1;3d_armor_stand_head.png]" ..
		"image[4,0.5;1,1;3d_armor_stand_torso.png]" ..
		"image[3,1.5;1,1;3d_armor_stand_legs.png]" ..
		"image[4,1.5;1,1;3d_armor_stand_feet.png]" ..
		(shield and "image[5,1.5;1,1;3d_armor_stand_shield.png]" or "") ..
		"button_exit[6,1.5;1,1;swap;Switch]" ..
		"list[current_player;main;0,3;8,1;]" ..
		"list[current_player;main;0,4.25;8,3;8]" ..
		"label[9,1;"..playername.."]" ..
		"list[detached:"..playername.."_armor;armor;9,4.25;2,3;]" ..
		"listring[detached:"..playername.."_armor;armor]"
end

local function drop_armor(pos)
	local meta = minetest.get_meta(pos)
	local inv = meta:get_inventory()
	for _, element in pairs(elements) do
		local stack = inv:get_stack("armor_"..element, 1)
		if stack and stack:get_count() > 0 then
			armor.drop_armor(pos, stack)
			inv:set_stack("armor_"..element, 1, nil)
		end
	end
end

local function get_stand_object(pos)
	local object = nil
	local objects = minetest.get_objects_inside_radius(pos, 0.5) or {}
	for _, obj in pairs(objects) do
		local ent = obj:get_luaentity()
		if ent then
			if ent.name == "3d_armor_stand:armor_entity" then
				-- Remove duplicates
				if object then
					obj:remove()
				else
					object = obj
				end
			end
		end
	end
	return object
end

local function update_entity(pos)
	local node = minetest.get_node(pos)
	local object = get_stand_object(pos)
	if object then
		if not string.find(node.name, "3d_armor_stand:") then
			object:remove()
			return
		end
	else
		object = minetest.add_entity(pos, "3d_armor_stand:armor_entity")
	end
	if object then
		local texture = "3d_armor_trans.png"
		local textures = {}
		local meta = minetest.get_meta(pos)
		local inv = meta:get_inventory()
		local yaw = 0
		if inv then
			for _, element in pairs(elements) do
				local stack = inv:get_stack("armor_"..element, 1)
				if stack:get_count() == 1 then
					local item = stack:get_name() or ""
					local def = stack:get_definition() or {}
					local groups = def.groups or {}
					if groups["armor_"..element] then
						if def.texture then
							table.insert(textures, def.texture)
						else
							table.insert(textures, item:gsub("%:", "_")..".png")
						end
					end
				end
			end
		end
		if #textures > 0 then
			texture = table.concat(textures, "^")
		end
		if node.param2 then
			local rot = node.param2 % 4
			if rot == 1 then
				yaw = 3 * math.pi / 2
			elseif rot == 2 then
				yaw = math.pi
			elseif rot == 3 then
				yaw = math.pi / 2
			end
		end
		object:set_yaw(yaw)
		object:set_properties({textures={texture}})
	end
end

local function has_locked_armor_stand_privilege(meta, player)
	local name = ""
	if player then
		if minetest.check_player_privs(player, "protection_bypass") then
			return true
		end
		name = player:get_player_name()
	end
	if name ~= meta:get_string("owner") then
		return false
	end
	return true
end

local function add_hidden_node(pos, player)
	local p = {x=pos.x, y=pos.y + 1, z=pos.z}
	local name = player:get_player_name()
	local node = minetest.get_node(p)
	if node.name == "air" and not minetest.is_protected(pos, name) then
		minetest.set_node(p, {name="3d_armor_stand:top"})
	end
end

local function remove_hidden_node(pos)
	local p = {x=pos.x, y=pos.y + 1, z=pos.z}
	local node = minetest.get_node(p)
	if node.name == "3d_armor_stand:top" then
		minetest.remove_node(p)
	end
end

local elements2groups = function(t)
	local result = {}
	for _,v in ipairs(t) do
		result["armor_" .. v] = false
	end
	return result
end

local take_player_items = function(inv)
	local result = {}
	local slots = elements2groups(elements)
	for i = 1, inv:get_size('armor') do
		local stack = inv:get_stack("armor", i)
		local def = stack:get_definition()
		local groups = def and def.groups or nil
		if groups then
			for slot,used in pairs(slots) do
				if not used and groups[slot] then
					slots[slot] = true
					result[slot] = {index=table.maxn(result)+1, stack=stack}
					inv:set_stack("armor", i, nil)
					break
				end
			end
		end
	end
	return result
end

local take_stand_items = function(inv)
	local result = {}
	for i, element in ipairs(elements) do
		local stack = inv:get_stack("armor_"..element, 1)
		if not stack:is_empty() then
			table.insert(result, stack)
			inv:set_stack("armor_"..element, 1, nil)
		end
	end
	return result
end

local function swap_armor(pos, player)

	-- Collect player items removing them from inventory
	local player_inv = minetest.get_inventory({type='detached',name=player:get_player_name()..'_armor'})
	local player_items = take_player_items(player_inv)

	-- Collect stand items removing them from inventory
	local stand_inv = minetest.get_meta(pos):get_inventory()
	local stand_items = take_stand_items(stand_inv)

	-- debug stuff
	local player_items_name = {}
	local stand_items_name = {}

	local size = player_inv:get_size('armor')
	local min = 1
	for _,stack in ipairs(stand_items) do
		for i = min,size do
			if player_inv:get_stack("armor", i):is_empty() then
				player_inv:set_stack("armor", i, stack)
				min = i + 1
				break
			else
				print('slot ' .. i .. ' in use, trying to add ' .. stack:get_name())
			end
		end
	end
	for slot,data in pairs(player_items) do
		-- save data.index into armor stand meta to keep ordering next time
		stand_inv:set_stack(slot, 1, data.stack)
	end

	-- update inventories managed by supported inventory mods
	update_entity(pos)
	inventory_update(player)
end

minetest.register_node("3d_armor_stand:top", {
	description = S("Armor stand top"),
	paramtype = "light",
	drawtype = "plantlike",
	sunlight_propagates = true,
	walkable = true,
	pointable = false,
	diggable = false,
	buildable_to = false,
	drop = "",
	groups = {not_in_creative_inventory = 1},
	on_blast = function() end,
	tiles = {"3d_armor_trans.png"},
})

minetest.register_node("3d_armor_stand:armor_stand", {
	description = S("Armor stand"),
	drawtype = "mesh",
	mesh = "3d_armor_stand.obj",
	tiles = {"3d_armor_stand.png"},
	paramtype = "light",
	paramtype2 = "facedir",
	walkable = false,
	selection_box = {
		type = "fixed",
		fixed = {
			{-0.25, -0.4375, -0.25, 0.25, 1.4, 0.25},
			{-0.5, -0.5, -0.5, 0.5, -0.4375, 0.5},
		},
	},
	groups = {choppy=2, oddly_breakable_by_hand=2},
	sounds = default.node_sound_wood_defaults(),
	on_construct = function(pos)
		local meta = minetest.get_meta(pos)
		meta:set_string("infotext", S("Armor Stand"))
		local inv = meta:get_inventory()
		for _, element in pairs(elements) do
			inv:set_size("armor_"..element, 1)
		end
	end,
	can_dig = function(pos, player)
		local meta = minetest.get_meta(pos)
		local inv = meta:get_inventory()
		for _, element in pairs(elements) do
			if not inv:is_empty("armor_"..element) then
				return false
			end
		end
		return true
	end,
	after_place_node = function(pos, placer)
		local meta = minetest.get_meta(pos)
		local formspec = armor_stand_formspec(placer and placer:get_player_name() or "")
		meta:set_string("formspec", formspec)
		minetest.add_entity(pos, "3d_armor_stand:armor_entity")
		add_hidden_node(pos, placer)
	end,
	on_receive_fields = function (pos, formname, fields, sender)
		if fields.swap then
			swap_armor(pos, sender)
		end
	end,
	allow_metadata_inventory_put = function(pos, listname, index, stack)
		local def = stack:get_definition() or {}
		local groups = def.groups or {}
		if groups[listname] then
			return 1
		end
		return 0
	end,
	allow_metadata_inventory_move = function(pos)
		return 0
	end,
	on_metadata_inventory_put = function(pos)
		update_entity(pos)
	end,
	on_metadata_inventory_take = function(pos)
		update_entity(pos)
	end,
	after_destruct = function(pos)
		update_entity(pos)
		remove_hidden_node(pos)
	end,
	on_blast = function(pos)
		drop_armor(pos)
		armor.drop_armor(pos, "3d_armor_stand:armor_stand")
		minetest.remove_node(pos)
	end,
})

minetest.register_node("3d_armor_stand:locked_armor_stand", {
	description = S("Locked Armor stand"),
	drawtype = "mesh",
	mesh = "3d_armor_stand.obj",
	tiles = {"3d_armor_stand_locked.png"},
	paramtype = "light",
	paramtype2 = "facedir",
	walkable = false,
	selection_box = {
		type = "fixed",
		fixed = {
			{-0.25, -0.4375, -0.25, 0.25, 1.4, 0.25},
			{-0.5, -0.5, -0.5, 0.5, -0.4375, 0.5},
		},
	},
	groups = {choppy=2, oddly_breakable_by_hand=2},
	sounds = default.node_sound_wood_defaults(),
	on_construct = function(pos)
		local meta = minetest.get_meta(pos)
		meta:set_string("formspec", armor_stand_formspec)
		meta:set_string("infotext", S("Armor Stand"))
		meta:set_string("owner", "")
		local inv = meta:get_inventory()
		for _, element in pairs(elements) do
			inv:set_size("armor_"..element, 1)
		end
	end,
	can_dig = function(pos, player)
		local meta = minetest.get_meta(pos)
		local inv = meta:get_inventory()
		for _, element in pairs(elements) do
			if not inv:is_empty("armor_"..element) then
				return false
			end
		end
		return true
	end,
	after_place_node = function(pos, placer)
		minetest.add_entity(pos, "3d_armor_stand:armor_entity")
		local meta = minetest.get_meta(pos)
		meta:set_string("owner", placer:get_player_name() or "")
		meta:set_string("infotext", S("Armor Stand (owned by @1)", meta:get_string("owner")))
		add_hidden_node(pos, placer)
	end,
	allow_metadata_inventory_put = function(pos, listname, index, stack, player)
		local meta = minetest.get_meta(pos)
		if not has_locked_armor_stand_privilege(meta, player) then
			return 0
		end
		local def = stack:get_definition() or {}
		local groups = def.groups or {}
		if groups[listname] then
			return 1
		end
		return 0
	end,
	allow_metadata_inventory_take = function(pos, listname, index, stack, player)
		local meta = minetest.get_meta(pos)
		if not has_locked_armor_stand_privilege(meta, player) then
			return 0
		end
		return stack:get_count()
	end,
	allow_metadata_inventory_move = function(pos)
		return 0
	end,
	on_metadata_inventory_put = function(pos)
		update_entity(pos)
	end,
	on_metadata_inventory_take = function(pos)
		update_entity(pos)
	end,
	after_destruct = function(pos)
		update_entity(pos)
		remove_hidden_node(pos)
	end,
	on_blast = function(pos)
		-- Not affected by TNT
	end,
})

minetest.register_entity("3d_armor_stand:armor_entity", {
	physical = true,
	visual = "mesh",
	mesh = "3d_armor_entity.obj",
	visual_size = {x=1, y=1},
	collisionbox = {0,0,0,0,0,0},
	textures = {"3d_armor_trans.png"},
	pos = nil,
	timer = 0,
	on_activate = function(self)
		local pos = self.object:get_pos()
		if pos then
			self.pos = vector.round(pos)
			update_entity(pos)
		end
	end,
	on_blast = function(self, damage)
		local drops = {}
		local node = minetest.get_node(self.pos)
		if node.name == "3d_armor_stand:armor_stand" then
			drop_armor(self.pos)
			self.object:remove()
		end
		return false, false, drops
	end,
})

minetest.register_abm({
	nodenames = {"3d_armor_stand:locked_armor_stand", "3d_armor_stand:armor_stand"},
	interval = 15,
	chance = 1,
	action = function(pos, node, active_object_count, active_object_count_wider)
		local num
		num = #minetest.get_objects_inside_radius(pos, 0.5)
		if num > 0 then return end
		update_entity(pos)
	end
})

minetest.register_craft({
	output = "3d_armor_stand:armor_stand",
	recipe = {
		{"", "group:fence", ""},
		{"", "group:fence", ""},
		{"default:steel_ingot", "default:steel_ingot", "default:steel_ingot"},
	}
})

minetest.register_craft({
	output = "3d_armor_stand:locked_armor_stand",
	recipe = {
		{"3d_armor_stand:armor_stand", "default:steel_ingot"},
	}
})
