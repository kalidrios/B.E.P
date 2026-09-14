--[[
	Rarity/code.luau — Destruction Simulator
	Displays skin rarity badge and gradient tint.
]]--

return function(blockFrame, _, rarityName)
	if not blockFrame:FindFirstChild("title") then
		return
	end
	blockFrame.title.Text = rarityName or "Basic"
	local backFrame = blockFrame.title:FindFirstChild("back")
	if backFrame then
		local assetsFolder = game.ReplicatedStorage:FindFirstChild("Assets")
		local uiFolder = assetsFolder and assetsFolder:FindFirstChild("UI")
		local gradientFolder = uiFolder and uiFolder:FindFirstChild("Gradient")
		local raritysFolder = (gradientFolder and gradientFolder:FindFirstChild("Raritys")) or (uiFolder and uiFolder:FindFirstChild("Raritys"))
		local gradientTemplate = raritysFolder and raritysFolder:FindFirstChild("InfoOverlay") and raritysFolder.InfoOverlay:FindFirstChild(rarityName)
		if gradientTemplate and gradientTemplate:IsA("UIGradient") then
			for _, child in ipairs(backFrame:GetChildren()) do
				if child:IsA("UIGradient") then
					child:Destroy()
				end
			end
			gradientTemplate:Clone().Parent = backFrame
		end
	end
end