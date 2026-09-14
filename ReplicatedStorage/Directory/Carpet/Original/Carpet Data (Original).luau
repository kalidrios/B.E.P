return {
	name = "Flying Carpet", 
	neededDesc = "1 Rbirth", 
	thumbnail = "rbxassetid://8312898681", 
	speed = 1, 
	sounds = {
		equip = { 103424339087380 }, 
		idle = { 122487986250903 }, 
		jump = { 72499189103258 }
	}, 
	callback = function(player)
		local rebirths = player:GetAttribute("Rebirth") or 0
		return rebirths >= 1
	end, 
	board = script.Parent:FindFirstChildWhichIsA("BasePart") or script.Parent:FindFirstChildWhichIsA("Model")
}
