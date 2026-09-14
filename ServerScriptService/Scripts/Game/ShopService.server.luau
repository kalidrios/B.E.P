--[[
	© DestructionSimulator [2025]
	Server/ShopService — Handles purchases from the GearShop.
	Provides remote functions for clients to fetch data and request purchases.
]]

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
local ShopConfig = require(ReplicatedStorage.Library.ShopConfig)
local DefaultStats = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Modules"):WaitForChild("DefaultStats"))

----------------------------------------------------------------------
-- Setup Remotes
----------------------------------------------------------------------
local RemotesFolder = workspace:WaitForChild("__THINGS"):WaitForChild("__REMOTES")

local getPlayerDataRemote = RemotesFolder:FindFirstChild("GetPlayerData") or Instance.new("RemoteFunction")
getPlayerDataRemote.Name = "GetPlayerData"
getPlayerDataRemote.Parent = RemotesFolder

local buyItemRemote = RemotesFolder:FindFirstChild("BuyItem") or Instance.new("RemoteFunction")
buyItemRemote.Name = "BuyItem"
buyItemRemote.Parent = RemotesFolder

local sellBlocksRemote = RemotesFolder:FindFirstChild("SellBlocks") or Instance.new("RemoteFunction")
sellBlocksRemote.Name = "SellBlocks"
sellBlocksRemote.Parent = RemotesFolder

local SellManager = require(ServerScriptService.Library.SellManager)
local InventoryUtil = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Modules"):WaitForChild("InventoryUtil"))

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
local function hasItem(profile, category, itemName)
	return InventoryUtil.OwnsBaseEquipment(profile, category, itemName)
end

----------------------------------------------------------------------
-- Remote Implementations
----------------------------------------------------------------------

getPlayerDataRemote.OnServerInvoke = function(player, target)
	-- Clients pass a target Player when they need someone else's public
	-- profile (trade list, trade ratings). Validate strictly and fall back
	-- to the caller for anything malformed.
	if typeof(target) ~= "Instance" or not target:IsA("Player") or not target.Parent then
		target = player
	end
	local profile = Saving.GetPlayerData(target)
	if not profile then return nil end
	
	-- Return a simplified/cloned table to avoid client mutation of server cache
	return {
		Coins = (profile.Currency and profile.Currency.Coins) or 0,
		Weapons = profile.Weapons or {},
		Backpacks = profile.Backpacks or {},
		EquippedBackpack = profile.EquippedBackpack or "SmallBag",
		StorageMax = (profile.Storage and profile.Storage.Max) or ((DefaultStats and DefaultStats.Storage and DefaultStats.Storage.Max) or 100),
		StorageAmount = (profile.Storage and profile.Storage.Amount) or 0,
		Skins = profile.Skins or {},
		EquippedSkins = profile.EquippedSkins or {},
		Settings = profile.Settings or {},
		UpgradesOwned = profile.UpgradesOwned or {},
		Contracts = profile.Contracts or 0
	}
end

local purchaseCooldowns = {}

local AnalyticsManager = require(ServerScriptService:WaitForChild("Library"):WaitForChild("AnalyticsManager"))

buyItemRemote.OnServerInvoke = function(player, category, itemName)
	local now = os.clock()
	if purchaseCooldowns[player] and now < purchaseCooldowns[player] then
		return { Success = false, Error = "Please wait a moment before purchasing again." }
	end
	purchaseCooldowns[player] = now + 0.3

	local profile = Saving.GetPlayerData(player)
	if not profile then
		return { Success = false, Error = "Player data not loaded." }
	end

	-- Find item config and validate world availability
	local currentWorld = player:GetAttribute("World") or "Spawn"
	local availableItems = ShopConfig.GetItems(category, currentWorld)
	local itemConfig = nil
	for _, item in ipairs(availableItems) do
		if item.Name == itemName then
			itemConfig = item
			break
		end
	end

	if not itemConfig then
		return { Success = false, Error = "This item is not available in your current world!" }
	end

	-- Check ownership
	if hasItem(profile, category, itemName) then
		return { Success = false, Error = "You already own this item!" }
	end

	-- Check balance
	if not profile.Currency then
		profile.Currency = { Coins = 0, Gems = 0 }
	end

	local coins = profile.Currency.Coins or 0
	if coins < itemConfig.Price then
		return { Success = false, Error = "Not enough Coins!" }
	end

	-- Deduct price
	profile.Currency.Coins = coins - itemConfig.Price

	-- Grant item
	if category == "Launcher" or category == "Bomb" then
		if not profile.Weapons then profile.Weapons = {} end
		local weaponType = category == "Launcher" and "LancaMisseis" or "Minas"
		table.insert(profile.Weapons, {
			ID = itemName,
			Type = weaponType,
			Float = math.random() -- Assign a random float multiplier as per Eveera schema
		})

		-- Auto-equip newly bought weapon immediately so player holds it right away
		local slot = (category == "Launcher") and "ROCKET" or "BOMB"
		if category == "Launcher" then
			profile.EquippedLauncher = itemName
			player:SetAttribute("EquippedLauncher", itemName)
		else
			profile.EquippedBomb = itemName
			player:SetAttribute("EquippedBomb", itemName)
		end
		if Library.Signal and Library.Signal.Fire then
			Library.Signal.Fire("Re-equip Player Loadout", player, slot)
		end
	elseif category == "BackPack" then
		if not profile.Backpacks then profile.Backpacks = { "SmallBag" } end
		table.insert(profile.Backpacks, itemName)
		profile.TutorialCompleted = true
		AnalyticsManager.LogOneTimeStep(player, "Onboarding_FTUE", 5, "Tutorial_Completed")

		-- Auto-equip newly bought backpack and update storage capacity
		profile.EquippedBackpack = itemName
		player:SetAttribute("EquippedBackpack", itemName)
		if itemConfig.Capacity and profile.Storage then
			profile.Storage.Max = itemConfig.Capacity
			player:SetAttribute("MaxBlocks", itemConfig.Capacity)
		end
		if Library.Signal and Library.Signal.Fire then
			Library.Signal.Fire("Re-equip Player Loadout", player)
		end
	end

	return {
		Success = true,
		Coins = profile.Currency.Coins,
		Weapons = profile.Weapons or {},
		Backpacks = profile.Backpacks or {}
	}
