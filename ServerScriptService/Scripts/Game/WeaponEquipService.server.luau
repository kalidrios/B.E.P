--[[
	Â© DestructionSimulator [2025]
	Server/WeaponEquipService â€” Handles attaching weapon models to the
	player's character via Motor6D when they equip from the Inventory.

	The Eveera approach: they use native Roblox Tool objects which
	auto-create a "RightGrip" Motor6D when parented to Character.
	Our approach: we skip the Tool wrapper entirely and manually create
	a Motor6D between the character's RightHand/Right Arm and the
	weapon model's Handle part. This gives us full control over
	positioning and avoids the overhead of the Tool system.
]]--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

----------------------------------------------------------------------
-- Wait for Library
----------------------------------------------------------------------
local Library = require(ReplicatedStorage:WaitForChild("Library"))
while not Library.IsLoaded() do
	task.wait()
end
local Saving = Library.Saving
local SkinEquip = require(ServerScriptService:WaitForChild("Library"):WaitForChild("SkinEquip"))
local InventoryUtil = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Modules"):WaitForChild("InventoryUtil"))

----------------------------------------------------------------------
-- Asset references
----------------------------------------------------------------------
local Assets = ReplicatedStorage:WaitForChild("Assets")
local LauncherModels = Assets:WaitForChild("Launcher", 3)
local BombModels = Assets:WaitForChild("Bomb", 3)

----------------------------------------------------------------------
-- Remote
----------------------------------------------------------------------
local RemotesFolder = workspace:WaitForChild("__THINGS"):WaitForChild("__REMOTES")

local equipEvent = Instance.new("RemoteEvent")
equipEvent.Name = "EquipItem"
equipEvent.Parent = RemotesFolder

----------------------------------------------------------------------
-- State: track each player's loadout and currently held weapon model
----------------------------------------------------------------------
local playerLoadouts = {} -- [player.UserId] = { ROCKET = "Classic Launcher", BOMB = "Classic Bomb", BACKPACK = "Classic Backpack" }
local equippedModels = {} -- [player.UserId] = { slot = "ROCKET", model = Model }

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
local function getHandPart(character)
	-- R15 check first, then R6 fallback
	return character:FindFirstChild("RightHand")
		or character:FindFirstChild("Right Arm")
end

local function clearHeldWeapon(player)
	local data = equippedModels[player.UserId]
	if data and data.model then
		data.model:Destroy()
	end
	equippedModels[player.UserId] = nil
end

local function getModelFolder(slotName)
	if slotName == "ROCKET" or slotName == "Launcher" then
		return LauncherModels or workspace:FindFirstChild("Launcher")
	elseif slotName == "BOMB" or slotName == "Bomb" then
		return BombModels or workspace:FindFirstChild("Bomb")
	end
	return nil
end

----------------------------------------------------------------------
-- Handle Loadout Change (From Inventory UI)
----------------------------------------------------------------------
local equipItemEvent = RemotesFolder:FindFirstChild("EquipItem") or Instance.new("RemoteEvent")
equipItemEvent.Name = "EquipItem"
equipItemEvent.Parent = RemotesFolder

-- Forward declarations for functions defined later
local HandleToolbarEquip
local GrantWeaponsToBackpack
local EquipPhysicalBackpackToCharacter

local function ValidateAction(player, actionType, cooldown)
	if not player or not player.Parent then return false end
	local attr = "LastAction_" .. tostring(actionType)
	local last = player:GetAttribute(attr)
	local now = os.clock()
	if last and (now - last) < cooldown then return false end
	player:SetAttribute(attr, now)
	return true
end

