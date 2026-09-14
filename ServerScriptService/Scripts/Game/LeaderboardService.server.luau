--[[
	© DestructionSimulator [2026]
	Game/LeaderboardService — Server-side leaderboards (ItalianBrainrotSimulator parity)

	Mirror of the reference Leaderboard.legacy.luau:
	- "Get Local Leaderboard":  players currently in this server, ranked by
	  POWER (sum of the destruction multiplier of all skins, BackPacks excluded),
	  refreshed every 2s. Honors HideFromLeaderboard.
	- "Get Global Leaderboard": all-time top 100 by RAP (sum of the community
	  market price of every skin) from an OrderedDataStore, refreshed every 30s.
	  Entries are { username, level } (no Player refs — global keys may belong
	  to offline users).
	- Scores are persisted on player leave / server close.
]]--

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local _L = require(game.ReplicatedStorage:WaitForChild("Library"))
while not _L.Loaded do
	game:GetService("RunService").Heartbeat:Wait()
end

local Saving = _L.Saving
local SkinMath = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Modules"):WaitForChild("SkinMath"))
local RAP_Validator = require(game:GetService("ServerScriptService"):WaitForChild("Library"):WaitForChild("RAP_Validator"))

----------------------------------------------------------------------
-- Score definitions
----------------------------------------------------------------------
-- POWER: how much destruction the player's skins grant, i.e. the sum of
-- each skin's multiplier (SkinMath.CalculateMultiplier over MultMin/MultMax).
-- BackPacks grant storage, not destruction, so they are excluded.
local function getSkinPower(profile)
	if not profile or type(profile.Skins) ~= "table" then
		return 0
	end
	local total = 0
	local skinsDir = ReplicatedStorage:FindFirstChild("Directory")
		and ReplicatedStorage.Directory:FindFirstChild("Skins")
	for _, skin in ipairs(profile.Skins) do
		if skin.Category ~= "BackPack" and skin.Category ~= "backpack" then
			local mult = 1
			local catFolder = skinsDir and skinsDir:FindFirstChild(skin.Category)
			local itemFolder = catFolder and catFolder:FindFirstChild(skin.ItemName)
			local skinFile = itemFolder and itemFolder:FindFirstChild(skin.ID)
			if skinFile then
				local ok, skinConfig = pcall(require, skinFile)
				if ok and skinConfig then
					mult = SkinMath.CalculateMultiplier(skin.Float or 0.5, skinConfig.MultMin or 1, skinConfig.MultMax or 1)
				end
			end
			total = total + mult
		end
	end
	return math.floor(total * 100) / 100
end

-- RAP: sum of the community market price (RAP_Validator EMA) of every skin
-- the player owns. Key format matches RAP_Validator docs: "Category_SkinID".
local function getSkinRAP(profile)
	if not profile or type(profile.Skins) ~= "table" then
		return 0
	end
	local total = 0
	for _, skin in ipairs(profile.Skins) do
		local key = tostring(skin.Category or "?") .. "_" .. tostring(skin.ID or "?")
		local rap = RAP_Validator.GetRAP(key)
		if rap then
			total = total + rap
		end
	end
	return total
end

----------------------------------------------------------------------
-- Local (in-server) leaderboard — same 2s refresh loop as the reference
----------------------------------------------------------------------
local localLeaderboardData = {}

task.spawn(function()
	while true do
		local entries = {}
		for _, player in ipairs(Players:GetPlayers()) do
			local profile = Saving.GetPlayerData(player)
			if profile then
				local power = getSkinPower(profile)
				local rap = getSkinRAP(profile)
				-- Replicate the viewer's own scores so the client can show
				-- them on the board's PlayerPart panel.
				player:SetAttribute("SkinPower", power)
				player:SetAttribute("SkinRAP", rap)
				if not profile.HideFromLeaderboard then
					table.insert(entries, {
						player = player,
						username = player.Name,
						level = power,
					})
				end
			end
		end
		table.sort(entries, function(a, b)
			return a.level > b.level
		end)
		localLeaderboardData = entries
		task.wait(2)
	end
end)

