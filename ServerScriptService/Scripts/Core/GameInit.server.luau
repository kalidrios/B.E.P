--[[
	Â© DestructionSimulator [2025]
	Core/GameInit â€” Main server initialization script
	
	This is the first server script to run. It:
	1. Sets up the intro remote (for Fail-Fast handshake with client)
	2. Initializes the Library
	3. Starts the auto-save system
]]--

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local AnalyticsManager = require(ServerScriptService:WaitForChild("Library"):WaitForChild("AnalyticsManager"))

local things = workspace:FindFirstChild("__THINGS")
if not things then
	things = Instance.new("Folder")
	things.Name = "__THINGS"
	things.Parent = workspace
end

local remotes = things:FindFirstChild("__REMOTES")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "__REMOTES"
	remotes.Parent = things
end

local introRemote = remotes:FindFirstChild("intro")
if not introRemote then
	introRemote = Instance.new("RemoteFunction")
	introRemote.Name = "intro"
	introRemote.Parent = remotes
end

local weaponHitRemote = remotes:FindFirstChild("WeaponHit")
if not weaponHitRemote then
	weaponHitRemote = Instance.new("RemoteEvent")
	weaponHitRemote.Name = "WeaponHit"
	weaponHitRemote.Parent = remotes
end

local levelUpEvent = remotes:FindFirstChild("LevelUpEvent")
if not levelUpEvent then
	levelUpEvent = Instance.new("RemoteEvent")
	levelUpEvent.Name = "LevelUpEvent"
	levelUpEvent.Parent = remotes
end

local rebirthRemote = remotes:FindFirstChild("PerformRebirth")
if not rebirthRemote then
	rebirthRemote = Instance.new("RemoteFunction")
	rebirthRemote.Name = "PerformRebirth"
	rebirthRemote.Parent = remotes
end

-- Pre-register server->client notification remotes so client listeners connect instantly without retries
local preRegisteredRemotes = {
	"setting changed",
	"start shutdown",
	"trade recieved",
	"trade cancelled",
	"trade ignored",
	"trade processed",
	"trade errored",
	"trade sent chat result",
	"init trade",
	"update trade",
	"update trade invites open",
	"send message",
	"accept trade invite",
	"ignore trade",
	"NotificationEvent",
	"OpenAdminHelp",
}

for _, remoteName in ipairs(preRegisteredRemotes) do
	if not remotes:FindFirstChild(remoteName) then
		local r = Instance.new("RemoteEvent")
		r.Name = remoteName
		r.Parent = remotes
	end
end

local preRegisteredRemoteFunctions = {
	"DeleteSkins",
	"AdminCommandInvoke",
	"GetAdminCommands",
	"IsAdmin",
}

for _, rfName in ipairs(preRegisteredRemoteFunctions) do
	if not remotes:FindFirstChild(rfName) then
		local rf = Instance.new("RemoteFunction")
		rf.Name = rfName
		rf.Parent = remotes
	end
end

introRemote.OnServerInvoke = function(player, ready)
	-- For now, always allow progression (no ban check)
	-- Returns: canProgress, isBanned, timeLeft
	return true, false, nil
end

-- Move Workspace.Launcher to ReplicatedStorage.Assets.Launcher for replication & StreamingEnabled bypass
local wl = workspace:FindFirstChild("Launcher")
local assets = ReplicatedStorage:FindFirstChild("Assets")
if wl and assets then
	local oldLauncher = assets:FindFirstChild("Launcher")
	if oldLauncher then oldLauncher:Destroy() end
	wl.Parent = assets
end



-- Initialize Library (FAIL-FAST: no pcall)
local Library = require(ReplicatedStorage:WaitForChild("Library"))

-- Wait for Library to fully load
while not Library.IsLoaded() do
	task.wait()
end

--print(" DestructionSimulator server initialized!")

-- Start auto-save
Library.Saving.StartAutoSave()

local LevelModule = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Modules"):WaitForChild("LevelModule"))
local DefaultStats = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Modules"):WaitForChild("DefaultStats"))

