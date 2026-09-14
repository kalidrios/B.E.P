--[[
	© DestructionSimulator [2025]
	Server/RAP_Validator — Recent Average Price validation for weapon skins

	Calculates and validates market prices using Exponential Moving Average (EMA).
	Includes anti-fraud protections: outlier rejection, self-trade detection,
	wash trading cooldowns, and minimum volume thresholds.

	Usage:
		local RAP = require(ServerLibrary.RAP_Validator)

		-- Record a completed transaction
		RAP.RecordTransaction("Launcher_Dragon", 1500, sellerPlayer, buyerPlayer)

		-- Get current RAP for a skin
		local rap = RAP.GetRAP("Launcher_Dragon")

		-- Validate a proposed listing price
		local isValid, reason = RAP.ValidatePrice("Launcher_Dragon", 9999)

		-- Get all RAP data (for UI)
		local allRAP = RAP.GetAllRAP()
]]--

local RAP_Validator = {}

----------------------------------------------------------------------
-- Services
----------------------------------------------------------------------
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

----------------------------------------------------------------------
-- Server modules
----------------------------------------------------------------------
local ServerLibrary = game:GetService("ServerScriptService"):WaitForChild("Library")
local Network = require(ServerLibrary.Network)

----------------------------------------------------------------------
-- Constants (configurable)
----------------------------------------------------------------------
local CONFIG = {
	--- EMA (Exponential Moving Average)
	EMA_WINDOW = 20,                     -- Number of transactions for EMA smoothing
	                                      -- α = 2 / (EMA_WINDOW + 1)

	--- Outlier Rejection
	MAX_DEVIATION = 3.0,                  -- Reject prices > EMA × MAX_DEVIATION
	MIN_DEVIATION = 0.333,                -- Reject prices < EMA × MIN_DEVIATION (1/3)

	--- Anti-Manipulation
	SELF_TRADE_BLOCKED = true,            -- Block seller == buyer
	PAIR_COOLDOWN_SECONDS = 300,          -- 5 min cooldown between same pair
	PAIR_MAX_TRADES_WINDOW = 5,           -- Max trades per pair in cooldown window
	MIN_VOLUME_FOR_STABLE = 5,            -- Min transactions before RAP is "stable"
	                                      -- (unstable RAP uses wider deviation tolerance)
	UNSTABLE_DEVIATION_MULT = 2.0,        -- Multiply deviation tolerance when unstable

	--- Persistence
	DATASTORE_NAME = "RAP_SkinMarket",
	SAVE_INTERVAL = 120,                  -- Auto-save every 2 minutes
	
	--- Network
	RAP_UPDATE_EVENT = "RAP_SkinUpdate",  -- RemoteEvent name for client updates

	--- History
	MAX_HISTORY_PER_SKIN = 100,           -- Max transaction records kept per skin
}

----------------------------------------------------------------------
-- Internal State
----------------------------------------------------------------------

-- RAP data per skin: { [skinId] = { rap, volume, lastPrice, history, updatedAt } }
local rapData: {[string]: {
	rap: number,           -- Current EMA value
	volume: number,        -- Total transaction count
	lastPrice: number,     -- Last accepted price
	history: {number},     -- Recent prices (for debugging/display)
	updatedAt: number,     -- os.time() of last update
}} = {}

-- Pair cooldown tracking: { ["sellerId:buyerId"] = { count, resetTime } }
local pairCooldowns: {[string]: {
	count: number,
	resetTime: number,
}} = {}

-- EMA alpha (computed once)
local EMA_ALPHA = 2 / (CONFIG.EMA_WINDOW + 1)

-- DataStore reference
local rapStore = nil
local isDirty = false

----------------------------------------------------------------------
-- Internal Helpers
----------------------------------------------------------------------

--- Generate a pair key for cooldown tracking
local function pairKey(sellerId: number, buyerId: number): string
	-- Normalize: always put smaller ID first to catch both directions
	local a, b = math.min(sellerId, buyerId), math.max(sellerId, buyerId)
	return string.format("%d:%d", a, b)
end

--- Initialize RAP entry for a new skin
local function initSkin(skinId: string)
	if rapData[skinId] then return end
	rapData[skinId] = {
		rap = 0,
		volume = 0,
		lastPrice = 0,
		history = {},
		updatedAt = os.time(),
	}
