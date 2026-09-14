--[[
	Wait.luau — Utility function for waiting a fixed or randomized duration.
]]--

local randomGenerator = Random.new()

return function(minDuration, maxDuration)
	local duration = minDuration
	if maxDuration then
		duration = randomGenerator:NextNumber(minDuration, maxDuration)
	end
	task.wait(duration)
end
