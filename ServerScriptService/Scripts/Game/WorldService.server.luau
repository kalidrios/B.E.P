--[[
	© DestructionSimulator [2025]
	Game/WorldService — Server-side world provider matching ItalianBrainrotSimulator (IBS) Architecture

	Master templates are stored in ServerStorage.__WORLDS (Spawn, Magic, etc.).
	Dynamic Multi-World Mover:
	- When a world has >= 1 player, it lives inside workspace.__MAP[worldName].
	- When a world has 0 players, it returns to ServerStorage.__WORLDS[worldName] to save memory and physics overhead.
	- Players can be in different worlds simultaneously. Teleporting ONLY moves the player who requested it.
]]--

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Library = require(ReplicatedStorage:WaitForChild("Library"))
while not Library.IsLoaded() do
	task.wait()
end

local AreaManager = require(script.Parent:WaitForChild("AreaManager"))

local WORLDS_FOLDER = ServerStorage:FindFirstChild("__WORLDS")
if not WORLDS_FOLDER then
	local wsWorlds = workspace:FindFirstChild("__WORLDS")
	if wsWorlds then
		wsWorlds.Parent = ServerStorage
		WORLDS_FOLDER = wsWorlds
	else
		WORLDS_FOLDER = ServerStorage:WaitForChild("__WORLDS", 10)
	end
end

if not WORLDS_FOLDER then
	warn("[WorldService] ServerStorage.__WORLDS not found yet, will check on demand.")
end

local RemotesFolder = workspace:WaitForChild("__THINGS"):WaitForChild("__REMOTES")
local RequestWorldRemote = RemotesFolder:FindFirstChild("RequestWorld")
if not RequestWorldRemote then
	RequestWorldRemote = Instance.new("RemoteFunction")
	RequestWorldRemote.Name = "RequestWorld"
	RequestWorldRemote.Parent = RemotesFolder
end

local TeleportToPlaceRemote = RemotesFolder:FindFirstChild("TeleportToPlace")
if not TeleportToPlaceRemote then
	TeleportToPlaceRemote = Instance.new("RemoteFunction")
	TeleportToPlaceRemote.Name = "TeleportToPlace"
	TeleportToPlaceRemote.Parent = RemotesFolder
end

local ALLOWED_TELEPORT_PLACES: { [number]: boolean } = {
	[88456767102569] = true,
}

local lastTeleportRequest: { [Player]: number } = {}

TeleportToPlaceRemote.OnServerInvoke = function(player, placeId)
	if not player or not player.Parent then return false, "Invalid player" end
	placeId = tonumber(placeId)
	if not placeId or not ALLOWED_TELEPORT_PLACES[placeId] then
		return false, "Unauthorized teleport destination"
	end

	local now = os.clock()
	if lastTeleportRequest[player] and (now - lastTeleportRequest[player] < 3) then
		return false, "Please wait before teleporting again"
	end
	lastTeleportRequest[player] = now

	if RunService:IsStudio() then
		print(string.format("[WorldService] Studio simulator cannot cross-teleport player %s to place %d", player.Name, placeId))
		return true, "Studio simulation"
	end

	local TeleportService = game:GetService("TeleportService")
	local success, err = pcall(function()
		TeleportService:TeleportAsync(placeId, { player })
	end)

	if not success then
		success, err = pcall(function()
			TeleportService:Teleport(placeId, player)
		end)
	end

	return success, err
end

-- Ensure workspace.__MAP container exists
local function getMapContainer()
	local container = workspace:FindFirstChild("__MAP")
	if not container then
		container = Instance.new("Folder")
		container.Name = "__MAP"
		container.Parent = workspace
	end
	return container
end