equipItemEvent.OnServerEvent:Connect(function(player, category, modelName, skinName)
	if not ValidateAction(player, "EquipItem", 0.5) then return end
	if type(category) ~= "string" or type(modelName) ~= "string" then return end
	
	local profile = Saving.GetPlayerData(player)
	if not profile then return end

	-- Authoritative validation: check if player can equip this item/skin
	local canEquip, err = InventoryUtil.CanEquip(profile, category, modelName, skinName)
	if not canEquip then
		return
	end

	if category == "BackPack" then
		profile.EquippedBackpack = modelName
		
		-- Save skin
		if not profile.EquippedSkins then profile.EquippedSkins = {} end
		if not profile.EquippedSkins[category] then profile.EquippedSkins[category] = {} end
		if skinName and skinName ~= "Default" then
			local skinFound = InventoryUtil.OwnsSkin(profile, category, modelName, skinName)
			if skinFound then
				profile.EquippedSkins[category][modelName] = {ID = skinName}
			else
				profile.EquippedSkins[category][modelName] = nil
			end
		else
			profile.EquippedSkins[category][modelName] = nil
		end
		
		-- Update storage capacity using single source of truth
		local newCapacity = InventoryUtil.GetBackpackCapacity(modelName)
		if profile.Storage then
			profile.Storage.Max = newCapacity
			player:SetAttribute("MaxBlocks", newCapacity)
			
			-- Truncate blocks if exceeding new capacity
			if profile.Storage.Amount > newCapacity then
				profile.Storage.Amount = newCapacity
				player:SetAttribute("Blocks", profile.Storage.Amount)
			end
		end
		
		if player.Character then
			EquipPhysicalBackpackToCharacter(player, player.Character)
		end
		return
	end

	if not playerLoadouts[player.UserId] then
		playerLoadouts[player.UserId] = { ROCKET = "Rocket Launcher", BOMB = "Bomb" }
	end

	-- Map UI category to Hotbar slot
	local slot = category == "Launcher" and "ROCKET" or (category == "Bomb" and "BOMB" or nil)
	if slot then
		playerLoadouts[player.UserId][slot] = modelName
		
		-- Save skin to profile
		if not profile.EquippedSkins then profile.EquippedSkins = {} end
		if not profile.EquippedSkins[category] then profile.EquippedSkins[category] = {} end
		if skinName and skinName ~= "Default" then
			local skinFound = false
			for _, s in ipairs(profile.Skins or {}) do
				if s.Category == category and s.ItemName == modelName and s.ID == skinName then
					skinFound = true
					break
				end
			end
			if skinFound then
				profile.EquippedSkins[category][modelName] = {ID = skinName}
			else
				profile.EquippedSkins[category][modelName] = nil
			end
		else
			profile.EquippedSkins[category][modelName] = nil
		end
		
		-- Persist to profile
		if category == "Launcher" then
			profile.EquippedLauncher = modelName
			player:SetAttribute("EquippedLauncher", modelName)
		elseif category == "Bomb" then
			profile.EquippedBomb = modelName
			player:SetAttribute("EquippedBomb", modelName)
		end
		
		-- Recreate physical tools with updated loadout and immediately equip into character's hand
		GrantWeaponsToBackpack(player, slot)
	end
end)

----------------------------------------------------------------------
-- Delete Skins Handler (Multi-select Delete System)
----------------------------------------------------------------------
local deleteSkinsRemote = RemotesFolder:FindFirstChild("DeleteSkins")
if not deleteSkinsRemote then
	deleteSkinsRemote = Instance.new("RemoteFunction")
	deleteSkinsRemote.Name = "DeleteSkins"
	deleteSkinsRemote.Parent = RemotesFolder
end

