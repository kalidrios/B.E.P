--[[
	© DestructionSimulator [2025]
	Library/UGCAuthService — UGC Limited qualification & reward grant (ModuleScript)

	Design invariants (v4 — production rewrite):
	- THE CLAIM IS THE MUTEX: rewards are only applied after an UpdateAsync on the
	  claims DataStore confirms a NEW claim counter increment. The profile is never
	  mutated before the DataStore confirms, and each counter increment is atomic
	  (concurrent callbacks can never double-count).
	- COMPATIBILITY: store "UGCClaims_v1", key "<userId>_UGCClaims",
	  value { [assetId] = true } — existing claims keep working untouched.
	- RECONCILIATION: ownership without claim is granted on PlayerAdded
	  (covers purchases made on the website or in another place of the experience).
	- READ-ONLY ELIGIBILITY: this module never charges Rebirths. The Rebirth cost
	  lives exclusively in RebirthService/ClaimUGCGate (single source of truth).
	- Encapsulated ModuleScript: no _G export. Consume via require().
]]

local MarketplaceService = game:GetService("MarketplaceService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local Saving = require(ServerScriptService:WaitForChild("Library"):WaitForChild("Saving"))

local UGCAuthService = {}

----------------------------------------------------------------------
-- Configuration
----------------------------------------------------------------------

-- COMPATIBILITY: store name, key format and value shape are FROZEN.
-- Do not rename or reformat — existing player claims depend on this.
local DATASTORE_NAME = "UGCClaims_v1"

local UGC_REWARDS = {
	[76844588440579] = {
		-- Economy rewards disabled: owning the UGC item is the reward itself.
		-- Title is kept (granted once) for future use.
		cash = 0,
		contracts = 0,
		title = "UGC Master",
		badgeId = nil,
	},
}

-- YOUR LIMIT LIVES HERE: how many times each player may claim the in-game
-- reward per asset. math.huge = unlimited; set any number you want (e.g. 5).
-- The UGC item itself is still bought ONCE on the Marketplace — this only
-- controls how many times the in-game bonus can be claimed.
local MAX_CLAIMS_PER_ASSET = math.huge

-- Server-side progression requirement to be ELIGIBLE for the reward. This is the
-- AUTHORITATIVE gate: the client 15-Rebirth check in InteractController is
-- bypassable (an exploiter can fire RequestUGCPrompt directly), so eligibility is
-- re-verified here. Keep in sync with ClaimUGCGate's cost and the client gate.
local UGC_REBIRTH_REQUIREMENT = 15

local OWNERSHIP_RETRY_INTERVAL = 5  -- seconds between PlayerOwnsAsset retries on join
local OWNERSHIP_RETRY_MAX = 6      -- give up after ~30s of failed ownership checks

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------

local claimsStore = nil
local apiServicesEnabled = true
local mockClaims = {} -- Studio fallback when API Services are disabled

-- Per-player memory caches. Tables are assigned in ONE SHOT after loads complete —
-- never reset after a yield (prevents the load-time clobber race).
local _eligible = {}      -- { [userId] = { [assetId] = true } } (challenge eligibility)
local _claimed = {}       -- { [userId] = { [assetId] = count } } (mirrors the DataStore)
local _claimsLoaded = {}  -- { [userId] = true }

local activeClaimOps = 0  -- in-flight DataStore writes, drained by BindToClose

local function getClaimsStore()
	if not apiServicesEnabled then return nil end
	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(DATASTORE_NAME)
	end)
	if ok then
		return store
	end
	apiServicesEnabled = false
	warn("[UGCAuth] DataStore unavailable (API Services off?). Falling back to in-memory mock.")
	return nil
end

local function getClaimKey(userId)
	return tostring(userId) .. "_UGCClaims" -- FROZEN key format (compat)
end

-- Resolve the store once at startup (also flips the Studio mock fallback early).
claimsStore = getClaimsStore()

----------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------

-- Remotes live in workspace.__THINGS.__REMOTES (same convention as Network.luau).
local remotesFolder = workspace:WaitForChild("__THINGS"):WaitForChild("__REMOTES")

local ugcNotifyRemote = remotesFolder:FindFirstChild("UGCNotifyMessage")
if not ugcNotifyRemote then
	ugcNotifyRemote = Instance.new("RemoteEvent")
	ugcNotifyRemote.Name = "UGCNotifyMessage"
	ugcNotifyRemote.Parent = remotesFolder
end

