local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

-- Wait for Library to load
local Library = require(ReplicatedStorage:WaitForChild("Library"))
while not Library.IsLoaded() do
	task.wait()
end

local Assets = ReplicatedStorage:WaitForChild("Assets", 5) or ReplicatedStorage:WaitForChild("Assets")
local Projectiles = Assets:FindFirstChild("Projectiles") or Assets:WaitForChild("Projectiles", 2)

local RocketController = {}
RocketController.ActiveProjectiles = {}

local TOOL_DATA = setmetatable({}, {
	__index = function(t, key)
		if not key or key == "" then return nil end
		local weapons = Library.Directory.Weapons
		if weapons then
			if weapons[key] then return weapons[key] end
			for name, data in pairs(weapons) do
				if string.lower(name) == string.lower(key) then
					return data
				end
			end
		end
		local bomb = Library.Directory.Bomb
		if bomb then
			if bomb[key] then return bomb[key] end
			for name, data in pairs(bomb) do
				if string.lower(name) == string.lower(key) then
					return data
				end
			end
		end
		return nil
	end
})

-- Helper to format raw asset IDs (numbers or strings) with Roblox prefix
local function formatAssetId(assetId)
	if not assetId or assetId == "" then return "" end
	local strId = tostring(assetId)
	if not string.find(strId, "://") then
		return "rbxassetid://" .. strId
	end
	return strId
end

local RemotesFolder = workspace:WaitForChild("__THINGS"):WaitForChild("__REMOTES")
local ExplodeEvent = RemotesFolder:WaitForChild("ExplodeEvent", 15) or RemotesFolder:WaitForChild("ExplodeEvent")

local FireWeaponEvent = RemotesFolder:WaitForChild("FireWeaponEvent", 15) or RemotesFolder:WaitForChild("FireWeaponEvent")
local RenderProjectileEvent = RemotesFolder:WaitForChild("RenderProjectileEvent", 15) or RemotesFolder:WaitForChild("RenderProjectileEvent")

-- Projectile Configurations now loaded from Directory/Projectiles

