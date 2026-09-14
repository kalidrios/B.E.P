--[[
	© DestructionSimulator [2025]
	Server/TradeUpContract — Pure data-driven Trade-Up logic.
]]--

local TradeUpContract = {}

local HttpService = game:GetService("HttpService")

--- Processes a Trade-Up Contract.
--- @param inputSkins table Array of skinData objects e.g. {{id="Skin_1", fl=0.2}, {id="Skin_2", fl=0.3}}
--- @param outputSkinConfig table Output config pool { id="Skin_NextTier", floatMin=0.0, floatMax=1.0 }
function TradeUpContract.ProcessContract(inputSkins, outputSkinConfig)
	if not inputSkins or #inputSkins == 0 then
		return false, "No skins provided."
	end

	-- 1. Average the Floats of the inputs
	local totalFloat = 0
	for _, skinData in ipairs(inputSkins) do
		totalFloat += skinData.fl
	end
	local avgFloat = totalFloat / #inputSkins

	-- 2. Calculate the Output Skin Float
	-- Formula: f_out = avg_f_in * (max_out - min_out) + min_out
	local outFloatMin = outputSkinConfig.floatMin or 0.0
	local outFloatMax = outputSkinConfig.floatMax or 1.0

	local finalFloat = avgFloat * (outFloatMax - outFloatMin) + outFloatMin

	-- 3. Generate the Output Unique Skin Data
	local uniqueSkinUID = HttpService:GenerateGUID(false)
	local newSkinData = {
		id = outputSkinConfig.id,
		fl = finalFloat,
		uid = uniqueSkinUID
	}

	return true, newSkinData
end

return TradeUpContract