-- Created at LOAD time (not on first grant): the client registers its
-- listener at join with a bounded wait; a lazily-created remote would be
-- missed by every client that joined before the first grant.
local ugcGrantedRemote = remotesFolder:FindFirstChild("UGCGranted")
if not ugcGrantedRemote then
	ugcGrantedRemote = Instance.new("RemoteEvent")
	ugcGrantedRemote.Name = "UGCGranted"
	ugcGrantedRemote.Parent = remotesFolder
end

-- Whitelist check + type refinement: anything passing this is a valid reward assetId.
local function isValidRewardAsset(assetId): boolean
	return type(assetId) == "number" and UGC_REWARDS[assetId :: number] ~= nil
end

-- Current claim count from the in-memory cache. Compat: legacy stores hold
-- boolean true (a single old claim) — that counts as 1.
local function getClaimCount(userId, assetId)
	local entry = _claimed[userId]
	local v = entry and entry[assetId]
	if v == true then return 1 end
	if type(v) == "number" then return v end
	return 0
end

local function isAtClaimLimit(userId, assetId)
	return getClaimCount(userId, assetId) >= MAX_CLAIMS_PER_ASSET
end

-- Server->player feedback. _G.Message only exists on the CLIENT, so the old
-- notify() was a silent no-op here; route the text through a dedicated remote
-- that InteractController listens to and displays as a Message modal.
local function notifyPlayer(player, messageText, title)
	if not player or not player.Parent then return end
	task.spawn(function()
		pcall(function()
			ugcNotifyRemote:FireClient(player, tostring(messageText), tostring(title or "UGC"))
		end)
	end)
end

-- Blocks until the Saving module finished loading this player's profile.
local function waitForProfile(player, timeout)
	local deadline = os.clock() + (timeout or 30)
	repeat
		if Saving.HasPlayerData(player) then
			return Saving.GetPlayerData(player)
		end
		if not player.Parent then return nil end
		task.wait(0.25)
	until os.clock() >= deadline
	return nil
end

-- Blocks until this player's claim cache finished loading from the DataStore.
-- No UGC interaction may happen before this returns true.
local function waitForClaimsLoaded(player, timeout)
	local deadline = os.clock() + (timeout or 20)
	repeat
		if _claimsLoaded[player.UserId] then return true end
		if not player.Parent then return false end
		task.wait(0.25)
	until os.clock() >= deadline
	return false
end

----------------------------------------------------------------------
-- Claim persistence — the DataStore IS the mutex (Rule 2)
--
-- Returns:  "granted"  -> UpdateAsync confirmed a counter increment; reward may be applied
--           "limit"    -> the configured claim limit was reached; nothing was written
--           "error"    -> DataStore write failed; nothing may be applied
----------------------------------------------------------------------
local function atomicClaim(userId, assetId)
	local key = getClaimKey(userId)

	local function transform(current)
		local data = current
		if type(data) ~= "table" then
			data = {}
		end
		-- Stored keys may come back as strings after JSON round-trip (compat)
		local existing = data[assetId]
		if existing == nil then
			existing = data[tostring(assetId)]
		end
		local count = 0
		if existing == true then
			count = 1 -- legacy boolean claim counts as one claim (compat)
		elseif type(existing) == "number" then
			count = existing
		end
		if count >= MAX_CLAIMS_PER_ASSET then
			return nil -- claim limit reached: abort the update, write nothing
		end
		data[assetId] = count + 1
		return data
	end

	local ok, result
	if claimsStore then
		activeClaimOps += 1
		ok, result = pcall(function()
			return claimsStore:UpdateAsync(key, transform)
		end)
		activeClaimOps -= 1
	else
		-- Studio mock: emulate the same semantics in memory
		local mockOk, mockResult = pcall(function()
			return transform(mockClaims[key])
		end)
		if mockOk and mockResult ~= nil then
			mockClaims[key] = mockResult
		end
		ok, result = mockOk, mockResult
	end

	if not ok then
		return "error", result
	end
	if result == nil then
		return "limit"
	end
	return "granted", result
end

