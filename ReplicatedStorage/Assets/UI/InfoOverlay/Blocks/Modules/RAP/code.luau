--[[
	RAP/code.luau — Destruction Simulator
	Displays Recent Average Price range for trading.
]]--

return function(blockFrame, _, rapValue)
	local numericValue = tonumber(rapValue)
	if numericValue and numericValue > 0 then
		local minRAP = math.round(numericValue * 0.9)
		local maxRAP = math.round(numericValue * 1.1)
		if blockFrame:FindFirstChild("title") then
			blockFrame.title.Text = string.format(" %s - %s", tostring(minRAP), tostring(maxRAP))
		end
		blockFrame.Visible = true
		return
	end
	blockFrame.Visible = false
end