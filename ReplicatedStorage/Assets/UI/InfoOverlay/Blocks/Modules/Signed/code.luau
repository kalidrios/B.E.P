--[[
	Signed/code.luau — Destruction Simulator
	Rainbow cycling color effect for signed skins.
]]--

return function(blockFrame, _)
	coroutine.wrap(function()
		while not blockFrame.Parent do
			task.wait()
		end
		local startTick = os.clock()
		while blockFrame and blockFrame.Parent do
			local hue = (os.clock() - startTick) * 0.1 % 1
			local rainbowColor = Color3.fromHSV(hue, 0.8, 1)
			if blockFrame:FindFirstChild("ImageLabel") then
				blockFrame.ImageLabel.ImageColor3 = rainbowColor
			end
			if blockFrame:FindFirstChild("title") then
				blockFrame.title.TextColor3 = rainbowColor
			end
			task.wait()
		end
	end)()
end