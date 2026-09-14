--[[
	© DestructionSimulator [2025]
	Server/RewardsManager — Block yield calculation and storage capping.

	Pure data-driven module: computes the final block reward from a base
	amount, applies the equipped Weapon Skin float multiplier via SkinEquip,
	and hard-caps at the player's Backpack max capacity.

	No physical Instances are created or manipulated.

	Usage:
		local RewardsManager = require(ServerLibrary.RewardsManager)

		local result = RewardsManager.GrantBlocks(playerProfile, 10)
		-- result = { added = 10, raw = 15, multiplier = 1.5, storageFull = false }
]]--

local RewardsManager = {}

----------------------------------------------------------------------
-- Dependencies
----------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SkinEquip = require(script.Parent.SkinEquip)

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

--- Grant blocks to the player's storage after applying the weapon skin multiplier.
---
--- Flow:
---   1. Look up the equipped weapon's skin multiplier (1.0 if none).
---   2. Multiply: rawYield = floor(baseAmount × multiplier).
---   3. Compute available space = Max - Amount.
---   4. actualAdded = min(rawYield, availableSpace).
---   5. Mutate playerProfile.Storage.Amount in place.
---
--- @param playerProfile table  The player's live save data (from Saving.GetPlayerData)
--- @param baseAmount    number The raw block yield before any multiplier
--- @return table { added: number, raw: number, multiplier: number, storageFull: boolean }
function RewardsManager.GrantBlocks(playerProfile: {}, baseAmount: number): {}
	assert(playerProfile, "[RewardsManager] playerProfile is nil")
	assert(type(baseAmount) == "number" and baseAmount > 0,
		"[RewardsManager] baseAmount must be a positive number")

	local storage = playerProfile.Storage
	assert(storage, "[RewardsManager] playerProfile.Storage is missing")

	-- 1. Resolve weapon skin multiplier & Rebirth multiplier (1.2x per Rebirth)
	local equippedWeaponID = playerProfile.EquippedWeapon
	local multiplier = 1.0
	if equippedWeaponID then
		multiplier = SkinEquip.GetEquippedMultiplier(playerProfile, equippedWeaponID)
	end
	
	local rebirthCount = playerProfile.Rebirth or 0
	local rebirthMultiplier = 1.0
	local Directory = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Directory"))
	local rebirthCategory = Directory and (Directory.Rebirths or Directory.Rebirth)
	local rebirthsConfig = (rebirthCategory and rebirthCategory.Rebirths) or rebirthCategory
	if rebirthsConfig and rebirthsConfig[rebirthCount] then
		rebirthMultiplier = rebirthsConfig[rebirthCount].BlocksMultiplier or 1.0
	elseif rebirthCount > 0 then
		rebirthMultiplier = 1.0 + (rebirthCount * 0.2)
	end
	multiplier = multiplier * rebirthMultiplier

	-- 2. Raw yield (always integer blocks)
	local rawYield = math.floor(baseAmount * multiplier)

	-- 3. Capacity enforcement
	local currentAmount = storage.Amount
	local maxCapacity   = storage.Max
	local availableSpace = math.max(0, maxCapacity - currentAmount)

	local actualAdded = math.min(rawYield, availableSpace)

	-- 4. Commit mutation
	storage.Amount = currentAmount + actualAdded
	
	-- 5. Award Experience & DestructiblesDestroyed stats
	playerProfile.Experience = (playerProfile.Experience or 0) + baseAmount
	playerProfile.DestructiblesDestroyed = (playerProfile.DestructiblesDestroyed or 0) + baseAmount

	if playerProfile.DestructiblesDestroyed >= 1 and playerProfile._playerInstance then
		local AnalyticsManager = require(game:GetService("ServerScriptService"):WaitForChild("Library"):WaitForChild("AnalyticsManager"))
		AnalyticsManager.LogOneTimeStep(playerProfile._playerInstance, "Onboarding_FTUE", 2, "First_Block_Destroyed")
	end

	return {
		added       = actualAdded,
		raw         = rawYield,
		multiplier  = multiplier,
		storageFull = (storage.Amount >= maxCapacity),
	}
end

--- Check whether the player's block storage is completely full.
--- @param playerProfile table
--- @return boolean
function RewardsManager.IsStorageFull(playerProfile: {}): boolean
	local storage = playerProfile.Storage
	if not storage then return true end
	return storage.Amount >= storage.Max
end

--- Return the fill ratio of the player's storage as a 0→1 value.
--- Useful for UI progress bars or "almost full" warnings.
--- @param playerProfile table
--- @return number  0.0 (empty) to 1.0 (full)
function RewardsManager.GetStorageFillPercent(playerProfile: {}): number
	local storage = playerProfile.Storage
	if not storage or storage.Max <= 0 then return 1.0 end
	return math.clamp(storage.Amount / storage.Max, 0, 1)
end

--- Return how many blocks of free space remain.
--- @param playerProfile table
--- @return number
function RewardsManager.GetAvailableSpace(playerProfile: {}): number
	local storage = playerProfile.Storage
	if not storage then return 0 end
	return math.max(0, storage.Max - storage.Amount)
end

return RewardsManager
