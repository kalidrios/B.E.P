--[[
	Replacement/code.luau — Destruction Simulator
	Replacements skin/weapon UI details and pulsing glow effect.
]]--

local Types = {
	Normal = Color3.fromRGB(252, 50, 242),
	Unique = Color3.fromRGB(252, 11, 15)
}

local function Color3ToString(color)
	return string.format("%d, %d, %d", math.round(color.R * 255), math.round(color.G * 255), math.round(color.B * 255))
end

return function(blockFrame, _, skinId, perkData)
	local perkTitle = "Unique Perk"
	local perkDescription = "This skin provides a special multiplier."
	local uniqueColor = Types.Unique

	if blockFrame:FindFirstChild("title") then
		blockFrame.title.Text = string.format('<font color="rgb(%s)">%s</font> - <font size="18">%s</font>', Color3ToString(uniqueColor), perkTitle, perkDescription)
		blockFrame.title.RichText = true
	end

	coroutine.wrap(function()
		while not blockFrame.Parent do
			task.wait()
		end

		local startTime = os.clock()
		while blockFrame and blockFrame.Parent do
			local sineWave = math.sin((os.clock() - startTime) * 4) / 2 + 0.5
			local lerpedColor = uniqueColor:Lerp(Color3.fromRGB(252, 167, 20), sineWave)
			if blockFrame:FindFirstChild("title") then
				blockFrame.title.Text = string.format('<font color="rgb(%s)">%s</font> - <font size="18">%s</font>', Color3ToString(lerpedColor), perkTitle, perkDescription)
			end
			task.wait()
		end
	end)()
end