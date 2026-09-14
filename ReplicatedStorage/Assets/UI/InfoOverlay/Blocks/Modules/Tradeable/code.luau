--[[
	Tradeable/code.luau — Destruction Simulator
	Displays tradeable status for skins.
]]--

return function(blockFrame, _, isTradeable)
	if not blockFrame:FindFirstChild("title") then
		return
	end
	if isTradeable == false then
		blockFrame.title.Text = "Untradeable"
		blockFrame.Visible = true
	else
		blockFrame.Visible = false
	end
end