end

--- Calculate whether the RAP is considered "stable" (enough volume)
local function isStable(skinId: string): boolean
	local data = rapData[skinId]
	if not data then return false end
	return data.volume >= CONFIG.MIN_VOLUME_FOR_STABLE
end

--- Get effective deviation limits (wider when unstable)
local function getDeviationLimits(skinId: string): (number, number)
	local maxDev = CONFIG.MAX_DEVIATION
	local minDev = CONFIG.MIN_DEVIATION
	
	if not isStable(skinId) then
		maxDev = maxDev * CONFIG.UNSTABLE_DEVIATION_MULT
		minDev = minDev / CONFIG.UNSTABLE_DEVIATION_MULT
	end
	
	return maxDev, minDev
end

--- Check pair cooldown
local function checkPairCooldown(sellerId: number, buyerId: number): (boolean, string?)
	local key = pairKey(sellerId, buyerId)
	local cooldown = pairCooldowns[key]
	
	if not cooldown then return true, nil end
	
	-- Reset if window expired
	if os.time() >= cooldown.resetTime then
		pairCooldowns[key] = nil
		return true, nil
	end
	
	-- Check if too many trades in window
	if cooldown.count >= CONFIG.PAIR_MAX_TRADES_WINDOW then
		local remaining = cooldown.resetTime - os.time()
		return false, string.format(
			"Trading cooldown: too many trades between these players. Wait %d seconds.",
			remaining
		)
	end
	
	return true, nil
end

--- Update pair cooldown after a trade
local function updatePairCooldown(sellerId: number, buyerId: number)
	local key = pairKey(sellerId, buyerId)
	local cooldown = pairCooldowns[key]
	
	if not cooldown or os.time() >= cooldown.resetTime then
		pairCooldowns[key] = {
			count = 1,
			resetTime = os.time() + CONFIG.PAIR_COOLDOWN_SECONDS,
		}
	else
		cooldown.count = cooldown.count + 1
	end
end

--- Update EMA with a new price
local function updateEMA(skinId: string, price: number)
	local data = rapData[skinId]
	assert(data, "[RAP_Validator] Skin not initialized: " .. skinId)
	
	if data.volume == 0 then
		-- First transaction: RAP = price directly
		data.rap = price
	else
		-- EMA formula: EMA_new = EMA_old × (1 - α) + price × α
		data.rap = data.rap * (1 - EMA_ALPHA) + price * EMA_ALPHA
	end
	
	data.volume = data.volume + 1
	data.lastPrice = price
	data.updatedAt = os.time()
	
	-- Append to history (capped)
	table.insert(data.history, price)
	if #data.history > CONFIG.MAX_HISTORY_PER_SKIN then
		table.remove(data.history, 1)
	end
	
	isDirty = true
end

----------------------------------------------------------------------
-- Persistence
----------------------------------------------------------------------

