--[[
	© DestructionSimulator [2025]
	Library/Functions — Shared utility functions registry
	
	Pattern: each function lives in its own file under Functions/.
	This init.luau loads them all into a single table.
]]--

local Functions = {
	-- Critical functions used by Saving/Datastore
	DeepCopyUnsafe = require(script:WaitForChild("DeepCopyUnsafe")),
	DeepEqualsUnsafe = require(script:WaitForChild("DeepEqualsUnsafe")),
	GenerateUID = require(script:WaitForChild("GenerateUID")),
	QuickValue = require(script:WaitForChild("QuickValue")),
	Wait = require(script:WaitForChild("Wait")),
}


-- Auto-discover additional function modules
require(game.ReplicatedStorage:WaitForChild("ModuleLoader"))(script, Functions, {
	warn = function(...)
		warn(...)
	end,
	noPrint = true,
})

-- Load modular FormatNumber utility (global abbreviator: 1000 -> 1k, 1251 -> 1,25k, 1000000 -> 1M)
local formatNumberModule = require(script:WaitForChild("FormatNumber"))
Functions.FormatNumber = formatNumberModule
Functions.NumberShorten = formatNumberModule
_G.FormatNumber = formatNumberModule


function Functions.DeepCopy(original)
	if type(original) ~= "table" then
		return original
	end
	local copy = {}
	for key, value in pairs(original) do
		copy[Functions.DeepCopy(key)] = Functions.DeepCopy(value)
	end
	return setmetatable(copy, getmetatable(original))
end

function Functions.Lerp(a, b, t)
	return a + (b - a) * t
end

function Functions.RandomFromTable(tbl)
	return tbl[math.random(1, #tbl)]
end

function Functions.ShallowCopy(tbl)
	local copy = {}
	for k, v in pairs(tbl) do
		copy[k] = v
	end
	return copy
end

function Functions.RegexEscape(text)
	return tostring(text):gsub("([^%w])", "%%%1")
end

function Functions.SearchArray(array, value)
	for _, item in ipairs(array or {}) do
		if item == value then
			return true
		end
	end
	return false
end

function Functions.SearchDictionary(dictionary, value)
	for _, item in pairs(dictionary or {}) do
		if item == value then
			return true
		end
	end
	return false
end

function Functions.StringByte(text)
	local total = 0
	for index = 1, #text do
		total += string.byte(text, index)
	end
	return total
end

function Functions.ResolutionScale()
	local camera = workspace.CurrentCamera
	if not camera then
		return 1
	end

	local viewport = camera.ViewportSize
	return math.clamp(math.min(viewport.X / 1920, viewport.Y / 1080), 0.35, 1.5)
end

function Functions.ParseNumberSmart(text)
	local cleaned = tostring(text):gsub(",", ""):gsub("%s+", "")
	return tonumber(cleaned)
end

function Functions.Commas(value)
	local number = math.floor(tonumber(value) or 0)
	local sign = number < 0 and "-" or ""
	local text = tostring(math.abs(number))
	local left, num, right = text:match("^([^%d]*%d)(%d*)(.-)$")
	return sign .. (left or "") .. (num or ""):reverse():gsub("(%d%d%d)", "%1,"):reverse() .. (right or "")
end

function Functions.NumberShorten(value)
	return Functions.FormatNumber(tonumber(value) or 0)
end

function Functions.TimeString(seconds)
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	local days = math.floor(seconds / 86400)
	local hours = math.floor((seconds % 86400) / 3600)
	local minutes = math.floor((seconds % 3600) / 60)

	if days > 0 then
		return days .. "d"
	elseif hours > 0 then
		return hours .. "h"
	elseif minutes > 0 then
		return minutes .. "m"
	end
	return seconds .. "s"
end

function Functions.UserIdToUsername(userId)
	local success, username = pcall(function()
		return game:GetService("Players"):GetNameFromUserIdAsync(userId)
	end)
	return success and username or tostring(userId)
end

return Functions