function RocketController.FireProjectile(toolName, originPos, lookVector, isLocal)
	if isLocal == nil then isLocal = true end
	
	local data = TOOL_DATA[toolName] or {}
	local projName = data.projectile or toolName
	local projData = Library.Directory.Projectiles and Library.Directory.Projectiles[projName]
	local speed = data.speed or (projData and projData.speed) or 150
	
	local modelTemplate = Projectiles:FindFirstChild(projName)
	if not modelTemplate and projData and projData.model then
		modelTemplate = Projectiles:FindFirstChild(projData.model)
	end
	if not modelTemplate then
		modelTemplate = Assets:FindFirstChild(projName, true)
	end
	
	local model
	if modelTemplate then
		model = modelTemplate:Clone()
	else
		-- Fallback glowing projectile if specific asset is not in Projectiles folder
		model = Instance.new("Part")
		model.Name = projName
		model.Size = Vector3.new(1.5, 1.5, 1.5)
		model.Shape = Enum.PartType.Ball
		model.Color = Color3.fromRGB(255, 170, 0)
		model.Material = Enum.Material.Neon
	end
	model.Parent = workspace
	
	local projData = Library.Directory.Projectiles and Library.Directory.Projectiles[projName]
	local rotationOffset = CFrame.new()
	if projData and projData.Y_ROT_180 then
		rotationOffset = CFrame.Angles(0, math.pi, 0)
	end
	
	model:PivotTo(CFrame.new(originPos, originPos + lookVector) * rotationOffset)
	
	-- Anchor all parts to prevent physics solver jitter
	for _, child in ipairs(model:GetDescendants()) do
		if child:IsA("BasePart") then
			child.Anchored = true
			child.CanCollide = false
			child.CanQuery = false
		end
	end

	local basePart = model:FindFirstChild("Base") or model:FindFirstChildWhichIsA("BasePart")

	-- Play flight sound dynamically or fallback to built-in / default sound
	local foundSwoosh = false
	for _, child in ipairs(model:GetDescendants()) do
		if child:IsA("Sound") and (child.Name == "Swoosh" or child.Name == "Fly" or child.Name == "Rocket" or child.Name == "RocketFly") then
			child.Looped = true
			child:Play()
			foundSwoosh = true
		end
	end
	
	if not foundSwoosh and basePart then
		local flightSoundId = (data and data.sounds and (data.sounds.Flight or data.sounds.Swoosh or data.sounds.RocketFly))
		if (not flightSoundId or flightSoundId == "") and projData and projData.sounds then
			flightSoundId = projData.sounds.Flight or projData.sounds.RocketFly
		end
		if not flightSoundId or flightSoundId == "" then
			flightSoundId = 12222084 -- Default Swoosh
		end
		
		local swoosh
		if type(flightSoundId) == "string" and not tonumber(flightSoundId) and not string.find(flightSoundId, "://") then
			local soundTemplate = Assets:FindFirstChild("Sounds") and Assets.Sounds:FindFirstChild(flightSoundId)
			if soundTemplate and soundTemplate:IsA("Sound") then
				swoosh = soundTemplate:Clone()
			end
		end
		
		if not swoosh then
			local formattedSoundId = formatAssetId(flightSoundId)
			if formattedSoundId ~= "" then
				swoosh = Instance.new("Sound")
				swoosh.SoundId = formattedSoundId
			end
		end
		
		if swoosh then
			swoosh.Name = "Swoosh"
			swoosh.Volume = 0.5
			swoosh.Looped = true
			swoosh.Parent = basePart
			swoosh:Play()
		end
	end
	local basePart = model:FindFirstChild("Base") or model:FindFirstChildWhichIsA("BasePart")
	
	local proj = {
		id = game:GetService("HttpService"):GenerateGUID(false),
		model = model,
		base = basePart,
		data = data,
		toolName = toolName, -- Store tool name for server explosion validation
		startPos = originPos,
		startVel = lookVector * speed,
		currentPos = originPos,
		rotationOffset = rotationOffset,
		t = 0,
		alive = true,
		isLocal = isLocal,
		ignored = { Players.LocalPlayer.Character, model }
	}
	
	table.insert(RocketController.ActiveProjectiles, proj)
	
	if isLocal then
		FireWeaponEvent:FireServer(toolName, originPos, lookVector)
	end
end

function RocketController.TickProjectile(proj, dt)
	if not proj.alive then return end
	if not proj.base then proj.alive = false; return end
	
	proj.t = proj.t + dt
	
	local oldPos = proj.currentPos
	local newPos
	
	if proj.data.gravity then
		newPos = proj.startPos + (proj.startVel * proj.t) + Vector3.new(0, (proj.t ^ 2) * (proj.data.gravity * -100) / 2, 0)
	else
		newPos = proj.startPos + (proj.startVel * proj.t)
	end
	
	proj.currentPos = newPos
	local rayDirection = newPos - oldPos
	
	-- FIX: "bico para cima"
	if rayDirection.Magnitude < 0.001 then
		rayDirection = proj.startVel * dt
	end
	
	local rayOrigin = oldPos
	
	local hitPart, hitPos
	
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { unpack(proj.ignored) }
	
	local function doRay()
		for _ = 1, 10 do -- Max 10 passthrough iterations to prevent stack overflow
			local result = workspace:Raycast(rayOrigin, rayDirection, rayParams)
			if not result then
				return nil, nil
			end
			-- Only skip parts that are fully invisible (Transparency >= 1) AND non-collidable
			if result.Instance.Anchored == true and result.Instance.CanCollide == false and result.Instance.Transparency >= 1 then
				table.insert(rayParams.FilterDescendantsInstances, result.Instance)
				continue
			end
			return result.Instance, result.Position
		end
		return nil, nil
	end
	
	hitPart, hitPos = doRay()
	
	if hitPart == nil then
		proj.model:PivotTo(CFrame.new(newPos, newPos + rayDirection) * proj.rotationOffset)
		return
	end
	
	proj.alive = false
	local finalHitPos = hitPos or proj.currentPos
	
	RocketController.CreateVisualExplosion(finalHitPos, proj.toolName, proj.isLocal, hitPart)

	if proj.model and proj.model.Parent then
		proj.model:Destroy()
	end
	
	if proj.isLocal then
		ExplodeEvent:FireServer(finalHitPos, hitPart, proj.toolName)
	end
