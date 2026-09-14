--[[
	© DestructionSimulator [2025]
	Server/SellManager — Block-to-Cash/XP conversion at the sell zone.

	Pure data-driven module: reads the player's stored block count,
	zeroes it out, converts blocks into Cash and XP, and mutates the
	player profile in place.

	Multiplier rule:
	  • The equipped Backpack Skin multiplier (float-based, via SkinEquip)
	    is applied STRICTLY to Cash.
	  • XP is NEVER affected by the skin multiplier.

	No physical Instances are created or manipulated.

	Usage:
		local SellManager = require(ServerLibrary.SellManager)

		local result = SellManager.SellBlocks(playerProfile)
		-- result = { blocksSold = 87, cashEarned = 130, xpEarned = 43,
		--            baseCash = 87, multiplier = 1.5 }
]]--

local SellManager = {}

----------------------------------------------------------------------
-- Dependencies
----------------------------------------------------------------------
local SkinEquip = require(script.Parent.SkinEquip)

----------------------------------------------------------------------
-- Configuration
----------------------------------------------------------------------
local CONFIG = {
	CASH_PER_BLOCK = 1,    -- Base cash earned per block sold
	XP_PER_BLOCK   = 0.5,  -- Base XP earned per block sold
}

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

--- Sell all stored blocks, converting them into Cash and XP.
---
--- Flow:
---   1. Read Storage.Amount; if 0, return early with zeroed result.
---   2. Reset Storage.Amount to 0 (blocks consumed).
---   3. baseCash  = floor(blockCount × CASH_PER_BLOCK).
---   4. baseXP    = floor(blockCount × XP_PER_BLOCK).
---   5. Fetch the equipped Backpack Skin multiplier via SkinEquip.
---   6. finalCash = floor(baseCash × backpackMultiplier).
---   7. finalXP   = baseXP  (no multiplier applied).
---   8. Accumulate into Currency.Coins and Experience.
---
--- @param playerProfile table  The player's live save data
--- @return table { blocksSold, cashEarned, xpEarned, baseCash, multiplier }
function SellManager.SellBlocks(playerProfile: {}): {}
	assert(playerProfile, "[SellManager] playerProfile is nil")

	if not playerProfile.Storage then
		playerProfile.Storage = { Amount = 0, Max = 100 }
	end
	if not playerProfile.Currency then
		playerProfile.Currency = { Coins = 0, Gems = 0 }
	end

	local storage = playerProfile.Storage
	local blockCount = storage.Amount

	-- ── Nothing to sell ──────────────────────────────────────────────
	if blockCount <= 0 then
		return {
			blocksSold = 0,
			cashEarned = 0,
			xpEarned   = 0,
			baseCash   = 0,
			multiplier = 1.0,
		}
	end

	-- 1. Consume all blocks
	storage.Amount = 0

	-- 2. Base conversions (always integer)
	local baseCash = math.floor(blockCount * CONFIG.CASH_PER_BLOCK)
	local baseXP   = math.floor(blockCount * CONFIG.XP_PER_BLOCK)

	-- 3. Resolve Backpack Skin multiplier
	--    EquippedSkins can map both weapon IDs *and* backpack IDs,
	--    so we pass the equipped backpack name as the lookup key.
	local equippedBackpack = playerProfile.EquippedBackpack
	local backpackMultiplier = 1.0
	if equippedBackpack then
		backpackMultiplier = SkinEquip.GetEquippedMultiplier(
			playerProfile, equippedBackpack
		)
	end

	-- 4. Apply backpack skin multiplier and Rebirth multiplier STRICTLY to Cash
	local rebirthCount = playerProfile.Rebirth or 0
	local rebirthMultiplier = 1.0
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Directory = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Directory"))
	local rebirthCategory = Directory and (Directory.Rebirths or Directory.Rebirth)
	local rebirthsConfig = (rebirthCategory and rebirthCategory.Rebirths) or rebirthCategory
	if rebirthsConfig and rebirthsConfig[rebirthCount] then
		rebirthMultiplier = rebirthsConfig[rebirthCount].CashMultiplier or 1.0
	elseif rebirthCount > 0 then
		rebirthMultiplier = 1.0 + (rebirthCount * 0.2)
	end
	local totalCashMultiplier = backpackMultiplier * rebirthMultiplier

	local finalCash = math.floor(baseCash * totalCashMultiplier)
	local finalXP   = baseXP  -- XP is never multiplied

	-- 5. Commit mutations
	if not playerProfile.Currency then
		playerProfile.Currency = { Coins = 0, Gems = 0 }
	end

	playerProfile.Currency.Coins = playerProfile.Currency.Coins + finalCash
	playerProfile.Experience = (playerProfile.Experience or 0) + finalXP

	return {
		blocksSold = blockCount,
		cashEarned = finalCash,
		xpEarned   = finalXP,
		baseCash   = baseCash,
		multiplier = backpackMultiplier,
	}
end

--- Preview what selling would yield without actually mutating the profile.
--- Useful for client-side UI tooltips.
--- @param playerProfile table
--- @return table  Same shape as SellBlocks return, but nothing is mutated.
function SellManager.PreviewSell(playerProfile: {}): {}
	assert(playerProfile, "[SellManager] playerProfile is nil")

	if not playerProfile.Storage then
		playerProfile.Storage = { Amount = 0, Max = 100 }
	end

	local storage = playerProfile.Storage
	if storage.Amount <= 0 then
		return {
			blocksSold = 0,
			cashEarned = 0,
			xpEarned   = 0,
			baseCash   = 0,
			multiplier = 1.0,
		}
	end

	local blockCount = storage.Amount
	local baseCash = math.floor(blockCount * CONFIG.CASH_PER_BLOCK)
	local baseXP   = math.floor(blockCount * CONFIG.XP_PER_BLOCK)

	local equippedBackpack = playerProfile.EquippedBackpack
	local backpackMultiplier = 1.0
	if equippedBackpack then
		backpackMultiplier = SkinEquip.GetEquippedMultiplier(
			playerProfile, equippedBackpack
		)
	end

	return {
		blocksSold = blockCount,
		cashEarned = math.floor(baseCash * backpackMultiplier),
		xpEarned   = baseXP,
		baseCash   = baseCash,
		multiplier = backpackMultiplier,
	}
end

--- Get the conversion config table (read-only reference for UI/debug).
--- @return table { CASH_PER_BLOCK, XP_PER_BLOCK }
function SellManager.GetConfig(): {}
	return CONFIG
end

return SellManager
