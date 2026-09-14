--[[
	Â© DestructionSimulator [2025]
	Library â€” Central module hub
	
	FAIL-FAST: All require() calls are direct (no pcall wrapping).
	If any module errors during load, the error propagates up and breaks the chain.
	This is intentional â€” we want loud failures, not silent bugs.
	
	Loading sequence:
	1. Client waits for _G.IntroDone (set by Intro.client.luau)
	2. Shared modules are required synchronously (Functions, Asserts, Types, etc.)
	3. Context-specific library is loaded (Client or Server)
	4. Late-loading discovers any unregistered child ModuleScripts
	5. Library.Loaded = true once both shared and context-specific are ready
	6. Signal fires "Server Loaded" or "Client Loaded"
]]--

local RunService = game:GetService("RunService")

-- Intro is handled separately, Library must be loadable during intro

local _c = os.clock()
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Library = {
	Loaded = false,
	Things = workspace:WaitForChild("__THINGS"),
	Assets = ReplicatedStorage:WaitForChild("Assets"),
	Players = Players,
	RunService = game:GetService("RunService"),
	TweenService = game:GetService("TweenService"),
	UserInputService = game:GetService("UserInputService"),
	Heartbeat = function(stepCount)
		for _ = 1, stepCount or 1 do
			RunService.Heartbeat:Wait()
		end
	end,
	RenderStepped = function(stepCount)
		for _ = 1, stepCount or 1 do
			RunService.RenderStepped:Wait()
		end
	end,
	LocalPlayer = Players.LocalPlayer,
	-- Core modules (FAIL-FAST: require() without pcall)
	Functions = require(script.Functions),
	Asserts = require(script.Asserts),
	Types = require(script.Types),
	Modules = require(script.Modules),
	Signal = require(script.Signal),
	Variables = require(script.Variables),
	Shared = require(script.Shared),
	Util = require(script.Util),
	Audio = require(script.Audio),
	Directory = require(script.Directory),
	ShopConfig = require(script.ShopConfig),
}

local isLoaded
if RunService:IsServer() then
	local ServerScriptService = game:GetService("ServerScriptService")
	local ServerLibrary = require(ServerScriptService:WaitForChild("Library"))
	setmetatable(Library, {__index = ServerLibrary})
	Library.Network = ServerLibrary.Network
	isLoaded = function() return ServerLibrary.Loaded end
else
	Library.Network = require(script.Network)
	local ClientLibrary = require(script:WaitForChild("Client"))
	setmetatable(Library, {__index = ClientLibrary})
	isLoaded = function() return ClientLibrary.Loaded end
end

--- Main loading process for Library
task.spawn(function()
	local lateLoading = false
	for _, module in ipairs(script:GetChildren()) do
		if module.Name ~= "Client" then
			if not module:GetAttribute("NOLOAD") then
				if module:IsA("ModuleScript") then
					if Library[module.Name] == nil then
						if not lateLoading then
							task.wait()
							lateLoading = true
						end
						--print("Library (Shared) - Late loading: ", module)
						Library[module.Name] = require(module)
					end
				end
			end
		end
	end

	while not isLoaded() do
		task.wait()
	end

	Library.Loaded = true
	local clock = os.clock()
	local runType = RunService:IsClient() and "CLIENT" or "SERVER"

	--print(string.format(" %s | _L took %dms to initialize!", runType, (math.round((clock - _c) * 1000))))

	if not lateLoading then
		task.wait()
	end

	task.spawn(function()
		if RunService:IsServer() then
			Library.Signal.Fire("Server Loaded")
		else
			Library.Signal.Fire("Client Loaded")
		end
	end)
end)

--- Internal function to load the Library
function Library.Load() 
	error("unused [switch to requiring manually!]")
end

--- Internal function to see if the Library is loaded
function Library.IsLoaded()
	return Library.Loaded
end

return Library