end

function RocketController.CreateVisualExplosion(finalHitPos, toolName, isLocal, hitPart)
	if isLocal == nil then isLocal = true end
	
	local save = Library.Save.Get()
	local settings = (save and save.Settings) or {}
	local perfMode = settings.PerformanceMode or 2 -- 1: Low, 2: Medium, 3: High
	local showMyVfx = (settings.ShowMyVFX or 1) ~= 2
	local showOtherVfx = (settings.ShowOtherVFX or 1) ~= 2

	local showVfx = true
	if isLocal then
		showVfx = showMyVfx
	else
		showVfx = showOtherVfx and (perfMode ~= 1)
	end

	local teamName = Players.LocalPlayer.Team and Players.LocalPlayer.Team.Name or "Yellow"
	
	local EffectsFolder = Assets:FindFirstChild("Effects")
	local explosionTemplate = nil
	
	local toolData = TOOL_DATA[toolName]
	local projName = toolData and (toolData.projectile or toolData.baseProjectile)
	local projData = projName and Library.Directory.Projectiles and Library.Directory.Projectiles[projName]
	
	-- Resolve Effects from FolderEffects, Effect, Effects, explodeParticle in projData or toolData
	local effectList = {}
	local rawFolderEffects = projData and projData.FolderEffects or (toolData and toolData.FolderEffects)
	local rawEffects = (projData and (projData.Effect or projData.Effects or projData.explodeParticle))
		or (toolData and (toolData.Effect or toolData.Effects or toolData.explodeParticle))
		or projName
		or "Rocket"

	if rawFolderEffects then
		if typeof(rawFolderEffects) == "table" then
			for _, folderName in ipairs(rawFolderEffects) do
				table.insert(effectList, folderName)
			end
		elseif typeof(rawFolderEffects) == "string" then
			table.insert(effectList, rawFolderEffects)
		end
	end

	if typeof(rawEffects) == "table" then
		for _, eff in ipairs(rawEffects) do
			table.insert(effectList, eff)
		end
	elseif typeof(rawEffects) == "string" then
		table.insert(effectList, rawEffects)
	end

	local visualExplosionContainer = Instance.new("Part")
	visualExplosionContainer.Name = "VisualExplosion"
	visualExplosionContainer.Size = Vector3.new(1, 1, 1)
	visualExplosionContainer.Transparency = 1
	visualExplosionContainer.Anchored = true
	visualExplosionContainer.CanCollide = false
	visualExplosionContainer.CanTouch = false
	visualExplosionContainer.CanQuery = false
	visualExplosionContainer.CFrame = CFrame.new(finalHitPos)
	visualExplosionContainer.Parent = workspace

	if EffectsFolder and showVfx then
		local templatesToSpawn = {}
		for _, effName in ipairs(effectList) do
			local found = EffectsFolder:FindFirstChild(effName)
			if found then
				table.insert(templatesToSpawn, found)
			end
		end

		if #templatesToSpawn == 0 then
			local fallback = (projName and EffectsFolder:FindFirstChild(projName))
				or EffectsFolder:FindFirstChild("Explosions")
				or EffectsFolder:FindFirstChild("Rocket")
			if fallback then
				table.insert(templatesToSpawn, fallback)
			end
		end

		for _, template in ipairs(templatesToSpawn) do
			local clone = template:Clone()
			if clone:IsA("BasePart") then
				clone.CFrame = CFrame.new(finalHitPos)
				clone.Anchored = true
				clone.CanCollide = false
				clone.Parent = visualExplosionContainer
			elseif clone:IsA("Model") then
				clone:PivotTo(CFrame.new(finalHitPos))
				clone.Parent = visualExplosionContainer
			else
				-- Folder: reparent all visual components to visualExplosionContainer so they have 3D position
				for _, desc in ipairs(clone:GetDescendants()) do
					if desc:IsA("ParticleEmitter") or desc:IsA("Attachment") or desc:IsA("Beam") or desc:IsA("Sound") or desc:IsA("Light") then
						desc.Parent = visualExplosionContainer
					end
				end
				for _, child in ipairs(clone:GetChildren()) do
					if child:IsA("ParticleEmitter") or child:IsA("Attachment") or child:IsA("Beam") or child:IsA("Sound") or child:IsA("Light") then
						child.Parent = visualExplosionContainer
					end
				end
				clone:Destroy()
			end
		end
	end
		
	if showVfx then
		local particleScale = (perfMode == 1 and 0.3) or (perfMode == 3 and 1.4) or 1.0
		for _, child in ipairs(visualExplosionContainer:GetDescendants()) do
			if child:IsA("ParticleEmitter") then
				local baseEmit = child:GetAttribute("EmitCount") or math.clamp(math.floor(child.Rate * 1.5), 20, 60)
				local emitCount = math.max(1, math.floor(baseEmit * particleScale))
				child:Emit(emitCount)
				
				if child.Enabled then
					task.delay(0.4, function()
						if child and child.Parent then
							child.Enabled = false
						end
					end)
				end
			elseif child:IsA("Sound") then
				child:Play()
			end
		end
	end
		
	-- Play explosion sound configured dynamically, or fallback to classic explosion
	local projData = toolData and toolData.projectile and Library.Directory.Projectiles and Library.Directory.Projectiles[toolData.projectile]
	local explodeSoundId = (toolData and toolData.sounds and (toolData.sounds.Explode or toolData.sounds.Explosion))
	if (not explodeSoundId or explodeSoundId == "") and projData and projData.sounds then
		explodeSoundId = projData.sounds.Explosion or projData.sounds.Explode
	end
	if not explodeSoundId or explodeSoundId == "" then
		explodeSoundId = 137549133359716 -- ExplosionRocket sound ID (same as ref_doomspire)
	end
	
	local clonedSound
	if type(explodeSoundId) == "string" and not tonumber(explodeSoundId) and not string.find(explodeSoundId, "://") then
		-- 1. Try Assets.Sounds recursively
		local assetsSounds = Assets:FindFirstChild("Sounds")
		if assetsSounds then
			local found = assetsSounds:FindFirstChild(explodeSoundId, true)
			if found and found:IsA("Sound") then
				clonedSound = found
			elseif found and found:IsA("Folder") then
				local subSound = found:FindFirstChild(explodeSoundId)
				if subSound and subSound:IsA("Sound") then
					clonedSound = subSound
				end
			end
		end
		
		-- 2. Try Workspace.Sounds recursively
		if not clonedSound then
			local wsSounds = workspace:FindFirstChild("Sounds")
			if wsSounds then
				local found = wsSounds:FindFirstChild(explodeSoundId, true)
				if found and found:IsA("Sound") then
					clonedSound = found
				end
			end
		end
		
		if clonedSound then
			clonedSound = clonedSound:Clone()
		end
	end
	
	if not clonedSound then
		local formattedExplodeId = formatAssetId(explodeSoundId)
		if formattedExplodeId ~= "" then
			clonedSound = Instance.new("Sound")
			clonedSound.SoundId = formattedExplodeId
		end
	end
	
	if clonedSound then
		local expVol = 0.5
		if save and save.Settings then
			expVol = save.Settings.ExplosionVolume or 0.5
		end
		
		clonedSound.Name = "Explosion"
		clonedSound.Volume = 0.8 * expVol
		clonedSound.Parent = visualExplosionContainer
		clonedSound:Play()
		
		-- Fallback safety net if Roblox Audio Privacy blocks the sound ID
		task.delay(0.25, function()
			if clonedSound and clonedSound.Parent and clonedSound.TimeLength == 0 then
				clonedSound.SoundId = "rbxassetid://142070127"
				clonedSound:Play()
			end
		end)
	end
	
	-- Block Detection: plays the brick-crumble sound when the explosion actually hit blocks.
	-- All debris physics is owned by the SERVER (real unanchored parts, replicated).
	local destroyedAnyBlock = false
	local blastRadius = 9
	if toolData and toolData.blastRadius then
		blastRadius = toolData.blastRadius
	end
	
	local areasFolder = workspace:FindFirstChild("Areas")
	-- Fast path: If the projectile directly collided with an Area block, avoid spatial bounds query
	if hitPart and areasFolder and hitPart:IsDescendantOf(areasFolder) then
		local current = hitPart
		local protected = false
		while current and current ~= workspace do
			local nameLower = string.lower(current.Name)
			if string.find(nameLower, "spawn") or string.find(nameLower, "protect") then
				protected = true
				break
			end
			current = current.Parent
		end
		if not protected then
			destroyedAnyBlock = true
		end
	elseif areasFolder then
		local overlapParams = OverlapParams.new()
		overlapParams.MaxParts = 10
		overlapParams.FilterType = Enum.RaycastFilterType.Include
		overlapParams.FilterDescendantsInstances = { areasFolder }
		
		local parts = workspace:GetPartBoundsInRadius(finalHitPos, blastRadius, overlapParams)
		for _, part in ipairs(parts) do
			if part:IsA("BasePart") and not part.Locked and part.Name ~= "Baseplate" and part.Name ~= "Terrain" then
				local current = part
				local protected = false
				while current and current ~= workspace do
					local nameLower = string.lower(current.Name)
					if string.find(nameLower, "spawn") or string.find(nameLower, "protect") then
						protected = true
						break
					end
					current = current.Parent
				end
				if not protected then
					destroyedAnyBlock = true
					break
				end
			end
		end
	end

	if destroyedAnyBlock and isLocal then
		local soundService = game:GetService("SoundService")
		local expVol = 0.5
		if save and save.Settings then
			expVol = save.Settings.ExplosionVolume or 0.5
		end
		
		--[[
			This function was disabled because having these two collection/destruction sounds play together was getting a bit repetitive and tiring for the player.
		--]]

		-- Sound 1: Block destruction sound (Local player only!)
		local brickSound = Instance.new("Sound")
		brickSound.Name = "BrickSound"
		brickSound.SoundId = "rbxassetid://71830649123106"
		brickSound.PlaybackSpeed = 1.15
		brickSound.Volume = 1.5 * expVol
		brickSound.Parent = soundService
		brickSound:Play()
		task.delay(2, function()
			if brickSound and brickSound.Parent then
				brickSound:Destroy()
			end
		end)
	end
	
	task.delay(3, function()
		if visualExplosionContainer and visualExplosionContainer.Parent then
			visualExplosionContainer:Destroy()
		end
	end)