local function handleDeleteSkins(player, uidsList)
	if not ValidateAction(player, "DeleteSkins", 0.3) then
		return false, "Please wait before deleting again."
	end
	if type(uidsList) ~= "table" or #uidsList == 0 then
		return false, "No skins selected to delete."
	end

	local profile = Saving.GetPlayerData(player)
	if not profile then
		return false, "Player profile not found."
	end

	-- Security Guard: Prevent deleting skins while actively in a trade session
	if _G.GetByPlyr and _G.GetByPlyr(player) then
		return false, "Cannot delete skins while in an active trade session."
	end

	local deletedCount, deletedUids = SkinEquip.DeleteSkins(profile, uidsList)
	if deletedCount > 0 then
		-- Re-equip weapons/backpack if any equipped skin was removed
		pcall(function()
			GrantWeaponsToBackpack(player)
			if player.Character then
				EquipPhysicalBackpackToCharacter(player, player.Character)
			end
		end)

		-- Notify cross-service listeners
		for _, uid in ipairs(deletedUids) do
			if Library.Signal then
				Library.Signal.Fire("Skin Deleted", uid, player)
			end
		end

		Saving.SaveData(player, false)
		return true, deletedCount
	end

	return false, "No eligible skins were deleted."
end

deleteSkinsRemote.OnServerInvoke = handleDeleteSkins

if Library.Network and Library.Network.Invoked then
	Library.Network.Invoked("Delete Several Skins").OnInvoke = handleDeleteSkins
end

----------------------------------------------------------------------
local function getEveeraToolName(slotName, modelName)
	-- Return the actual model name so the Tool.Name matches the weapon model.
	-- This ensures TOOL_DATA lookups work even without the ToolName attribute.
	return modelName
end

local function clearBackpack(player)
	if player.Backpack then
		for _, item in ipairs(player.Backpack:GetChildren()) do
			if item:IsA("Tool") then
				item:Destroy()
			end
		end
	end
	if player.Character then
		for _, item in ipairs(player.Character:GetChildren()) do
			if item:IsA("Tool") then
				item:Destroy()
			end
		end
	end
end

