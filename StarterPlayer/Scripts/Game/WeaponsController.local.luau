--[[
	Â© DestructionSimulator [2025]
	WeaponsController â€” Handles client-side firing
]]
--

local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Assets = ReplicatedStorage:WaitForChild("Assets", 5) or ReplicatedStorage:WaitForChild("Assets")
local Projectiles = Assets:FindFirstChild("Projectiles") or Assets:WaitForChild("Projectiles", 2)
local Animations = Assets:FindFirstChild("Animations") or Assets:WaitForChild("Animations", 2)
local Ball = Assets:FindFirstChild("Ball") or Assets:WaitForChild("Ball", 2)

-- Wait for Library to load (Fail-Fast model)
local Library = require(ReplicatedStorage:WaitForChild("Library"))
while not Library.IsLoaded() do
	task.wait()
end

local Player = Players.LocalPlayer
local Mouse = Player:GetMouse()

-- Dynamic reference to RocketController to prevent startup lock
local function getRocketController()
	if not _G.RocketController then
		local scriptsFolder = script.Parent
		local rcScript = scriptsFolder and scriptsFolder:FindFirstChild("RocketController")
		if rcScript then
			pcall(function()
				_G.RocketController = require(rcScript)
			end)
		end
	end
	return _G.RocketController
end

local RocketController = setmetatable({}, {
	__index = function(targetTable, key)
		local rocketCtrl = getRocketController()
		return rocketCtrl and rocketCtrl[key]
	end,
})

-- Fetching the remotes from the defined structure
local RemotesFolder = workspace:WaitForChild("__THINGS"):WaitForChild("__REMOTES")
local WeaponHitRemote = RemotesFolder:WaitForChild("WeaponHit")

-- Control variables
local Firing = false
local LastFireTimes = {}
local AnimCache = {} -- Cached animation tracks per WEAPON NAME (tools are destroyed/re-cloned constantly)
local TrackById = {} -- [formattedAnimId] = AnimationTrack (one track per animation per character)
local AnimInstanceById = {} -- [formattedAnimId] = Animation instance (kept alive for its track)

local currentAmmoDummy = nil
local animConnection = nil
local activeHoldTrack = nil
local activeReloadTrack = nil

local function stopReloadAnim()
	if activeReloadTrack then
		activeReloadTrack:Stop()
		activeReloadTrack = nil
	end
end

local playHoldAnim, stopHoldAnim

local function clearAmmoDummy()
	if currentAmmoDummy then
		currentAmmoDummy:Destroy()
		currentAmmoDummy = nil
	end
	if animConnection then
		animConnection:Disconnect()
		animConnection = nil
	end
end

local function setDummyVisible(dummy, visible)
	if not dummy then
		return
	end
	local targetTransparency = visible and 0 or 1
	if dummy:IsA("BasePart") then
		dummy.Transparency = targetTransparency
	end
	for _, child in ipairs(dummy:GetDescendants()) do
		if child:IsA("BasePart") or child:IsA("Decal") or child:IsA("Texture") then
			child.Transparency = targetTransparency
		end
	end
end

local function setPartVisible(instance, visible)
	if not instance then
		return
	end
	local targetTransparency = visible and 0 or 1
	if instance:IsA("BasePart") or instance:IsA("Decal") or instance:IsA("Texture") then
		instance.Transparency = targetTransparency
	end
	for _, child in ipairs(instance:GetDescendants()) do
		if child:IsA("BasePart") or child:IsA("Decal") or child:IsA("Texture") then
			child.Transparency = targetTransparency
		elseif child:IsA("ParticleEmitter") or child:IsA("Sparkles") or child:IsA("Fire") or child:IsA("Light") then
			child.Enabled = visible
		end
	end
end

