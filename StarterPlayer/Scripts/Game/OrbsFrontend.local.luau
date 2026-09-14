--[[
	© DestructionSimulator [2025]
	Client/OrbsFrontend — Renders block orbs and handles magnet attraction + collection.
	
	Faithfully based on the ProfileService Orbs Frontend behavior:
	- Receives orb creation data from the server via RemoteEvent.
	- Spawns a non-collidable transparent Part (CanCollide = false) with a BillboardGui.
	- Uses highly optimized physics-free manual CFrame interpolation (no physics sleeping, no constraint lag).
	- Spawns with a beautiful parabolic jump arc projecting to the ground via Raycast.
	- Pulls to the player with smooth acceleration once inside the 30-stud pickup distance.
	- Sends batched claim requests with unique GUIDs to the server.
]]--

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local Player = Players.LocalPlayer

local Library = require(ReplicatedStorage:WaitForChild("Library"))
while not Library.IsLoaded() do
	task.wait()
end
local Audio = Library.Audio

local function getPickupDistance()
	local baseDist = 20 -- Base range rounded up to 20 studs
	local save = Library.Save and Library.Save.Get()
	if save and save.UpgradesOwned then
		local magnetLevel = save.UpgradesOwned.Magnet or 0
		-- 20 studs base range + 20% additional boost per upgrade level
		local magnetMultiplier = 1.0 + (magnetLevel * 0.20)
		baseDist = baseDist * magnetMultiplier
	end

	if Player:GetAttribute("StarterBoostActive") then
		baseDist = baseDist * 2
	end

	return baseDist
end

-- References
local thingsFolder = workspace:WaitForChild("__THINGS")
local remotesFolder = thingsFolder:WaitForChild("__REMOTES")
local assetsFolder = ReplicatedStorage:WaitForChild("Assets")
local billboardsFolder = assetsFolder:WaitForChild("Billboards")
local orbTemplate = billboardsFolder:WaitForChild("Orb")



-- Remotes
local orbsCreateEvent = remotesFolder:WaitForChild("OrbsCreate")
local orbsClaimEvent = remotesFolder:WaitForChild("OrbsClaim")

-- Orbs container folder in workspace
local orbsContainer = thingsFolder:FindFirstChild("Orbs")
if not orbsContainer then
	orbsContainer = Instance.new("Folder")
	orbsContainer.Name = "Orbs"
	orbsContainer.Parent = thingsFolder
end

-- Config
local CONFIG = {
	DefaultPickupDistance = 60,     -- studs before magnet starts pulling
	CollectDistance       = 2.5,    -- studs to collect
	CleanupDistance       = 450,    -- studs before client-side cleanup
	OrbPartSize           = Vector3.new(2, 2, 2),
}

--[[
	This function was disabled because having these two collection sounds play together was getting a bit repetitive and tiring for the player.
--]]

-- Sound 1: Played when a block is destroyed / spawned orb pops out
local BLOCK_DESTRUCTION_SOUND = "rbxassetid://71830649123106"

-- Sound 2: Played when collecting orbs from broken blocks
local ORB_COLLECTION_SOUND = "rbxassetid://106646179039780"

-- Spawn sound (sell / cosmetic orbs)
local SPAWN_SOUND = "rbxassetid://80200653870147"

-- Cash collect sound
local CASH_COLLECT_SOUND = "rbxassetid://100409943575421"

-- State
local activeOrbs = {} -- { [uid] = { uid, part, billboard, startPos, targetPos, landed, forcingMagnet, magnetSpeed, spawnTick } }
local networkQueue = {} -- UIDs to send to server
local rng = Random.new()

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

local function getPlayerRoot()
	local character = Player.Character
	if not character then return nil end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	return hrp
end