end

function RocketController.DropBomb(toolName, originPos, lookVector, isLocal)
	if isLocal == nil then isLocal = true end

	local bombData = Library.Directory.Bomb and Library.Directory.Bomb[toolName]
	local isThrowable = bombData and (bombData.throwable or bombData.isSticky or string.find(string.lower(toolName), "sticky") or string.find(string.lower(toolName), "potion"))
	local isSticky = bombData and (bombData.isSticky or string.find(string.lower(toolName), "sticky"))

	-- Find bomb model in Assets.Bomb folder
	local bombFolder = Assets:FindFirstChild("Bomb")
	local modelTemplate = bombFolder and bombFolder:FindFirstChild(toolName)
	if not modelTemplate then
		modelTemplate = Projectiles:FindFirstChild(toolName)
	end
	
	local bombModel
	if modelTemplate then
		bombModel = modelTemplate:Clone()
	else
		bombModel = Instance.new("Part")
		bombModel.Name = toolName
		bombModel.Size = Vector3.new(2.5, 2.5, 2.5)
		bombModel.Color = Color3.fromRGB(50, 50, 50)
		bombModel.Material = Enum.Material.Metal
	end
	
	local primaryPart = (bombModel:IsA("Model") and (bombModel.PrimaryPart or bombModel:FindFirstChildWhichIsA("BasePart"))) or (bombModel:IsA("BasePart") and bombModel)
	if bombModel:IsA("Model") and not bombModel.PrimaryPart and primaryPart then
		bombModel.PrimaryPart = primaryPart
	end

	-- Configure unanchored physical state and weld parts together
	if bombModel:IsA("Model") and primaryPart then
		for _, part in ipairs(bombModel:GetDescendants()) do
			if part:IsA("BasePart") then
				if part == primaryPart then
					part.Anchored = false
					part.CanCollide = true
					part.CanTouch = true
					part.CanQuery = true
					part.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.35, 0.45, 1, 1)
				else
					part.Anchored = false
					part.CanCollide = false
					part.Massless = true
					local weld = part:FindFirstChildOfClass("WeldConstraint") or part:FindFirstChildOfClass("Weld") or part:FindFirstChildOfClass("Motor6D")
					if not weld then
						local newWeld = Instance.new("WeldConstraint")
						newWeld.Part0 = primaryPart
						newWeld.Part1 = part
						newWeld.Parent = primaryPart
					end
				end
			end
		end
	elseif bombModel:IsA("BasePart") then
		bombModel.Anchored = false
		bombModel.CanCollide = true
		bombModel.CanTouch = true
		bombModel.CanQuery = true
		bombModel.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.35, 0.45, 1, 1)
	end

	local localPlayer = Players.LocalPlayer
	local character = (isLocal and localPlayer and localPlayer.Character)
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	local charVelocity = (hrp and hrp.AssemblyLinearVelocity) or Vector3.zero
	local moveDir = (humanoid and humanoid.MoveDirection.Magnitude > 0.05) and humanoid.MoveDirection or Vector3.zero
	local isMoving = moveDir.Magnitude > 0.05 or (charVelocity * Vector3.new(1, 0, 1)).Magnitude > 1.5

	-- Calculate initial spawn CFrame
	local spawnCFrame = CFrame.new(originPos, originPos + lookVector)
	if bombModel:IsA("Model") then
		bombModel:PivotTo(spawnCFrame)
	else
		bombModel.CFrame = spawnCFrame
	end
	bombModel.Parent = workspace

	-- Apply initial velocity / momentum
	if primaryPart then
		if isThrowable then
			local throwVel = (lookVector * 70) + Vector3.new(0, 14, 0) + (charVelocity * 0.6)
			primaryPart.AssemblyLinearVelocity = throwVel
			primaryPart.AssemblyAngularVelocity = Vector3.new(math.random(-8, 8), math.random(-8, 8), math.random(-8, 8))
		elseif isMoving then
			local forwardDirection = (moveDir.Magnitude > 0 and moveDir) or (lookVector * Vector3.new(1, 0, 1)).Unit
			local launchVel = (charVelocity * 0.85) + (forwardDirection * 14) + Vector3.new(0, 3.5, 0)
			primaryPart.AssemblyLinearVelocity = launchVel
			primaryPart.AssemblyAngularVelocity = Vector3.new(lookVector.Z * 8, 0, -lookVector.X * 8)
		else
			local gentlePush = (lookVector * Vector3.new(1, 0, 1)).Unit * 6 + Vector3.new(0, 1.5, 0)
			primaryPart.AssemblyLinearVelocity = gentlePush
			primaryPart.AssemblyAngularVelocity = Vector3.new(lookVector.Z * 4, 0, -lookVector.X * 4)
		end
	end

	-- If Sticky bomb, stick to first solid object touched
	if isSticky and primaryPart then
		local touchedConn
		touchedConn = primaryPart.Touched:Connect(function(hitPart)
			if not hitPart or (character and hitPart:IsDescendantOf(character)) or hitPart:IsDescendantOf(bombModel) then
				return
			end
			if touchedConn then
				touchedConn:Disconnect()
				touchedConn = nil
			end
			primaryPart.Anchored = true
			primaryPart.AssemblyLinearVelocity = Vector3.zero
			primaryPart.AssemblyAngularVelocity = Vector3.zero
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = primaryPart
			weld.Part1 = hitPart
			weld.Parent = primaryPart
		end)
	end

	-- Flash, Beep, and Sound sequence with BombTick (1.00) and BombTick2 (1.15 playback speed)
	task.spawn(function()
		local beepInterval = 0.45
		
		-- Fetch Assets.Sounds.BombTick or fallback
		local assetsSounds = Assets:FindFirstChild("Sounds")
		local bombTickSound = assetsSounds and assetsSounds:FindFirstChild("BombTick")
		local customBeepId = bombData and bombData.sounds and (bombData.sounds.Tick or bombData.sounds.PlantedTick or bombData.sounds.Beep)
		local soundAssetId = formatAssetId(customBeepId or (bombTickSound and bombTickSound.SoundId) or 111453669796139)

		local beepSound = Instance.new("Sound")
		beepSound.SoundId = soundAssetId
		beepSound.Volume = 0.85
		beepSound.Parent = bombModel:IsA("Model") and (bombModel.PrimaryPart or bombModel:FindFirstChildWhichIsA("BasePart")) or bombModel

		-- Look for/create light
		local light = bombModel:FindFirstChildWhichIsA("Light")
		if not light then
			light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255, 0, 0)
			light.Range = 15
			light.Brightness = 3
			light.Enabled = false
			light.Parent = bombModel:IsA("Model") and (bombModel.PrimaryPart or bombModel:FindFirstChildWhichIsA("BasePart")) or bombModel
		end
		
		for step = 1, 8 do
			if not bombModel.Parent then break end
			
			-- Alternating Tick 1 (1.00) vs Tick 2 (1.15 PlaybackSpeed)
			if step % 2 == 0 then
				beepSound.PlaybackSpeed = 1.15
			else
				beepSound.PlaybackSpeed = 1.00
			end
			beepSound:Play()
			
			if light then light.Enabled = true end
			task.wait(0.08)
			if light then light.Enabled = false end
			
			task.wait(beepInterval)
			beepInterval = math.max(0.06, beepInterval - 0.05)
		end
		
		-- Explode!
		if bombModel.Parent then
			local finalPos = bombModel:IsA("Model") and (bombModel.PrimaryPart and bombModel.PrimaryPart.Position or bombModel:GetPivot().Position) or bombModel.Position
			bombModel:Destroy()
			
			-- Render locally
			RocketController.CreateVisualExplosion(finalPos, toolName, isLocal)
			
			-- Send explosion event to server if we are the owner
			if isLocal then
				ExplodeEvent:FireServer(finalPos, nil, toolName)
			end
		end
	end)
end

RenderProjectileEvent.OnClientEvent:Connect(function(otherPlayer, toolName, originPos, lookVector)
	if otherPlayer ~= Players.LocalPlayer then
		local isPlaceableBomb = string.find(string.lower(toolName), "bomb") and not string.find(string.lower(toolName), "bombardier")
		if isPlaceableBomb then
			RocketController.DropBomb(toolName, originPos, lookVector, false)
		else
			RocketController.FireProjectile(toolName, originPos, lookVector, false)
		end
	end
end)

RunService.RenderStepped:Connect(function(dt)
	for i = #RocketController.ActiveProjectiles, 1, -1 do
		local proj = RocketController.ActiveProjectiles[i]
		if proj.alive then
			RocketController.TickProjectile(proj, dt)
		else
			table.remove(RocketController.ActiveProjectiles, i)
		end
	end
end)

RocketController.TOOL_DATA = TOOL_DATA

-- Expose via _G to avoid "require" bugs with LocalScripts!
_G.RocketController = RocketController

--print("[RC] RocketController loaded and exposed via _G")

return RocketController