----------------------------------------------------------------------
-- Logic
----------------------------------------------------------------------
-- Called to grant the player their inventory loadout into their Character / Backpack
GrantWeaponsToBackpack = function(player, forceEquipSlot)
	local character = player.Character
	if not character then return end

	-- Determine which slot was actively held by the character before clearing
	local currentlyHeldSlot = forceEquipSlot
	if not currentlyHeldSlot then
		for _, item in ipairs(character:GetChildren()) do
			if item:IsA("Tool") then
				currentlyHeldSlot = item:GetAttribute("SlotName")
				break
			end
		end
	end

	clearBackpack(player)

	-- Ensure loadout is loaded from profile
	local profile = Saving.GetPlayerData(player)
	if profile then
		local eqLauncher = profile.EquippedLauncher or "Rocket Launcher"
		local eqBomb = profile.EquippedBomb or "Bomb"
		
		-- Sanity check: verify they actually own the equipped launcher
		local launcherOwned = InventoryUtil.OwnsBaseEquipment(profile, "Launcher", eqLauncher)
		if not launcherOwned then
			eqLauncher = "Rocket Launcher"
			profile.EquippedLauncher = eqLauncher
		end

		-- Sanity check: verify they actually own the equipped bomb
		local bombOwned = InventoryUtil.OwnsBaseEquipment(profile, "Bomb", eqBomb)
		if not bombOwned then
			eqBomb = "Bomb"
			profile.EquippedBomb = eqBomb
		end

		playerLoadouts[player.UserId] = {
			ROCKET = eqLauncher,
			BOMB = eqBomb
		}
		
		player:SetAttribute("EquippedLauncher", eqLauncher)
		player:SetAttribute("EquippedBomb", eqBomb)
	else
		if not playerLoadouts[player.UserId] or playerLoadouts[player.UserId].ROCKET == "" or playerLoadouts[player.UserId].ROCKET == nil then
			playerLoadouts[player.UserId] = { ROCKET = "Rocket Launcher", BOMB = "Bomb" }
		end
	end

	local loadout = playerLoadouts[player.UserId]
	if not loadout then return end

	player:SetAttribute("EquippedLauncher", loadout.ROCKET or "")
	player:SetAttribute("EquippedBomb", loadout.BOMB or "")

	for slotName, modelName in pairs(loadout) do
		if modelName and modelName ~= "" then
			local folder = getModelFolder(slotName)
			if folder then
				local sourceModel = folder:FindFirstChild(modelName)
				if sourceModel then
					local tool = Instance.new("Tool")
					tool.Name = getEveeraToolName(slotName, modelName)
					tool.CanBeDropped = false
					tool.RequiresHandle = true
					
					-- Eveera animations (such as IdleAnim and FireRocket) already 
					-- apply the correct rotation to the arm/weapon. Base Grip must be 0,0,0!
					tool.Grip = CFrame.new()
					tool:SetAttribute("ToolName", modelName)

					-- CRITICAL FIX: Clone the entire model FIRST to preserve internal Weld references (Part0/Part1)
					local clonedModel = sourceModel:Clone()
					
					-- Apply skin texture
					local catName = (slotName == "ROCKET" and "Launcher") or "Bomb"
					local profile = Saving.GetPlayerData(player)
					local activeSkin = profile and profile.EquippedSkins and profile.EquippedSkins[catName] and profile.EquippedSkins[catName][modelName]
					if activeSkin then
						local success, skinConfig = pcall(function() return require(ReplicatedStorage:WaitForChild("Directory"):WaitForChild("Skins"):WaitForChild(catName):WaitForChild(modelName):WaitForChild(activeSkin.ID)) end)
						if success and skinConfig and skinConfig.textureId then
							for _, part in ipairs(clonedModel:GetDescendants()) do
								if part:IsA("MeshPart") then
									part.TextureID = "rbxassetid://" .. skinConfig.textureId
								elseif part:IsA("SpecialMesh") then
									part.TextureId = "rbxassetid://" .. skinConfig.textureId
								elseif part:IsA("Texture") or part:IsA("Decal") then
									part.Texture = "rbxassetid://" .. skinConfig.textureId
								end
							end
						end
					end
					
					for _, child in ipairs(clonedModel:GetChildren()) do
						if child:IsA("BasePart") then
							child.CanCollide = false
							child.Massless = true
						end
						child.Parent = tool
					end
					clonedModel:Destroy()

					-- Save a custom attribute so the Client Toolbar knows which slot this tool belongs to
					tool:SetAttribute("SlotName", slotName)
					
					-- If this is the active slot (or force-equipped slot, or default ROCKET), put directly into character's hand!
					if currentlyHeldSlot == slotName or (not currentlyHeldSlot and slotName == "ROCKET") then
						tool.Parent = character
					else
						tool.Parent = player.Backpack
					end
				end
			end
		end
	end
end

-- Listen for system-wide Re-equip requests (e.g. from RebirthService or ShopService)
if Library.Signal and Library.Signal.Fired then
	Library.Signal.Fired("Re-equip Player Loadout"):Connect(function(targetPlayer, forceSlot)
		if not targetPlayer or not targetPlayer.Parent then return end
		GrantWeaponsToBackpack(targetPlayer, forceSlot or "ROCKET")
		if targetPlayer.Character then
			EquipPhysicalBackpackToCharacter(targetPlayer, targetPlayer.Character)
		end
	end)
end

-- NOTE: EquipItem handler already registered above (line 84) with full validation,
-- loadout update, profile persistence, and HandleToolbarEquip/EquipPhysicalBackpack.
-- A second handler was here previously calling GrantWeaponsToBackpack which destroyed
-- and recreated all tools, causing a "two clicks to equip" bug.

