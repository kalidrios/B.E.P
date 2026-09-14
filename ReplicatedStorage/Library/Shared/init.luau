--[[
	Library/Shared — Shared data (Variables + Functions)
]]--

local SharedVariables = require(script.Variables)
local SharedFunctions = require(script.Functions)

setmetatable(SharedVariables, {
	__index = SharedFunctions,
})

return SharedVariables