local function setupAmmoDummyForTool(tool)
	clearAmmoDummy()

	local weaponName = tool:GetAttribute("ToolName") or tool.Name
	local toolData = RocketController.TOOL_DATA and RocketController.TOOL_DATA[weaponName]

	--print("[DEBUG] setupAmmoDummyForTool for:", weaponName)
	if not toolData then
		--print("[DEBUG] No toolData for:", weaponName)
		return
	end
	if toolData.noAmmoDummy then
		--print("[DEBUG] toolData.noAmmoDummy is true for:", weaponName)
		return
	end

	local character = Player.Character
	if not character then
		--print("[DEBUG] No character found")
		return
	end

	local projName = toolData.projectile or toolData.baseProjectile
	local baseProjName = toolData.baseProjectile or "BombRocket"
	--print("[DEBUG] projName:", projName, "baseProjName:", baseProjName)

	-- Search in Projectiles folder first, then Ball folder, then fallback to recursive search
	local modelTemplate = (projName and Projectiles:FindFirstChild(projName))
		or (projName and Ball and Ball:FindFirstChild(projName))
		or (baseProjName and Projectiles:FindFirstChild(baseProjName))
		or (baseProjName and Ball and Ball:FindFirstChild(baseProjName))
		or (projName and Assets:FindFirstChild(projName, true))
		or (baseProjName and Assets:FindFirstChild(baseProjName, true))
		or Projectiles:FindFirstChild("BombRocket")
		or Projectiles:FindFirstChild("Rocket")
		or tool:FindFirstChild("Ammo")
		or tool:FindFirstChild("Rocket")

	if not modelTemplate then
		--print("[DEBUG] modelTemplate not found for:", projName)
		return
	end
	--print("[DEBUG] Found modelTemplate:", modelTemplate.Name, "ClassName:", modelTemplate.ClassName)

	-- Doomspire Style: Clone ONLY the "Base" part (or principal part) of the projectile model
	local templatePart = nil
	if modelTemplate:IsA("BasePart") then
		templatePart = modelTemplate
	elseif modelTemplate:IsA("Model") then
		templatePart = modelTemplate:FindFirstChild("Base")
			or modelTemplate:FindFirstChild("Rocket")
			or modelTemplate.PrimaryPart
			or modelTemplate:FindFirstChildWhichIsA("BasePart", true)
	end

	if not templatePart then
		--print("[DEBUG] templatePart not resolved from modelTemplate")
		return
	end
	--print("[DEBUG] Cloning templatePart:", templatePart.Name)

	local dummy = templatePart:Clone()
	dummy.Name = "LeftHandAmmoDummy"
	dummy.Size = dummy.Size * 0.5
	dummy.CanCollide = false
	dummy.CanQuery = false
	dummy.Anchored = false
	dummy.Massless = true
	dummy:ClearAllChildren() -- deletes any extra particles/fx/welds

	local leftHand = character:FindFirstChild("LeftHand") or character:FindFirstChild("Left Arm")
	if leftHand then
		local projData = Library.Directory.Projectiles
			and (Library.Directory.Projectiles[projName] or Library.Directory.Projectiles[baseProjName])
		local rotationOffset = CFrame.new()
		if projData and projData.Y_ROT_180 then
			rotationOffset = CFrame.Angles(0, math.pi, 0)
			--print("[DEBUG] Applied 180 Y rotation offset")
		end

		dummy.CFrame = leftHand.CFrame * rotationOffset

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = leftHand
		weld.Part1 = dummy
		weld.Parent = dummy

		dummy.Parent = tool
		currentAmmoDummy = dummy
		setDummyVisible(dummy, false)
		--print("[DEBUG] Successfully created and attached LeftHandAmmoDummy (Doomspire style). Visibility set to false.")
	else
		--print("[DEBUG] LeftHand / Left Arm not found in Character, destroying dummy")
		dummy:Destroy()
	end
end

-- Fire animation name mapping (weapon name -> animation name in Assets.Animations)
local FIRE_ANIM_MAP = {
	["Bow"] = "BowFire",
	["Rock Star"] = "GuitarFire",
	["Golden Racket"] = "RacketFire",
}