----------------------------------------------------------------------
-- Reward grant — profile is ONLY mutated after the claim is confirmed
----------------------------------------------------------------------
local function grantReward(player, assetId, source)
	if not player or not player.Parent then return false end
	if not isValidRewardAsset(assetId) then return false end

	local userId = player.UserId
	local rewardConfig = UGC_REWARDS[assetId]

	local profile = waitForProfile(player, 30)
	if not profile then
		warn(string.format("[UGCAuth] (%s) Profile not loaded for %s — reward grant aborted, reconciliation will retry on next join.", source, player.Name))
		return false
	end

	-- Stage values in locals; the profile is NOT touched yet.
	local currentCoins = (profile.Currency and profile.Currency.Coins) or 0
	local stagedCoins = currentCoins + (rewardConfig.cash or 0)

	local currentContracts = (profile.Currency and profile.Currency.Contracts) or (profile.Contracts or 0)
	local stagedContracts = currentContracts + (rewardConfig.contracts or 0)

	-- THE mutex: atomic check-and-increment in the DataStore.
	local outcome, resultOrErr = atomicClaim(userId, assetId)

	if outcome == "limit" then
		_claimed[userId] = _claimed[userId] or {}
		_claimed[userId][assetId] = MAX_CLAIMS_PER_ASSET -- sync memory with persisted truth
		return false
	end

	if outcome == "error" then
		-- Nothing was persisted and nothing was granted. Reconciliation on
		-- PlayerAdded retries next session; ownership remains the proof.
		warn(string.format("[UGCAuth] (%s) Claim UpdateAsync FAILED for %s (asset %s) — grant aborted, nothing applied: %s", source, player.Name, tostring(assetId), tostring(resultOrErr)))
		return false
	end

	-- UpdateAsync confirmed a counter increment. Only now may memory/profile mutate.
	_claimed[userId] = _claimed[userId] or {}
	local newCount = (type(resultOrErr) == "table" and type(resultOrErr[assetId]) == "number")
		and resultOrErr[assetId]
		or (getClaimCount(userId, assetId) + 1)
	_claimed[userId][assetId] = newCount

	if not profile.Currency then profile.Currency = {} end
	profile.Currency.Coins = stagedCoins
	profile.Currency.Contracts = stagedContracts
	profile.Contracts = stagedContracts -- kept in sync for legacy consumers

	if rewardConfig.title then
		if not profile.Titles then profile.Titles = {} end
		if not table.find(profile.Titles, rewardConfig.title) then
			table.insert(profile.Titles, rewardConfig.title)
		end
		player:SetAttribute("EquippedTitle", rewardConfig.title)
	end

	player:SetAttribute("Coins", stagedCoins)
	player:SetAttribute("Contracts", stagedContracts)

	-- Persist the live profile (one retry; the claim itself is already durable)
	local saved = Saving.SaveData(player, false)
	if not saved then
		task.wait(1)
		saved = Saving.SaveData(player, false)
	end
	if not saved then
		warn(string.format("[UGCAuth] (%s) Profile save failed after granting asset %s to %s — values live in memory only until next auto-save.", source, tostring(assetId), player.Name))
	end

	notifyPlayer(
		player,
		"Congratulations! You claimed the UGC reward" .. (rewardConfig.title and (" and earned the \"" .. rewardConfig.title .. "\" title") or "") .. "!",
		"UGC Reward Claimed"
	)
	
	--[[
		REMOVED LEGACY TEXT PROMPT FOR LIKE/FAVORITE:
		This secondary text notification was commented out because the Like/Feedback prompt is now handled
		natively via SocialService:PromptFeedbackSubmissionAsync() on the client upon receiving the UGCGranted RemoteEvent.
		
		task.delay(0.5, function()
			notifyPlayer(player, "Enjoying the game? Please leave a 👍 LIKE and ⭐ FAVORITE to help us release more free UGC items!", "Support The Game! 👍")
		end)
	--]]

	-- Fire UGCGranted remote to client so client can present SocialService Feedback prompt
	-- (remote is created at module load; see helpers section)
	ugcGrantedRemote:FireClient(player, assetId)

	print(string.format("[UGCAuth] (%s) Granted UGC reward for asset %s to %s", source, tostring(assetId), player.Name))
	return true
end

----------------------------------------------------------------------
-- Ownership reconciliation (Rule 3 & 10)
-- Covers purchases made outside this place/flow. On API failure, retry later.
----------------------------------------------------------------------
local function reconcileOwnership(player, assetId, attempt)
	if not player or not player.Parent then return end

	local ok, owns = pcall(function()
		return MarketplaceService:PlayerOwnsAsset(player, assetId)
	end)

	if not ok then
		if (attempt or 1) < OWNERSHIP_RETRY_MAX then
			task.delay(OWNERSHIP_RETRY_INTERVAL, function()
				reconcileOwnership(player, assetId, (attempt or 1) + 1)
			end)
		else
			warn(string.format("[UGCAuth] Ownership check kept failing for %s (asset %s) — giving up this session.", player.Name, tostring(assetId)))
		end
		return
	end

	if owns == true then
		grantReward(player, assetId, "reconciliation")
	end
end

