local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Network = {}
local events = {}

local function getRemotesFolder()
	local things = workspace:FindFirstChild("__THINGS")
	if not things then
		things = workspace:WaitForChild("__THINGS", 5)
	end
	if not things then return nil end
	local remotes = things:FindFirstChild("__REMOTES")
	if not remotes then
		remotes = things:WaitForChild("__REMOTES", 5)
	end
	return remotes
end

local function findRemote(folder, targetName)
	if not folder or typeof(targetName) ~= "string" then return nil end
	local exact = folder:FindFirstChild(targetName)
	if exact then return exact end

	local lowerTarget = string.lower(targetName)
	for _, child in ipairs(folder:GetChildren()) do
		if string.lower(child.Name) == lowerTarget then
			return child
		end
	end
	return nil
end

local function getRemote(name, isRF)
	if typeof(name) ~= "string" then return nil end

	local folder = getRemotesFolder()
	if not folder then
		local things = workspace:WaitForChild("__THINGS", 10)
		folder = things and things:WaitForChild("__REMOTES", 10)
		if not folder then
			return nil
		end
	end

	local remote = findRemote(folder, name)
	if not remote then
		if RunService:IsServer() then
			remote = Instance.new(isRF and "RemoteFunction" or "RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		else
			local directWait = folder:WaitForChild(name, 3)
			remote = directWait or findRemote(folder, name)
		end
	end
	return remote
end

function Network.Fire(a, b, ...)
	local player, name, args
	if typeof(a) == "Instance" and a:IsA("Player") then
		-- Fire(player, name, ...) convention
		player = a
		name = b
		args = { ... }
	elseif typeof(b) == "Instance" and b:IsA("Player") then
		-- Fire(name, player, ...) convention
		name = a
		player = b
		args = { ... }
	else
		-- Fire(name, ...) client/broadcast convention
		name = a
		args = { b, ... }
	end

	if typeof(name) ~= "string" then
		warn("[Network] Fire called with invalid remote name: " .. tostring(name))
		return
	end

	local remote = getRemote(name, false)
	if not remote then return end

	if RunService:IsServer() then
		if player and typeof(player) == "Instance" and player:IsA("Player") then
			remote:FireClient(player, unpack(args))
		else
			remote:FireAllClients(unpack(args))
		end
	else
		remote:FireServer(unpack(args))
	end
end

function Network.FireAll(name, ...)
	if typeof(name) ~= "string" then return end
	local args = {...}
	local remote = getRemote(name, false)
	if remote then
		remote:FireAllClients(unpack(args))
	end
end

function Network.Invoke(a, b, ...)
	local player, name, args
	if typeof(a) == "Instance" and a:IsA("Player") then
		player = a
		name = b
		args = { ... }
	elseif typeof(b) == "Instance" and b:IsA("Player") then
		name = a
		player = b
		args = { ... }
	else
		name = a
		args = { b, ... }
	end

	if typeof(name) ~= "string" then
		warn("[Network] Invoke called with invalid remote name: " .. tostring(name))
		return nil
	end

	local remote = getRemote(name, true)
	if not remote then return nil end

	if RunService:IsServer() then
		if player and typeof(player) == "Instance" and player:IsA("Player") then
			return remote:InvokeClient(player, unpack(args))
		end
		return nil
	else
		return remote:InvokeServer(unpack(args))
	end
end

function Network.Fired(name)
	local key = string.lower(name)
	local event = events[key]
	if not event then
		event = Instance.new("BindableEvent")
		events[key] = event
		
		task.spawn(function()
			local remote = getRemote(name, false)
			while not remote and not RunService:IsServer() do
				task.wait(1.5)
				remote = getRemote(name, false)
			end
			if remote then
				if RunService:IsServer() then
					remote.OnServerEvent:Connect(function(player, ...)
						event:Fire(player, ...)
					end)
				else
					remote.OnClientEvent:Connect(function(...)
						event:Fire(...)
					end)
				end
			end
		end)
	end
	return event.Event
end

function Network.Invoked(name)
	local key = string.lower(name)
	local event = events[key]
	if not event then
		event = Instance.new("BindableFunction")
		events[key] = event
		
		task.spawn(function()
			local remote = getRemote(name, true)
			while not remote and not RunService:IsServer() do
				task.wait(1.5)
				remote = getRemote(name, true)
			end
			if remote then
				if RunService:IsServer() then
					remote.OnServerInvoke = function(player, ...)
						return event:Invoke(player, ...)
					end
				else
					remote.OnClientInvoke = function(...)
						return event:Invoke(...)
					end
				end
			end
		end)
	end
	return event
end

return Network