-- Helper: set ammo components visible or invisible in the Tool
local function setToolAmmoVisible(tool, toolData, visible)
	if not tool then
		return
	end

	local slotName = tool:GetAttribute("SlotName") or ""
	local weaponName = tool:GetAttribute("ToolName") or tool.Name
	local isPlaceableBomb = (slotName == "BOMB")
		or (string.find(string.lower(weaponName), "bomb") and not string.find(string.lower(weaponName), "bombardier"))

	if isPlaceableBomb then
		-- FOR BOMB TOOLS: Hide/show all parts of the bomb (Bomb, Fuse, Rings, Wick, Cap)
		local bombPartNames = { "Bomb", "Fuse", "Rings", "Ring", "Wick", "Cap" }
		for _, name in ipairs(bombPartNames) do
			local part = tool:FindFirstChild(name, true)
			if part then
				setPartVisible(part, visible)
			end
		end
	else
		-- FOR ROCKET LAUNCHERS: NEVER HIDE THE LAUNCHER BODY/BASE!
		-- Only hide the rocket inside the launcher barrel if present
		local projName = toolData and (toolData.projectile or toolData.baseProjectile)
		local ammoInsideLauncher = (projName and tool:FindFirstChild(projName))
			or tool:FindFirstChild("Rocket")
			or tool:FindFirstChild("Ammo")

		if ammoInsideLauncher and ammoInsideLauncher ~= tool:FindFirstChild("Handle") then
			setPartVisible(ammoInsideLauncher, visible)
		end
	end
end

-- Helper: apply special tool visual properties (Arm Cannon Dome, Shadow Shuriken / Wise Eye, Crystal Blaster Gems/Reticle)
local function applySpecialToolState(tool, state)
	if not tool then
		return
	end

	-- 1. Arm Cannon: Dome Transparency (0 when reloaded/equipped, 0.51 on fire)
	local dome = tool:FindFirstChild("Dome", true)
	if dome and dome:IsA("BasePart") then
		if state == "fire" then
			dome.Transparency = 0.51
		elseif state == "reloaded" or state == "equip" then
			dome.Transparency = 0
		end
	end

	-- 2. Shadow Shuriken / Wise Eye: Eye Part Transparency (0 when reloaded/equipped, 1 on fire)
	local eye = tool:FindFirstChild("Eye", true)
	if eye and eye:IsA("BasePart") then
		if state == "fire" then
			eye.Transparency = 1
		elseif state == "reloaded" or state == "equip" then
			eye.Transparency = 0
		end
	end

	-- 3. Crystal Blaster: Reticle and Gems
	local reticle = tool:FindFirstChild("Reticle", true)
	local gems = tool:FindFirstChild("Gems", true)
	local gems2 = tool:FindFirstChild("Gems2", true)
	if state == "fire" then
		if reticle and reticle:IsA("BasePart") then
			reticle.Transparency = 1
		end
		if gems and gems:IsA("BasePart") then
			gems.Transparency = 1
		end
		if gems2 and gems2:IsA("BasePart") then
			gems2.Transparency = 0
		end
	elseif state == "reloaded" or state == "equip" then
		if reticle and reticle:IsA("BasePart") then
			reticle.Transparency = 0
		end
		if gems and gems:IsA("BasePart") then
			gems.Transparency = 0
		end
		if gems2 and gems2:IsA("BasePart") then
			gems2.Transparency = 1
		end
		local barrel = tool:FindFirstChild("Barrel", true)
		local reloadFx = barrel and barrel:FindFirstChild("fx") and barrel.fx:FindFirstChild("Reload")
		if reloadFx and reloadFx:IsA("ParticleEmitter") and state == "reloaded" then
			reloadFx:Emit(1)
		end
	end
end

-- Helper: get the main rocket/ammo part inside a Tool
local function getToolAmmoPart(tool, toolData)
	if not tool then
		return nil
	end
	local projName = toolData and (toolData.projectile or toolData.baseProjectile)
	local part = tool:FindFirstChild("Ammo")
		or tool:FindFirstChild("Bomb")
		or tool:FindFirstChild("Fuse")
		or tool:FindFirstChild("Rocket")
		or (projName and tool:FindFirstChild(projName))
		or tool:FindFirstChild("AmmoDummy")
	if part then
		return part
	end
	-- Last resort: any BasePart inside the tool, but never the Handle itself
	-- (special weapons like Arm Cannon/Crystal Blaster have custom part layouts).
	local fallback = projName and tool:FindFirstChildWhichIsA("BasePart", true) or nil
	if fallback and fallback ~= tool:FindFirstChild("Handle") then
		return fallback
	end
	return nil
end

-- Helper: get the currently equipped Tool from the character
local function getEquippedTool()
	local character = Player.Character
	if not character then
		return nil
	end
	for _, tool in ipairs(character:GetChildren()) do
		if tool:IsA("Tool") then
			return tool
		end
	end
	return nil