-- Server-side spawn lookup: reads the PlayerSpawn parts directly from MAP.PlayerSpawn
local function getServerSpawnCFrame(worldFolder)
	if not worldFolder then
		local container = getMapContainer()
		worldFolder = container:FindFirstChild("Spawn") or container:GetChildren()[1]
	end
	if not worldFolder then return CFrame.new(0, 50, 0) end

	local map = worldFolder:FindFirstChild("MAP") or worldFolder
	local playerSpawnFolder = map:FindFirstChild("PlayerSpawn")

	if playerSpawnFolder then
		local spawnParts = playerSpawnFolder:GetChildren()
		if #spawnParts > 0 then
			local chosen = spawnParts[math.random(1, #spawnParts)]
			if chosen:IsA("BasePart") then
				return chosen.CFrame + Vector3.new(0, 3, 0)
			end
		end
	end

	return worldFolder:GetPivot() + Vector3.new(0, 10, 0)
end

-- Moves a world from ServerStorage.__WORLDS to workspace.__MAP if not already loaded
local function ensureWorldLoaded(worldName)
	worldName = worldName or "Spawn"
	local container = getMapContainer()
	local activeWorld = container:FindFirstChild(worldName)
	if activeWorld then
		return activeWorld
	end

	local worlds = WORLDS_FOLDER or ServerStorage:FindFirstChild("__WORLDS")
	if not worlds then
		warn("[WorldService] __WORLDS folder missing in ServerStorage")
		return nil
	end

	local worldFolder = worlds:FindFirstChild(worldName)
	if not worldFolder then
		warn("[WorldService] World not found in ServerStorage.__WORLDS: " .. tostring(worldName))
		return nil
	end

	worldFolder.Parent = container
	-- print(string.format("[WorldService] Moved world '%s' to workspace.__MAP (0 clones, instant move)", worldName))

	task.spawn(function()
		AreaManager.LoadWorldAreas(worldName)
	end)

	return worldFolder
end

-- Checks all active worlds in workspace.__MAP and returns empty worlds (0 players) to ServerStorage.__WORLDS
local function checkAndUnloadEmptyWorlds()
	local container = getMapContainer()
	local worlds = WORLDS_FOLDER or ServerStorage:FindFirstChild("__WORLDS")
	if not worlds then return end

	-- Snapshot: reparenting children below mutates the container's child list
	-- mid-iteration, which would skip worlds.
	for _, worldFolder in ipairs(table.clone(container:GetChildren())) do
		local worldName = worldFolder.Name
		local playerCount = 0

		for _, p in ipairs(Players:GetPlayers()) do
			if p:GetAttribute("World") == worldName then
				playerCount = playerCount + 1
			end
		end

		-- If world is empty (0 players), return it to ServerStorage
		if playerCount == 0 then
			-- Re-verify at the moment of the move: onRequestWorld sets the
			-- requesting player's World attribute BEFORE ensureWorldLoaded, so a
			-- player who claimed this world between the count and now is
			-- visible here and cancels the unload.
			local stillEmpty = true
			for _, p in ipairs(Players:GetPlayers()) do
				if p:GetAttribute("World") == worldName then
					stillEmpty = false
					break
				end
			end
			if stillEmpty and worldFolder.Parent == container then
				-- print(string.format("[WorldService] 0 players in '%s'. Returning to ServerStorage.__WORLDS.", worldName))
				AreaManager.UnloadWorldAreas(worldName)
				worldFolder.Parent = worlds
			end
		end
	end
end

-- Handles a player requesting to travel to a world (ONLY teleports the requester)
local function onRequestWorld(player, worldName)
	if not player or not player.Parent then return false, "Invalid player" end
	if not worldName or typeof(worldName) ~= "string" then
		return false, "Invalid world name"
	end

	local isStudio = RunService:IsStudio()
	local isCreator = (player.UserId == game.CreatorId)
	local data = Library.Saving.GetPlayerData(player)

	-- Check requirements from Directory.Worlds
	local dirWorlds = ReplicatedStorage:FindFirstChild("Directory") and ReplicatedStorage.Directory:FindFirstChild("Worlds")
	local worldModule = dirWorlds and dirWorlds:FindFirstChild(worldName)
	local worldConfig = nil
	if worldModule and worldModule:IsA("ModuleScript") then
		pcall(function()
			worldConfig = require(worldModule)
		end)
	end

	if worldConfig and worldName ~= "Spawn" then
		if worldConfig.Disabled and not (isStudio or isCreator) then
			return false, "This world is currently coming soon!"
		end

		local playerLevel = player:GetAttribute("Level") or (data and (data.Level or (data.Storage and data.Storage.Level))) or 1
		local playerRebirth = player:GetAttribute("Rebirth") or (data and data.Rebirth) or 0

		if (worldConfig.RequiredRebirths or 0) > 0 and playerRebirth < worldConfig.RequiredRebirths and not (isStudio or isCreator) then
			return false, string.format("You need Rebirth %d or higher to enter %s!", worldConfig.RequiredRebirths, worldConfig.DisplayName or worldName)
		end

		if (worldConfig.RequiredLevel or 0) > 0 and playerLevel < worldConfig.RequiredLevel and not (isStudio or isCreator) then
			return false, string.format("You need Level %d or higher to enter %s!", worldConfig.RequiredLevel, worldConfig.DisplayName or worldName)
		end
	end

	local previousWorldName = player:GetAttribute("World") or "Spawn"

	-- Claim occupancy BEFORE loading: the attribute is the occupancy counter
	-- used by checkAndUnloadEmptyWorlds. Setting it after ensureWorldLoaded
	-- opened a window where a concurrent unload (PlayerRemoving delay) could
	-- return the freshly loaded world to ServerStorage mid-travel.
	player:SetAttribute("World", worldName)

	local targetWorldFolder = ensureWorldLoaded(worldName)
	if not targetWorldFolder then
		player:SetAttribute("World", previousWorldName)
		return false, "Failed to load target world"
	end

	-- Update player's persistent world state
	if data then
		data.CurrentWorld = worldName
		data.UnlockedWorlds = data.UnlockedWorlds or { "Spawn" }
		if not table.find(data.UnlockedWorlds, worldName) then
			table.insert(data.UnlockedWorlds, worldName)
		end
	end

	-- Teleport ONLY this player to the target world spawn
	local spawnCFrame = getServerSpawnCFrame(targetWorldFolder)
	local character = player.Character
	if character and character.Parent then
		character:PivotTo(spawnCFrame)
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if hrp then
			hrp.AssemblyLinearVelocity = Vector3.new()
			hrp.AssemblyAngularVelocity = Vector3.new()
		end
	end

	-- If previous world has no players left, return it to ServerStorage
	if previousWorldName ~= worldName then
		task.delay(2, checkAndUnloadEmptyWorlds)
	end

	return true
end

RequestWorldRemote.OnServerInvoke = onRequestWorld

-- Allow other server services (e.g. RebirthService) to safely request world teleports
if Library.Signal and Library.Signal.Connect then
	Library.Signal.Connect("Teleport Player World", function(player, worldName)
		onRequestWorld(player, worldName)
	end)
end

-- Unload empty worlds when a player disconnects
Players.PlayerRemoving:Connect(function(player)
	lastTeleportRequest[player] = nil
	task.delay(2, checkAndUnloadEmptyWorlds)
end)

-- Server-side character spawn handler: guarantees players always spawn on their world's floor on join, reset, or death
local function onServerCharacterAdded(player, character)
	task.spawn(function()
		local hrp = character:WaitForChild("HumanoidRootPart", 10)
		if not hrp then return end

		local currentWorldName = player:GetAttribute("World") or "Spawn"
		local worldFolder = ensureWorldLoaded(currentWorldName)

		if worldFolder then
			local spawnCFrame = getServerSpawnCFrame(worldFolder)
			character:PivotTo(spawnCFrame)
			hrp.AssemblyLinearVelocity = Vector3.new()
			hrp.AssemblyAngularVelocity = Vector3.new()
		end
	end)
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		onServerCharacterAdded(player, character)
	end)
	if player.Character then
		onServerCharacterAdded(player, player.Character)
	end
end)

for _, player in ipairs(Players:GetPlayers()) do
	player.CharacterAdded:Connect(function(character)
		onServerCharacterAdded(player, character)
	end)
	if player.Character then
		onServerCharacterAdded(player, player.Character)
	end
end

-- Initialize default Spawn world and areas on server boot
task.spawn(function()
	ensureWorldLoaded("Spawn")
	task.wait(1)
	AreaManager.LoadAllAreas()
end)
