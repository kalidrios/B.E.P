--[[
	DeepCopyUnsafe.luau — Recursively clones a table and all its nested tables/keys.
]]--

local function deepCopy(targetObject)
	if type(targetObject) == "table" then
		local clonedTable = {}
		local arrayLength = #targetObject
		if arrayLength > 0 then
			for index = 1, arrayLength do
				table.insert(clonedTable, deepCopy(targetObject[index]))
			end
			return clonedTable
		else
			for key, value in next, targetObject do
				clonedTable[deepCopy(key)] = deepCopy(value)
			end
			return clonedTable
		end
	else
		return targetObject
	end
end

return deepCopy
