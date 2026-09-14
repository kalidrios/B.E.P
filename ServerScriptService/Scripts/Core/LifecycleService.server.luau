--[[
	© DestructionSimulator [2025]
	Core/LifecycleService — Dispatches server-wide player lifecycle & shutdown signals
	
	Dispatches signals required by TradingService, Saving, and other services:
	- "Player Added" (player)
	- "Player Removing" (player)
	- "Server Closing" ()
	- "Save Fail" (player)
]]--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Library = require(ReplicatedStorage:WaitForChild("Library"))
while not Library.IsLoaded() do
	task.wait()
end

local function onPlayerAdded(player)
	Library.Signal.Fire("Player Added", player)
end

local function onPlayerRemoving(player)
	Library.Signal.Fire("Player Removing", player)
end

-- Connect Player lifecycle events
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- Handle any players that joined before this script executed
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

-- Connect Server Closing
game:BindToClose(function()
	Library.Signal.Fire("Server Closing")
	-- Short delay to allow graceful cleanup in listening services
	task.wait(1)
end)

--print("[LifecycleService] Server Lifecycle Service initialized!")
