--[[
	© DestructionSimulator [2025]
	Server/SkinEquip — Data-driven mapping and stat multiplier logic.
]]--

local SkinEquip = {}
local SkinMath = require(game:GetService("ReplicatedStorage"):WaitForChild("Library"):WaitForChild("Modules"):WaitForChild("SkinMath"))

--- Calculate the collection multiplier based on the Skin's float.
function SkinEquip.CalculateMultiplier(skinFloat, multMin, multMax)
	return SkinMath.CalculateMultiplier(skinFloat, multMin or 1, multMax or 1)
end

--- Update the player's profile data to map a Unique Skin UID to a Base Weapon.
function SkinEquip.EquipSkin(playerProfile, category, baseWeaponID, uniqueSkinUID)
	if not playerProfile.EquippedSkins then
		playerProfile.EquippedSkins = {}
	end
	if not playerProfile.EquippedSkins[category] then
		playerProfile.EquippedSkins[category] = {}
	end

	-- Pure Data mapping
	if uniqueSkinUID then
		playerProfile.EquippedSkins[category][baseWeaponID] = {ID = uniqueSkinUID}
	else
		playerProfile.EquippedSkins[category][baseWeaponID] = nil
	end

	return playerProfile.EquippedSkins
end

--- Retrieves the multiplier for a specific Base Weapon based on what skin is equipped.
function SkinEquip.GetEquippedMultiplier(playerProfile, baseWeaponID)
	-- Determine category dynamically
	local category = "BackPack"
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local skinsFolder = ReplicatedStorage:FindFirstChild("Directory") and ReplicatedStorage.Directory:FindFirstChild("Skins")
	if skinsFolder then
		if skinsFolder:FindFirstChild("Launcher") and skinsFolder.Launcher:FindFirstChild(baseWeaponID) then
			category = "Launcher"
		elseif skinsFolder:FindFirstChild("Bomb") and skinsFolder.Bomb:FindFirstChild(baseWeaponID) then
			category = "Bomb"
		end
	end
	
	if not playerProfile.EquippedSkins then return 1.0 end
	if not playerProfile.EquippedSkins[category] then return 1.0 end
	
	local equippedSkin = playerProfile.EquippedSkins[category][baseWeaponID]
	if not equippedSkin or not equippedSkin.ID then return 1.0 end

	local skinID = equippedSkin.ID
	local skinFloat = 1
	if playerProfile.Skins then
		for _, skin in ipairs(playerProfile.Skins) do
			if skin.Category == category and skin.ItemName == baseWeaponID and skin.ID == skinID then
				skinFloat = skin.Float or 1
				break
			end
		end
	end

	local success, skinConfig = pcall(function() return require(game:GetService("ReplicatedStorage"):WaitForChild("Directory"):WaitForChild("Skins"):WaitForChild(category):WaitForChild(baseWeaponID):WaitForChild(skinID)) end)
	if success and skinConfig then
		return SkinEquip.CalculateMultiplier(skinFloat, skinConfig.MultMin, skinConfig.MultMax)
	end

	return 1.0
end

--- Safely deletes a list of skin UIDs from a player's profile data.
--- Unequips any deleted skins, removes them from profile.Skins, and returns deletedCount, deletedUids.
function SkinEquip.DeleteSkins(playerProfile, uidsList)
	if not playerProfile or not playerProfile.Skins or type(uidsList) ~= "table" then
		return 0, {}
	end

	local uidsSet = {}
	for _, uid in ipairs(uidsList) do
		if type(uid) == "string" and uid ~= "" then
			uidsSet[uid] = true
		end
	end

	if next(uidsSet) == nil then
		return 0, {}
	end

	local deletedCount = 0
	local deletedUids = {}
	local i = 1
	while i <= #playerProfile.Skins do
		local skin = playerProfile.Skins[i]
		if skin and skin.UID and uidsSet[skin.UID] then
			-- Safety rule: Do not delete locked skins
			if skin.Locked == true or skin.l == true then
				i = i + 1
			else
				-- If equipped, unequip it
				if playerProfile.EquippedSkins and skin.Category and skin.ItemName then
					local catEquipped = playerProfile.EquippedSkins[skin.Category]
					if catEquipped and catEquipped[skin.ItemName] then
						if catEquipped[skin.ItemName].ID == skin.ID then
							catEquipped[skin.ItemName] = nil
						end
					end
				end

				table.insert(deletedUids, skin.UID)
				table.remove(playerProfile.Skins, i)
				deletedCount = deletedCount + 1
			end
		else
			i = i + 1
		end
	end

	return deletedCount, deletedUids
end

return SkinEquip
