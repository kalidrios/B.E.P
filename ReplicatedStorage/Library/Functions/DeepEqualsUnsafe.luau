--[[
	DeepEqualsUnsafe.luau — Recursively compares two tables or primitive values for equality.
]]--

local function deepEquals(valueA, valueB)
	if valueA == valueB then
		return true
	elseif type(valueA) ~= "table" or type(valueB) ~= "table" then
		-- Handle NaN == NaN
		if valueA ~= valueA and valueB ~= valueB then
			return true
		else
			return false
		end
	elseif #valueA ~= #valueB then
		return false
	else
		for key, value in next, valueA do
			local partnerValue = valueB[key]
			if partnerValue == nil or not deepEquals(value, partnerValue) then
				return false
			end
		end
		for key, value in next, valueB do
			local partnerValue = valueA[key]
			if partnerValue == nil or not deepEquals(value, partnerValue) then
				return false
			end
		end
		return true
	end
end

return deepEquals
