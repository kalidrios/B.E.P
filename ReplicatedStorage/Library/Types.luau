--[[
	© DestructionSimulator [2025]
	Library/Types — Shared type definitions
]]--

local Types = {}

-- Destruction-specific types will be added here as the game evolves.
-- For now, this provides the module structure that Library/init.luau expects.

export type DestructibleObject = {
	Id: string,
	Name: string,
	Health: number,
	MaxHealth: number,
	Position: Vector3,
	Rewards: { [string]: number },
}

export type PlayerData = {
	UserId: number,
	Coins: number,
	Gems: number,
	Power: number,
	Rebirth: number,
	Inventory: { [string]: any },
	Settings: { [string]: any },
}

return Types