end

-- Helper: get or create the Animator inside the character's Humanoid
local function getAnimator(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	return animator
end

-- Helper to format raw asset IDs (numbers or strings) with Roblox prefix
local function formatAssetId(assetId)
	if not assetId or assetId == "" then
		return ""
	end
	local strId = tostring(assetId)
	if not string.find(strId, "://") then
		return "rbxassetid://" .. strId
	end
	return strId
end

-- Helper: play a sound by name from the tool's Handle using dynamic IDs
local function playToolSound(tool, soundName)
	local handle = tool:FindFirstChild("Handle")
	if not handle then
		return
	end

	local weaponName = tool:GetAttribute("ToolName") or tool.Name
	local toolData = RocketController.TOOL_DATA and RocketController.TOOL_DATA[weaponName]

	local soundId = nil
	if toolData and toolData.sounds then
		-- Specific handling for Rock Star guitar chords
		if soundName == "Fire" and toolData.sounds.FireChords then
			local chords = toolData.sounds.FireChords
			if typeof(chords) == "table" and #chords > 0 then
				soundId = chords[math.random(1, #chords)]
			else
				soundId = toolData.sounds.Fire
			end
		else
			soundId = toolData.sounds[soundName]
		end
	end

	--[[
		ARCHITECTURAL RULE (ARCHITECTURAL_UNIFIED.md):
		DO NOT HARDCODE FALLBACK SOUND IDs IN THIS CONTROLLER.
		All sounds (Fire, Reload, Beep, Explode, etc.) must be defined and configured
		strictly inside the authoritative Directory modules (e.g. ReplicatedStorage.Directory.Weapons
		and ReplicatedStorage.Directory.Bomb) to maintain 100% data-driven modularity.
		Hardcoding fallback IDs in script controllers bypasses directory configuration, breaks data isolation,
		and causes maintenance confusion across weapons.

		[LEGACY HARDCODED SOUND FALLBACKS COMMENTED OUT BELOW]:
		if not soundId or soundId == "" or tostring(soundId) == "5" then
			local isPlaceableBomb = (tool:GetAttribute("SlotName") == "BOMB")
				or (
					string.find(string.lower(weaponName), "bomb") and not string.find(
						string.lower(weaponName),
						"bombardier"
					)
				)
			if isPlaceableBomb then
				if soundName == "Reload" then
					soundId = 120560969301439
				elseif soundName == "Beep" then
					soundId = 111453669796139
				elseif soundName == "Explode" then
					soundId = 142070127
				end
			else
				if soundName == "Fire" then
					soundId = 108666329732912
				elseif soundName == "Reload" then
					soundId = 93535777617414
				end
			end
		end
	]]

	local formattedSoundId = formatAssetId(soundId)
	if formattedSoundId ~= "" then
		local sound = Instance.new("Sound")
		sound.Name = soundName
		sound.SoundId = formattedSoundId

		local save = Library.Save.Get()
		local volumeScale = 1
		if save and save.Settings then
			if soundName == "Fire" then
				volumeScale = save.Settings.ExplosionVolume or 0.5
			else
				volumeScale = save.Settings.SFX or 1
			end
		end

		sound.Volume = 0.5 * volumeScale
		sound.Parent = handle
		sound:Play()
		game:GetService("Debris"):AddItem(sound, 3)
	end
end

-- Helper to create and load an animation programmatically by ID
local function loadAnimById(animator, animationId)
	local formattedAnimId = formatAssetId(animationId)
	if formattedAnimId == "" then
		return nil
	end

	-- Reuse already-loaded tracks: the Animator has a HARD CAP of 64 live tracks
	-- ("AnimationTrack limit of 64 tracks exceeded"), and every fresh LoadAnimation
	-- with a new Animation instance adds one that is never released.
	local cachedTrack = TrackById[formattedAnimId]
	if cachedTrack then
		return cachedTrack
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = formattedAnimId
	local success, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if success and track then
		TrackById[formattedAnimId] = track
		AnimInstanceById[formattedAnimId] = animation
		return track
	end
	return nil
end

-- Helper: get or cache animation tracks for a tool
local function getCachedAnims(tool, character)
	local weaponName = tool:GetAttribute("ToolName") or tool.Name

	-- Keyed by weapon NAME, not tool instance: WeaponEquipService destroys and
	-- re-clones tools on every loadout refresh, so instance keys missed every
	-- time and re-loaded 2-3 fresh tracks onto the same Animator per swap.
	if AnimCache[weaponName] then
		return AnimCache[weaponName]
	end

	local animator = getAnimator(character)
	if not animator then
		return nil
	end

	local tracks = {}

	local toolData = RocketController.TOOL_DATA and RocketController.TOOL_DATA[weaponName]
	local isPlaceableBomb = (tool:GetAttribute("SlotName") == "BOMB")
		or (string.find(string.lower(weaponName), "bomb") and not string.find(string.lower(weaponName), "bombardier"))

	local fireAnimId = toolData and toolData.animations and (toolData.animations.Fire or toolData.animations.Throw)
	local reloadAnimId = toolData and toolData.animations and (toolData.animations.Reload or toolData.animations.reload)
	local idleAnimId = toolData and toolData.animations and (toolData.animations.Idle or toolData.animations.Hold)

	--[[
		ARCHITECTURAL RULE (ARQUITETURA_UNIFICADA.md):
		DO NOT HARDCODE FALLBACK ANIMATION IDs IN THIS CONTROLLER.
		All animation IDs (Fire, Throw, Reload, Idle, Hold, etc.) must be defined and configured
		strictly inside the authoritative Directory modules (e.g. ReplicatedStorage.Directory.Weapons
		and ReplicatedStorage.Directory.Bomb) to maintain 100% data-driven modularity.
		Hardcoding animation asset IDs directly inside gameplay controllers fragments the weapon pipeline,
		masks missing directory data, and prevents easy visual tuning.

		[LEGACY HARDCODED ANIMATION FALLBACKS COMMENTED OUT BELOW]:
		if not isPlaceableBomb then
			if
				not fireAnimId
				or (typeof(fireAnimId) ~= "number" and typeof(fireAnimId) ~= "string")
				or tostring(fireAnimId) == "5"
			then
				fireAnimId = "rbxassetid://126196362232460"
			end
			if
				not reloadAnimId
				or (typeof(reloadAnimId) ~= "number" and typeof(reloadAnimId) ~= "string")
				or tostring(reloadAnimId) == "5"
			then
				reloadAnimId = "rbxassetid://90459419850787"
			end
		else
			if
				not fireAnimId
				or (typeof(fireAnimId) ~= "number" and typeof(fireAnimId) ~= "string")
				or tostring(fireAnimId) == "5"
			then
				fireAnimId = "rbxassetid://126445680136837"
			end
			if
				not reloadAnimId
				or (typeof(reloadAnimId) ~= "number" and typeof(reloadAnimId) ~= "string")
				or tostring(reloadAnimId) == "5"
			then
				reloadAnimId = "rbxassetid://91997583325567"
			end
			if
				not idleAnimId
				or (typeof(idleAnimId) ~= "number" and typeof(idleAnimId) ~= "string")
				or tostring(idleAnimId) == "5"
			then
				idleAnimId = "rbxassetid://124110925133084"
			end
		end
	]]

	tracks.fire = loadAnimById(animator, fireAnimId)
	if tracks.fire then
		tracks.fire.Looped = false
	end

	tracks.reload = loadAnimById(animator, reloadAnimId)
	if tracks.reload then
		tracks.reload.Looped = false
	end

	-- Hold animation (Idle/Hold for launchers and bombs)
	if idleAnimId then
		tracks.hold = loadAnimById(animator, idleAnimId)
		if tracks.hold then
			tracks.hold.Looped = true
		end
	end

	AnimCache[weaponName] = tracks
	return tracks
end

function playHoldAnim(tool)
	if activeHoldTrack then
		activeHoldTrack:Stop(0.1)
		activeHoldTrack = nil
	end

	local character = Player.Character
	if not character then
		return
	end

	local anims = getCachedAnims(tool, character)
	if anims and anims.hold then
		activeHoldTrack = anims.hold
		activeHoldTrack.Looped = true
		activeHoldTrack:Play(0.1)
	end
end

function stopHoldAnim()
	if activeHoldTrack then
		activeHoldTrack:Stop(0.1)
		activeHoldTrack = nil
	end
end

-- Weapon-aware variant: only returns tools that exist in TOOL_DATA (launchers,
-- bombs...). Used by the fire/input paths so non-data tools like the Sword never
-- trigger FireWeapon or the reload delays.
local function getEquippedWeapon()
	local character = Player.Character
	if not character then
		return nil
	end
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") then
			local weaponName = child:GetAttribute("ToolName") or child.Name
			local toolData = RocketController.TOOL_DATA and RocketController.TOOL_DATA[weaponName]
			if toolData then
				return child
			end
		end
	end
	return nil
end

local function FireWeapon()
	local now = os.clock()
	local tool = getEquippedWeapon()
	if not tool then
		return
	end

	local weaponName = tool:GetAttribute("ToolName") or tool.Name
	local slotName = tool:GetAttribute("SlotName") or "ROCKET"

	-- Check reload cooldown from RocketController data
	local toolData = RocketController.TOOL_DATA and RocketController.TOOL_DATA[weaponName]
	local cooldown = toolData and toolData.reload or 0.5
	local lastFired = LastFireTimes[slotName] or 0
	if now - lastFired < cooldown then
		return
	end
	LastFireTimes[slotName] = now

	local character = Player.Character
	if not character then
		return
	end

	-- Play fire sound from the tool's Handle
	playToolSound(tool, "Fire")

	-- Play fire animation (cached)
	local anims = getCachedAnims(tool, character)
	if anims and anims.fire then
		anims.fire:Play(0.1)
	end

	if toolData then
		-- Projectile weapon
		-- Direction: from HumanoidRootPart.Position to Mouse.Hit.Position
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not hrp then
			return
		end
		local origin = hrp.Position
		local targetPos = Mouse.Hit.Position
		local lookVector = targetPos - origin
		if lookVector.Magnitude < 0.1 then
			lookVector = hrp.CFrame.LookVector
		else
			lookVector = lookVector.Unit
		end

		-- Hide ammo / Bomb / Rocket / Fuse / Rings inside the TOOL
		setToolAmmoVisible(tool, toolData, false)
		applySpecialToolState(tool, "fire")

		-- Fire the projectile or drop the bomb
		local isPlaceableBomb = (tool:GetAttribute("SlotName") == "BOMB")
			or (
				string.find(string.lower(weaponName), "bomb") and not string.find(
					string.lower(weaponName),
					"bombardier"
				)
			)

		if isPlaceableBomb then
			RocketController.DropBomb(weaponName, origin, lookVector, true)
		else
			RocketController.FireProjectile(weaponName, origin, lookVector, true)
		end

		local remotes = workspace:WaitForChild("__THINGS"):WaitForChild("__REMOTES")
		local cooldownEvent = remotes:FindFirstChild("WeaponCooldownEvent")
		if not cooldownEvent then
			cooldownEvent = Instance.new("BindableEvent")
			cooldownEvent.Name = "WeaponCooldownEvent"
			cooldownEvent.Parent = remotes
		end
		cooldownEvent:Fire(slotName, cooldown)

		-- Schedule reload animation + sound
		local isBomb = isPlaceableBomb

		if isBomb then
			-- Stop holding pose when throwing the bomb
			if activeHoldTrack then
				activeHoldTrack:Stop()
			end

			-- BOMB RELOAD BEHAVIOR (Eveera style: reload starts cooldown - 0.8s, visible on marker or 0.4s fallback)
			task.delay(math.max(cooldown - 0.8, 0.1), function()
				if getEquippedTool() == tool and Player.Character == character then
					local restored = false
					local bombConnections = {}

					local function onBombRestored()
						if not restored and getEquippedTool() == tool and Player.Character == character then
							restored = true
							setToolAmmoVisible(tool, toolData, true)
							applySpecialToolState(tool, "reloaded")
							playToolSound(tool, "Reload")

							-- Restart the HoldingBomb pose now that the player has a new bomb in hand
							if anims and anims.hold then
								anims.hold:Play(0.1)
							end
						end
					end

					if anims and anims.reload then
						activeReloadTrack = anims.reload
						activeReloadTrack.Looped = false
						activeReloadTrack:Play(0.1)

						local function onBombMarker(event)
							local lowerEvent = string.lower(tostring(event or ""))
							if string.find(lowerEvent, "cubic")
								or string.find(lowerEvent, "rocketin")
								or string.find(lowerEvent, "bombin")
								or string.find(lowerEvent, "ammoin")
							then
								onBombRestored()
							end
						end

						table.insert(bombConnections, anims.reload:GetMarkerReachedSignal("AnimEvent"):Connect(onBombMarker))
						table.insert(bombConnections, anims.reload:GetMarkerReachedSignal("Cubic"):Connect(function() onBombMarker("Cubic") end))
						table.insert(bombConnections, anims.reload:GetMarkerReachedSignal("RocketIn"):Connect(function() onBombMarker("RocketIn") end))
						table.insert(bombConnections, anims.reload:GetMarkerReachedSignal("BombIn"):Connect(function() onBombMarker("BombIn") end))
						table.insert(bombConnections, anims.reload:GetMarkerReachedSignal("AmmoIn"):Connect(function() onBombMarker("AmmoIn") end))
						table.insert(bombConnections, anims.reload.KeyframeReached:Connect(onBombMarker))
					end

					task.delay(0.4, function()
						onBombRestored()
						for _, conn in ipairs(bombConnections) do
							conn:Disconnect()
						end
					end)
				end
			end)
		else
			-- ROCKET RELOAD BEHAVIOR (Doomspire style: reload animation plays 1s after firing)
			task.delay(1, function()
				if getEquippedTool() == tool and Player.Character == character then
					if anims and anims.reload then
						activeReloadTrack = anims.reload
						activeReloadTrack.Looped = false
						activeReloadTrack:Play(0.1)

						if animConnection then
							animConnection:Disconnect()
						end

						local connections = {}
						local rocketOutFired = false
						local function onMarker(event)
							local lowerEvent = string.lower(tostring(event or ""))
							--[[print(
								"[DEBUG] reload marker event fired:",
								event,
								"currentAmmoDummy exists:",
								currentAmmoDummy ~= nil
							)]]
							if string.find(lowerEvent, "rocketout") then
								rocketOutFired = true
								if currentAmmoDummy then
									setDummyVisible(currentAmmoDummy, true)
									--print("[DEBUG] Made currentAmmoDummy visible via RocketOut marker")
								end
							elseif string.find(lowerEvent, "rocketin")
								or string.find(lowerEvent, "cubic")
								or string.find(lowerEvent, "ammoin")
							then
								if currentAmmoDummy then
									setDummyVisible(currentAmmoDummy, false)
									--print("[DEBUG] Made currentAmmoDummy invisible via RocketIn/Cubic marker")
								end
								setToolAmmoVisible(tool, toolData, true)
								applySpecialToolState(tool, "reloaded")
								playToolSound(tool, "Reload")
							end
						end
						
						table.insert(connections, anims.reload:GetMarkerReachedSignal("AnimEvent"):Connect(onMarker))
						table.insert(
							connections,
							anims.reload:GetMarkerReachedSignal("RocketOut"):Connect(function()
								onMarker("RocketOut")
							end)
						)
						table.insert(
							connections,
							anims.reload:GetMarkerReachedSignal("RocketIn"):Connect(function()
								onMarker("RocketIn")
							end)
						)
						table.insert(
							connections,
							anims.reload:GetMarkerReachedSignal("Cubic"):Connect(function()
								onMarker("Cubic")
							end)
						)
						table.insert(
							connections,
							anims.reload:GetMarkerReachedSignal("AmmoIn"):Connect(function()
								onMarker("AmmoIn")
							end)
						)
						table.insert(connections, anims.reload.KeyframeReached:Connect(onMarker))

						-- Fallback: If RocketOut marker signal doesn't trigger within 0.15s, manually make currentAmmoDummy visible
						task.delay(0.15, function()
							if
								not rocketOutFired
								and currentAmmoDummy
								and anims
								and anims.reload
								and anims.reload.IsPlaying
							then
								--print("[DEBUG] RocketOut fallback triggered. Making dummy visible manually.")
								setDummyVisible(currentAmmoDummy, true)
							end
						end)

						table.insert(
							connections,
							anims.reload.Stopped:Connect(function()
								--print("[DEBUG] reload animation stopped naturally")
								if currentAmmoDummy then
									setDummyVisible(currentAmmoDummy, false)
								end
								if getEquippedTool() == tool and Player.Character == character then
									playHoldAnim(tool)
								end
							end)
						)

						animConnection = {
							Disconnect = function()
								for _, conn in ipairs(connections) do
									conn:Disconnect()
								end
							end,
						}
					else
						-- Fallback reload sound if no animation track
						playToolSound(tool, "Reload")
						task.delay(1.2, function()
							setToolAmmoVisible(tool, toolData, true)
							applySpecialToolState(tool, "reloaded")
							if currentAmmoDummy then
								setDummyVisible(currentAmmoDummy, false)
							end
						end)
					end
				end
			end)
		end
	end
end

local holdTimer = nil

local function startHoldTracking()
	local tool = getEquippedWeapon()
	if not tool then
		return
	end
	local weaponName = tool:GetAttribute("ToolName") or tool.Name
	if weaponName == "Rock Star" then
		if holdTimer then
			task.cancel(holdTimer)
		end
		holdTimer = task.delay(1.0, function()
			local currentTool = getEquippedTool()
			if currentTool and (currentTool:GetAttribute("ToolName") or currentTool.Name) == "Rock Star" and Firing then
				local character = Player.Character
				if character then
					local animator = getAnimator(character)
					if animator then
						-- Cached track: the previous code ran Instance.new + LoadAnimation
						-- on EVERY hold-fire trigger, leaking one track per trigger.
						local track = loadAnimById(animator, 94611660617253)
						if track then
							track.Looped = false
							track:Play()
						end
					end
				end
			end
		end)
	end
end

local function cancelHoldTracking()
	if holdTimer then
		task.cancel(holdTimer)
		holdTimer = nil
	end
end

-- PC input
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		Firing = true
		FireWeapon()
		startHoldTracking()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		Firing = false
		cancelHoldTracking()
	end
end)

-- Mobile (Touch)
UserInputService.TouchStarted:Connect(function(touch, gameProcessed)
	if gameProcessed then
		return
	end
	Firing = true
	FireWeapon()
	startHoldTracking()
end)

UserInputService.TouchEnded:Connect(function(touch)
	Firing = false
	cancelHoldTracking()
end)

-- Consolidated character load and tool connection setup
local function onCharacterAdded(character)
	AnimCache = {}
	-- New character = new Animator: tracks do not carry over, and the Animator
	-- track budget (64) resets with it.
	TrackById = {}
	AnimInstanceById = {}
	clearAmmoDummy()
	stopHoldAnim()
	cancelHoldTracking()

	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			task.wait(0.05)
			setupAmmoDummyForTool(child)
			playHoldAnim(child)
			local ammo = child:FindFirstChild("Ammo") or child:FindFirstChild("Bomb")
			if ammo then
				setPartVisible(ammo, true)
			end
			-- AFTER forcing ammo visibility, so special-part states (Gems/Reticle/Dome/Eye)
			-- are not overwritten back to hidden by the generic visibility pass.
			applySpecialToolState(child, "equip")
			child.Activated:Connect(function()
				Firing = true
				FireWeapon()
			end)
		end
	end)

	character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then
			clearAmmoDummy()
			stopHoldAnim()
			stopReloadAnim()
			cancelHoldTracking()
		end
	end)

	local activeTool = getEquippedTool()
	if activeTool then
		setupAmmoDummyForTool(activeTool)
		playHoldAnim(activeTool)
		local ammo = activeTool:FindFirstChild("Ammo") or activeTool:FindFirstChild("Bomb")
		if ammo then
			setPartVisible(ammo, true)
		end
		-- AFTER forcing ammo visibility (same reason as in ChildAdded above)
		applySpecialToolState(activeTool, "equip")
		activeTool.Activated:Connect(function()
			Firing = true
			FireWeapon()
		end)
	end
end

Player.CharacterAdded:Connect(onCharacterAdded)
if Player.Character then
	onCharacterAdded(Player.Character)
end

--print(" WeaponsController initialized (FIRING ENABLED).")
