--[[
	Power/code.luau — Calculates and displays multiplier bonus for weapon skin float values.
]]--

local SkinMath = require(game.ReplicatedStorage:WaitForChild("Library"):WaitForChild("Modules"):WaitForChild("SkinMath"))

local Types = {
	Normal = Color3.fromRGB(252, 50, 242),
	Unique = Color3.fromRGB(252, 11, 15)
}

local function Color3ToString(color)
	return string.format("%d, %d, %d", math.round(color.R * 255), math.round(color.G * 255), math.round(color.B * 255))
end

return function(blockFrame, _, floatValue, multMin, multMax)
	if not floatValue then
		blockFrame.Visible = false
		return
	end
	
	blockFrame.Visible = true
	local finalMultiplier = SkinMath.CalculateMultiplier(floatValue, multMin, multMax)
	local percentIncrease = math.round((finalMultiplier - 1) * 100)
	local floatFormatted = SkinMath.FormatFloat(floatValue)
	local colorString = Color3ToString(Types.Unique)
	
	if blockFrame:FindFirstChild("title") then
		blockFrame.title.Text = string.format('<font color="rgb(%s)">%s</font> - <font size="18">This skin provides a %d%% multiplier over the default.</font>', colorString, floatFormatted, percentIncrease)
		blockFrame.title.RichText = true
	end
end