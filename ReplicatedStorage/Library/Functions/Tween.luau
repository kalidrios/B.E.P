--[[
	© DestructionSimulator [2025]
	Tween helper wrapping TweenService:Create.
]]--

local TweenService = game:GetService("TweenService")

return function(instance, properties, params)
	local duration = params[1] or 1
	local easingStyle = Enum.EasingStyle[params[2] or "Sine"]
	local easingDirection = Enum.EasingDirection[params[3] or "InOut"]
	local tweenInfo = TweenInfo.new(duration, easingStyle, easingDirection)
	local tween = TweenService:Create(instance, tweenInfo, properties)
	tween:Play()
	return tween
end