local function playSound(soundIds, parent, volume, pitchMin, pitchMax)
	if not parent then return end
	local soundId = (type(soundIds) == "table") and soundIds[rng:NextInteger(1, #soundIds)] or soundIds
	local pitch = rng:NextNumber(pitchMin or 0.95, pitchMax or 1.05)
	local audioModule = Audio or Library.Audio
	if audioModule and audioModule.Play then
		audioModule.Play(soundId, parent, pitch, volume or 0.45)
	end
end

----------------------------------------------------------------------
-- Orb Lifecycle
----------------------------------------------------------------------

local function createOrb(orbData)
	local uid = orbData.uid
	if activeOrbs[uid] then return end
	
	local position = orbData.position
	if typeof(position) ~= "Vector3" then return end
	
	-- Create the visual tracking part
	local part = Instance.new("Part")
	part.Name = uid
	part.Size = CONFIG.OrbPartSize
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false -- No character collision!
	part.CanTouch = false
	part.CanQuery = false
	part.CFrame = CFrame.new(position)
	
	-- Clone the BillboardGui from Assets
	local billboard = orbTemplate:Clone()
	billboard.Enabled = true
	billboard.Parent = part
	
	local itemImage = billboard:FindFirstChild("Item", true)
	if itemImage and itemImage:IsA("ImageLabel") then
		if orbData.image then
			itemImage.Image = orbData.image
		else
			local currentWorld = Player:GetAttribute("World") or "Spawn"
			if currentWorld == "Magic" then
				itemImage.Image = "rbxassetid://114046103719772"
			else
				itemImage.Image = "rbxassetid://113137643980619"
			end
		end
	end
	
	-- Create and configure Attachment0
	local a0 = Instance.new("Attachment")
	a0.Name = "Attachment0"
	a0.Position = Vector3.new(0, 0.5798837542533875, -0.18044662475585938)
	a0.Parent = part
	
	-- Create and configure Attachment1
	local a1 = Instance.new("Attachment")
	a1.Name = "Attachment1"
	a1.Position = Vector3.new(0, -0.16823267936706543, -0.18044662475585938)
	a1.Parent = part
	
	-- Create and configure Trail
	local t = Instance.new("Trail")
	t.Name = "Trail"
	t.Attachment0 = a0
	t.Attachment1 = a1
	t.Lifetime = 2
	t.FaceCamera = false
	
	-- Cyan color gradient (matches the template's color keypoints)
	t.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255))
	})
	
	-- Fade-out transparency profile (matches the template's transparency keypoints)
	t.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.498, 0),
		NumberSequenceKeypoint.new(1, 1)
	})
	t.Parent = part
	
	-- Calculate landing spot with offset (larger horizontal scatter for dramatic destruction feel)
	local randomOffset = Vector3.new(rng:NextNumber(-25, 25), 0, rng:NextNumber(-25, 25))
	local targetPos = position + randomOffset
	
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	
	local excludeList = { Player.Character, thingsFolder }
	local areasFolder = workspace:FindFirstChild("Areas")
	if areasFolder then
		table.insert(excludeList, areasFolder)
	end
	raycastParams.FilterDescendantsInstances = excludeList
	
	local rayResult = workspace:Raycast(targetPos + Vector3.new(0, 0, 0), Vector3.new(0, -1000, 0), raycastParams)
	if rayResult then
		targetPos = rayResult.Position + Vector3.new(0, 0.8, 0) -- hover slightly above floor
	else
		targetPos = targetPos - Vector3.new(0, 5, 0) -- fallback
	end
	
	local orbJumpHeight = rng:NextNumber(10, 22) -- randomize jump height per orb
	
	local orbEntry = {
		uid = uid,
		part = part,
		billboard = billboard,
		startPos = position,
		targetPos = targetPos,
		landed = false,
		forcingMagnet = false,
		magnetSpeed = 20,
		spawnTick = tick(),
	}
	activeOrbs[uid] = orbEntry
	
	-- Parabolic entrance animation
	task.spawn(function()
		part.Parent = orbsContainer
		
		-- Small initial delay for pop out feel
		task.wait(rng:NextNumber(0, 0.15))
		if not activeOrbs[uid] then return end
		
		local duration = 0.72
		local elapsed = 0
		while elapsed < duration do
			if not activeOrbs[uid] or not part.Parent then return end
			elapsed = elapsed + RunService.Heartbeat:Wait()
			local t = math.clamp(elapsed / duration, 0, 1)
			
			local currentXZ = position:Lerp(targetPos, t)
			local currentY
			if t < 0.35 then
				local localT = t / 0.35
				currentY = position.Y + orbJumpHeight * math.sin(localT * math.pi / 2)
			else
				local localT = (t - 0.35) / 0.65
				local peakY = position.Y + orbJumpHeight
				currentY = peakY + (targetPos.Y - peakY) * (localT * localT)
			end
			
			part.Position = Vector3.new(currentXZ.X, currentY, currentXZ.Z)
		end
		
		orbEntry.landed = true
		orbEntry.landedTime = tick()
	end)
