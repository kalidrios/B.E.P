--[[
	Title/code.luau — Destruction Simulator
	Displays skin title and applies rarity UI effects.
]]--

return function(blockFrame, _, skinTitle, rarityName)
	if not blockFrame:FindFirstChild("title") then
		return
	end
	blockFrame.title.Text = tostring(skinTitle or "")
	if rarityName == "Mythical" or rarityName == "Secret" or rarityName == "Event" or rarityName == "Exclusive" then
		blockFrame.title.TextColor3 = Color3.new(1, 1, 1)
		local assetsFolder = game.ReplicatedStorage:FindFirstChild("Assets")
		local uiFolder = assetsFolder and assetsFolder:FindFirstChild("UI")
		local gradientFolder = uiFolder and uiFolder:FindFirstChild("Gradient")
		local raritysFolder = (gradientFolder and gradientFolder:FindFirstChild("Raritys")) or (uiFolder and uiFolder:FindFirstChild("Raritys"))
		local rarityEffect = raritysFolder and raritysFolder:FindFirstChild(rarityName)
		if rarityEffect then
			rarityEffect:Clone().Parent = blockFrame.title
		end
	end
end