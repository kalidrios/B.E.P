--[[
	© DestructionSimulator [2025]
	Library/Asserts — Runtime assertion utilities
]]--

local Asserts = {}

function Asserts.IsType(value, expectedType, name)
	assert(typeof(value) == expectedType, string.format("Expected %s to be %s, got %s", name or "value", expectedType, typeof(value)))
end

function Asserts.IsNotNil(value, name)
	assert(value ~= nil, string.format("Expected %s to not be nil", name or "value"))
end

function Asserts.IsInstance(value, className, name)
	Asserts.IsType(value, "Instance", name)
	if className then
		assert(value:IsA(className), string.format("Expected %s to be a %s, got %s", name or "instance", className, value.ClassName))
	end
end

function Asserts.IsPlayer(value, name)
	Asserts.IsInstance(value, "Player", name)
end

function Asserts.IsPositive(value, name)
	Asserts.IsType(value, "number", name)
	assert(value > 0, string.format("Expected %s to be positive, got %s", name or "value", tostring(value)))
end

function Asserts.IsInRange(value, min, max, name)
	Asserts.IsType(value, "number", name)
	assert(value >= min and value <= max, string.format("Expected %s to be in range [%s, %s], got %s", name or "value", tostring(min), tostring(max), tostring(value)))
end

return Asserts
