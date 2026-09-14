--[[
	© DestructionSimulator [2025]
]]--

local v_u_1 = game:GetService("HttpService")
return function()
	return v_u_1:GenerateGUID(false):gsub("%-", ""):lower()
end
