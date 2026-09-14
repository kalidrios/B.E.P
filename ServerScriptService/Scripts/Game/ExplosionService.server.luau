--[[
	© DestructionSimulator [2025]
	Server/ExplosionService — Handles server-side explosion validation,
	block destruction (delayed delete), reward granting, and structural integrity.
]]
--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Library = require(ReplicatedStorage:WaitForChild("Library"))
while not Library.IsLoaded() do
	task.wait()
end

local Saving = Library.Saving
local RewardsManager = Library.RewardsManager
local OrbsManager = require(game:GetService("ServerScriptService"):WaitForChild("Library"):WaitForChild("OrbsManager"))
local SkinMath = require(game:GetService("ReplicatedStorage"):WaitForChild("Library"):WaitForChild("Modules"):WaitForChild("SkinMath"))

local RemotesFolder = workspace:WaitForChild("__THINGS"):WaitForChild("__REMOTES")
local explodeEvent = RemotesFolder:FindFirstChild("ExplodeEvent") or Instance.new("RemoteEvent")
explodeEvent.Name = "ExplodeEvent"
explodeEvent.Parent = RemotesFolder

local AreaManager = require(script.Parent:WaitForChild("AreaManager"))

-- Initialize Areas on Startup
AreaManager.LoadAllAreas()

local CONFIG = {
	EXPLOSION_RADIUS = 9,
	MAX_HIT_DISTANCE = 600,
	BLOCKS_PER_PART = 1,
	RATE_LIMIT_INTERVAL = 0.15,
	RAYCAST_TOLERANCE = 70,
	MAX_BLOCKS_PER_EXPLOSION = 250, -- Hard cap: blocks affected per single explosion
}

local BUCKET_MAX = 3.0
local BUCKET_DRAIN_RATE = 1 / CONFIG.RATE_LIMIT_INTERVAL -- ~6.67 tokens drained per second

local playerBuckets = {}



