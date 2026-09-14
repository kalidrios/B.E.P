--[[
	LazyModuleLoader.luau — Recursively indexes ModuleScripts and loads them lazily on first access.
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
	local pendingModuleScripts = {}
	local rootScriptName = loadOptions.rootName or "script"
	local typeAnnotation = loadOptions.typeCast and ("::" .. loadOptions.typeCast) or ""
	local warnFunction = loadOptions.warn or warn

	local unaddedEntries = {}
	local loadedKeys = {}

	local function traverseAndIndex(childInstance, parentHierarchyPath)
		if childInstance:GetAttribute("NOLOAD") then
			return
		elseif childInstance:IsA("Folder") then
			for _, subChild in ipairs(childInstance:GetChildren()) do
				local nextHierarchyPath = string.format('%s:WaitForChild("%s")', parentHierarchyPath, childInstance.Name)
				traverseAndIndex(subChild, nextHierarchyPath)
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
				local preloadedValue = destinationTable[entryKey]
				if not preloadedValue then
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
					pendingModuleScripts[entryKey] = childInstance
					return
				else
					if loadOptions.shouldInject and type(preloadedValue) == "table" then
						if preloadedValue._id == nil then
							preloadedValue._id = entryKey
						end
						if preloadedValue._script == nil then
							preloadedValue._script = childInstance
						end
					end
					local startTime = os.clock()
					local requiredModule = require(childInstance)
					local durationMs = math.ceil((os.clock() - startTime) * 1000)
					if durationMs >= 25 then
						warnFunction("[SlowModule]", childInstance.Name, string.format("%dms", durationMs))
					end
					if preloadedValue ~= requiredModule then
						warnFunction(string.format("Mismatched entry: %s", entryKey))
						return
					end
				end
			else
				warnFunction(string.format("Duplicate entry: %s", entryKey))
			end
		end
	end

	for _, directChild in ipairs(targetFolder:GetChildren()) do
		traverseAndIndex(directChild, rootScriptName)
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

	setmetatable(destinationTable, {
		__index = function(_, requestedKey)
			local targetScript = pendingModuleScripts[requestedKey]
			if not targetScript then
				error(string.format("Unknown entry '%s'", tostring(requestedKey)))
			end
			pendingModuleScripts[requestedKey] = nil
			local loadedModule = require(targetScript)

			if loadOptions.shouldInject and type(loadedModule) == "table" then
				if loadedModule._id == nil then
					loadedModule._id = requestedKey
				end
				if loadedModule._script == nil then
					loadedModule._script = targetScript
				end
			end

			rawset(destinationTable, requestedKey, loadedModule)
			return loadedModule
		end,
		__newindex = function(_, key, _)
			error(string.format("Tried to set key '%s' on read-only table!", tostring(key)))
		end,
		__metatable = "Locked",
	})
end