--- Load RAP data from DataStore
local function loadFromDataStore()
	if RunService:IsStudio() then
		-- In Studio, optionally skip DataStore
		--warn("[RAP_Validator] Running in Studio — DataStore load skipped (using empty state)")
		return
	end
	
	local success, err = pcall(function()
		rapStore = DataStoreService:GetDataStore(CONFIG.DATASTORE_NAME)
		local stored = rapStore:GetAsync("RAP_DATA")
		
		if stored and type(stored) == "table" then
			for skinId, skinData in pairs(stored) do
				rapData[skinId] = {
					rap = skinData.rap or 0,
					volume = skinData.volume or 0,
					lastPrice = skinData.lastPrice or 0,
					history = skinData.history or {},
					updatedAt = skinData.updatedAt or os.time(),
				}
			end
			print(string.format("[RAP_Validator] Loaded RAP data for %d skins", #stored))
		end
	end)
	
	if not success then
		warn("[RAP_Validator] Failed to load DataStore:", err)
	end
end

--- Save RAP data to DataStore
local function saveToDataStore()
	if not isDirty then return end
	if RunService:IsStudio() then return end
	if not rapStore then return end
	
	-- Serialize: strip history for storage efficiency (keep only last 20)
	local serialized = {}
	for skinId, data in pairs(rapData) do
		local historySlice = {}
		local startIdx = math.max(1, #data.history - 19)
		for i = startIdx, #data.history do
			table.insert(historySlice, data.history[i])
		end
		
		serialized[skinId] = {
			rap = data.rap,
			volume = data.volume,
			lastPrice = data.lastPrice,
			history = historySlice,
			updatedAt = data.updatedAt,
		}
	end
	
	local success, err = pcall(function()
		rapStore:SetAsync("RAP_DATA", serialized)
	end)
	
	if success then
		isDirty = false
		print("[RAP_Validator] Saved RAP data to DataStore")
	else
		warn("[RAP_Validator] Failed to save DataStore:", err)
	end
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

--- Record a completed market transaction.
--- Returns (success, reason)
function RAP_Validator.RecordTransaction(
	skinId: string,
	price: number,
	seller: Player,
	buyer: Player
): (boolean, string?)
	
	-- Basic input validation
	assert(type(skinId) == "string" and #skinId > 0, "[RAP_Validator] Invalid skinId")
	assert(type(price) == "number" and price > 0, "[RAP_Validator] Price must be positive")
	assert(typeof(seller) == "Instance" and seller:IsA("Player"), "[RAP_Validator] Invalid seller")
	assert(typeof(buyer) == "Instance" and buyer:IsA("Player"), "[RAP_Validator] Invalid buyer")
	
	local sellerId = seller.UserId
	local buyerId = buyer.UserId
	
	-- ┌────────────────────────────────────────────┐
	-- │  ANTI-FRAUD CHECK 1: Self-Trade Detection  │
	-- └────────────────────────────────────────────┘
	if CONFIG.SELF_TRADE_BLOCKED and sellerId == buyerId then
		return false, "Self-trading is not allowed."
	end
	
	-- ┌────────────────────────────────────────────┐
	-- │  ANTI-FRAUD CHECK 2: Pair Cooldown         │
	-- └────────────────────────────────────────────┘
	local cooldownOk, cooldownReason = checkPairCooldown(sellerId, buyerId)
	if not cooldownOk then
		return false, cooldownReason
	end
	
	-- Initialize skin if first time
	initSkin(skinId)
	
	-- ┌────────────────────────────────────────────┐
	-- │  ANTI-FRAUD CHECK 3: Outlier Rejection     │
	-- └────────────────────────────────────────────┘
	local data = rapData[skinId]
	if data.volume > 0 and data.rap > 0 then
		local maxDev, minDev = getDeviationLimits(skinId)
		local upperBound = data.rap * maxDev
		local lowerBound = data.rap * minDev
		
		if price > upperBound then
			return false, string.format(
				"Price rejected: %.0f exceeds maximum allowed (%.0f). Current RAP: %.0f",
				price, upperBound, data.rap
			)
		end
		
		if price < lowerBound then
			return false, string.format(
				"Price rejected: %.0f is below minimum allowed (%.0f). Current RAP: %.0f",
				price, lowerBound, data.rap
			)
		end
	end
	
	-- ┌────────────────────────────────────────────┐
	-- │  All checks passed — Record transaction    │
	-- └────────────────────────────────────────────┘
	updateEMA(skinId, price)
	updatePairCooldown(sellerId, buyerId)
	
	-- Broadcast updated RAP to all clients
	pcall(function()
		Network.FireAllClients(CONFIG.RAP_UPDATE_EVENT, skinId, rapData[skinId].rap, rapData[skinId].volume)
	end)
	
	return true, nil
end

--- Get the current RAP for a skin. Returns nil if no data exists.
function RAP_Validator.GetRAP(skinId: string): number?
	local data = rapData[skinId]
	if not data or data.volume == 0 then
		return nil
	end
	return math.round(data.rap)
end

--- Get full RAP info for a skin (for admin/debug UI)
function RAP_Validator.GetRAPInfo(skinId: string): {
	rap: number?,
	volume: number?,
	lastPrice: number?,
	stable: boolean,
	updatedAt: number?,
}
	local data = rapData[skinId]
	if not data then
		return {
			rap = nil,
			volume = 0,
			lastPrice = nil,
			stable = false,
			updatedAt = nil,
		}
	end
	
	return {
		rap = math.round(data.rap),
		volume = data.volume,
		lastPrice = data.lastPrice,
		stable = isStable(skinId),
		updatedAt = data.updatedAt,
	}
end

--- Get all RAP data as a simple table { [skinId] = rapValue }
function RAP_Validator.GetAllRAP(): {[string]: number}
	local result = {}
	for skinId, data in pairs(rapData) do
		if data.volume > 0 then
			result[skinId] = math.round(data.rap)
		end
	end
	return result
end

--- Validate whether a proposed price is acceptable for listing.
--- Does NOT record a transaction — use before listing.
--- Returns (isValid, reason)
function RAP_Validator.ValidatePrice(skinId: string, proposedPrice: number): (boolean, string?)
	if type(proposedPrice) ~= "number" or proposedPrice <= 0 then
		return false, "Price must be a positive number."
	end
	
	local data = rapData[skinId]
	
	-- No RAP data yet — any price is valid (first listing)
	if not data or data.volume == 0 or data.rap == 0 then
		return true, nil
	end
	
	local maxDev, minDev = getDeviationLimits(skinId)
	local upperBound = data.rap * maxDev
	local lowerBound = data.rap * minDev
	
	if proposedPrice > upperBound then
		return false, string.format(
			"Price too high. Maximum: %.0f (RAP: %.0f)",
			upperBound, data.rap
		)
	end
	
	if proposedPrice < lowerBound then
		return false, string.format(
			"Price too low. Minimum: %.0f (RAP: %.0f)",
			lowerBound, data.rap
		)
	end
	
	return true, nil
end

--- Manually set RAP for a skin (admin override).
--- Use sparingly — bypasses all validation.
function RAP_Validator.AdminSetRAP(skinId: string, rapValue: number)
	initSkin(skinId)
	rapData[skinId].rap = rapValue
	rapData[skinId].updatedAt = os.time()
	isDirty = true
	
	warn(string.format("[RAP_Validator] Admin override: %s RAP set to %.0f", skinId, rapValue))
	
	pcall(function()
		Network.FireAllClients(CONFIG.RAP_UPDATE_EVENT, skinId, rapValue, rapData[skinId].volume)
	end)
end

--- Reset all RAP data for a skin (admin)
function RAP_Validator.AdminResetSkin(skinId: string)
	rapData[skinId] = nil
	isDirty = true
	warn(string.format("[RAP_Validator] Admin reset: %s", skinId))
end

--- Get the config table (read-only reference for inspection)
function RAP_Validator.GetConfig()
	return CONFIG
end

----------------------------------------------------------------------
-- Network: Serve RAP to clients on request
----------------------------------------------------------------------
task.spawn(function()
	-- Create the RemoteEvent for RAP updates
	Network.CreateRemote(CONFIG.RAP_UPDATE_EVENT, "RemoteEvent")
	
	-- Create a RemoteFunction for clients to request all RAP data
	Network.CreateRemote("RAP_GetAll", "RemoteFunction")
	Network.OnServerInvoke("RAP_GetAll", function(player: Player)
		return RAP_Validator.GetAllRAP()
	end)
	
	-- Create a RemoteFunction for clients to request specific skin RAP
	Network.CreateRemote("RAP_GetSkin", "RemoteFunction")
	Network.OnServerInvoke("RAP_GetSkin", function(player: Player, skinId: string)
		if type(skinId) ~= "string" then return nil end
		return RAP_Validator.GetRAPInfo(skinId)
	end)
end)

----------------------------------------------------------------------
-- Persistence: Auto-save loop & Cooldown Cleanup
----------------------------------------------------------------------
task.spawn(function()
	loadFromDataStore()
	
	while true do
		task.wait(CONFIG.SAVE_INTERVAL)
		
		-- Clean up stale pair cooldowns to prevent memory leaks
		local now = os.time()
		for key, cooldown in pairs(pairCooldowns) do
			if now >= cooldown.resetTime then
				pairCooldowns[key] = nil
			end
		end
		
		saveToDataStore()
	end
end)

-- Save on server shutdown
game:BindToClose(function()
	saveToDataStore()
end)

return RAP_Validator
