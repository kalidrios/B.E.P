--[[
	© DestructionSimulator [2025]
	Server/Network — Network communication module
	
	Handles RemoteEvents and RemoteFunctions between client and server.
]]--

local Network = {}

local RunService = game:GetService("RunService")

-- Remote storage
local remotes = {}

local function getRemotesFolder()
	local things = workspace:FindFirstChild("__THINGS") or workspace:WaitForChild("__THINGS", 10)
	if not things then
		error("[Network] workspace.__THINGS was not found")
	end

	local folder = things:FindFirstChild("__REMOTES")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "__REMOTES"
		folder.Parent = things
	end

	return folder
end

function Network.CreateRemote(name, className)
	className = className or "RemoteEvent"
	
	local remote = Instance.new(className)
	remote.Name = name
	remote.Parent = getRemotesFolder()
	
	remotes[name] = remote
	return remote
end

function Network.GetRemote(name, timeout)
	if remotes[name] then
		return remotes[name]
	end
	
	local folder = getRemotesFolder()
	local remote = folder:FindFirstChild(name)
	if not remote and not RunService:IsServer() then
		remote = folder:WaitForChild(name, timeout or 10)
	end

	if remote then
		remotes[name] = remote
	end
	return remote
end

function Network.FireClient(player, remoteName, ...)
	local remote = Network.GetRemote(remoteName) or Network.CreateRemote(remoteName, "RemoteEvent")
	if remote and remote:IsA("RemoteEvent") then
		remote:FireClient(player, ...)
	end
end

function Network.FireAllClients(remoteName, ...)
	local remote = Network.GetRemote(remoteName) or Network.CreateRemote(remoteName, "RemoteEvent")
	if remote and remote:IsA("RemoteEvent") then
		remote:FireAllClients(...)
	end
end

function Network.OnServerEvent(remoteName, callback)
	local remote = Network.GetRemote(remoteName)
	if remote and remote:IsA("RemoteEvent") then
		return remote.OnServerEvent:Connect(callback)
	end
end

function Network.OnServerInvoke(remoteName, callback)
	local remote = Network.GetRemote(remoteName)
	if remote and remote:IsA("RemoteFunction") then
		remote.OnServerInvoke = callback
	end
end

-- Velvet group compatibility extensions for Trading system support
local events = {}

function Network.Fired(name)
	name = string.lower(name)
	local event = events[name]
	if not event then
		event = Instance.new("BindableEvent")
		events[name] = event
		
		task.spawn(function()
			local remote = Network.GetRemote(name) or Network.CreateRemote(name, "RemoteEvent")
			if remote and remote:IsA("RemoteEvent") then
				remote.OnServerEvent:Connect(function(player, ...)
					event:Fire(player, ...)
				end)
			end
		end)
	end
	return event.Event
end

function Network.Invoked(name)
	name = string.lower(name)
	local event = events[name]
	if not event then
		event = Instance.new("BindableFunction")
		events[name] = event
		
		task.spawn(function()
			local remote = Network.GetRemote(name) or Network.CreateRemote(name, "RemoteFunction")
			if remote and remote:IsA("RemoteFunction") then
				remote.OnServerInvoke = function(player, ...)
					-- pcall the handler: an unprotected throw propagates into the
					-- invoking client's InvokeServer and fails the whole request
					-- with a generic error. Instead log the real cause server-side
					-- and return it so the client can display it.
					local results = table.pack(pcall(event.Invoke, event, player, ...))
					if not results[1] then
						warn(("[Network] '%s' handler error: %s"):format(name, tostring(results[2])))
						return false, "Server error: " .. tostring(results[2])
					end
					return table.unpack(results, 2, results.n)
				end
			end
		end)
	end
	return event
end

function Network.Fire(a, b, ...)
	local player, remoteName, args
	if typeof(a) == "Instance" and a:IsA("Player") then
		player, remoteName = a, b
		args = { ... }
	elseif typeof(b) == "Instance" and b:IsA("Player") then
		remoteName, player = a, b
		args = { ... }
	else
		remoteName = a
		args = { b, ... }
	end

	if not remoteName or typeof(remoteName) ~= "string" then
		warn("[Network] Fire called with invalid remoteName: " .. tostring(remoteName))
		return
	end

	if player and typeof(player) == "Instance" and player:IsA("Player") then
		Network.FireClient(player, string.lower(remoteName), unpack(args))
	else
		Network.FireAllClients(string.lower(remoteName), unpack(args))
	end
end

function Network.Invoke(player, remoteName, ...)
	local remote = Network.GetRemote(remoteName) or Network.CreateRemote(remoteName, "RemoteFunction")
	if remote and remote:IsA("RemoteFunction") then
		return remote:InvokeClient(player, ...)
	end
	return nil
end

return Network