end

local function cleanupOrb(uid)
	local orbEntry = activeOrbs[uid]
	if orbEntry then
		if orbEntry.part and orbEntry.part.Parent then
			orbEntry.part:Destroy()
		end
		activeOrbs[uid] = nil
	end
end

local function collectOrb(uid)
	local orbEntry = activeOrbs[uid]
	if not orbEntry then return end
	
	-- Play collect sound at player character
	local playerRoot = getPlayerRoot()
	if playerRoot then
		if orbEntry.noClaim then
			-- Cash / Sell Orb collect sound
			playSound({CASH_COLLECT_SOUND}, playerRoot, 0.5, 0.98, 1.02)
		else
			-- Sound 2: Block Orb collect sound
			playSound({ORB_COLLECTION_SOUND}, playerRoot, 0.45, 0.95, 1.05)
		end
	end
	
	-- Queue for claim ONLY if not client-only/sell orb!
	if not orbEntry.noClaim then
		table.insert(networkQueue, uid)
	end
	
	cleanupOrb(uid)
end

----------------------------------------------------------------------
-- Frame Loop (Heartbeat) for Magnet and Collection
----------------------------------------------------------------------

RunService.Heartbeat:Connect(function(dt)
	local playerRoot = getPlayerRoot()
	if not playerRoot then return end
	
	local now = tick()
	
	for uid, orb in pairs(activeOrbs) do
		local part = orb.part
		if not part or not part.Parent then continue end
		
		-- 1. Calculate distance
		local distance = (part.Position - playerRoot.Position).Magnitude
		
		-- 2. Cleanup if player moved too far
		if distance > CONFIG.CleanupDistance then
			cleanupOrb(uid)
			continue
		end
		
		-- 3. Run Magnet logic if landed and delay has elapsed
		if orb.landed then
			local delay = orb.magnetDelay or 0
			local elapsedSinceLanding = now - (orb.landedTime or now)
			
			if elapsedSinceLanding >= delay then
				local pickupRange = getPickupDistance()
				if distance <= pickupRange or orb.forcingMagnet then
					orb.forcingMagnet = true
					
					-- Accelerate toward player
					orb.magnetSpeed = orb.magnetSpeed + (55 * dt)
					local direction = (playerRoot.Position - part.Position).Unit
					part.Position = part.Position + (direction * orb.magnetSpeed * dt)
					
					-- Check for collection
					if distance <= CONFIG.CollectDistance then
						collectOrb(uid)
					end
				end
			end
		end
	end
end)

----------------------------------------------------------------------
-- Network: Batch claim UIDs to server (every 0.1s)
----------------------------------------------------------------------

task.spawn(function()
	while task.wait(0.1) do
		if #networkQueue > 0 then
			-- Batch the list inside another array to match server expectation
			orbsClaimEvent:FireServer({ networkQueue })
			networkQueue = {}
		end
	end
end)

----------------------------------------------------------------------
-- Event Listeners
----------------------------------------------------------------------

orbsCreateEvent.OnClientEvent:Connect(function(orbDataList)
	if typeof(orbDataList) ~= "table" then return end
	for _, orbData in ipairs(orbDataList) do
		createOrb(orbData)
	end
end)

--print("[OrbsFrontend] Manual-CFrame Mode initialized.")