local function HandleExplosion(player, hitPosition, hitPart, toolName)
	-- ============================================
	-- INPUT VALIDATION
	-- ============================================
	if typeof(hitPosition) ~= "Vector3" then
		return
	end
	if hitPart ~= nil and typeof(hitPart) ~= "Instance" then
		return
	end
	if type(toolName) ~= "string" then
		return
	end

	local SanitizeInput = require(game:GetService("ServerScriptService").Library.SanitizeInput)
	if not SanitizeInput.isValidString(toolName, 100) or not SanitizeInput.isValidVector3(hitPosition) then
		return
	end

	-- ============================================
	-- SANITY CHECK 1: Character exists
	-- ============================================
	local character = player.Character
	if not character then
		return
	end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

	-- ============================================
	-- SANITY CHECK 2: Distance to explosion is reasonable
	-- ============================================
	local distanceToHit = (hitPosition - rootPart.Position).Magnitude
	if distanceToHit > CONFIG.MAX_HIT_DISTANCE then
		-- warn("[ExplosionService] Distance sanity check failed! dist: " .. distanceToHit)
		return
	end

	-- ============================================
	-- OWNERSHIP CHECK: Weapon must be owned by player
	-- ============================================
	local profile = Saving.GetPlayerData(player)
	if not profile then
		return
	end

	local weaponOwned = false
	if toolName == "Rocket Launcher" or toolName == "Bomb" then
		weaponOwned = true -- Default items
	else
		for _, weapon in ipairs(profile.Weapons or {}) do
			if weapon.ID == toolName then
				weaponOwned = true
				break
			end
		end
	end

	if not weaponOwned then
		return
	end

	-- Validation check: ensure player is actually holding/equipping a Tool
	local heldTool = character:FindFirstChildOfClass("Tool")
	if not heldTool then
		return
	end

	-- ============================================
	-- RATE LIMITING: Leaky Bucket
	-- ============================================
	local now = os.clock()
	local bucket = playerBuckets[player.UserId]
	if not bucket then
		bucket = { tokens = 0, lastDrain = now }
		playerBuckets[player.UserId] = bucket
	end

	local elapsed = now - bucket.lastDrain
	bucket.tokens = math.max(0, bucket.tokens - (elapsed * BUCKET_DRAIN_RATE))
	if bucket.tokens ~= bucket.tokens then bucket.tokens = 0 end -- Proteção contra NaN
	bucket.lastDrain = now
	bucket.tokens = bucket.tokens + 1.0

	if bucket.tokens > BUCKET_MAX then
		-- warn("[ExplosionService] Rate limit hit for player: " .. player.Name .. " (tokens: " .. tostring(bucket.tokens) .. ")")
		return
	end

	-- ============================================
	-- RAYCAST SANITY CHECK: Verify line of sight to hit position
	-- ============================================
	local sanityRayDir = hitPosition - rootPart.Position
	local sanityParams = RaycastParams.new()
	sanityParams.FilterType = Enum.RaycastFilterType.Exclude
	sanityParams.FilterDescendantsInstances = { character }
	sanityParams.IgnoreWater = true

	local sanityHit = workspace:Raycast(rootPart.Position, sanityRayDir, sanityParams)
	if sanityHit and sanityHit.Instance then
		local distToSanityHit = (sanityHit.Position - rootPart.Position).Magnitude
		if distanceToHit - distToSanityHit > CONFIG.RAYCAST_TOLERANCE then
			-- warn("[ExplosionService] Sanity check failed! Hit instance: " .. sanityHit.Instance:GetFullName() .. " distToHit: " .. distanceToHit .. " distToSanity: " .. distToSanityHit)
			return
		end
	end

	local blastRadius = 9
	if toolName and typeof(toolName) == "string" then
		local weaponData = Library.Directory.Weapons[toolName]
			or (Library.Directory.Bomb and Library.Directory.Bomb[toolName])
		if weaponData and weaponData.blastRadius then
			blastRadius = weaponData.blastRadius
		end
	end
	blastRadius = math.min(blastRadius, 50) -- Cap de segurança limitando exploração de raios absurdos

	local overlapParams = OverlapParams.new()
	overlapParams.MaxParts = CONFIG.MAX_BLOCKS_PER_EXPLOSION

	local areasFolder = workspace:FindFirstChild("Areas")
	local fallbackMode = false

	if areasFolder then
		overlapParams.FilterType = Enum.RaycastFilterType.Include
		local filterList = { areasFolder }
		local hitboxes = CollectionService:GetTagged("PlayerHitbox")
		for _, hb in ipairs(hitboxes) do
			table.insert(filterList, hb)
		end
		overlapParams.FilterDescendantsInstances = filterList
	else
		fallbackMode = true
		overlapParams.FilterType = Enum.RaycastFilterType.Exclude
		local excludeList = { character, workspace:FindFirstChild("__THINGS"), workspace:FindFirstChild("__DEBRIS") }
		for _, p in ipairs(Players:GetPlayers()) do
			if p.Character then
				table.insert(excludeList, p.Character)
			end
		end
		overlapParams.FilterDescendantsInstances = excludeList
	end

	local partsInRadius = workspace:GetPartBoundsInRadius(hitPosition, blastRadius, overlapParams)
	local playerProfile = Saving.GetPlayerData(player)
	if not playerProfile then
		return
	end

	if not playerProfile.Storage then
		playerProfile.Storage = { Amount = 0, Max = 100 }
	end
	if not playerProfile.Currency then
		playerProfile.Currency = { Coins = 0, Gems = 0 }
	end

	local areasToUpdate = {}
	local hitVoxels = {}
	local VOXEL_SIZE = 3
	local validTargets = {}

	local function processBlock(part)
		if not part:IsA("BasePart") then
			return
		end
		if part.Locked or part.Name == "Baseplate" or part.Name == "SpawnLocation" or part.Name == "Terrain" then
			return
		end
		if part:GetAttribute("DestroyScheduled") or part:GetAttribute("ExplosionPending") then
			return
		end

		-- Only allow parts inside workspace.Areas to be exploded
		local areasFolder = workspace:FindFirstChild("Areas")
		if not areasFolder or not part:IsDescendantOf(areasFolder) then
			return
		end

		-- Only allow parts inside a "Blocks" folder
		local inBlocks = false
		local current = part.Parent
		while current and current ~= areasFolder do
			if current:IsA("Folder") and current.Name == "Blocks" then
				inBlocks = true
				break
			end
			current = current.Parent
		end
		if not inBlocks then
			return
		end

		-- Protect any parts belonging to Spawns, Protects or containing those keywords
		local currentProtect = part
		local protected = false
		while currentProtect and currentProtect ~= workspace do
			local nameLower = string.lower(currentProtect.Name)
			if string.find(nameLower, "spawn") or string.find(nameLower, "protect") then
				protected = true
				break
			end
			currentProtect = currentProtect.Parent
		end
		if protected then
			return
		end

		local model = part:FindFirstAncestorOfClass("Model")
		if model and model:FindFirstChildOfClass("Humanoid") then
			return
		end

		local areaName = AreaManager.FindAreaOfPart(part)

		if areaName then
			-- Anti-cheat: player must have sufficient level for this area (bypassed in Studio / for creator)
			local RunService = game:GetService("RunService")
			local isStudio = RunService:IsStudio()
			local isCreator = (player.UserId == game.CreatorId)

			if not (isStudio or isCreator) then
				local currentWorld = player:GetAttribute("World") or (playerProfile and playerProfile.CurrentWorld) or "Spawn"
				local areaConfig = nil
				if Library.Directory.Areas then
					local worldAreas = Library.Directory.Areas[currentWorld] or Library.Directory.Areas.Spawn or Library.Directory.Areas
					if worldAreas and typeof(worldAreas) == "table" then
						areaConfig = worldAreas[areaName]
						if not areaConfig then
							local normalizedSearch = string.lower(string.gsub(areaName, "%s+", ""))
							for name, config in pairs(worldAreas) do
								if typeof(config) == "table" and string.lower(string.gsub(name, "%s+", "")) == normalizedSearch then
									areaConfig = config
									break
								end
							end
						end
					end
				end
				if areaConfig then
					local reqLevel = areaConfig.RequiredLevel or areaConfig.LevelRequired or areaConfig.Level or areaConfig.ReqLevel or 1
					-- Beginner safety: Area 1 (Spawn starter zone) is always destructible by Level 1 players
					if (areaConfig and (areaConfig.Order == 1)) or areaName == "Area 1" or areaName == "Area1" then
						reqLevel = 1
					end
					local LevelModule = ReplicatedStorage:FindFirstChild("Library") and ReplicatedStorage.Library:FindFirstChild("Modules") and ReplicatedStorage.Library.Modules:FindFirstChild("LevelModule")
					local playerLevel = player:GetAttribute("Level")
					if not playerLevel and LevelModule then
						local exp = (playerProfile and playerProfile.Experience) or 0
						pcall(function()
							playerLevel = require(LevelModule).GetLevelDataFromXP(exp)
						end)
					end
					playerLevel = playerLevel or 1

					if playerLevel < reqLevel then
						return
					end
				end
			end
		end

		-- Pre-mark part to prevent duplicate processing in the same explosion
		part:SetAttribute("ExplosionPending", true)
		part:SetAttribute("ExplosionOwner", player.UserId)

		table.insert(validTargets, {
			part = part,
			areaName = areaName,
		})

		-- Voxelization check: map part bounds within explosion area to voxels
		local pos = part.Position
		local size = part.Size
		local minX = pos.X - size.X/2
		local maxX = pos.X + size.X/2
		local minY = pos.Y - size.Y/2
		local maxY = pos.Y + size.Y/2
		local minZ = pos.Z - size.Z/2
		local maxZ = pos.Z + size.Z/2
		
		local expMinX = hitPosition.X - blastRadius
		local expMaxX = hitPosition.X + blastRadius
		local expMinY = hitPosition.Y - blastRadius
		local expMaxY = hitPosition.Y + blastRadius
		local expMinZ = hitPosition.Z - blastRadius
		local expMaxZ = hitPosition.Z + blastRadius
		
		local interMinX = math.max(minX, expMinX)
		local interMaxX = math.min(maxX, expMaxX)
		local interMinY = math.max(minY, expMinY)
		local interMaxY = math.min(maxY, expMaxY)
		local interMinZ = math.max(minZ, expMinZ)
		local interMaxZ = math.min(maxZ, expMaxZ)
		
		local voxelAdded = false
		if interMinX < interMaxX and interMinY < interMaxY and interMinZ < interMaxZ then
			local startGx = math.floor(interMinX / VOXEL_SIZE)
			local endGx = math.floor(interMaxX / VOXEL_SIZE)
			local startGy = math.floor(interMinY / VOXEL_SIZE)
			local endGy = math.floor(interMaxY / VOXEL_SIZE)
			local startGz = math.floor(interMinZ / VOXEL_SIZE)
			local endGz = math.floor(interMaxZ / VOXEL_SIZE)
			
			for gx = startGx, endGx do
				for gy = startGy, endGy do
					for gz = startGz, endGz do
						local vx = (gx + 0.5) * VOXEL_SIZE
						local vy = (gy + 0.5) * VOXEL_SIZE
						local vz = (gz + 0.5) * VOXEL_SIZE
						local distSq = (vx - hitPosition.X)^2 + (vy - hitPosition.Y)^2 + (vz - hitPosition.Z)^2
						if distSq <= (blastRadius + VOXEL_SIZE * 0.5)^2 then
							local key = gx .. "_" .. gy .. "_" .. gz
							hitVoxels[key] = true
							voxelAdded = true
						end
					end
				end
			end
		end
		
		-- Fallback to center voxel if no voxel was added (extremely small part)
		if not voxelAdded then
			local cgx = math.floor(pos.X / VOXEL_SIZE)
			local cgy = math.floor(pos.Y / VOXEL_SIZE)
			local cgz = math.floor(pos.Z / VOXEL_SIZE)
			local key = cgx .. "_" .. cgy .. "_" .. cgz
			hitVoxels[key] = true
		end
	end

	for _, part in ipairs(partsInRadius) do
		processBlock(part)
	end

	if hitPart and hitPart.Parent then
		processBlock(hitPart)
	end

	-- ============================================================================
	-- CRITICAL PERFORMANCE / ANTI-REGRESSION INVARIANT (DO NOT REMOVE!):
	-- Staggered physics shockwave unanchoring ("dar um tempo / onda de choque").
	-- Low-end hardware (e.g. HP laptops with 8GB RAM, mobile devices) suffers massive
	-- frame freezes if dozens or hundreds of parts wake up simultaneously on frame 0.
	-- We sort targets by distance from the explosion center and stagger their physical
	-- unanchoring in batches (15 blocks per ~0.03s). This produces an expanding shockwave
	-- while keeping physics calculations completely smooth and stutter-free.
	-- DO NOT REMOVE THIS STAGGER OR REVERT TO IMMEDIATE MASS UNANCHORING!
	-- ============================================================================
	table.sort(validTargets, function(a, b)
		local distA = (a.part.Position - hitPosition).Magnitude
		local distB = (b.part.Position - hitPosition).Magnitude
		return distA < distB
	end)

	local BATCH_SIZE = 15
	local BATCH_INTERVAL = 0.03

	for i, target in ipairs(validTargets) do
		local batchIndex = math.floor((i - 1) / BATCH_SIZE)
		local staggerDelay = batchIndex * BATCH_INTERVAL

		if target.areaName then
			AreaManager.SchedulePartDestruction(target.part, target.areaName, hitPosition, blastRadius, player, staggerDelay)
			areasToUpdate[target.areaName] = true
		else
			target.part:SetAttribute("DestroyScheduled", true)
			target.part:SetAttribute("ExplosionPending", nil)
			local function unanchorNonAreaPart()
				if not target.part or not target.part.Parent then return end
				target.part.CanTouch = false
				target.part.CanQuery = false
				target.part.Anchored = false
				local vel, angVel = AreaManager.GetExplosionImpulse(target.part.Position, hitPosition, blastRadius)
				target.part.AssemblyLinearVelocity = vel
				target.part.AssemblyAngularVelocity = angVel
				pcall(function()
					target.part:SetNetworkOwner(player)
				end)
				local batches = AreaManager.DELETION_BATCHES or { 3, 5, 7 }
				local lifetime = batches[math.random(1, #batches)]
				task.delay(lifetime, function()
					if target.part and target.part.Parent then
						AreaManager.QueuePartDestruction(target.part)
					end
				end)
			end

			if staggerDelay > 0 then
				task.delay(staggerDelay, unanchorNonAreaPart)
			else
				unanchorNonAreaPart()
			end
		end
	end

	-- Count the total unique voxels hit in this explosion
	local blocksDestroyedCount = 0
	for _ in pairs(hitVoxels) do
		blocksDestroyedCount = blocksDestroyedCount + 1
	end

	-- Skin Multiplier Logic
	local finalBlocksCount = blocksDestroyedCount
	if toolName and typeof(toolName) == "string" then
		local category = nil
		if Library.Directory.Weapons[toolName] then
			category = "Launcher"
		elseif Library.Directory.Bomb and Library.Directory.Bomb[toolName] then
			category = "Bomb"
		end
		
		if category and playerProfile.EquippedSkins and playerProfile.EquippedSkins[category] and playerProfile.EquippedSkins[category][toolName] then
			local activeSkinID = playerProfile.EquippedSkins[category][toolName].ID
			if activeSkinID then
				-- Find float
				local skinFloat = 1
				for _, s in ipairs(playerProfile.Skins or {}) do
					if s.Category == category and s.ItemName == toolName and s.ID == activeSkinID then
						skinFloat = s.Float or 1
						break
					end
				end
				
				-- Get MultMin/MultMax
				local success, skinConfig = pcall(function() return require(game:GetService("ReplicatedStorage"):WaitForChild("Directory"):WaitForChild("Skins"):WaitForChild(category):WaitForChild(toolName):WaitForChild(activeSkinID)) end)
				if success and skinConfig then
					local mult = SkinMath.CalculateMultiplier(skinFloat, skinConfig.MultMin or 1, skinConfig.MultMax or 1)
					finalBlocksCount = math.floor(blocksDestroyedCount * mult)
				end
			end
		end
	end

	OrbsManager.CreateOrbs(player, hitPosition, finalBlocksCount)

	-- Run BFS structural integrity on affected areas. Debounced & scheduled off the
	-- explosion shockwave so BFS runs after debris has launched, without freezing the frame.
	for areaName in pairs(areasToUpdate) do
		AreaManager.ScheduleStructuralIntegrity(areaName, player)
	end

	-- Knockback
	local bombJumpMultiplier = 1
	if toolName and typeof(toolName) == "string" then
		local weaponData = Library.Directory.Weapons[toolName]
			or (Library.Directory.Bomb and Library.Directory.Bomb[toolName])
		if weaponData and weaponData.bombJumpMultiplier then
			bombJumpMultiplier = weaponData.bombJumpMultiplier
		end
	end

	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		if char then
			local hrp = char:FindFirstChild("HumanoidRootPart")
			local humanoid = char:FindFirstChild("Humanoid")
			if hrp and humanoid and humanoid.Health > 0 then
				local dist = (hrp.Position - hitPosition).Magnitude
				local jumpRadius = math.max(blastRadius + 8, 12)
				if dist <= jumpRadius then
					local rawDir = hrp.Position - hitPosition
					local totalDist = rawDir.Magnitude
					local direction = if totalDist < 0.5 then Vector3.new(0, 1, 0) else rawDir.Unit

					local dirY = math.clamp(direction.Y, 0.2, 1.0)
					local horizVector = Vector3.new(direction.X, 0, direction.Z)
					local horizMag = horizVector.Magnitude
					local horizDir = if horizMag > 0.01 then horizVector.Unit else Vector3.new(0, 0, 0)

					local distScale = math.clamp(1 - (totalDist / jumpRadius), 0.5, 1)

					-- Powerful horizontal launch force
					local horizForce = 140 * horizMag * bombJumpMultiplier * distScale

					-- Powerful vertical Rocket Jump / Bomb Jump launch force (110 - 150)
					local vertForce = math.clamp(100 + (dirY * 50), 90, 160) * bombJumpMultiplier * distScale

					local knockbackVel = Vector3.new(horizDir.X * horizForce, vertForce, horizDir.Z * horizForce)

					humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
					local bv = Instance.new("BodyVelocity")
					bv.MaxForce = Vector3.new(25000, 25000, 25000)
					bv.Velocity = knockbackVel
					bv.Parent = hrp
					game:GetService("Debris"):AddItem(bv, 0.25)

					local animator = humanoid:FindFirstChildOfClass("Animator")
					local bombJumpAnim = ReplicatedStorage:WaitForChild("Assets"):FindFirstChild("Animations")
						and ReplicatedStorage.Assets.Animations:FindFirstChild("BombJump")
					if animator and bombJumpAnim then
						local track = animator:LoadAnimation(bombJumpAnim)
						track:Play()
					end
				end
			end
		end
	end
end

explodeEvent.OnServerEvent:Connect(HandleExplosion)

game:GetService("Players").PlayerRemoving:Connect(function(player)
	playerBuckets[player.UserId] = nil
end)
