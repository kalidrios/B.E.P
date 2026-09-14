--[[
	© DestructionSimulator [2025]
	Library/Util — General-purpose utilities
]]--

local Util = {}

function Util.Tween(instance, properties, tweenInfo)
	local TweenService = game:GetService("TweenService")
	
	if typeof(tweenInfo) == "table" then
		local duration = tweenInfo[1] or 1
		local style = tweenInfo[2] or Enum.EasingStyle.Sine
		local direction = tweenInfo[3] or Enum.EasingDirection.Out
		
		if type(style) == "string" then
			if string.lower(style) == "expo" then
				style = Enum.EasingStyle.Exponential
			else
				style = Enum.EasingStyle[style]
			end
		end
		
		if type(direction) == "string" then
			direction = Enum.EasingDirection[direction]
		end
		
		tweenInfo = TweenInfo.new(duration, style, direction)
	end
	
	local tween = TweenService:Create(instance, tweenInfo, properties)
	tween:Play()
	return tween
end

function Util.WaitForChildren(parent, childNames, timeout)
	timeout = timeout or 99999999
	local results = {}
	for _, name in ipairs(childNames) do
		results[name] = parent:WaitForChild(name, timeout)
	end
	return results
end

function Util.SafeDestroy(instance)
	if instance and typeof(instance) == "Instance" then
		instance:Destroy()
	end
end

return Util
