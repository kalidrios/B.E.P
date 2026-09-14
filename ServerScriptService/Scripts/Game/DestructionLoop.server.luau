--[[
	Â© DestructionSimulator [2025]
	DestructionLoop â€” Server responsible for attack rate-limiting and injecting rewards
]]
--

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Library = require(ReplicatedStorage:WaitForChild("Library"))

-- Wait for Library to load
while not Library.IsLoaded() do
	task.wait()
end

local WeaponHitRemote = workspace:WaitForChild("__THINGS"):WaitForChild("__REMOTES"):WaitForChild("WeaponHit")

-- Security Memory for Rate Limiting
local playerBuckets = {}
local BUCKET_MAX = 3.0
local BUCKET_DRAIN_RATE = 1 / 0.5 -- 2 tokens drained per second (1 shot per 0.5s)


local function HandleWeaponHit(player, hitPosition)
	-- ============================================
	-- INPUT VALIDATION
	-- ============================================
	if typeof(hitPosition) ~= "Vector3" then
		return
	end

	local SanitizeInput = require(game:GetService("ServerScriptService").Library.SanitizeInput)
	if not SanitizeInput.isValidVector3(hitPosition) then
		return
	end

	-- ============================================
	-- SANITY CHECK: Player character proximity
	-- ============================================
	local character = player.Character
	if not character then
		return
	end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

	local distanceToHit = (hitPosition - rootPart.Position).Magnitude
	if distanceToHit > 300 then -- Max 300 studs away
		-- warn(string.format("[Security] Distance sanity check failed! Player %s tried to hit from %f studs away", player.Name, distanceToHit))
		return
	end

	-- Ownership Check: Player must have a weapon (Tool) equipped or in their Backpack
	local hasTool = character:FindFirstChildOfClass("Tool") or player.Backpack:FindFirstChildOfClass("Tool")
	if not hasTool then
		return
	end

	-- ============================================
	-- RATE LIMITING (Leaky Bucket)
	-- ============================================
	local now = os.clock()
	local bucket = playerBuckets[player.UserId]
	if not bucket then
		bucket = { tokens = 0, lastDrain = now }
		playerBuckets[player.UserId] = bucket
	end

	local elapsed = now - bucket.lastDrain
	bucket.tokens = math.max(0, bucket.tokens - (elapsed * BUCKET_DRAIN_RATE))
	if bucket.tokens ~= bucket.tokens then bucket.tokens = 0 end -- NaN Protection
	bucket.lastDrain = now
	
	bucket.tokens = bucket.tokens + 1.0
	
	if bucket.tokens > BUCKET_MAX then
		-- Ignore silently, spamming
		return
	end

	-- Input validated and rate limited cleanly without free reward injection.
	-- Rewards are awarded strictly via ExplosionService when blocks are actually destroyed.
end

WeaponHitRemote.OnServerEvent:Connect(HandleWeaponHit)

game:GetService("Players").PlayerRemoving:Connect(function(player)
	playerBuckets[player.UserId] = nil
end)
