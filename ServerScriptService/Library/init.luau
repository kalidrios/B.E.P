--[[
	Â© DestructionSimulator [2025]
	ServerScriptService/Library â€” Server-side Library
	
	FAIL-FAST: All require() calls are direct (no pcall).
	If any server module errors, the error propagates and the server fails to start.
	
	This module is loaded by the shared Library/init.luau on the server context.
	It sets Loaded = true when all server modules are initialized.
]]--

local Library = {
	Loaded = false,
	-- Core server modules (FAIL-FAST: require() without pcall)
	Network = require(script.Network),
	Datastore = require(script.Datastore),
	Saving = require(script.Saving),
}

-- Auto-discover and load any unregistered child ModuleScripts
task.spawn(function()
	local bool = false
	for _, child in ipairs(script:GetChildren()) do
		if child:GetAttribute("NOLOAD") then
			continue
		end
		
		if Library[child.Name] then
			continue
		end
		
		if not child:IsA("ModuleScript") then
			continue
		end
		
		if (not bool) then 
			bool = true
			task.wait() 
		end
		
		--print("Library (Server) - Late loading: ", child)
		
		local s = os.clock()
		Library[child.Name] = require(child)
		local e = math.round((os.clock() - s) * 1000)
		if e >= 25 then
			--warn("[SlowModule]", child, string.format("%dms", e))
		end
	end

	Library.Loaded = true
end)

return Library
