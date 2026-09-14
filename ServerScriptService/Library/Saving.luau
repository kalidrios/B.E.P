--[[
	© DestructionSimulator [2025]
	Server/Saving — Player data persistence
	
	Manages loading, saving, and auto-saving of player data.
]]--

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local DefaultStats = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Modules"):WaitForChild("DefaultStats"))
local Datastore = require(script.Parent:WaitForChild("Datastore"))

local Saving = {}

-- Player data cache
local playerData = {}

local AUTO_SAVE_INTERVAL = 120 -- seconds
local DATASTORE_NAME = "r"
local SCOPE = "global"

-- Fallback mock storage for Studio when API is disabled
local apiServicesEnabled = true
local mockDataStore = {}

local function getStore()
	if not apiServicesEnabled then return nil end
	local success, store = pcall(function()
		return Datastore.GetStore(DATASTORE_NAME, SCOPE)
	end)
	if success then
		return store
	else
		apiServicesEnabled = false
		warn("[Saving] Roblox API Services are not enabled. Falling back to local mock data.")
		return nil
	end
end

function Saving.GetDefaultData()
	local function deepClone(t)
		local clone = {}
		for k, v in pairs(t) do
			if type(v) == "table" then
				clone[k] = deepClone(v)
			else
				clone[k] = v
			end
		end
		return clone
	end

	local data = deepClone(DefaultStats)
	data.JoinTime = os.time()
	data.LastSave = os.time()
	return data
end

function Saving.GetPlayerData(player)
	return playerData[player.UserId]
end

function Saving.SetPlayerData(player, data)
	playerData[player.UserId] = data
end

function Saving.RemovePlayerData(player)
	playerData[player.UserId] = nil
end

function Saving.HasPlayerData(player)
	return playerData[player.UserId] ~= nil
end

function Saving.LoadData(player)
	local userId = player.UserId
	local store = getStore()
	
	local data
	local loadSuccess = false
	
	if store then
		local success, result = pcall(function()
			return Datastore.GetAsync(store, tostring(userId))
		end)
		
		if success then
			data = result
			loadSuccess = true
		else
			-- GetAsync failed after all retries: kick the player to prevent data loss
			warn("[Saving] Failed to fetch data from DataStore for key " .. userId .. ": " .. tostring(result))
			pcall(function()
				player:Kick("Falha ao carregar seus dados. Tente novamente em alguns segundos.")
			end)
			return nil
		end
	else
		-- Fallback to local mock cache
		data = mockDataStore[userId]
		loadSuccess = true
	end
	
	-- Deep copy default stats if no existing save found
	if not data then
		data = Saving.GetDefaultData()
	else
		-- Ensure any new stats keys from schema are merged (lazy initialization)
		local default = Saving.GetDefaultData()
		local function mergeDefaults(target, source)
			for k, v in pairs(source) do
				if target[k] == nil then
					if type(v) == "table" then
						target[k] = {}
						mergeDefaults(target[k], v)
					else
						target[k] = v
					end
				elseif type(v) == "table" and type(target[k]) == "table" then
					mergeDefaults(target[k], v)
				end
			end
		end
		mergeDefaults(data, default)
	end
	
	-- Session Lock via UpdateAsync (atomic TOCTOU-safe)
	if loadSuccess and data and not RunService:IsStudio() then
		local now = os.time()
		local lastSave = data.LastSaveTimestamp or data.LastSave or 0
		
		-- Break lock if it has been inactive for more than 180 seconds (3 minutes)
		if data.PlayingSession and (now - lastSave) < 180 then
			player:Kick("Sua sessão anterior ainda está ativa. Aguarde 1 minuto e tente novamente (Proteção contra Dupe).")
			return nil
		end
		
		-- Acquire lock atomically via UpdateAsync
		local sessionId = HttpService:GenerateGUID(false)
		if store then
			local lockAcquired = false
			local lockSuccess, lockErr = pcall(function()
				Datastore.UpdateAsync(store, tostring(userId), function(currentData)
					if not currentData then
						-- New player, no lock conflict
						data.PlayingSession = true
						data.SessionId = sessionId
						data.LastSaveTimestamp = now
						lockAcquired = true
						return data
					end
					
					local currentLastSave = currentData.LastSaveTimestamp or currentData.LastSave or 0
					if currentData.PlayingSession and (now - currentLastSave) < 180 then
						-- Lock is still held by another server
						lockAcquired = false
						return nil -- Abort the update
					end
					
					-- Lock is stale or absent, acquire it
					currentData.PlayingSession = true
					currentData.SessionId = sessionId
					currentData.LastSaveTimestamp = now
					lockAcquired = true
					
					-- Use the freshest data from the store
					data = currentData
					return currentData
				end)
			end)
			
			if not lockSuccess or not lockAcquired then
				pcall(function()
					player:Kick("Sua sessão anterior ainda está ativa em outro servidor. Tente novamente em breve.")
				end)
				return nil
			end
		else
			-- Mock store: just set lock fields
			data.PlayingSession = true
			data.SessionId = sessionId
			data.LastSaveTimestamp = now
		end
		
		-- Re-merge defaults after potentially refreshed data from UpdateAsync
		local default = Saving.GetDefaultData()
		local function mergeDefaults(target, source)
			for k, v in pairs(source) do
				if target[k] == nil then
					if type(v) == "table" then
						target[k] = {}
						mergeDefaults(target[k], v)
					else
						target[k] = v
					end
				elseif type(v) == "table" and type(target[k]) == "table" then
					mergeDefaults(target[k], v)
				end
			end
		end
		mergeDefaults(data, default)

		-- Ensure Storage fields always exist (prevent accidental nil causing 100 fallback)
		if not data.Storage then
			data.Storage = { Amount = 0, Max = (DefaultStats and DefaultStats.Storage and DefaultStats.Storage.Max) or 75 }
		end
		if data.Storage.Amount == nil then
			data.Storage.Amount = 0
		end
		if data.Storage.Max == nil then
			data.Storage.Max = (DefaultStats and DefaultStats.Storage and DefaultStats.Storage.Max) or 75
		end
	end
	
	data.LoginTime = os.time()
	data._playerInstance = player
	playerData[userId] = data
	player:SetAttribute("__LOADED", true)

	-- TradingService.CheckBro (and the reference ItalianBrainrotSimulator)
	-- gate trading on player:FindFirstChild("__LOADED"). FindFirstChild only
	-- sees child INSTANCES, not attributes, so the flag must also exist as a
	-- BoolValue parented to the player or no trade can ever initialize.
	if not player:FindFirstChild("__LOADED") then
		local loadedVar = Instance.new("BoolValue")
		loadedVar.Name = "__LOADED"
		loadedVar.Value = true
		loadedVar.Parent = player
	end
	
	return data
