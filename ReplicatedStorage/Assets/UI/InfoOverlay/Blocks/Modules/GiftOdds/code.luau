--[[
	GiftOdds/code.luau — Destruction Simulator
	Displays unboxing odds for weapon boxes and cases.
]]--

local Library = require(game.ReplicatedStorage:WaitForChild("Library"))

return function(blockFrame, _, _, caseOddsList)
	if not caseOddsList or typeof(caseOddsList) ~= "table" then
		return
	end
	
	local totalWeight = 0
	for _, itemEntry in ipairs(caseOddsList) do
		totalWeight = totalWeight + (itemEntry[2] or 0)
	end
	if totalWeight <= 0 then
		return
	end
	
	for _, itemEntry in ipairs(caseOddsList) do
		local weight = itemEntry[2] or 0
		local chance = (weight / totalWeight) * 100
		
		local assetsUI = Library.Assets and Library.Assets.UI and Library.Assets.UI
		local boxInfo = assetsUI and (assetsUI:FindFirstChild("BoxInfo") or assetsUI:FindFirstChild("CaseInfo"))
		local skinTemplate = boxInfo and (boxInfo:FindFirstChild("Skin") or boxInfo:FindFirstChild("Item"))
		
		if skinTemplate then
			local itemCard = skinTemplate:Clone()
			if itemCard:FindFirstChild("Thumbnail") and itemCard.Thumbnail:FindFirstChild("Chance") then
				itemCard.Thumbnail.Chance.Text = string.format("%.2f%%", chance)
			end
			itemCard.Parent = blockFrame
		end
	end
end