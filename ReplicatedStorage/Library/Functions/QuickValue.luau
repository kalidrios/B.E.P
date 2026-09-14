--[[
	QuickValue.luau — Utility function to create typed ValueObject instances quickly.
]]--

local TYPE_TO_VALUE_CLASS = {
	["boolean"] = "BoolValue",
	["number"] = "NumberValue",
	["string"] = "StringValue",
	["BrickColor"] = "BrickColorValue",
	["CFrame"] = "CFrameValue",
	["Color3"] = "Color3Value",
	["Ray"] = "RayValue",
	["Vector3"] = "Vector3Value",
	["Instance"] = "InstanceValue",
}

return function(rawValue, parentInstance)
	local valueClassName = TYPE_TO_VALUE_CLASS[typeof(rawValue)]
	if valueClassName then
		local valueObject = Instance.new(valueClassName)
		valueObject.Value = rawValue
		if parentInstance then
			valueObject.Parent = parentInstance
		end
		return valueObject
	end
	error("Value type not supported: " .. typeof(rawValue))
end
