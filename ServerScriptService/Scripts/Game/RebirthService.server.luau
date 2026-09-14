--[[
	© DestructionSimulator [2025]
	Server/RebirthService — Handles modular Rebirth requests and unlocks Flying Carpet.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Library = require(ReplicatedStorage:WaitForChild("Library"))
while not Library.IsLoaded() do
	task.wait()
end

local LevelModule = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Modules"):WaitForChild("LevelModule"))
local Directory = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Directory"))

local remotesFolder = workspace:WaitForChild("__THINGS"):WaitForChild("__REMOTES")
local rebirthRemote = remotesFolder:FindFirstChild("PerformRebirth")
if not rebirthRemote then
	rebirthRemote = Instance.new("RemoteFunction")
	rebirthRemote.Name = "PerformRebirth"
	rebirthRemote.Parent = remotesFolder
end

-- Per-player rate limits (prevents DataStore throttle abuse via SaveData spam)
local rebirthCooldowns = {}
local claimGateCooldowns = {}

--- Helper to fetch Rebirth config by tier index
local function getRebirthConfig(rebirthTier: number)
	local rebirthCategory = Directory.Rebirths or Directory.Rebirth
	local rebirthsConfig = (rebirthCategory and rebirthCategory.Rebirths) or rebirthCategory
	if rebirthsConfig and rebirthsConfig[rebirthTier] then
		return rebirthsConfig[rebirthTier]
	end
	return nil
end

rebirthRemote.OnServerInvoke = function(player)
	if not player or not player.Parent then return false, "Invalid player" end
	
	local now = os.clock()
	if rebirthCooldowns[player.UserId] and (now - rebirthCooldowns[player.UserId]) < 2 then
		return false, "Please wait a moment..."
	end
	rebirthCooldowns[player.UserId] = now
	
	local profile = Library.Saving.GetPlayerData(player)
	if not profile then
		return false, "Player data not loaded. Please try again."
	end
	
	local currentRebirthCount = profile.Rebirth or 0
	local nextRebirthTier = currentRebirthCount + 1
	local rebirthConfig = getRebirthConfig(nextRebirthTier)

	-- Check if player has already reached max rebirth tier
	if not rebirthConfig then
		return false, "You have already reached the Maximum Rebirth level!"
	end
	
	local xp = profile.Experience or 0
	local level = LevelModule.GetLevelDataFromXP(xp)
	local reqLevel = rebirthConfig.LevelRequired or 75
	
	if level < reqLevel then
		return false, string.format("You need to reach Level %d to perform Rebirth %d! (Current Level: %d)", reqLevel, nextRebirthTier, level)
	end
	
	-- Perform Rebirth
	profile.Rebirth = nextRebirthTier
	profile.Experience = 0
	
	-- Reset currency values (Coins) and Storage Amount
	if profile.Currency then
		profile.Currency.Coins = 0
	end
	if profile.Storage then
		profile.Storage.Amount = 0
		profile.Storage.Max = 100
	end

	-- Reset equipment types (Weapons and Backpacks) to starter items
	-- Skins, Contracts, Gems, and UnlockedWorlds remain completely intact!
	profile.Weapons = {
		{ ID = "Rocket Launcher", Type = "LancaMisseis", Float = 0.5 },
		{ ID = "Bomb", Type = "Minas", Float = 0.5 }
	}

	-- Buyers of ElitePack keep their Spooky Staff and Sticky Bomb after Rebirth!
	if profile.UpgradesOwned and profile.UpgradesOwned.ElitePack then
		local hasSpooky = false
		local hasSticky = false
		for _, w in ipairs(profile.Weapons) do
			if w.ID == "Spooky Staff" then hasSpooky = true end
			if w.ID == "Sticky Bomb" then hasSticky = true end
		end
		if not hasSpooky then
			table.insert(profile.Weapons, { ID = "Spooky Staff", Type = "LancaMisseis", Float = 0.5 })
		end
		if not hasSticky then
			table.insert(profile.Weapons, { ID = "Sticky Bomb", Type = "Minas", Float = 0.5 })
		end
	end

	profile.Backpacks = { "SmallBag" }
	profile.EquippedLauncher = "Rocket Launcher"
	profile.EquippedBomb = "Bomb"
	profile.EquippedBackpack = "SmallBag"
	profile.EquippedWeapon = nil

	if not profile.Carpets then profile.Carpets = {} end
	if not table.find(profile.Carpets, "Original") then
		table.insert(profile.Carpets, "Original")
	end
	profile.EquippedCarpet = "Original"
	
	-- Persist immediately to prevent rollback / dupe
	Library.Saving.SaveData(player, false)
	
	-- Update player attributes
	player:SetAttribute("Rebirth", profile.Rebirth)
	player:SetAttribute("Experience", 0)
	player:SetAttribute("Coins", 0)
	player:SetAttribute("Blocks", 0)
	player:SetAttribute("MaxBlocks", 100)
	player:SetAttribute("EquippedLauncher", "Rocket Launcher")
	player:SetAttribute("EquippedBomb", "Bomb")
	player:SetAttribute("EquippedBackpack", "SmallBag")
	player:SetAttribute("EquippedCarpet", "Original")

	-- Re-equip starter weapons and SmallBag physically on the character!
	if Library.Signal and Library.Signal.Fire then
		Library.Signal.Fire("Re-equip Player Loadout", player, "ROCKET")
	end

	-- Teleport player back to Spawn world
	Library.Signal.Fire("Teleport Player World", player, "Spawn")

	return true, string.format("Rebirth #%d Successful! Multiplier & Flying Carpet Updated!", profile.Rebirth)
end

-- ClaimUGCGate Remote Function (Consumes 1 Rebirth to grant UGC_Sandbox access)
local claimUGCGateRemote = remotesFolder:FindFirstChild("ClaimUGCGate")
if not claimUGCGateRemote then
	claimUGCGateRemote = Instance.new("RemoteFunction")
	claimUGCGateRemote.Name = "ClaimUGCGate"
	claimUGCGateRemote.Parent = remotesFolder
end

claimUGCGateRemote.OnServerInvoke = function(player)
	if not player or not player.Parent then return false, "Invalid player" end

	local now = os.clock()
	if claimGateCooldowns[player.UserId] and (now - claimGateCooldowns[player.UserId]) < 2 then
		return false, "Please wait a moment..."
	end
	claimGateCooldowns[player.UserId] = now

	local profile = Library.Saving.GetPlayerData(player)
	if not profile then
		return false, "Player data not loaded. Please try again."
	end

	-- Idempotent: already unlocked → free travel, no double charge
	if profile.OwnsUGCVault then
		player:SetAttribute("OwnsUGCVault", true)
		return true
	end

	local rebirths = profile.Rebirth or 0
	if rebirths < 15 then
		return false, "You need at least 15 Rebirths to claim the UGC!"
	end

	-- Deduct 15 Rebirths and permanently unlock UGC Vault
	profile.Rebirth = rebirths - 15
	profile.OwnsUGCVault = true
	player:SetAttribute("Rebirth", profile.Rebirth)
	player:SetAttribute("OwnsUGCVault", true)

	-- Unlock UGC_Sandbox world in unlocked list if needed
	if not profile.UnlockedWorlds then profile.UnlockedWorlds = { "Spawn" } end
	if not table.find(profile.UnlockedWorlds, "UGC_Sandbox") then
		table.insert(profile.UnlockedWorlds, "UGC_Sandbox")
	end

	-- Persist immediately
	Library.Saving.SaveData(player, false)

	return true
end
