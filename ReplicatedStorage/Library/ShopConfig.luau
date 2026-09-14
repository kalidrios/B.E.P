--!strict
--[[
	© DestructionSimulator [2025]
	ShopConfig — Dynamic configuration loader for the Gear Shop.
	Reads pricing and layoutOrder keys from ReplicatedStorage.Directory configs.
]]

export type ShopItem = {
	Name: string,
	Price: number,
	LayoutOrder: number,
	Reload: number?,
	BlastRadius: number?,
	Capacity: number?,
}

export type ShopConfigTable = {
	Launcher: { ShopItem },
	Bomb: { ShopItem },
	BackPack: { ShopItem },
}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Library = ReplicatedStorage:WaitForChild("Library")
local Directory = require(Library:WaitForChild("Directory")) :: any

local ShopConfig: ShopConfigTable = {
	Launcher = {},
	Bomb = {},
	BackPack = {},
}

-- Populate Launcher from Directory.Weapons
if Directory.Weapons then
	for name, data in pairs(Directory.Weapons) do
		table.insert(ShopConfig.Launcher, {
			Name = name,
			Price = data.price or 0,
			Reload = data.reload or 3.0,
			LayoutOrder = data.layoutOrder or 1,
		})
	end
	
	-- Sort by LayoutOrder first, then by Price
	table.sort(ShopConfig.Launcher, function(a: ShopItem, b: ShopItem)
		if a.LayoutOrder ~= b.LayoutOrder then
			return a.LayoutOrder < b.LayoutOrder
		else
			return a.Price < b.Price
		end
	end)
end

-- Populate Bomb from Directory.Bomb
if Directory.Bomb then
	for name, data in pairs(Directory.Bomb) do
		table.insert(ShopConfig.Bomb, {
			Name = name,
			Price = data.price or 0,
			BlastRadius = data.blastRadius or 9,
			LayoutOrder = data.layoutOrder or 1,
		})
	end
	
	-- Sort by LayoutOrder first, then by Price
	table.sort(ShopConfig.Bomb, function(a: ShopItem, b: ShopItem)
		if a.LayoutOrder ~= b.LayoutOrder then
			return a.LayoutOrder < b.LayoutOrder
		else
			return a.Price < b.Price
		end
	end)
end

-- Populate BackPack from Directory.Backpack or Directory.BackPack
local backpackDir = Directory.Backpack or Directory.BackPack
if backpackDir then
	ShopConfig.BackPack = {}
	for name, data in pairs(backpackDir) do
		-- Entries flagged Purchasable = false (e.g. the default Starter bag) are
		-- runtime config only and must never appear in the Gear Shop.
		if data.Purchasable ~= false then
			table.insert(ShopConfig.BackPack, {
				Name = name,
				Price = data.Price or data.price or 0,
				Capacity = data.Capacity or data.capacity or 100,
				LayoutOrder = data.LayoutOrder or data.layoutOrder or 1,
			})
		end
	end
	
	table.sort(ShopConfig.BackPack, function(a: ShopItem, b: ShopItem)
		if a.LayoutOrder ~= b.LayoutOrder then
			return a.LayoutOrder < b.LayoutOrder
		else
			return a.Price < b.Price
		end
	end)
end

-- Support both "BackPack" and "Backpack" casing
ShopConfig.Backpack = ShopConfig.BackPack

-- Normalization helper for category keys
local function normalizeCategory(category: string): string
	local lower = string.lower(category)
	if lower == "backpack" then
		return "BackPack"
	elseif lower == "bomb" then
		return "Bomb"
	elseif lower == "launcher" then
		return "Launcher"
	end
	return category
end

-- Helper to safely retrieve world config
local function getWorldConfig(worldName: string?): any
	if not worldName or worldName == "" then
		worldName = "Spawn"
	end
	if Directory.Worlds and Directory.Worlds[worldName] then
		return Directory.Worlds[worldName]
	end
	return nil
end

--- Get all available shop items for a specific category and world.
--- If worldName is omitted or world has no whitelist, returns all items in that category.
function ShopConfig.GetItems(category: string, worldName: string?): { ShopItem }
	local normCat = normalizeCategory(category)
	local masterList = ShopConfig[normCat] or {}
	local worldCfg = getWorldConfig(worldName)
	if not worldCfg then
		return masterList
	end

	-- Look for world whitelist: worldCfg.Launcher, worldCfg.Bomb, worldCfg.Backpack / worldCfg.BackPack
	local allowedNames: { string }? = worldCfg[normCat] or (normCat == "BackPack" and worldCfg.Backpack)
	if not allowedNames or #allowedNames == 0 then
		return masterList
	end

	local allowedSet = {}
	for _, name in ipairs(allowedNames) do
		allowedSet[name] = true
	end

	local filtered = {}
	for _, item in ipairs(masterList) do
		if allowedSet[item.Name] then
			table.insert(filtered, item)
		end
	end

	return filtered
end

--- Check whether an item is available in a given world
function ShopConfig.IsItemAvailableInWorld(category: string, itemName: string, worldName: string?): boolean
	local items = ShopConfig.GetItems(category, worldName)
	for _, item in ipairs(items) do
		if item.Name == itemName then
			return true
		end
	end
	return false
end

return ShopConfig
