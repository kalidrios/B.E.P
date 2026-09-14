--[[
	Block/code.luau — Generic info block for InfoOverlay
]]--

local Library = require(game.ReplicatedStorage:WaitForChild("Library"))

return function(blockFrame, _, titleText, backgroundColor)
	if not titleText then
		return
	end
	if not backgroundColor then
		backgroundColor = Color3.fromRGB(111, 111, 111)
	end
	
	if blockFrame:FindFirstChild("title") then
		blockFrame.title.Text = tostring(titleText)
		local backFrame = blockFrame.title:FindFirstChild("back")
		if backFrame then
			backFrame.BackgroundColor3 = backgroundColor
		end
	end
end