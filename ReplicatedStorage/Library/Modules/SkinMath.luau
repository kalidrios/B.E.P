--!strict
--[[
	© DestructionSimulator [2025]
	SkinMath — Shared utility module for skin float calculations, conditions, and multipliers.
	Used by both client (UI display) and server (orb/sell multiplier application).
]]--

export type ConditionRange = {
	max: number,
	name: string,
	short: string,
}

local SkinMath = {}

----------------------------------------------------------------------
-- Float Condition Table (CS-style wear ranges)
----------------------------------------------------------------------
local CONDITIONS: { ConditionRange } = {
	{ max = 0.07, name = "Factory New",   short = "FN" },
	{ max = 0.15, name = "Minimal Wear",  short = "MW" },
	{ max = 0.38, name = "Field-Tested",  short = "FT" },
	{ max = 0.45, name = "Well-Worn",     short = "WW" },
	{ max = 1.00, name = "Battle-Scarred", short = "BS" },
}

--- Roll a random float between 0.0000 and 1.0000
function SkinMath.RollFloat(): number
	return math.floor(math.random() * 10000) / 10000
end

--- Calculate the final multiplier from a float and MultMin/MultMax range.
-- Lower float (closer to 0.00) = higher multiplier (better condition = more power).
function SkinMath.CalculateMultiplier(float: number?, multMin: number?, multMax: number?): number
	if not float or not multMin or not multMax then return 1 end
	return multMin + ((1 - float) * (multMax - multMin))
end

--- Get the full condition name for a float value.
function SkinMath.GetCondition(float: number?): string
	if not float then return "Unknown" end
	for _, cond in ipairs(CONDITIONS) do
		if float < cond.max then
			return cond.name
		end
	end
	return CONDITIONS[#CONDITIONS].name
end

--- Get the abbreviated condition name for a float value.
function SkinMath.GetConditionShort(float: number?): string
	if not float then return "?" end
	for _, cond in ipairs(CONDITIONS) do
		if float < cond.max then
			return cond.short
		end
	end
	return CONDITIONS[#CONDITIONS].short
end

--- Format a float for display (4 decimal places).
function SkinMath.FormatFloat(float: number?): string
	return string.format("%.4f", float or 0)
end

--- Format a multiplier for display (2 decimal places with 'x' suffix).
function SkinMath.FormatMultiplier(multiplier: number?): string
	return string.format("%.2fx", multiplier or 1)
end

return SkinMath
