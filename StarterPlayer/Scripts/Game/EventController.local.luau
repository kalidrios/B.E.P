--[[
	EventController.local.luau — Client-side Event & Countdown Controller
	Destruction Simulator

	Features:
	- Automatically discovers any "Event" model across all current and future worlds (Spawn, Magic, etc.).
	- Continuously updates the Billboard countdown on Attachment.Collect.Header.
	- Listens to workspace changes to dynamically hook new worlds as they load/unload.
	- Centralized configuration via ReplicatedStorage.Directory.Event.EventConfig.
]]--

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EventConfig = require(ReplicatedStorage:WaitForChild("Directory"):WaitForChild("Event"):WaitForChild("EventConfig"))

-- Tracked event models: [eventModel] = { header = TextLabel, targetTimestamp = number }
local trackedEvents = {}

-- Find Header TextLabel within an Event model
local function findHeaderLabel(eventModel)
	if not eventModel then return nil end

	-- Direct hierarchy: MAP.Event.Attachment.Collect.Header
	local attachment = eventModel:FindFirstChild("Attachment")
	if attachment then
		local collect = attachment:FindFirstChild("Collect")
		if collect then
			local header = collect:FindFirstChild("Header")
			if header and header:IsA("TextLabel") then
				return header
			end
		end
	end

	-- Fallback search inside eventModel for any BillboardGui with a Header
	for _, desc in ipairs(eventModel:GetDescendants()) do
		if desc.Name == "Header" and desc:IsA("TextLabel") and desc:FindFirstAncestorOfClass("BillboardGui") then
			return desc
		end
	end

	return nil
end

-- Resolve target timestamp for a specific event model
local function resolveEventTargetTime(eventModel)
	if not eventModel then
		return EventConfig.GetTargetTimestamp()
	end

	-- Check for attribute override on model
	local customTimestamp = eventModel:GetAttribute("TargetTimestamp")
		or eventModel:GetAttribute("EventTime")
		or eventModel:GetAttribute("Timestamp")

	if customTimestamp and type(customTimestamp) == "number" and customTimestamp > 0 then
		return customTimestamp
	end

	return EventConfig.GetTargetTimestamp()
end

-- Register an Event model into the active tracking list
local function registerEventModel(eventModel)
	if not eventModel or trackedEvents[eventModel] then return end
	if not (eventModel:IsA("Model") or eventModel:IsA("Folder")) then return end
	if eventModel.Name ~= "Event" then return end

	local header = findHeaderLabel(eventModel)
	if not header then
		-- In case children replicate slightly after parent
		task.spawn(function()
			for _ = 1, 10 do
				task.wait(0.5)
				if not eventModel.Parent then return end
				header = findHeaderLabel(eventModel)
				if header then
					local targetTime = resolveEventTargetTime(eventModel)
					trackedEvents[eventModel] = {
						header = header,
						targetTimestamp = targetTime,
					}
					-- print(string.format("[EventController] Registered Event countdown in '%s'", eventModel:GetFullName()))
					break
				end
			end
		end)
		return
	end

	local targetTime = resolveEventTargetTime(eventModel)
	trackedEvents[eventModel] = {
		header = header,
		targetTimestamp = targetTime,
	}

	-- print(string.format("[EventController] Registered Event countdown in '%s'", eventModel:GetFullName()))
end

-- Unregister an Event model
local function unregisterEventModel(eventModel)
	if trackedEvents[eventModel] then
		trackedEvents[eventModel] = nil
	end
end

-- Initial scan of workspace for existing Event models
local function scanAllEvents()
	for _, desc in ipairs(Workspace:GetDescendants()) do
		if desc.Name == "Event" and (desc:IsA("Model") or desc:IsA("Folder")) then
			registerEventModel(desc)
		end
	end
end

-- Watch for worlds/events being loaded or unloaded dynamically
Workspace.DescendantAdded:Connect(function(descendant)
	if descendant.Name == "Event" and (descendant:IsA("Model") or descendant:IsA("Folder")) then
		registerEventModel(descendant)
	elseif descendant.Name == "Header" and descendant:IsA("TextLabel") then
		local parentModel = descendant:FindFirstAncestor("Event")
		if parentModel then
			registerEventModel(parentModel)
		end
	end
end)

Workspace.DescendantRemoving:Connect(function(descendant)
	if descendant.Name == "Event" then
		unregisterEventModel(descendant)
	end
end)

-- Start initial scan
task.spawn(function()
	task.wait(1)
	scanAllEvents()
end)

-- Main countdown loop (updates every second)
task.spawn(function()
	while true do
		task.wait(1)

		local now = os.time()
		for eventModel, data in pairs(trackedEvents) do
			if not eventModel.Parent or not data.header.Parent then
				trackedEvents[eventModel] = nil
			else
				local target = data.targetTimestamp or EventConfig.GetTargetTimestamp()
				local remaining = math.max(0, target - now)
				local formatted = EventConfig.FormatRemaining(remaining)

				if data.header.Text ~= formatted then
					data.header.Text = formatted
				end
			end
		end
	end
end)
