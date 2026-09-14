--[[
	Â© DestructionSimulator [2025]
	Library/Client â€” Client-side Library extension
	
	This module is loaded only on the client. It extends the shared Library
	with client-specific modules and sets Library.Loaded = true when ready.
]]--

local RunService = game:GetService("RunService")
assert(RunService:IsClient(), "Library/Client should only be required on the client!")

local Client = {
	Loaded = false,
}

-- Client modules will be added here as the game grows.
-- Example: Client.UI = require(script.UI)

-- Auto-load any child ModuleScripts not yet registered
task.spawn(function()
	--print("Library (Client) - Starting load sequence")
	local lateLoading = false
	for _, module in ipairs(script:GetChildren()) do
		--print("Library (Client) - Checking child: ", module.Name)
		if not module:GetAttribute("NOLOAD") then
			if module:IsA("ModuleScript") then
				if Client[module.Name] == nil then
					if not lateLoading then
						task.wait()
						lateLoading = true
					end
					--print("Library (Client) - Late loading: ", module.Name)
					Client[module.Name] = require(module)
					--print("Library (Client) - Finished late loading: ", module.Name)
				end
			end
		end
	end

	--print("Library (Client) - Load sequence complete!")
	Client.Loaded = true
end)

return Client