end

function Saving.SaveData(player, playerLeaving)
	local userId = player.UserId
	local data = playerData[userId]
	if not data then return false end
	
	local store = getStore()
	
	data.LastSaveTimestamp = os.time()
	data.LastSave = os.time()
	
	if playerLeaving then
		data.PlayingSession = false
		data.SessionId = nil
	end
	
	local saveSuccess = false
	if store then
		-- Create a copy without temporary non-serializable runtime keys (e.g. Instance objects like _playerInstance)
		local dataToSave = {}
		for k, v in pairs(data) do
			if k ~= "_playerInstance" and type(v) ~= "userdata" and type(v) ~= "function" and type(v) ~= "thread" then
				dataToSave[k] = v
			end
		end

		local success, err = pcall(function()
			Datastore.SetAsync(store, tostring(userId), dataToSave)
		end)
		if success then
			saveSuccess = true
		else
			warn("[Saving] Datastore SetAsync error: " .. tostring(err))
		end
	else
		-- Save to local mock store
		mockDataStore[userId] = data
		saveSuccess = true
	end
	
	if not saveSuccess then
		-- Fire Save Fail signal so systems like TradingService can abort active sessions safely
		pcall(function()
			local Signal = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Signal"))
			Signal.Fire("Save Fail", player)
		end)

		if playerLeaving and not RunService:IsStudio() then
			-- Critical save failure on leave: keep data in cache for BindToClose retry
			pcall(function()
				player:Kick("Falha crítica ao salvar seus dados. Entre novamente para evitar perda de progresso.")
			end)
		end
	end
	
	return saveSuccess
end

-- Auto-save loop
function Saving.StartAutoSave()
	task.spawn(function()
		while true do
			task.wait(AUTO_SAVE_INTERVAL)
			
			for _, player in ipairs(Players:GetPlayers()) do
				if playerData[player.UserId] then
					task.spawn(function()
						Saving.SaveData(player, false)
						--print(string.format("[Saving] Auto-saved data for %s", player.Name))
					end)
				end
			end
		end
	end)
end

return Saving
