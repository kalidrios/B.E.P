local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local AreaManager = {}
AreaManager.Areas = {}

local destructionQueue = {}
local MAX_DESTRUCTIONS_PER_FRAME = 15 -- Spreads out the Destroy() calls to prevent server lag spikes

RunService.Heartbeat:Connect(function()
	if #destructionQueue == 0 then return end
	local count = math.min(#destructionQueue, MAX_DESTRUCTIONS_PER_FRAME)
	for _ = 1, count do
		local part = table.remove(destructionQueue, 1)
		if part then
			part:Destroy()
		end
	end
end)

function AreaManager.QueuePartDestruction(part)
	if not part or not part.Parent then return end
	part.Parent = nil -- Instantly hide/remove from workspace to stop physics and rendering overhead
	table.insert(destructionQueue, part)
end

-- ============================================================
-- Explosion impulse — SERVER-ONLY. The server is the single owner of all
-- debris physics: it unanchors the real parts and launches them. Clients
-- never compute trajectories — they just receive the replicated physics.
--
-- Tuned for a "fireworks box" effect: strong outward blast with a heavy
-- upward bias so blocks scatter up and out in chaotic directions.
-- ============================================================
local IMPULSE_FORCE = 250 -- launch speed at the blast center (studs/s)
local IMPULSE_SPIN = 30    -- base angular speed (rad/s), randomized ±50% per part

local function pseudoUnit(seedA, seedB)
	local n = math.sin(seedA * 12.9898 + seedB * 78.233) * 43758.5453
	return (n - math.floor(n)) * 2 - 1 -- deterministic value in -1..1
end

function AreaManager.GetExplosionImpulse(partPos, hitPos, blastRadius)
	local raw = partPos - hitPos
	local dist = raw.Magnitude
	local dir = if dist > 0.01 then raw / dist else Vector3.yAxis
	-- Floor raised to 0.45: even blocks at the edge of the blast still fly hard
	local distScale = math.clamp(1 - (dist / blastRadius), 0.45, 1)

	local jx = pseudoUnit(partPos.X, partPos.Z)
	local jy = pseudoUnit(partPos.Y, partPos.X)
	local jz = pseudoUnit(partPos.Z, partPos.Y)

	-- Y is biased always-positive (+0.6 .. +1.5) so debris goes UP, never down
	local scatter = Vector3.new(jx, 0.6 + math.abs(jy) * 0.9, jz)
	local velocity = (dir + scatter).Unit * (IMPULSE_FORCE * distScale)
	local angular = Vector3.new(jx, jy, jz) * (IMPULSE_SPIN * (0.5 + math.abs(pseudoUnit(partPos.X, partPos.Y))))
	return velocity, angular
end

-- Staggered deletion batches: spreads Destroy() calls across time so a single
-- explosion never queues every block for the same frame (QueuePartDestruction
-- still throttles the actual Destroy() at MAX_DESTRUCTIONS_PER_FRAME).
local DELETION_BATCHES = { 3, 5, 7 }
AreaManager.DELETION_BATCHES = DELETION_BATCHES

local GRID_SIZE = 4

local function getGridKey(x, y, z)
	return string.format("%d,%d,%d", x, y, z)
end

local function indexPart(grid, part)
	local pos = part.Position
	local size = part.Size
	local minX = math.round((pos.X - size.X/2) / GRID_SIZE)
	local maxX = math.round((pos.X + size.X/2) / GRID_SIZE)
	local minY = math.round((pos.Y - size.Y/2) / GRID_SIZE)
	local maxY = math.round((pos.Y + size.Y/2) / GRID_SIZE)
	local minZ = math.round((pos.Z - size.Z/2) / GRID_SIZE)
	local maxZ = math.round((pos.Z + size.Z/2) / GRID_SIZE)

	for x = minX, maxX do
		for y = minY, maxY do
			for z = minZ, maxZ do
				local key = getGridKey(x, y, z)
				if not grid[key] then grid[key] = {} end
				grid[key][part] = true
			end
		end
	end
end

local function removePartFromGrid(grid, part)
	local pos = part.Position
	local size = part.Size
	local minX = math.round((pos.X - size.X/2) / GRID_SIZE)
	local maxX = math.round((pos.X + size.X/2) / GRID_SIZE)
	local minY = math.round((pos.Y - size.Y/2) / GRID_SIZE)
	local maxY = math.round((pos.Y + size.Y/2) / GRID_SIZE)
	local minZ = math.round((pos.Z - size.Z/2) / GRID_SIZE)
	local maxZ = math.round((pos.Z + size.Z/2) / GRID_SIZE)

	for x = minX, maxX do
		for y = minY, maxY do
			for z = minZ, maxZ do
				local key = getGridKey(x, y, z)
				if grid[key] then
					grid[key][part] = nil
				end
			end
		end
	end
end

local function getNeighbors(grid, part)
	local pos = part.Position
	local size = part.Size
	local minX = math.round((pos.X - size.X/2) / GRID_SIZE) - 1
	local maxX = math.round((pos.X + size.X/2) / GRID_SIZE) + 1
	local minY = math.round((pos.Y - size.Y/2) / GRID_SIZE) - 1
	local maxY = math.round((pos.Y + size.Y/2) / GRID_SIZE) + 1
	local minZ = math.round((pos.Z - size.Z/2) / GRID_SIZE) - 1
	local maxZ = math.round((pos.Z + size.Z/2) / GRID_SIZE) + 1

	local neighbors = {}
	local seen = {}

	for x = minX, maxX do
		for y = minY, maxY do
			for z = minZ, maxZ do
				local key = getGridKey(x, y, z)
				if grid[key] then
					for neighbor in pairs(grid[key]) do
						if neighbor ~= part and not seen[neighbor] then
							seen[neighbor] = true
							table.insert(neighbors, neighbor)
						end
					end
				end
			end
		end
	end
	return neighbors
end

local function isGroundPart(part, areaMinY)
	return part.Position.Y < areaMinY + 4 or part.Name == "SpawnLocation"
end

local function isPropPart(part)
	local ancestor = part.Parent
	while ancestor and ancestor ~= workspace do
		if ancestor:IsA("Model") then
			local name = string.lower(ancestor.Name)
			-- Exclude vegetables and other common words starting with 'car'
			if string.find(name, "carrot") or string.find(name, "carrost") or string.find(name, "carpet") then
				-- Skip this model check, proceed to parent
			else
				local propKeywords = {
					"car", "vehicle", "prop", "truck", "tractor", 
					"bulldozer", "excavator", "boat", "ufo", 
					"plane", "train", "helicopter", "motorcycle"
				}
				for _, keyword in ipairs(propKeywords) do
					if string.find(name, keyword) then
						return true
					end
				end
			end
		end
		ancestor = ancestor.Parent
	end
	return false
end

local function setProtectState(areaFolder, active)
	local protect = areaFolder:FindFirstChild("Protect")
	if protect then
		local parts = {}
		if protect:IsA("BasePart") then
			table.insert(parts, protect)
		end
		for _, descendant in ipairs(protect:GetDescendants()) do
			if descendant:IsA("BasePart") then
				table.insert(parts, descendant)
			end
		end
		
		for _, part in ipairs(parts) do
			part.Transparency = active and 0.5 or 1
			part.CanCollide = active
			part.CanQuery = active
			part.CanTouch = active
		end
	end
end

local function teleportPlayersInArea(areaName)
	local state = AreaManager.Areas[areaName]
	if not state or not state.basePart then return end
	
	local basePart = state.basePart
	local baseSize = basePart.Size
	local basePos = basePart.Position
	
	local spawnsFolder = state.folder:FindFirstChild("Spawns")
	local spawns = spawnsFolder and spawnsFolder:GetChildren() or {}
	local lobbySpawn = workspace:FindFirstChildOfClass("SpawnLocation")

	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		if char and char:FindFirstChild("HumanoidRootPart") then
			local hrp = char.HumanoidRootPart
			local rel = basePart.CFrame:PointToObjectSpace(hrp.Position)
			if math.abs(rel.X) <= baseSize.X/2 and math.abs(rel.Y) <= baseSize.Y/2 and math.abs(rel.Z) <= baseSize.Z/2 then
				if #spawns > 0 then
					local spawnPart = spawns[math.random(1, #spawns)]
					hrp.CFrame = spawnPart.CFrame + Vector3.new(0, 3, 0)
				elseif lobbySpawn then
					hrp.CFrame = lobbySpawn.CFrame + Vector3.new(0, 4, 0)
				else
					hrp.CFrame = CFrame.new(0, 50, 0)
				end
			end
		end
	end
end

-- Clean backup storage in ServerStorage so ReconstructArea can always clone fresh buildings
local function getOrCreateAreaBackup(worldName, areaName, sourceFolder)
	local backupsRoot = ServerStorage:FindFirstChild("__AREA_BACKUPS")
	if not backupsRoot then
		backupsRoot = Instance.new("Folder")
		backupsRoot.Name = "__AREA_BACKUPS"
		backupsRoot.Parent = ServerStorage
	end
	local worldBackup = backupsRoot:FindFirstChild(worldName)
	if not worldBackup then
		worldBackup = Instance.new("Folder")
		worldBackup.Name = worldName
		worldBackup.Parent = backupsRoot
	end
	local areaBackup = worldBackup:FindFirstChild(areaName)
	if not areaBackup and sourceFolder then
		areaBackup = sourceFolder:Clone()
		areaBackup.Name = areaName
		areaBackup.Parent = worldBackup
	end
	return areaBackup
end

-- Areas from different worlds can share plain names ("Area 1", "City"...),
-- so state is keyed by "world/area". Every internal consumer derives the key
-- from FindAreaOfPart, so the whole chain stays consistent.
local function areaKey(worldName, areaName)
	return worldName .. "/" .. areaName
end

local function loadAreaInternal(areaName, basePart, worldName, isReconstructing)
	local mapFolder = workspace:FindFirstChild("__MAP")
	if not worldName then
		worldName = mapFolder and mapFolder:GetAttribute("WorldName") or "Spawn"
	end

	local areasFolderWs = workspace:FindFirstChild("Areas")
	if not areasFolderWs then
		areasFolderWs = Instance.new("Folder")
		areasFolderWs.Name = "Areas"
		areasFolderWs.Parent = workspace
	end

	local targetAreaFolder = nil

	if isReconstructing then
		-- ReconstructArea: clone a fresh building from pristine backup in ServerStorage
		local backup = getOrCreateAreaBackup(worldName, areaName, nil)
		if not backup then
			local worldsFolder = ServerStorage:FindFirstChild("__WORLDS")
			local worldT = worldsFolder and worldsFolder:FindFirstChild(worldName)
			local src = worldT and ((worldT:FindFirstChild("MAP") and worldT.MAP:FindFirstChild("Areas")) or worldT:FindFirstChild("Areas"))
			local tmpl = src and src:FindFirstChild(areaName)
			if tmpl then
				backup = getOrCreateAreaBackup(worldName, areaName, tmpl)
			end
		end

		if backup then
			targetAreaFolder = backup:Clone()
			targetAreaFolder.Name = areaName
			targetAreaFolder.Parent = areasFolderWs
		end
	else
		-- Initial load: MOVE the pristine area out of the world template into
		-- workspace.Areas (zero clones, no duplicate overlapping blocks).
		-- Lookup is scoped to THIS world's template — a flat search over the
		-- whole __MAP container can grab another world's area of the same name.
		-- Reuse ONLY this world's already-loaded folder (identity via the state
		-- entry). The old name-based areasFolderWs:FindFirstChild(areaName) was
		-- cross-world unsafe: with two worlds coexisting in workspace.Areas that
		-- share a plain area name ("Area 1"), it could hand world B's state a
		-- folder owned by world A, so unloading A would delete B's area too.
		local existingState = AreaManager.Areas[areaKey(worldName, areaName)]
		local existingInAreas = existingState and existingState.folder
		if existingInAreas and existingInAreas.Parent == areasFolderWs then
			targetAreaFolder = existingInAreas
		else
			local mapContainer = workspace:FindFirstChild("__MAP")
			local worldFolder = mapContainer and mapContainer:FindFirstChild(worldName)
			if not worldFolder then
				local worldsFolder = ServerStorage:FindFirstChild("__WORLDS")
				worldFolder = worldsFolder and worldsFolder:FindFirstChild(worldName)
			end
			local worldMap = worldFolder and (worldFolder:FindFirstChild("MAP") or worldFolder)
			local mapAreas = worldMap and worldMap:FindFirstChild("Areas")
			local foundArea = mapAreas and mapAreas:FindFirstChild(areaName)
			if not foundArea and mapAreas then
				local searchClean = string.lower(string.gsub(areaName, "%s+", ""))
				for _, child in ipairs(mapAreas:GetChildren()) do
					if string.lower(string.gsub(child.Name, "%s+", "")) == searchClean then
						foundArea = child
						break
					end
				end
			end

			if foundArea then
				getOrCreateAreaBackup(worldName, areaName, foundArea)
				foundArea.Parent = areasFolderWs
				targetAreaFolder = foundArea
			else
				local backup = getOrCreateAreaBackup(worldName, areaName, nil)
				if backup then
					targetAreaFolder = backup:Clone()
					targetAreaFolder.Name = areaName
					targetAreaFolder.Parent = areasFolderWs
				end
			end
		end
	end

	if not targetAreaFolder then
		warn("[AreaManager] Could not resolve area: " .. tostring(areaName) .. " for world: " .. tostring(worldName))
		return nil
	end

	local state = {
		grid = {},
		totalBlocks = 0,
		destroyedBlocks = 0,
		folder = targetAreaFolder,
		basePart = basePart,
		isReconstructing = false,
		minY = math.huge,
		worldName = worldName,
	}

	local blocksFolder = targetAreaFolder:FindFirstChild("Blocks")
	local partsToProcess = blocksFolder and blocksFolder:GetDescendants() or targetAreaFolder:GetDescendants()

	local processedCount = 0
	for _, part in ipairs(partsToProcess) do
		processedCount = processedCount + 1
		if processedCount % 250 == 0 then
			task.wait()
		end

		if part:IsA("BasePart") then
			-- Skip any parts that are inside Spawns, Protects or containing those keywords
			local isProtected = false
			local current = part
			while current and current ~= targetAreaFolder do
				local nameLower = string.lower(current.Name)
				if string.find(nameLower, "spawn") or string.find(nameLower, "protect") then
					isProtected = true
					break
				end
				current = current.Parent
			end

			if not isProtected then
				if part.Position.Y < state.minY then
					state.minY = part.Position.Y
				end
				if not part.Locked and part.Name ~= "Baseplate" and part.Name ~= "SpawnLocation" then
					if isPropPart(part) then
						part:SetAttribute("IsProp", true)
						part.Anchored = false
						CollectionService:AddTag(part, "Breakable")
					else
						state.totalBlocks = state.totalBlocks + 1
						indexPart(state.grid, part)
						CollectionService:AddTag(part, "Breakable")
					end
				end
			end
		end
	end

	setProtectState(targetAreaFolder, false)
	AreaManager.Areas[areaKey(worldName, areaName)] = state
	return state
end

function AreaManager.LoadWorldAreas(worldName)
	worldName = worldName or "Spawn"
	local mapContainer = workspace:FindFirstChild("__MAP")
	if not mapContainer then return end

	local worldFolder = mapContainer:FindFirstChild(worldName) or (mapContainer:GetAttribute("WorldName") == worldName and mapContainer)
	if not worldFolder then return end

	local innerMap = worldFolder:FindFirstChild("MAP") or worldFolder
	local sourceAreas = innerMap:FindFirstChild("Areas")
	local baseAreas = innerMap:FindFirstChild("BaseAreas") or worldFolder:FindFirstChild("BaseAreas")

	-- Collect area names from BOTH the live template and the durable backup.
	-- loadAreaInternal MOVES each area out of world/MAP/Areas into workspace.Areas
	-- on first load, so when a world is re-visited after being returned to
	-- ServerStorage its template Areas folder is EMPTY. Enumerating only the
	-- template (old behavior) loaded nothing on the second visit and the areas
	-- looked "deleted". __AREA_BACKUPS/<world> is the stable name list that
	-- survives the move, and loadAreaInternal already re-clones from it when the
	-- template no longer holds the area.
	local areaNames = {}
	if sourceAreas then
		for _, areaFolder in ipairs(sourceAreas:GetChildren()) do
			areaNames[areaFolder.Name] = true
		end
	end

	local backupsRoot = ServerStorage:FindFirstChild("__AREA_BACKUPS")
	local worldBackup = backupsRoot and backupsRoot:FindFirstChild(worldName)
	if worldBackup then
		for _, backupFolder in ipairs(worldBackup:GetChildren()) do
			areaNames[backupFolder.Name] = true
		end
	end

	for areaName in pairs(areaNames) do
		local key = areaKey(worldName, areaName)
		if not AreaManager.Areas[key] then
			local basePart = baseAreas and (baseAreas:FindFirstChild(areaName) or baseAreas:FindFirstChildWhichIsA("BasePart"))
			loadAreaInternal(areaName, basePart, worldName)
			task.wait()
		end
	end
end

function AreaManager.UnloadWorldAreas(worldName)
	worldName = worldName or "Spawn"
	local areasFolderWs = workspace:FindFirstChild("Areas")
	for key, state in pairs(AreaManager.Areas) do
		if state and state.worldName == worldName then
			if state.folder and state.folder.Parent then
				-- Destroy instead of returning the (mutated) debris to the world
				-- template: re-parented folders would pollute the template's Areas
				-- folder and could be picked up as the "pristine" template on the
				-- next load. Reconstruction stays covered by __AREA_BACKUPS.
				state.folder:Destroy()
			end
			AreaManager.Areas[key] = nil
		end
	end
end

function AreaManager.LoadAllAreas()
	local mapContainer = workspace:FindFirstChild("__MAP")
	if not mapContainer then return end

	for _, child in ipairs(mapContainer:GetChildren()) do
		if child:IsA("Folder") or child:IsA("Model") then
			AreaManager.LoadWorldAreas(child.Name)
		end
	end

	if mapContainer:FindFirstChild("MAP") or mapContainer:FindFirstChild("BaseAreas") then
		AreaManager.LoadWorldAreas(mapContainer:GetAttribute("WorldName") or "Spawn")
	end
end

function AreaManager.UnloadAllAreas()
	local mapContainer = workspace:FindFirstChild("__MAP")
	if mapContainer then
		for _, child in ipairs(mapContainer:GetChildren()) do
			if child:IsA("Folder") or child:IsA("Model") then
				AreaManager.UnloadWorldAreas(child.Name)
			end
		end
	end
	table.clear(AreaManager.Areas)
end

function AreaManager.ReconstructArea(areaName)
	local state = AreaManager.Areas[areaName]
	if not state or state.isReconstructing then return end
	state.isReconstructing = true

	setProtectState(state.folder, true)

	local basePart = state.basePart
	local worldName = state.worldName or (workspace:FindFirstChild("__MAP") and workspace.__MAP:GetAttribute("WorldName")) or "Spawn"
	-- `areaName` is the NAMESPACED key ("world/area") that FindAreaOfPart returns
	-- and the whole destruction chain propagates. loadAreaInternal and
	-- getOrCreateAreaBackup expect the PLAIN area name (that is how the backup and
	-- the workspace.Areas folder are named). Passing the key made the backup
	-- lookup miss (__AREA_BACKUPS/<world>/<world>/<area>), so the area destroyed
	-- just below was NEVER rebuilt -- a permanent deletion once 70% was damaged.
	local plainAreaName = state.folder.Name
	state.folder:Destroy()
	AreaManager.Areas[areaName] = nil

	local newState = loadAreaInternal(plainAreaName, basePart, worldName, true)
	if newState then
		newState.isReconstructing = true
		setProtectState(newState.folder, true)
		
		-- Teleport players to spawns after the new map folder is loaded in Workspace
		teleportPlayersInArea(areaName)
		
		task.delay(5, function()
			setProtectState(newState.folder, false)
			newState.isReconstructing = false
		end)
	end
end

local pendingIntegrity = {}

-- Debounced & scheduled structural integrity check:
-- Waiting a short delay allows the explosion shockwave unanchoring to finish,
-- prevents redundant BFS grid traversals on consecutive hits, and spreads physics frame load.
function AreaManager.ScheduleStructuralIntegrity(areaName, ownerPlayer)
	if pendingIntegrity[areaName] then return end
	pendingIntegrity[areaName] = true
	task.delay(0.15, function()
		pendingIntegrity[areaName] = nil
		AreaManager.RunStructuralIntegrity(areaName, ownerPlayer)
	end)
end

function AreaManager.RunStructuralIntegrity(areaName, ownerPlayer)
	local state = AreaManager.Areas[areaName]
	if not state or state.isReconstructing then return end

	local visited = {}
	local queue = {}
	local allParts = {}

	for _, bucket in pairs(state.grid) do
		for p in pairs(bucket) do
			if not allParts[p] then
				allParts[p] = true
				if isGroundPart(p, state.minY) then
					visited[p] = true
					table.insert(queue, p)
				end
			end
		end
	end

	local head = 1
	while head <= #queue do
		local current = queue[head]
		head = head + 1

		local neighbors = getNeighbors(state.grid, current)
		for _, n in ipairs(neighbors) do
			if not visited[n] then
				visited[n] = true
				table.insert(queue, n)
			end
		end
	end

	local floatingParts = {}
	for p in pairs(allParts) do
		if not visited[p] and p.Anchored then
			floatingParts[p] = true
		end
	end

	local clusterVisited = {}
	for p in pairs(floatingParts) do
		if not clusterVisited[p] then
			local clusterQueue = {p}
			local cluster = {p}
			clusterVisited[p] = true

			local clusterHead = 1
			while clusterHead <= #clusterQueue do
				local current = clusterQueue[clusterHead]
				clusterHead = clusterHead + 1

				local neighbors = getNeighbors(state.grid, current)
				for _, n in ipairs(neighbors) do
					if floatingParts[n] and not clusterVisited[n] then
						clusterVisited[n] = true
						table.insert(clusterQueue, n)
						table.insert(cluster, n)
					end
				end
			end

			-- Pick the cluster's largest part as the assembly root: welds bind the
			-- whole cluster into ONE rigid body, so it falls as a single piece
			-- (original architecture: snaps/welds kept floating clusters glued)
			-- instead of dozens of loose parts scattering and slipping through
			-- collisions into the void.
			local rootPart = cluster[1]
			local rootVolume = rootPart.Size.X * rootPart.Size.Y * rootPart.Size.Z
			for _, part in ipairs(cluster) do
				local volume = part.Size.X * part.Size.Y * part.Size.Z
				if volume > rootVolume then
					rootPart = part
					rootVolume = volume
				end
			end

			-- Weld every cluster part to the root while still anchored (constraints
			-- between anchored parts are inert until unanchored).
			if #cluster > 1 then
				for _, part in ipairs(cluster) do
					if part ~= rootPart then
						local weld = Instance.new("WeldConstraint")
						weld.Part0 = rootPart
						weld.Part1 = part
						weld.Parent = rootPart
					end
				end
			end

			-- Cluster parts count as destroyed blocks: without this the server
			-- never reaches the 70% threshold and the area never reconstructs.
			state.destroyedBlocks = state.destroyedBlocks + #cluster
			if not state.isReconstructing and state.totalBlocks > 0 and (state.destroyedBlocks / state.totalBlocks) >= 0.70 then
				AreaManager.ReconstructArea(areaName)
			end

			-- Remove the cluster parts from the grid and unanchor them as a single
			-- welded assembly (server physics replicates one body, not N loose parts).
			for _, part in ipairs(cluster) do
				removePartFromGrid(state.grid, part)
				if part and part.Parent then
					part:SetAttribute("DestroyScheduled", true)
					part.CanTouch = false
					part.CanQuery = false
					-- CanCollide stays ENABLED: collision with the map is what stops debris
					-- from falling through the floor into the void (original architecture).
					-- Hand the falling cluster to the shooter's client so they simulate
					-- the collapse locally (no replication wait). Ownership is set while
					-- still anchored so the welded assembly keeps a single owner.
					if ownerPlayer then
						pcall(function()
							part:SetNetworkOwner(ownerPlayer)
						end)
					end
					part.Anchored = false
				end
			end

			local lifetime = DELETION_BATCHES[math.random(1, #DELETION_BATCHES)]
			task.delay(lifetime, function()
				for _, part in ipairs(cluster) do
					if part and part.Parent then
						AreaManager.QueuePartDestruction(part)
					end
				end
			end)
		end
	end
end

-- ============================================================================
-- CRITICAL PERFORMANCE / ANTI-REGRESSION INVARIANT (DO NOT REMOVE!):
-- Staggered physics unanchoring ("dar um tempo / onda de choque").
-- Low-end hardware (e.g. 8GB RAM laptops, mobile phones) experiences severe
-- frame-rate drops and physics engine freezes if dozens of parts wake up simultaneously.
-- Logical block destruction (grid removal, damage state, reconstruction check) occurs
-- IMMEDIATELY to prevent double-hits and preserve instantaneous reward feedback.
-- Physical unanchoring (Anchored = false, impulse, network ownership) is staggered
-- across frames so the physics engine never simulates more than a small batch at once.
-- DO NOT REMOVE THIS STAGGER OR REVERT TO SYNCHRONOUS UNANCHORING!
-- ============================================================================
function AreaManager.SchedulePartDestruction(part, areaName, hitPosition, blastRadius, ownerPlayer, staggerDelay: number?)
	if part:GetAttribute("DestroyScheduled") then return end
	part:SetAttribute("DestroyScheduled", true)
	part:SetAttribute("ExplosionPending", nil)

	local state = AreaManager.Areas[areaName]
	if state then
		if part:GetAttribute("IsProp") then
			-- Props don't count towards map reconstruction progress
		else
			removePartFromGrid(state.grid, part) -- MUST run before unanchoring (uses original position)
			state.destroyedBlocks = state.destroyedBlocks + 1

			if not state.isReconstructing and state.totalBlocks > 0 and (state.destroyedBlocks / state.totalBlocks) >= 0.70 then
				AreaManager.ReconstructArea(areaName)
			end
		end
	end

	-- ReconstructArea may have destroyed the whole area folder above
	if not part.Parent then return end

	local function unanchorPhysics()
		if not part or not part.Parent then return end

		-- Unanchor the REAL part and launch it (server physics, replicated to all clients).
		-- CanCollide stays ENABLED: ground collision is what keeps debris out of the void.
		part.CanTouch = false
		part.CanQuery = false
		part.Anchored = false
		if hitPosition then
			local vel, angVel = AreaManager.GetExplosionImpulse(part.Position, hitPosition, blastRadius or 9)
			part.AssemblyLinearVelocity = vel
			part.AssemblyAngularVelocity = angVel
		end
		-- Hand physics ownership to the shooter: their client simulates the debris
		-- locally (zero perceived delay) instead of waiting for server replication.
		-- The impulse above was computed on the server, so trajectories stay
		-- authoritative; if the owner leaves, physics falls back to the server.
		if ownerPlayer then
			pcall(function()
				part:SetNetworkOwner(ownerPlayer)
			end)
		end

		local lifetime = DELETION_BATCHES[math.random(1, #DELETION_BATCHES)]
		task.delay(lifetime, function()
			if part and part.Parent then
				AreaManager.QueuePartDestruction(part)
			end
		end)
	end

	if staggerDelay and staggerDelay > 0 then
		task.delay(staggerDelay, unanchorPhysics)
	else
		unanchorPhysics()
	end
end

function AreaManager.FindAreaOfPart(part)
	local current = part
	while current and current ~= workspace do
		if current.Parent and current.Parent.Name == "Areas" then
			-- workspace.Areas is flat; the area's world is whatever world owns
			-- the state entry. Namespaced keys keep same-named areas from
			-- different worlds from colliding.
			for key, state in pairs(AreaManager.Areas) do
				if state and state.folder == current then
					return key
				end
			end
			return current.Name
		end
		current = current.Parent
	end
	return nil
end

return AreaManager
