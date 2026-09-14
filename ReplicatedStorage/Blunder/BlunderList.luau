--[[
	© DestructionSimulator [2025]
	BlunderList.luau — Telemetry error and log aggregation list for client/server tracking.
	--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BlunderFolder = ReplicatedStorage:WaitForChild("Blunder", 99999999)
local BlunderMessage = require(BlunderFolder:WaitForChild("BlunderMessage", 99999999))

local BlunderList = {}
BlunderList.__index = BlunderList

--- Creates a new BlunderList instance to store errors for a specific player
function BlunderList.new(userId: number, username: string, displayName: string)
	local self = setmetatable({
		playerUserId = userId,
		playerName = username,
		playerDisplayName = displayName,
		list = {}, -- Array of BlunderMessage instances in order
		map = {},  -- Dictionary of BlunderMessage instances keyed by message unique key
	}, BlunderList)

	return self
end

--- Adds a new BlunderMessage to the list or appends it to an existing message if duplicate
function BlunderList:add(messageInstance)
	local messageKey = messageInstance:key()
	local existingMessage = self.map[messageKey]

	if not existingMessage then
		self.map[messageKey] = messageInstance
		table.insert(self.list, messageInstance)
	else
		existingMessage:append(messageInstance)
	end
end

--- Clears all messages from the list and lookup map
function BlunderList:clear()
	self.list = {}
	self.map = {}
end

--- Retrieves the current list of messages and clears the storage for the next batch
function BlunderList:getAndClear()
	local activeList = self.list
	if #activeList > 0 then
		self.list = {}
		self.map = {}
		return activeList
	else
		return nil
	end
end

--- Checks whether the message list is empty
function BlunderList:empty()
	return #self.list == 0
end

table.freeze(BlunderList)
return BlunderList