----------------------------------------------------------------------
-- Claim loading on join (Rule 1 & 5)
-- The cache is assigned in ONE SHOT after GetAsync — never reset mid-flight.
----------------------------------------------------------------------
local function loadPlayerClaims(player)
	local userId = player.UserId

	local loaded = {}
	if claimsStore then
		local key = getClaimKey(userId)
		local ok, data = pcall(function()
			return claimsStore:GetAsync(key)
		end)
		if ok and type(data) == "table" then
			for storedId, val in pairs(data) do
				local idKey = tonumber(storedId) or storedId -- compat: numeric keys back
				if val == true then
					loaded[idKey] = 1 -- legacy boolean claim counts as one claim
				elseif type(val) == "number" then
					loaded[idKey] = val
				end
			end
		elseif not ok then
			warn(string.format("[UGCAuth] Failed to load claims for %s: %s — treating as unclaimed this session.", player.Name, tostring(data)))
		end
	else
		local mock = mockClaims[getClaimKey(userId)]
		if type(mock) == "table" then
			for storedId, val in pairs(mock) do
				local idKey = tonumber(storedId) or storedId
				if val == true then
					loaded[idKey] = 1
				elseif type(val) == "number" then
					loaded[idKey] = val
				end
			end
		end
	end

	_claimed[userId] = loaded
	_claimsLoaded[userId] = true
	pcall(function()
		player:SetAttribute("__claimsLoaded", true)
	end)
end

local function onPlayerAdded(player)
	task.spawn(function()
		loadPlayerClaims(player)
		if not player.Parent then return end

		-- Reconcile every configured reward asset (Rule 3). Only players who have
		-- NEVER claimed are reconciled on join: reconciliation guarantees the
		-- FIRST grant for owners who bought elsewhere; repeat claims (up to
		-- MAX_CLAIMS_PER_ASSET) happen through the interact/prompt flow, so a
		-- join never hands out free extra claims.
		for assetId in pairs(UGC_REWARDS) do
			if getClaimCount(player.UserId, assetId) < 1 then
				reconcileOwnership(player, assetId, 1)
			end
		end
	end)
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

--- Marks challenge eligibility. READ-ONLY downstream: this module never charges.
--- The Rebirth cost belongs exclusively to RebirthService/ClaimUGCGate. (Rule 4)
function UGCAuthService.AuthorizeUGCClaim(player: Player, assetId: any)
	if not player or not player.Parent then return end
	if not isValidRewardAsset(assetId) then return end -- whitelist (Rule 7)

	local userId = player.UserId
	_eligible[userId] = _eligible[userId] or {}
	_eligible[userId][assetId] = true
	pcall(function()
		player:SetAttribute("UGC_Eligible_" .. tostring(assetId), true)
	end)
end

--- Whether the player reached the configured claim limit (MAX_CLAIMS_PER_ASSET)
--- for this asset. With the default unlimited setting this is always false.
function UGCAuthService.HasClaimedReward(player: Player, assetId: any): boolean
	if not player then return false end
	if not isValidRewardAsset(assetId) then return false end
	return isAtClaimLimit(player.UserId, assetId)
end

--- Eligibility is READ-ONLY here: in-memory challenge flag or server-side Rebirth
-- count. Never mutates anything, never charges. (Rule 4)
function UGCAuthService.IsEligibleForReward(player: Player, assetId: any): boolean
	if not player then return false end
	if not isValidRewardAsset(assetId) then return false end

	local userId = player.UserId
	if _eligible[userId] and _eligible[userId][assetId] == true then
		return true
	end

	-- SECURITY: the server is the authority. The client 15-Rebirth gate is
	-- trivially bypassable by firing RequestUGCPrompt directly, so eligibility is
	-- re-checked here. The old `Rebirth >= 1` test let ANY player with a single
	-- Rebirth claim the reward -- that is exactly the reported bypass. Require the
	-- real cost: the persisted vault flag OR UGC_REBIRTH_REQUIREMENT live Rebirths.
	local profile = Saving.GetPlayerData(player)

	-- ClaimUGCGate CONSUMES 15 Rebirths to unlock the vault, so players who went
	-- through the gate can be sitting below the threshold. The persisted vault
	-- flag is the proof they already paid -- denying them here deadlocks the flow.
	if profile and profile.OwnsUGCVault == true then
		return true
	end

	if profile and (profile.Rebirth or 0) >= UGC_REBIRTH_REQUIREMENT then
		return true
	end

	return false
end

