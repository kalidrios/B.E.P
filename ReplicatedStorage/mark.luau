--[[
	mark.luau — Performance profiler for tracking slow require executions.
]]--

return function(moduleIdentifier)
	local currentTime = os.clock()
	local callerEnvironment = getfenv(2)
	local previousMarkTime = callerEnvironment.__mark
	callerEnvironment.__mark = currentTime

	if previousMarkTime then
		local elapsedMilliseconds = math.ceil((currentTime - previousMarkTime) * 1000)
		if elapsedMilliseconds >= 25 then
			warn("SlowRequire:", moduleIdentifier, string.format("%dms", elapsedMilliseconds))
		end
	end
end