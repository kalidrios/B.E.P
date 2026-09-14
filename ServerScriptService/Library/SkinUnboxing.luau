--[[
	© DestructionSimulator [2025]
	Server/SkinUnboxing — Pure data-driven Case unboxing and Skin generation.
]]--

local SkinUnboxing = {}

local HttpService = game:GetService("HttpService")

-- Pure Data Weights for Float Generation (0.0 to 1.0 raw scale)
-- Pristine: 3%, Minimal: 8%, Standard: 45%, Well-Worn: 14%, Worn: 30%
local FLOAT_WEAR_TIERS = {
	{ name = "Pristine", min = 0.00, max = 0.07, weight = 3 },
	{ name = "Minimal Wear", min = 0.07, max = 0.15, weight = 8 },
	{ name = "Standard", min = 0.15, max = 0.38, weight = 45 },
	{ name = "Well-Worn", min = 0.38, max = 0.45, weight = 14 },
	{ name = "Worn", min = 0.45, max = 1.00, weight = 30 }
}

local TOTAL_WEAR_WEIGHT = 0
for _, tier in ipairs(FLOAT_WEAR_TIERS) do
	TOTAL_WEAR_WEIGHT += tier.weight
end

-- Generate a raw float using the strict weighted distribution
local function GenerateStrictWeightedFloat()
	local rng = math.random(1, TOTAL_WEAR_WEIGHT)
	local currentWeight = 0
	local selectedTier = FLOAT_WEAR_TIERS[#FLOAT_WEAR_TIERS]

	for _, tier in ipairs(FLOAT_WEAR_TIERS) do
		currentWeight += tier.weight
		if rng <= currentWeight then
			selectedTier = tier
			break
		end
	end

	-- Flat random inside the selected tier's range
	local rawFloat = selectedTier.min + (math.random() * (selectedTier.max - selectedTier.min))
	return rawFloat
end

-- Simulates Functions.Lottery for drop tables: {{SkinID, Weight}, ...}
local function SelectSkinFromDropTable(dropTable)
	local totalWeight = 0
	for _, drop in ipairs(dropTable) do
		totalWeight += drop[2] -- weight is at index 2
	end

	local rng = math.random() * totalWeight
	local currentWeight = 0

	for _, drop in ipairs(dropTable) do
		currentWeight += drop[2]
		if rng <= currentWeight then
			return drop[1] -- return SkinID
		end
	end

	return dropTable[#dropTable][1]
end

--- Unbox a Case: consumes Contracts, returns the newly generated Unique Skin data schema
function SkinUnboxing.UnboxCase(player, caseData)
	-- 1. Roll the Skin from the Case's drop table
	local selectedSkinID = SelectSkinFromDropTable(caseData.drops)

	-- 2. Fetch the specific Skin's float bounds. 
	local floatMin = caseData.skinDirectory and caseData.skinDirectory[selectedSkinID] and caseData.skinDirectory[selectedSkinID].FloatMin or 0.0
	local floatMax = caseData.skinDirectory and caseData.skinDirectory[selectedSkinID] and caseData.skinDirectory[selectedSkinID].FloatMax or 1.0

	-- 3. Calculate Strict Weighted Float
	local rawFloat = GenerateStrictWeightedFloat()
	local finalFloat = rawFloat * (floatMax - floatMin) + floatMin

	-- 4. Create the Unique Skin Data object
	local uniqueSkinUID = HttpService:GenerateGUID(false)
	local skinData = {
		id = selectedSkinID,
		fl = finalFloat,
		uid = uniqueSkinUID -- Local UID for data mapping
	}

	return skinData
end

return SkinUnboxing
