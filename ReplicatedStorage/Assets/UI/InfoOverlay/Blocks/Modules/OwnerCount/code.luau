--[[
	OwnerCount/code.luau — Destruction Simulator
	Displays the total number of previous owners for this skin.
]]--

return function(blockFrame, _, totalOwners)
	if not blockFrame:FindFirstChild("title") then
		return
	end
	blockFrame.title.Text = string.format(" Number of owners: %s", tostring(totalOwners or 1))
	task.defer(function()
		local titleLabel = blockFrame:FindFirstChild("title")
		if titleLabel then
			local currentSize = titleLabel.Size
			titleLabel.Size = UDim2.new(currentSize.X.Scale, currentSize.X.Offset + 10, currentSize.Y.Scale, currentSize.Y.Offset)
		end
	end)
end