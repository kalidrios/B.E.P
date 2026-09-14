--!strict
--[[
	© DestructionSimulator [2025]
	Library/Modules/InventoryUtil — Single Source of Truth for inventory, equipment ownership, and skin validation.
]]--

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InventoryUtil = {}

-- Starter items that are always owned by any player
local STARTER_ITEMS = {
	["Rocket Launcher"] = true,
	["Bomb"] = true,
	["SmallBag"] = true,
}

--- Returns whether an item is a starter base item (owned by default)
function InventoryUtil.IsStarterItem(name: string): boolean
	return STARTER_ITEMS[name] == true
end

--- Checks if a player owns the base equipment (purchased from GearShop or starter)
function InventoryUtil.OwnsBaseEquipment(dataOrProfile: table?, category: string, name: string): boolean
	if not dataOrProfile or not name then return false end
	if InventoryUtil.IsStarterItem(name) then
		return true
	end

	if category == "Launcher" or category == "Bomb" then
		for _, w in ipairs(dataOrProfile.Weapons or {}) do
			if type(w) == "table" and (w.ID == name or w.Name == name or w.Type == name) then
				return true
			elseif type(w) == "string" and w == name then
				return true
			end
		end
	elseif category == "BackPack" then
		for _, bp in ipairs(dataOrProfile.Backpacks or {}) do
			if bp == name then
				return true
			end
		end
	end

	return false
end

--- Checks if a player owns a specific skin for an item
function InventoryUtil.OwnsSkin(dataOrProfile: table?, category: string, itemName: string, skinId: string?): boolean
	if not dataOrProfile or not itemName then return false end

	-- Default skin requires owning the base equipment
	if not skinId or skinId == "Default" then
		return InventoryUtil.OwnsBaseEquipment(dataOrProfile, category, itemName)
	end

	if dataOrProfile.Skins then
		for _, s in ipairs(dataOrProfile.Skins) do
			local sItem = s.ItemName or s.itemName
			local sCat = s.Category or s.category
			local sId = s.ID or s.id
			if sCat == category and sItem == itemName and sId == skinId then
				return true
			end
		end
	end

	return false
end

--- Master validator for equipping: verifies base equipment in GearShop and skin ownership
--- Returns (canEquip: boolean, errorMessage: string?)
function InventoryUtil.CanEquip(dataOrProfile: table?, category: string, itemName: string, skinName: string?): (boolean, string?)
	if not dataOrProfile then
		return false, "Player data not available."
	end

	-- 1. Base weapon MUST be owned in GearShop
	if not InventoryUtil.OwnsBaseEquipment(dataOrProfile, category, itemName) then
		return false, "You must purchase the " .. tostring(itemName) .. " in the GearShop first to equip this!"
	end

	-- 2. If a non-default skin is specified, player must own the skin
	if skinName and skinName ~= "Default" then
		if not InventoryUtil.OwnsSkin(dataOrProfile, category, itemName, skinName) then
			return false, "You do not own the " .. tostring(skinName) .. " skin!"
		end
	end

	return true, nil
end

--- Checks if an item is currently equipped (supports Player instance or Data table)
function InventoryUtil.IsEquipped(playerOrData: any, category: string, name: string): boolean
	if not playerOrData or not name then return false end

	-- If passed a Player instance (client-side check via attributes)
	if typeof(playerOrData) == "Instance" and playerOrData:IsA("Player") then
		if category == "Launcher" then
			return playerOrData:GetAttribute("EquippedLauncher") == name
		elseif category == "Bomb" then
			return playerOrData:GetAttribute("EquippedBomb") == name
		elseif category == "BackPack" then
			return playerOrData:GetAttribute("EquippedBackpack") == name
		end
	-- If passed a table (data or profile)
	elseif type(playerOrData) == "table" then
		if category == "Launcher" then
			return (playerOrData.EquippedLauncher == name)
		elseif category == "Bomb" then
			return (playerOrData.EquippedBomb == name)
		elseif category == "BackPack" then
			return (playerOrData.EquippedBackpack == name)
		end
	end

	return false
end

--- Resolves maximum capacity for a backpack by name from ShopConfig / Directory
local cachedCapacities = {}
function InventoryUtil.GetBackpackCapacity(backpackName: string): number
	if cachedCapacities[backpackName] then
		return cachedCapacities[backpackName]
	end

	local cap = nil
	local success, ShopConfig = pcall(function()
		return require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("ShopConfig"))
	end)
	if success and ShopConfig and ShopConfig.BackPack then
		for _, item in ipairs(ShopConfig.BackPack) do
			if item.Name == backpackName then
				cap = item.Capacity
				break
			end
		end
	end

	if not cap then
		local dirFolder = ReplicatedStorage:FindFirstChild("Directory") and ReplicatedStorage.Directory:FindFirstChild("Backpack")
		local bpFile = dirFolder and dirFolder:FindFirstChild(backpackName)
		if bpFile then
			local ok, cfg = pcall(function() return require(bpFile) end)
			if ok and cfg and (cfg.Capacity or cfg.capacity) then
				cap = cfg.Capacity or cfg.capacity
			end
		end
	end

	local finalCap = cap or 100
	cachedCapacities[backpackName] = finalCap
	return finalCap
end

return InventoryUtil