--- Server-side purchase prompt. If the player already OWNS the asset, grants the
--- reward instead of prompting (reconciliation path, Rule 3). Ownership-check
--- failure assumes "not owned" so the prompt is never blocked by an API hiccup. (Rule 10)
function UGCAuthService.PromptUGC(player: Player, assetId: any)
	if not player or not player.Parent then return end
	if not isValidRewardAsset(assetId) then return end -- whitelist (Rule 7)

	if not waitForClaimsLoaded(player, 10) then
		notifyPlayer(player, "Your UGC claim data is still loading. Please try again in a few seconds!", "One Moment")
		return
	end

	if UGCAuthService.HasClaimedReward(player, assetId) then
		notifyPlayer(player, "You have reached the claim limit for this UGC reward!", "Limit Reached")
		return
	end

	local ok, owns = pcall(function()
		return MarketplaceService:PlayerOwnsAsset(player, assetId)
	end)

	if ok and owns == true then
		grantReward(player, assetId, "prompt-ownership")
		return
	end
	-- ok == false -> assume not owned; do not block the prompt on API failure.

	pcall(function()
		MarketplaceService:PromptPurchase(player, assetId)
	end)
end

----------------------------------------------------------------------
-- Remote: RequestUGCPrompt (client intention -> server verification)
----------------------------------------------------------------------
local requestUGCPromptRemote = remotesFolder:FindFirstChild("RequestUGCPrompt")
if not requestUGCPromptRemote then
	requestUGCPromptRemote = Instance.new("RemoteEvent")
	requestUGCPromptRemote.Name = "RequestUGCPrompt"
	requestUGCPromptRemote.Parent = remotesFolder
end

requestUGCPromptRemote.OnServerEvent:Connect(function(player, assetId)
	if not player or not player.Parent then return end

	-- Input validation + whitelist: never trust the client's assetId (Rule 7)
	if not isValidRewardAsset(assetId) then return end

	-- No UGC interaction before claims finished loading (Rule 5)
	if not waitForClaimsLoaded(player, 10) then
		-- Never fail silently: tell the player to retry instead of dead air.
		notifyPlayer(player, "Your UGC claim data is still loading. Please try again in a few seconds!", "One Moment")
		return
	end

	-- Rate limiting (2s cooldown)
	local last = player:GetAttribute("LastUGCPrompt")
	local now = os.clock()
	if last and (now - last) < 2 then return end
	player:SetAttribute("LastUGCPrompt", now)

	-- Server-side eligibility (read-only)
	if not UGCAuthService.IsEligibleForReward(player, assetId) then
		warn(string.format("[UGCAuth] %s requested UGC prompt without server eligibility", player.Name))
		notifyPlayer(player, "You need at least " .. UGC_REBIRTH_REQUIREMENT .. " Rebirths (or the UGC Vault unlocked) to claim this reward!", "UGC Locked")
		return
	end

	-- Community group is a server-verifiable claim requirement (the game-favorite
	-- step is trust-based on the client: Roblox exposes no API to query it).
	local UGC_COMMUNITY_GROUP_ID = 1105415251
	local inGroup = false
	local groupOk, groupRes = pcall(function()
		return player:IsInGroup(UGC_COMMUNITY_GROUP_ID)
	end)
	if groupOk then
		inGroup = groupRes == true
	end
	if not inGroup then
		notifyPlayer(player, "Please Join our Community Group (ID: " .. UGC_COMMUNITY_GROUP_ID .. ") to claim this reward!", "Community Required")
		return
	end

	UGCAuthService.PromptUGC(player, assetId)
end)

----------------------------------------------------------------------
-- Marketplace callback — idempotent by design (Rule 9)
-- May fire N times for the same purchase: only the first call wins, because the
-- real mutex is the UpdateAsync in atomicClaim, not an in-memory flag.
----------------------------------------------------------------------
MarketplaceService.PromptPurchaseFinished:Connect(function(player, assetId, isPurchased)
	if not isPurchased then return end
	if not player or not player.Parent then return end

	if not isValidRewardAsset(assetId) then return end -- whitelist (Rule 7)

	grantReward(player, assetId, "purchase-callback")
end)

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------
Players.PlayerAdded:Connect(onPlayerAdded)
for _, existingPlayer in ipairs(Players:GetPlayers()) do
	onPlayerAdded(existingPlayer)
end

Players.PlayerRemoving:Connect(function(player)
	local userId = player.UserId
	_eligible[userId] = nil
	_claimed[userId] = nil
	_claimsLoaded[userId] = nil
	-- No claims save needed here: every claim is persisted atomically at grant time.
end)

-- Shutdown flush (Rule 8, same pattern as RAP_Validator/Saving): wait for any
-- in-flight claim writes so a shutdown never interrupts a confirmed grant.
game:BindToClose(function()
	local deadline = os.clock() + 5
	while activeClaimOps > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
end)

return UGCAuthService
