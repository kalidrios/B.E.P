local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Save = {}
local cache = {}

local function getPlayerDataRemote()
	local things = workspace:FindFirstChild("__THINGS")
	if not things then
		things = workspace:WaitForChild("__THINGS", 5)
	end
	if not things then return nil end
	local remotes = things:FindFirstChild("__REMOTES")
	if not remotes then
		remotes = things:WaitForChild("__REMOTES", 5)
	end
	if not remotes then return nil end
	return remotes:FindFirstChild("GetPlayerData") or remotes:WaitForChild("GetPlayerData", 5)
end

function Save.Get(player, ignoreCache)
	if not player then
		player = game.Players.LocalPlayer
	end
	
	if not ignoreCache and cache[player.UserId] then
		return cache[player.UserId]
	end
	
	local remote = getPlayerDataRemote()
	if not remote then
		warn("[Save] GetPlayerData remote not found yet for player: " .. player.Name)
		return nil
	end
	
	local success, data = pcall(function()
		return remote:InvokeServer(player)
	end)
	
	if success and data then
		cache[player.UserId] = data
		return data
	end
	
	return nil
end

function Save.Invalidate(player)
	if not player then
		player = game.Players.LocalPlayer
	end
	if player then
		cache[player.UserId] = nil
	end
end

task.spawn(function()
	local Network = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Network"))
	Network.Fired("Setting Changed"):Connect(function(setting, value)
		local localPlayer = game.Players.LocalPlayer
		local data = cache[localPlayer.UserId]
		if data then
			if not data.Settings then
				data.Settings = {}
			end
			data.Settings[setting] = value
		end
	end)

	Network.Fired("Upgrade Changed"):Connect(function(upgradeName, level)
		local localPlayer = game.Players.LocalPlayer
		local data = cache[localPlayer.UserId]
		if data then
			if not data.UpgradesOwned then
				data.UpgradesOwned = {}
			end
			data.UpgradesOwned[upgradeName] = level
		end
	end)
end)

return Save
