--[[
	Rare/code.luau — Destruction Simulator
	Displays rare/special edition tag text.
]]--

return function(blockFrame, _, rareTagText)
	if blockFrame:FindFirstChild("title") then
		blockFrame.title.Text = tostring(rareTagText or "")
	end
end