-- Central Stats Replication Thread (replicates live player profile stats to client attributes)
local lastReplicated = {}
task.spawn(function()
	while true do
		task.wait(0.1)
		for _, player in ipairs(Players:GetPlayers()) do
			local data = Library.Saving.GetPlayerData(player)
			if data then
				local coins = (data.Currency and data.Currency.Coins) or 0
				local gems = (data.Currency and data.Currency.Gems) or 0
				local blocks = (data.Storage and data.Storage.Amount) or 0
				local defaultMax = (DefaultStats and DefaultStats.Storage and DefaultStats.Storage.Max) or 100
				local maxBlocks = (data.Storage and data.Storage.Max) or defaultMax
				local exp = data.Experience or 0
				local destroyed = data.DestructiblesDestroyed or 0
				local level = LevelModule.GetLevelDataFromXP(exp)
				
				-- Root `Contracts` is the authoritative key (TradingService and shops
				-- write it first); Currency.Contracts is a legacy mirror. Reading
				-- Currency first would re-replicate a stale value and freeze the HUD
				-- after a trade.
				local contracts = data.Contracts or (data.Currency and data.Currency.Contracts) or 0
				
				local key = player.UserId
				local last = lastReplicated[key]
				
				if last and level > last.Level then
					-- Level Up detected! Reward contracts proportional to level: level + 10
					local contractsGained = LevelModule.GetContractsGained(level)
					if not data.Currency then data.Currency = {} end
					-- Converge both keys from the authoritative value instead of
					-- adding onto each (which would preserve any prior divergence).
					contracts = contracts + contractsGained
					data.Contracts = contracts
					data.Currency.Contracts = contracts
					
					levelUpEvent:FireClient(player, level, contractsGained)

					if level >= 2 then
						AnalyticsManager.LogOneTimeStep(player, "Onboarding_FTUE", 4, "First_LevelUp")
					end
				end

				local rebirth = data.Rebirth or 0
				local tutorialCompleted = data.TutorialCompleted or false
				local guideCompleted = data.GuideCompleted or false
				local ownsUGCVault = data.OwnsUGCVault or false

				if not last or last.Coins ~= coins or last.Gems ~= gems or last.Blocks ~= blocks or last.MaxBlocks ~= maxBlocks or last.Experience ~= exp or last.Contracts ~= contracts or last.TutorialCompleted ~= tutorialCompleted or last.GuideCompleted ~= guideCompleted or last.OwnsUGCVault ~= ownsUGCVault or last.Rebirth ~= rebirth then
					player:SetAttribute("Coins", coins)
					player:SetAttribute("Gems", gems)
					player:SetAttribute("Blocks", blocks)
					player:SetAttribute("MaxBlocks", maxBlocks)
					player:SetAttribute("Experience", exp)
					player:SetAttribute("Level", level)
					player:SetAttribute("Contracts", contracts)
					player:SetAttribute("DestructiblesDestroyed", destroyed)
					player:SetAttribute("TutorialCompleted", tutorialCompleted)
					player:SetAttribute("GuideCompleted", guideCompleted)
					player:SetAttribute("OwnsUGCVault", ownsUGCVault)
					player:SetAttribute("Rebirth", rebirth)
					
					lastReplicated[key] = {
						Coins = coins,
						Gems = gems,
						Blocks = blocks,
						MaxBlocks = maxBlocks,
						Experience = exp,
						Level = level,
						Contracts = contracts,
						DestructiblesDestroyed = destroyed,
						TutorialCompleted = tutorialCompleted,
						GuideCompleted = guideCompleted,
						OwnsUGCVault = ownsUGCVault,
						Rebirth = rebirth
					}
				end
			end
		end
	end
end)

-- Tutorial completion remote handler (saves tutorial progression permanently)
local remotesFolder = workspace:WaitForChild("__THINGS"):WaitForChild("__REMOTES")
local completeTutorialRemote = remotesFolder:FindFirstChild("CompleteTutorial") or Instance.new("RemoteEvent")
completeTutorialRemote.Name = "CompleteTutorial"
completeTutorialRemote.Parent = remotesFolder

completeTutorialRemote.OnServerEvent:Connect(function(player, tutorialType)
	local data = Library.Saving.GetPlayerData(player)
	if not data then return end
	if tutorialType == "Main" or tutorialType == "FirstTutorial" then
		data.TutorialCompleted = true
		player:SetAttribute("TutorialCompleted", true)
		AnalyticsManager.LogOneTimeStep(player, "Onboarding_FTUE", 5, "Tutorial_Completed")
	elseif tutorialType == "Guide" or tutorialType == "SecondTutorial" or tutorialType == "ThirdBeam" then
		data.GuideCompleted = true
		player:SetAttribute("GuideCompleted", true)
	end
	Library.Saving.SaveData(player)
end)

-- Player join/leave handlers
local function onPlayerAdded(player)
	Library.Saving.LoadData(player)
	
	-- Log Funnel 1 Step 1: Player_Joined
	AnalyticsManager.LogOneTimeStep(player, "Onboarding_FTUE", 1, "Player_Joined")

	-- Check existing milestones for reconnecting / existing players
	local data = Library.Saving.GetPlayerData(player)
	if (data.DestructiblesDestroyed or 0) >= 1 then
		AnalyticsManager.LogOneTimeStep(player, "Onboarding_FTUE", 2, "First_Block_Destroyed")
	end
	if (data.Currency and data.Currency.Coins or 0) > 0 then
		AnalyticsManager.LogOneTimeStep(player, "Onboarding_FTUE", 3, "First_Blocks_Sold")
	end
	local level = LevelModule.GetLevelDataFromXP(data.Experience or 0)
	if level >= 2 then
		AnalyticsManager.LogOneTimeStep(player, "Onboarding_FTUE", 4, "First_LevelUp")
	end
	if data.TutorialCompleted then
		AnalyticsManager.LogOneTimeStep(player, "Onboarding_FTUE", 5, "Tutorial_Completed")
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	--print(string.format("[GameInit] Player leaving: %s (%d)", player.Name, player.UserId))
	lastReplicated[player.UserId] = nil
	
	-- Save player data and cleanup cache
	Library.Saving.SaveData(player, true)
	Library.Saving.RemovePlayerData(player)
end)

-- Save everyone on server shutdown
game:BindToClose(function()
	-- print("[GameInit] Server shutting down, saving all players...")
	for _, player in ipairs(Players:GetPlayers()) do
		Library.Saving.SaveData(player, true)
	end
end)