EquipPhysicalBackpackToCharacter = function(player, character)
	if not player or not character then return end
	local profile = Library.Saving.GetPlayerData(player)
	local equippedName = (profile and profile.EquippedBackpack) or "SmallBag"

	-- Remove existing equipped 3D backpack model from character
	local oldBag = character:FindFirstChild("EquippedBackpack")
	if oldBag then
		oldBag:Destroy()
	end

	-- Find backpack model in ReplicatedStorage.Assets.Backpacks or Assets or workspace
	local backpacksFolder = Assets:FindFirstChild("Backpacks") or workspace:FindFirstChild("Backpacks") or Assets
	local modelTemplate = (backpacksFolder and backpacksFolder:FindFirstChild(equippedName))
		or Assets:FindFirstChild(equippedName)
		or workspace:FindFirstChild(equippedName)
		or (backpacksFolder and (backpacksFolder:FindFirstChild("SmallBag") or backpacksFolder:FindFirstChild("MediumBag")))

	if not modelTemplate then return end

	local bagModel = modelTemplate:Clone()
	bagModel.Name = "EquippedBackpack"
	
	-- Apply skin texture
	local activeSkin = profile and profile.EquippedSkins and profile.EquippedSkins["BackPack"] and profile.EquippedSkins["BackPack"][equippedName]
	if activeSkin then
		local success, skinConfig = pcall(function() return require(ReplicatedStorage:WaitForChild("Directory"):WaitForChild("Skins"):WaitForChild("BackPack"):WaitForChild(equippedName):WaitForChild(activeSkin.ID)) end)
		if success and skinConfig and skinConfig.textureId then
			for _, part in ipairs(bagModel:GetDescendants()) do
				if part:IsA("MeshPart") then
					part.TextureID = "rbxassetid://" .. skinConfig.textureId
				elseif part:IsA("SpecialMesh") then
					part.TextureId = "rbxassetid://" .. skinConfig.textureId
				elseif part:IsA("Texture") or part:IsA("Decal") then
					part.Texture = "rbxassetid://" .. skinConfig.textureId
				end
			end
		end
	end

	-- Resolve base part
	local basePart = bagModel.PrimaryPart 
		or bagModel:FindFirstChild("Base") 
		or bagModel:FindFirstChild("Main") 
		or bagModel:FindFirstChildWhichIsA("BasePart", true)

	if not basePart then return end

	-- Anchor/Weld all parts inside bagModel to basePart
	for _, part in ipairs(bagModel:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			part.Massless = true
			if part ~= basePart then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = basePart
				weld.Part1 = part
				weld.Parent = part
			end
		end
	end

	-- Find torso (UpperTorso for R15 or Torso for R6)
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	if not torso then return end

	-- Position on the back with slight offset and rotate 180 degrees
	basePart.CFrame = torso.CFrame * CFrame.new(0, 0, 0.6) * CFrame.Angles(0, math.rad(180), 0)

	local charWeld = Instance.new("WeldConstraint")
	charWeld.Part0 = torso
	charWeld.Part1 = basePart
	charWeld.Parent = basePart

	bagModel.Parent = character
end

-- Export to global for ShopService/InventoryController calls
_G.EquipPhysicalBackpackToCharacter = EquipPhysicalBackpackToCharacter

local function onCharacterAdded(player, character)
	-- Wait for player data to be loaded before equipping tools
	while player.Parent and not Saving.GetPlayerData(player) do
		task.wait(0.1)
	end
	if not player.Parent then return end

	-- Eveera ANIMATION REQUIREMENT
	local animFolder = Assets:FindFirstChild("Animations")
	if animFolder then
		for _, anim in ipairs(animFolder:GetChildren()) do
			if anim:IsA("Animation") then
				anim:Clone().Parent = character
			end
		end
	end
	
	-- Grant their tools to the backpack
	GrantWeaponsToBackpack(player)
	
	-- Attach 3D Backpack model to character's back
	task.delay(0.2, function()
		EquipPhysicalBackpackToCharacter(player, character)
	end)
end

Players.PlayerAdded:Connect(function(player)
	playerLoadouts[player.UserId] = { ROCKET = "", BOMB = "" } -- Starts empty
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	playerLoadouts[player.UserId] = nil
end)

for _, player in ipairs(Players:GetPlayers()) do
	if not playerLoadouts[player.UserId] then
		playerLoadouts[player.UserId] = { ROCKET = "", BOMB = "" }
	end
	if player.Character then
		onCharacterAdded(player, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
end

--print(" WeaponEquipService (Backpack Logic) initialized.")
