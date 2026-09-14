--[[
	OpenedBy/code.luau — Destruction Simulator
	Renders the player who unboxed/opened the weapon skin.
]]--

local Library = require(game.ReplicatedStorage:WaitForChild("Library"))

return function(blockFrame, _, openerUserId, timestamp)
	if not blockFrame:FindFirstChild("title") then
		return
	end
	blockFrame.title.Text = ""
	task.spawn(function()
		local username = Library.Functions.UserIdToUsername(openerUserId)
		local ageText = Library.Functions.FormatTimeShort(os.time() - (timestamp or os.time()))
		local formattedMessage = string.format("Unboxed by %s, age: %s", tostring(username), tostring(ageText))
		
		if blockFrame:FindFirstChild("title") then
			blockFrame.title.Text = formattedMessage
			task.defer(function()
				local titleLabel = blockFrame:FindFirstChild("title")
				if titleLabel then
					local currentSize = titleLabel.Size
					titleLabel.Size = UDim2.new(currentSize.X.Scale, currentSize.X.Offset + 10, currentSize.Y.Scale, currentSize.Y.Offset)
				end
			end)
		end
	end)
end