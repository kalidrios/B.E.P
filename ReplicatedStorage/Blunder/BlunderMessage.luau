--[[
	BlunderMessage.luau — Telemetry error message object representing single or clustered errors.
]]--

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local BlunderMessage = {
	Source = {
		SCRIPT_CONTEXT = 0,
		LOG_SERVICE = 1,
		OTHER = 2,
		NETWORK = 3,
	},
	SourceInv = {},
}

for sourceName, sourceId in pairs(BlunderMessage.Source) do
	BlunderMessage.SourceInv[sourceId] = sourceName
end

local function isFiniteNumber(value)
	return (value == value) and (value ~= -math.huge) and (value ~= math.huge)
end

function BlunderMessage.new(sourceId, rawMessage, messageType, isServer, stackTrace, sourceScript, playerInstance, messageId)
	if typeof(sourceId) ~= "number" or not BlunderMessage.SourceInv[sourceId] then
		return nil
	end
	if typeof(rawMessage) ~= "string" then
		return nil
	end
	if typeof(messageType) ~= "EnumItem" or messageType.EnumType ~= Enum.MessageType then
		return nil
	end
	if typeof(isServer) ~= "boolean" then
		return nil
	end
	if stackTrace ~= nil and typeof(stackTrace) ~= "string" then
		return nil
	end
	if sourceScript ~= nil and typeof(sourceScript) ~= "string" then
		return nil
	end

	local sanitizedMessage = rawMessage
	local sanitizedStackTrace = stackTrace
	local sanitizedSourceScript = sourceScript

	if playerInstance ~= nil then
		if typeof(playerInstance) == "Instance" and playerInstance:IsA("Player") then
			sanitizedMessage = sanitizedMessage:gsub(playerInstance.Name, "<Player>")
			if sanitizedStackTrace then
				sanitizedStackTrace = sanitizedStackTrace:gsub(playerInstance.Name, "<Player>")
			end
			if sanitizedSourceScript then
				sanitizedSourceScript = sanitizedSourceScript:gsub(playerInstance.Name, "<Player>")
			end
		else
			return nil
		end
	end

	if messageId ~= nil and not (typeof(messageId) == "string" and #messageId == 32 and messageId:match("^[0-9a-f]+$")) then
		return nil
	end

	local serverTimestamp = workspace:GetServerTimeNow()
	return setmetatable({
		source = sourceId,
		message = sanitizedMessage,
		messageType = messageType,
		isServer = isServer,
		stackTrace = sanitizedStackTrace,
		sourceScript = sanitizedSourceScript,
		id = messageId,
		occurrences = 1,
		firstOccurrence = serverTimestamp,
		lastOccurrence = serverTimestamp,
	}, {
		__index = BlunderMessage,
	})
end

function BlunderMessage:key()
	return HttpService:JSONEncode({
		self.source,
		self.message,
		self.messageType.Value,
		self.isServer,
		self.stackTrace,
		self.sourceScript,
	})
end

function BlunderMessage:append(otherMessage)
	self.occurrences = self.occurrences + otherMessage.occurrences
	self.firstOccurrence = math.min(self.firstOccurrence, otherMessage.firstOccurrence)
	self.lastOccurrence = math.max(self.lastOccurrence, otherMessage.lastOccurrence)
end

function BlunderMessage:encode()
	return {
		self.source,
		self.message,
		self.messageType,
		self.stackTrace,
		self.sourceScript,
		self.occurrences,
		self.firstOccurrence,
		self.lastOccurrence,
		self.id,
		0,
	}
end

function BlunderMessage:encodeForAPI()
	local encodedData = {
		source = self.source,
		message = HttpService:UrlEncode(self.message),
		type = self.messageType.Value,
		is_server = self.isServer,
		stack_trace = self.stackTrace and HttpService:UrlEncode(self.stackTrace) or nil,
		source_script = self.sourceScript and HttpService:UrlEncode(self.sourceScript) or nil,
		occurrences = self.occurrences,
		first_occurrence = self.firstOccurrence,
		last_occurrence = self.lastOccurrence,
		id = self.id,
	}
	return encodedData
end

function BlunderMessage.decode(encodedArray, isServer)
	if typeof(encodedArray) ~= "table" or #encodedArray ~= 10 or typeof(isServer) ~= "boolean" then
		return nil
	end

	local sourceId = encodedArray[1]
	local rawMessage = encodedArray[2]
	local messageType = encodedArray[3]
	local stackTrace = encodedArray[4]
	local sourceScript = encodedArray[5]
	local occurrences = encodedArray[6]
	local firstOccurrence = encodedArray[7]
	local lastOccurrence = encodedArray[8]
	local messageId = encodedArray[9]
	local formatVersion = encodedArray[10]

	if typeof(sourceId) ~= "number" or not BlunderMessage.SourceInv[sourceId] then
		return nil
	end
	if typeof(rawMessage) ~= "string" then
		return nil
	end
	if typeof(messageType) ~= "EnumItem" or messageType.EnumType ~= Enum.MessageType then
		return nil
	end
	if stackTrace ~= nil and typeof(stackTrace) ~= "string" then
		return nil
	end
	if sourceScript ~= nil and typeof(sourceScript) ~= "string" then
		return nil
	end
	if typeof(occurrences) ~= "number" or not isFiniteNumber(occurrences) or occurrences < 1 or math.floor(occurrences) ~= occurrences then
		return nil
	end
	if typeof(firstOccurrence) ~= "number" or not isFiniteNumber(firstOccurrence) then
		return nil
	end
	if typeof(lastOccurrence) ~= "number" or not isFiniteNumber(lastOccurrence) then
		return nil
	end
	if messageId ~= nil and not (typeof(messageId) == "string" and #messageId == 32 and messageId:match("^[0-9a-f]+$")) then
		return nil
	end
	if formatVersion ~= 0 then
		return nil
	end

	return setmetatable({
		source = sourceId,
		message = rawMessage,
		messageType = messageType,
		isServer = isServer,
		stackTrace = stackTrace,
		sourceScript = sourceScript,
		occurrences = occurrences,
		firstOccurrence = firstOccurrence,
		lastOccurrence = lastOccurrence,
		id = messageId,
	}, {
		__index = BlunderMessage,
	})
end

function BlunderMessage:isWanted(filterConfig)
	if filterConfig.AllowedTypes and not filterConfig.AllowedTypes[self.messageType] then
		return false
	end

	if filterConfig.MessageBlacklist then
		for _, pattern in ipairs(filterConfig.MessageBlacklist) do
			if self.message:find(pattern) then
				return false
			end
		end
	end

	if filterConfig.MessageWhitelist then
		for _, pattern in ipairs(filterConfig.MessageWhitelist) do
			if self.message:find(pattern) then
				return true
			end
		end
		return false
	end

	return true
end

table.freeze(BlunderMessage)
return BlunderMessage