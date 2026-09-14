--[[
	© DestructionSimulator [2025]
	Library/Shared/Functions — Shared utility functions accessible via Shared.FunctionName
]]--

local Functions = {}

local formatNumberModule = require(script.Parent.Parent:WaitForChild("Functions"):WaitForChild("FormatNumber"))

function Functions.FormatNumber(selfOrNumber, maybeNumber)
	local num = (typeof(selfOrNumber) == "table" and maybeNumber) or selfOrNumber
	return formatNumberModule(num)
end

function Functions.FormatTime(_, seconds)
	local days = math.floor(seconds / 86400)
	local hours = math.floor((seconds % 86400) / 3600)
	local mins = math.floor((seconds % 3600) / 60)
	local secs = math.floor(seconds % 60)
	
	if days > 0 then
		return string.format("%dd %dh %dm", days, hours, mins)
	elseif hours > 0 then
		return string.format("%dh %dm %ds", hours, mins, secs)
	elseif mins > 0 then
		return string.format("%dm %ds", mins, secs)
	else
		return string.format("%ds", secs)
	end
end

function Functions.GetPowerDir()
	return nil
end

return Functions
