local function deepCopyTable(sourceTable, cache)
	if typeof(sourceTable) ~= "table" then
		return sourceTable
	end

	local targetTable = nil
	if not cache then
		targetTable = {}
		cache = { [sourceTable] = targetTable }
	else
		local cachedCopy = cache[sourceTable]
		if cachedCopy ~= nil then
			return cachedCopy
		else
			targetTable = {}
			cache[sourceTable] = targetTable
		end
	end

	for key, value in next, sourceTable, nil do
		targetTable[deepCopyTable(key, cache)] = deepCopyTable(value, cache)
	end

	local tableMetatable = getmetatable(sourceTable)
	if tableMetatable then
		setmetatable(targetTable, deepCopyTable(tableMetatable, cache))
	end

	return targetTable
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ScriptContext = game:GetService("ScriptContext")
local LogService = game:GetService("LogService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local blunderFolder = ReplicatedStorage:WaitForChild("Blunder", 99999999)
local BlunderMessage = require(blunderFolder:WaitForChild("BlunderMessage", 99999999))
local BlunderList = require(blunderFolder:WaitForChild("BlunderList", 99999999))
local BlunderConfig = require(blunderFolder:WaitForChild("Config", 99999999))

BlunderMessage = deepCopyTable(BlunderMessage)
BlunderList = deepCopyTable(BlunderList)
BlunderConfig = deepCopyTable(BlunderConfig)

local remoteName = script:GetAttribute("__REMOTE")
if typeof(remoteName) ~= "string" then
	return
end
script:SetAttribute("__REMOTE", nil)

local telemetryRemote = ReplicatedStorage:WaitForChild(remoteName, 99999999)
local isReporterShutdown = false
local messageQueue = BlunderList.new()

local function flushMessageQueue()
	local pendingMessages = messageQueue:getAndClear()
	if pendingMessages then
		local encodedBatch = {}
		for _, messageObj in ipairs(pendingMessages) do
			table.insert(encodedBatch, messageObj:encode())
		end
		telemetryRemote:FireServer(encodedBatch)
	end
end

local filterMap = {
	[BlunderMessage.Source.SCRIPT_CONTEXT] = BlunderConfig.ErrorFilter,
	[BlunderMessage.Source.LOG_SERVICE] = BlunderConfig.MessageFilter,
	[BlunderMessage.Source.OTHER] = BlunderConfig.OtherFilter,
	[BlunderMessage.Source.NETWORK] = BlunderConfig.NetworkFilter,
}

local function reportTelemetryMessage(messageObj)
	pcall(function()
		if messageObj then
			local activeFilter = filterMap[messageObj.source]
			if activeFilter and messageObj:isWanted(activeFilter) then
				messageQueue:add(messageObj)
				if not (BlunderConfig.ReportRate and not isReporterShutdown) then
					flushMessageQueue()
				end
			end
		end
	end)
end

-- Capture unhandled script errors
local errorConnection = ScriptContext.Error:Connect(function(errorMessage, stackTrace, scriptInstance)
	pcall(function()
		local errorClusterId = nil
		local blunderTagMatch = errorMessage:match(" ?%[Blunder:([0-9a-f]+)%]")
		if blunderTagMatch and #blunderTagMatch == 32 then
			errorClusterId = blunderTagMatch
			errorMessage = errorMessage:gsub(" ?%[Blunder:" .. blunderTagMatch .. "%]", "")
		end

		local scriptPath = scriptInstance and scriptInstance:GetFullName() or nil
		local messageObj = BlunderMessage.new(
			BlunderMessage.Source.SCRIPT_CONTEXT,
			errorMessage,
			Enum.MessageType.MessageError,
			false,
			stackTrace,
			scriptPath,
			Players.LocalPlayer,
			errorClusterId
		)

		reportTelemetryMessage(messageObj)
	end)
end)

-- Capture LogService console output
local logConnection = LogService.MessageOut:Connect(function(rawMessage, messageType)
	pcall(function()
		local errorClusterId = nil
		local blunderTagMatch = rawMessage:match(" ?%[Blunder:([0-9a-f]+)%]")
		if blunderTagMatch and #blunderTagMatch == 32 then
			errorClusterId = blunderTagMatch
			rawMessage = rawMessage:gsub(" ?%[Blunder:" .. blunderTagMatch .. "%]", "")
		end

		local messageObj = BlunderMessage.new(
			BlunderMessage.Source.LOG_SERVICE,
			rawMessage,
			messageType,
			false,
			nil,
			nil,
			Players.LocalPlayer,
			errorClusterId
		)

		reportTelemetryMessage(messageObj)
	end)
end)

local function sendPingTelemetry()
	pcall(function()
		if errorConnection and logConnection then
			local pingMessage = BlunderMessage.new(BlunderMessage.Source.OTHER, "PING", Enum.MessageType.MessageInfo, false)
			reportTelemetryMessage(pingMessage)
		end
	end)
end

-- Global Blunder logging hook
task.spawn(function()
	local function logGlobalBlunder(messageType, rawMessage, sourceOverride)
		local messageObj = BlunderMessage.new(
			sourceOverride or BlunderMessage.Source.OTHER,
			rawMessage,
			messageType,
			false,
			nil,
			nil,
			Players.LocalPlayer
		)
		reportTelemetryMessage(messageObj)
	end

	_G.BlunderSource = BlunderMessage.Source
	_G.Blunder = logGlobalBlunder
end)

-- Heartbeat flush and ping loop
local timeSinceLastPing = 0
local timeSinceLastFlush = 0
local pingInterval = BlunderConfig.ReportRate and (BlunderConfig.ReportRate > 0) and BlunderConfig.ReportRate or 15
local nextPingThreshold = math.random() * pingInterval

local heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime)
	if isReporterShutdown then
		return
	end

	local clampedDelta = (deltaTime >= 0 and deltaTime <= 1) and deltaTime or 0
	timeSinceLastPing = timeSinceLastPing + clampedDelta

	if timeSinceLastPing >= nextPingThreshold then
		timeSinceLastPing = 0
		local currentInterval = (BlunderConfig.ReportRate and BlunderConfig.ReportRate > 0) and BlunderConfig.ReportRate or 15
		nextPingThreshold = math.random() * currentInterval
		sendPingTelemetry()
	end

	if BlunderConfig.ReportRate and not messageQueue:empty() then
		timeSinceLastFlush = timeSinceLastFlush + clampedDelta
		if timeSinceLastFlush >= BlunderConfig.ReportRate then
			timeSinceLastFlush = 0
			flushMessageQueue()
		end
	end
end)

-- Initial ping
task.spawn(function()
	sendPingTelemetry()
end)