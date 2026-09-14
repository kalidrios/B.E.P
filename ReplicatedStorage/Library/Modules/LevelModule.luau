--!strict
--[[
	© DestructionSimulator [2025]
	LevelModule — Shared utility module for level formulas, XP curves, and contract rewards.
]]--

local LevelModule = {}

-- Contracts rewarded upon reaching a given level: level + math.random(5, 10)
function LevelModule.GetContractsGained(level: number): number
	local lvl = math.max(1, math.floor(tonumber(level) or 1))
	return lvl + math.random(5, 10)
end

-- Cumulative total XP required to reach `targetLevel`
-- Step XP for level l is (100 * l + 10).
-- Total XP for targetLevel is sum_{l=1}^{targetLevel-1} (100*l + 10) = 50*(targetLevel-1)*targetLevel + 10*(targetLevel-1)
function LevelModule.GetRequiredXPForLevel(targetLevel: number): number
	local lvl = tonumber(targetLevel)
	if not lvl or lvl <= 1 then
		return 0
	end
	local n = math.floor(lvl) - 1
	return 50 * n * (n + 1) + 10 * n
end

-- Returns level data from player's total accumulated Experience in O(1)
function LevelModule.GetLevelDataFromXP(xp: number): (number, number, number, number)
	local rawXP = math.max(0, tonumber(xp) or 0)
	
	-- Solve 50*n^2 + 60*n - rawXP <= 0
	-- Quadratic formula: n = (-60 + sqrt(3600 + 200 * rawXP)) / 100
	local discriminant = 3600 + 200 * rawXP
	local n = math.floor((-60 + math.sqrt(discriminant)) / 100)
	if n < 0 then
		n = 0
	end
	
	local level = n + 1
	local currentLevelBaseXP = 50 * n * (n + 1) + 10 * n
	local nextN = n + 1
	local nextLevelTotalXP = 50 * nextN * (nextN + 1) + 10 * nextN
	
	local currentXP = rawXP - currentLevelBaseXP
	local targetXP = math.max(1, nextLevelTotalXP - currentLevelBaseXP)
	local progress = math.clamp(currentXP / targetXP, 0, 1)
	
	return level, currentXP, targetXP, progress
end

return LevelModule
