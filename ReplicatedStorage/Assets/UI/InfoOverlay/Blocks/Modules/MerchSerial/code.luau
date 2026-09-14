--[[
	MerchSerial/code.luau — Destruction Simulator
	Renders the serial number of custom skins.
]]--

local Library = require(game.ReplicatedStorage:WaitForChild("Library"))

return function(blockFrame, _, serialNumber)
	if blockFrame:FindFirstChild("title") then
		blockFrame.title.Text = "#" .. Library.Functions.FormatNumber(serialNumber or 0)
	end
end