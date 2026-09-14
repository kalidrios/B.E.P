local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Library = require(ReplicatedStorage:WaitForChild("Library"))

--[[
	Animation / Asset Fallbacks

	NOTE: Animation IDs, sound IDs and other static asset properties MUST be
	declared in `ReplicatedStorage.Directory` (exposed via `Library.Directory`).
	Centralizing these values in `Directory` keeps asset metadata editable
	without touching gameplay logic, enables safer overrides, localization and
	A/B testing, and prevents hard-coded IDs scattered across server scripts.

	The weapons logic should read configured IDs from `Library.Directory` and
	only use built-in fallback IDs as a last resort. Avoid embedding raw
	`rbxassetid://` literals in logic files; place them in the directory data.
]]

local RemotesFolder = workspace:WaitForChild("__THINGS"):WaitForChild("__REMOTES")

local FireWeaponEvent = RemotesFolder:FindFirstChild("FireWeaponEvent") or Instance.new("RemoteEvent")
FireWeaponEvent.Name = "FireWeaponEvent"
if not FireWeaponEvent.Parent then
	FireWeaponEvent.Parent = RemotesFolder
end

local RenderProjectileEvent = RemotesFolder:FindFirstChild("RenderProjectileEvent") or Instance.new("RemoteEvent")
RenderProjectileEvent.Name = "RenderProjectileEvent"
if not RenderProjectileEvent.Parent then
	RenderProjectileEvent.Parent = RemotesFolder
end

----------------------------------------------------------------------
-- Leaky Bucket Rate Limiting (per ServerArchitecture.md)
-- Each shot adds 1.0 to the bucket. The bucket drains at a constant
-- rate (1 / weapon_reload). If the bucket exceeds the threshold,
-- the behavior is statistically impossible = exploit.
----------------------------------------------------------------------
local BUCKET_MAX = 3.0 -- Max tokens before rejecting (allows small bursts from jitter)

local playerBuckets = {} -- { [UserId] = { tokens = number, lastDrain = number } }


FireWeaponEvent.OnServerEvent:Connect(function(player, toolName, originPos, lookVector)
	-- ============================================
	-- INPUT VALIDATION
	-- ============================================
	if type(toolName) ~= "string" or typeof(originPos) ~= "Vector3" or typeof(lookVector) ~= "Vector3" then
		return
	end

	local SanitizeInput = require(game:GetService("ServerScriptService").Library.SanitizeInput)
	if not SanitizeInput.isValidString(toolName, 100) then return end
	if not SanitizeInput.isValidVector3(originPos) then return end
	if not SanitizeInput.isValidVector3(lookVector) then return end
	if lookVector.Magnitude < 0.01 then return end

	local data = Library.Directory.Weapons[toolName] or (Library.Directory.Bomb and Library.Directory.Bomb[toolName])
	if not data then return end

	-- ============================================
	-- SANITY CHECK: Character & Distance
	-- ============================================
	local character = player.Character
	if not character then
		return
	end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

	-- Verify the shot origin is close to the player
	local distanceToOrigin = (originPos - rootPart.Position).Magnitude
	if distanceToOrigin > 50 then -- Max 50 studs from player position
		return
	end

	-- Verify lookVector is normalized and not zero
	local lookMag = lookVector.Magnitude
	if lookMag < 0.1 or lookMag > 1.5 then
		return
	end

	-- ============================================
	-- OWNERSHIP CHECK: Player must have equipped this weapon
	-- ============================================
	local profile = Library.Saving.GetPlayerData(player)
	if not profile then
		return
	end

	local equipped = false
	if toolName == "Rocket Launcher" or toolName == "Bomb" then
		equipped = true -- Default items always allowed
	else
		-- Check if player owns this weapon
		local isLauncher = data.type == "LancaMisseis"
			or string.find(toolName, "Launcher")
			or string.find(toolName, "Cannon")
			or string.find(toolName, "Bombardier")
			or toolName == "Bow"
		local isBomb = data.type == "Minas"
			or string.find(toolName, "Bomb")
			or toolName == "Super Bomb"
			or toolName == "Remote Detonator"

		for _, weapon in ipairs(profile.Weapons or {}) do
			if weapon.ID == toolName then
				equipped = true
				break
			end
		end

		if not equipped then
			return
		end
	end

	-- ============================================
	-- RATE LIMITING: Leaky Bucket per weapon type
	-- ============================================
	local now = os.clock()
	local drainRate = 1 / math.max(data.reload or 0.5, 0.1) -- tokens drained per second

	-- Initialize bucket for new players
	local bucket = playerBuckets[player.UserId]
	if not bucket then
		bucket = { tokens = 0, lastDrain = now }
		playerBuckets[player.UserId] = bucket
	end

	-- Drain the bucket based on elapsed time
	local elapsed = now - bucket.lastDrain
	bucket.tokens = math.max(0, bucket.tokens - (elapsed * drainRate))
	if bucket.tokens ~= bucket.tokens then bucket.tokens = 0 end -- Proteção contra NaN
	bucket.lastDrain = now

	-- Add cost for this shot
	bucket.tokens = bucket.tokens + 1.0

	-- Reject if bucket overflows (exploit behavior)
	if bucket.tokens > BUCKET_MAX then
		-- warn("[FireWeaponEvent] Rate limit exceeded for " .. player.Name .. " (tokens: " .. bucket.tokens .. ")")
		return
	end

	-- ============================================
	-- BROADCAST TO OTHER PLAYERS
	-- ============================================
	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer ~= player then
			RenderProjectileEvent:FireClient(otherPlayer, player, toolName, originPos, lookVector)
		end
	end
end)

game:GetService("Players").PlayerRemoving:Connect(function(player)
	playerBuckets[player.UserId] = nil
end)
