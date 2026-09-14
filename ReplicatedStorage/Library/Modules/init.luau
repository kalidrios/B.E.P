--[[
	© DestructionSimulator [2025]
	Library/Modules — Shared module registry
	
	Add game-specific shared modules here as the game grows.
	Modules added here are accessible via Library.Modules.ModuleName
]]--

local Modules = {}

-- CountedLock: simple counter-based lock pattern (used by Variables.Locks)
Modules.CountedLock = require(script.CountedLock)
Modules.InventoryUtil = require(script.InventoryUtil)

return Modules
