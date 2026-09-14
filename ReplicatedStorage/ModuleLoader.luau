--[[
	ModuleLoader.luau — Recursively discovers, validates, and loads ModuleScripts into target directories.
]]--

local function keyToString(key)
	local stringKey = tostring(key)
	if type(key) == "string" then
		return string.format('"%s"', stringKey)
	else
		return stringKey
	end
end

return function(targetFolder, destinationTable, options)
	local loadOptions = options or {}
	local rootScriptName = loadOptions.rootName or "script"
	local typeAnnotation = loadOptions.typeCast and ("::" .. loadOptions.typeCast) or ""
	local warnFunction = loadOptions.warn or warn

	local unaddedEntries = {}
	local loadedKeys = {}

	local function traverseAndLoad(childInstance, parentHierarchyPath)
		if childInstance:GetAttribute("NOLOAD") then
			return
		elseif childInstance:IsA("Folder") then
			for _, subChild in ipairs(childInstance:GetChildren()) do
				local nextHierarchyPath = string.format('%s:WaitForChild("%s")', parentHierarchyPath, childInstance.Name)
				traverseAndLoad(subChild, nextHierarchyPath)
			end
			return
		elseif childInstance:IsA("ModuleScript") then
			local entryKey = childInstance.Name:gsub("^(.-)%s*|%s*", "")
			if loadOptions.keyParser then
				local parsedKey = loadOptions.keyParser(entryKey)
				if not parsedKey then
					warnFunction(string.format("Invalid key: %s", entryKey))
					return
				else
					entryKey = parsedKey
				end
			end

			if not loadedKeys[entryKey] then
				loadedKeys[entryKey] = true
				local startTime = os.clock()
				local loadedModule = require(childInstance)
				local loadDurationMs = math.ceil((os.clock() - startTime) * 1000)

				if loadDurationMs >= 25 then
					warnFunction("[SlowModule]", childInstance.Name, string.format("%dms", loadDurationMs))
				end

				if loadOptions.shouldInject and type(loadedModule) == "table" then
					if loadedModule._id == nil then
						loadedModule._id = entryKey
					end
					if loadedModule._script == nil then
						loadedModule._script = childInstance
					end
				end

				if not destinationTable[entryKey] then
					if not loadOptions.noPrint then
						local entryCode = string.format(
							'[%s] = require(%s:WaitForChild("%s"))%s',
							keyToString(entryKey),
							parentHierarchyPath,
							childInstance.Name,
							typeAnnotation
						)
						table.insert(unaddedEntries, entryCode)
					end
					destinationTable[entryKey] = loadedModule
					return
				elseif destinationTable[entryKey] ~= loadedModule then
					warnFunction(string.format("Mismatched entry: %s", entryKey))
					return
				end
			else
				warnFunction(string.format("Duplicate entry: %s", entryKey))
			end
		end
	end

	for _, directChild in ipairs(targetFolder:GetChildren()) do
		traverseAndLoad(directChild, rootScriptName)
	end

	if #unaddedEntries > 0 and not loadOptions.noPrint then
		table.sort(unaddedEntries)
		warnFunction(string.format("Unadded entries: \n\n%s,\n", table.concat(unaddedEntries, ",\n")))
	end

	for existingKey, _ in pairs(destinationTable) do
		if not loadedKeys[existingKey] then
			warnFunction(string.format("Unknown entry: %s", tostring(existingKey)))
		end
	end
end