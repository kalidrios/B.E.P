--!strict
--[[
	© DestructionSimulator [2025]
	SanitizeInput — Server-side input validation and sanitization utility.
]]--

local SanitizeInput = {}

function SanitizeInput.isValidNumber(n: any): boolean
	if type(n) ~= "number" then return false end
	if n ~= n then return false end -- NaN check
	if n == math.huge or n == -math.huge then return false end -- Infinity check
	return true
end

function SanitizeInput.isValidVector3(v: any): boolean
	if typeof(v) ~= "Vector3" then return false end
	if not SanitizeInput.isValidNumber(v.X) or not SanitizeInput.isValidNumber(v.Y) or not SanitizeInput.isValidNumber(v.Z) then
		return false
	end
	return true
end

function SanitizeInput.isValidString(s: any, maxLen: number?): boolean
	if type(s) ~= "string" then return false end
	if maxLen and string.len(s) > maxLen then return false end
	if string.find(s, "%z") then return false end -- Zero-byte check
	return true
end

return SanitizeInput