end

local function ValidateAction(player, actionType, cooldown)
	if not player or not player.Parent then return false end
	local attr = "LastAction_" .. tostring(actionType)
	local last = player:GetAttribute(attr)
	local now = os.clock()
	if last and (now - last) < cooldown then return false end
	player:SetAttribute(attr, now)
	return true
end

sellBlocksRemote.OnServerInvoke = function(player)
	if not ValidateAction(player, "SellBlocks", 0.3) then return nil end
	local character = player.Character
	if not character or not character:FindFirstChild("HumanoidRootPart") then return nil end
	
	-- Distance check to the closest Sell part in the player's active world
	local playerPos = character.HumanoidRootPart.Position
	local closestDist = math.huge
	local currentWorld = player:GetAttribute("World") or "Spawn"
	local mapFolder = workspace:FindFirstChild("__MAP") or workspace:FindFirstChild("MAP") or workspace
	local worldFolder = mapFolder:FindFirstChild(currentWorld) or mapFolder

	for _, desc in ipairs(worldFolder:GetDescendants()) do
		if desc.Name == "Sell" and (desc:IsA("Model") or desc:IsA("Folder") or desc:IsA("BasePart")) then
			local part = desc:FindFirstChild("Interact") or desc:FindFirstChild("Part") or (desc:IsA("BasePart") and desc) or desc.PrimaryPart
			if part and part:IsA("BasePart") then
				local d = (playerPos - part.Position).Magnitude
				if d < closestDist then
					closestDist = d
				end
			end
		end
	end

	-- Fallback check across whole workspace if not found in worldFolder
	if closestDist == math.huge then
		for _, desc in ipairs(workspace:GetDescendants()) do
			if desc.Name == "Sell" and (desc:IsA("Model") or desc:IsA("Folder") or desc:IsA("BasePart")) then
				local part = desc:FindFirstChild("Interact") or desc:FindFirstChild("Part") or (desc:IsA("BasePart") and desc) or desc.PrimaryPart
				if part and part:IsA("BasePart") then
					local d = (playerPos - part.Position).Magnitude
					if d < closestDist then
						closestDist = d
					end
				end
			end
		end
	end

	if closestDist > 80 then
		warn(string.format("%s tried to sell too far away (closest sell part is %.1f studs)", player.Name, closestDist))
		return nil
	end
	
	local profile = Saving.GetPlayerData(player)
	if not profile then return nil end
	
	local result = SellManager.SellBlocks(profile)
	if result and result.blocksSold and result.blocksSold > 0 then
		-- Update player attributes immediately for instant HUD sync
		player:SetAttribute("Blocks", profile.Storage and profile.Storage.Amount or 0)
		player:SetAttribute("Coins", profile.Currency and profile.Currency.Coins or 0)
		player:SetAttribute("Experience", profile.Experience or 0)
		
		-- Log Onboarding Step 3: First_Blocks_Sold (where player learned to sell)
		local AnalyticsManager = require(ServerScriptService:WaitForChild("Library"):WaitForChild("AnalyticsManager"))
		AnalyticsManager.LogOneTimeStep(player, "Onboarding_FTUE", 3, "First_Blocks_Sold")

		-- Save profile
		Saving.SaveData(player, false)
	end
	
	return result
end

Players.PlayerRemoving:Connect(function(player)
	purchaseCooldowns[player] = nil
end)

--print(" ShopService initialized.")
