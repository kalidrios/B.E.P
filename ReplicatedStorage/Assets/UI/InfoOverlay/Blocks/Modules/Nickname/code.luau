--[[
	Nickname/code.luau — Destruction Simulator
	Renders custom skin nickname.
]]--

return function(blockFrame, _, nicknameText)
	if not blockFrame:FindFirstChild("title") then
		return
	end
	blockFrame.title.Text = tostring(nicknameText or "")
	task.defer(function()
		local titleLabel = blockFrame:FindFirstChild("title")
		if titleLabel then
			local currentSize = titleLabel.Size
			titleLabel.Size = UDim2.new(currentSize.X.Scale, currentSize.X.Offset + 10, currentSize.Y.Scale, currentSize.Y.Offset)
		end
	end)
end