----------------------------------------------------------------------
-- Expose global function to spawn cosmetic sell orbs
----------------------------------------------------------------------
_G.SpawnSellOrbs = function(startPosition, count)
	local HttpService = game:GetService("HttpService")
	for i = 1, count do
		local uid = "sell_" .. HttpService:GenerateGUID(false)
		
		-- Create the visual part
		local part = Instance.new("Part")
		part.Name = uid
		part.Size = CONFIG.OrbPartSize
		part.Transparency = 1
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CFrame = CFrame.new(startPosition)
		
		-- Clone BillboardGui
		local billboard = orbTemplate:Clone()
		billboard.Enabled = true
		billboard.Parent = part
		
		local itemImage = billboard:FindFirstChild("Item", true)
		if itemImage and itemImage:IsA("ImageLabel") then
			itemImage.Image = "rbxassetid://89138141963297"
		end
		
		-- Attach programmatic trail & attachments
		local a0 = Instance.new("Attachment")
		a0.Name = "Attachment0"
		a0.Position = Vector3.new(0, 0.5798837542533875, -0.18044662475585938)
		a0.Parent = part
		
		local a1 = Instance.new("Attachment")
		a1.Name = "Attachment1"
		a1.Position = Vector3.new(0, -0.16823267936706543, -0.18044662475585938)
		a1.Parent = part
		
		local t = Instance.new("Trail")
		t.Name = "Trail"
		t.Attachment0 = a0
		t.Attachment1 = a1
		t.Lifetime = 2
		t.FaceCamera = false
		
		t.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255))
		})
		
		t.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.498, 0),
			NumberSequenceKeypoint.new(1, 1)
		})
		t.Parent = part
		
		-- Calculate landing spot with offset
		local randomOffset = Vector3.new(rng:NextNumber(-12, 12), 0, rng:NextNumber(-12, 12))
		local targetPos = startPosition + randomOffset
		
		local raycastParams = RaycastParams.new()
		raycastParams.FilterType = Enum.RaycastFilterType.Exclude
		local excludeList = { Player.Character, thingsFolder }
		local areasFolder = workspace:FindFirstChild("Areas")
		if areasFolder then
			table.insert(excludeList, areasFolder)
		end
		raycastParams.FilterDescendantsInstances = excludeList
		
		local rayResult = workspace:Raycast(targetPos + Vector3.new(0, 0, 0), Vector3.new(0, -1000, 0), raycastParams)
		if rayResult then
			targetPos = rayResult.Position + Vector3.new(0, 0.8, 0)
		else
			targetPos = targetPos - Vector3.new(0, 5, 0)
		end
		
		local orbJumpHeight = rng:NextNumber(8, 16) -- Slightly lower jump for sell orbs
		
		local orbEntry = {
			uid = uid,
			part = part,
			billboard = billboard,
			startPos = startPosition,
			targetPos = targetPos,
			landed = false,
			forcingMagnet = false,
			magnetSpeed = 20,
			spawnTick = tick(),
			magnetDelay = 0.7, -- Wait 0.7 seconds after landing before flying to player
			noClaim = true,    -- Cosmetic only
		}
		activeOrbs[uid] = orbEntry
		
		task.spawn(function()
			part.Parent = orbsContainer
			task.wait(rng:NextNumber(0, 0.25)) -- Staggered spawn
			if not activeOrbs[uid] then return end
			
			playSound({SPAWN_SOUND}, part, 0.2, 1.0, 1.2)
			
			local duration = 0.72
			local elapsed = 0
			while elapsed < duration do
				if not activeOrbs[uid] or not part.Parent then return end
				elapsed = elapsed + RunService.Heartbeat:Wait()
				local t = math.clamp(elapsed / duration, 0, 1)
				
				local currentXZ = startPosition:Lerp(targetPos, t)
				local currentY
				if t < 0.35 then
					local localT = t / 0.35
					currentY = startPosition.Y + orbJumpHeight * math.sin(localT * math.pi / 2)
				else
					local localT = (t - 0.35) / 0.65
					local peakY = startPosition.Y + orbJumpHeight
					currentY = peakY + (targetPos.Y - peakY) * (localT * localT)
				end
				part.Position = Vector3.new(currentXZ.X, currentY, currentXZ.Z)
			end
			orbEntry.landed = true
			orbEntry.landedTime = tick()
		end)
	end
end