_L.Network.Invoked("Get Local Leaderboard").OnInvoke = function(player, metric)
	local entries = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local profile = Saving.GetPlayerData(p)
		if profile then
			local power = getSkinPower(profile)
			local rap = getSkinRAP(profile)
			p:SetAttribute("SkinPower", power)
			p:SetAttribute("SkinRAP", rap)
			if not profile.HideFromLeaderboard then
				local score = (metric == "RAP") and rap or power
				table.insert(entries, {
					player = p,
					username = p.Name,
					level = score,
				})
			end
		end
	end
	table.sort(entries, function(a, b)
		return a.level > b.level
	end)
	return entries
end

----------------------------------------------------------------------
-- Global leaderboards — OrderedDataStore for RAP and Power
----------------------------------------------------------------------
local globalLeaderboardDataRAP = {}
local globalLeaderboardDataPower = {}
local nameCache = {}
local orderedStoreRAP = nil
local orderedStorePower = nil

pcall(function()
	orderedStoreRAP = DataStoreService:GetOrderedDataStore("globalRAP_v1")
	orderedStorePower = DataStoreService:GetOrderedDataStore("globalPower_v1")
end)

local function fetchGlobalPage(store)
	if not store then return {} end
	local page = nil
	for attempt = 1, 3 do
		local ok, result = pcall(function()
			return store:GetSortedAsync(false, 100):GetCurrentPage()
		end)
		if ok and result then
			page = result
			break
		end
		task.wait(2)
	end
	if not page then return {} end

	local converted = {}
	for _, data in ipairs(page) do
		local userId = tonumber(data.key)
		if userId and userId >= 1 and tonumber(data.value) then
			local name = nameCache[userId]
			if not name then
				local ok, fetched = pcall(function()
					return Players:GetNameFromUserIdAsync(userId)
				end)
				if ok and fetched then
					name = fetched
					nameCache[userId] = name
				end
			end
			table.insert(converted, {
				username = name or "???",
				level = math.floor(data.value),
			})
		end
	end
	return converted
end

local function refreshGlobal()
	local rapList = fetchGlobalPage(orderedStoreRAP)
	if #rapList > 0 then
		globalLeaderboardDataRAP = rapList
	end

	local powerList = fetchGlobalPage(orderedStorePower)
	if #powerList > 0 then
		globalLeaderboardDataPower = powerList
	end
end

task.spawn(function()
	refreshGlobal()
	while true do
		task.wait(30)
		refreshGlobal()
	end
end)

local function getFallbackList(metric)
	local fallback = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local profile = Saving.GetPlayerData(p)
		if profile and not profile.HideFromLeaderboard then
			local score = (metric == "Power") and getSkinPower(profile) or getSkinRAP(profile)
			table.insert(fallback, {
				player = p,
				username = p.Name,
				level = score,
			})
		end
	end
	table.sort(fallback, function(a, b)
		return a.level > b.level
	end)
	return fallback
end

_L.Network.Invoked("Get Global Leaderboard").OnInvoke = function(player, metric)
	metric = metric or "RAP"
	if metric == "Power" then
		if #globalLeaderboardDataPower > 0 then
			return globalLeaderboardDataPower
		else
			return getFallbackList("Power")
		end
	else
		if #globalLeaderboardDataRAP > 0 then
			return globalLeaderboardDataRAP
		else
			return getFallbackList("RAP")
		end
	end
end

_L.Network.Invoked("Get Global Power Leaderboard").OnInvoke = function(player)
	if #globalLeaderboardDataPower > 0 then
		return globalLeaderboardDataPower
	else
		return getFallbackList("Power")
	end
end

----------------------------------------------------------------------
-- Persistence — saves both RAP and Power scores
----------------------------------------------------------------------
local function saveScore(player)
	local profile = Saving.GetPlayerData(player)
	if not profile or profile.HideFromLeaderboard then return end

	local rapScore = getSkinRAP(profile)
	if orderedStoreRAP and rapScore > 0 then
		pcall(function()
			orderedStoreRAP:SetAsync(tostring(player.UserId), math.floor(rapScore))
		end)
	end

	local powerScore = getSkinPower(profile)
	if orderedStorePower and powerScore > 0 then
		pcall(function()
			orderedStorePower:SetAsync(tostring(player.UserId), math.floor(powerScore))
		end)
	end
end

Players.PlayerAdded:Connect(function(player)
	task.delay(5, function()
		saveScore(player)
		refreshGlobal()
	end)
end)

Players.PlayerRemoving:Connect(saveScore)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		saveScore(player)
	end
end)
