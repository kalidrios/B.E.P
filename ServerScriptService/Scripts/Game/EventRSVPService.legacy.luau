local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EventConfig
pcall(function()
	EventConfig = require(ReplicatedStorage:WaitForChild("Directory"):WaitForChild("Event"):WaitForChild("EventConfig"))
end)

local EVENT_ID = (EventConfig and EventConfig.EventId) or "5882426026797171320"

-- Get or create the RemoteEvent in workspace.__THINGS.__REMOTES (INV-001)
local RemotesFolder = workspace:WaitForChild("__THINGS"):WaitForChild("__REMOTES")
local remoteEvent = RemotesFolder:FindFirstChild("PromptEventRSVP")
if not remoteEvent then
	remoteEvent = Instance.new("RemoteEvent")
	remoteEvent.Name = "PromptEventRSVP"
	remoteEvent.Parent = RemotesFolder
end

local debounce = {}

-- Find the Interact part dynamically (handles world rebuilds)
local function findInteractPart()
	-- Primary path: Spawn.MAP.Event.Interact
	local spawnFolder = workspace:FindFirstChild("Spawn")
	local mapFolder = spawnFolder and spawnFolder:FindFirstChild("MAP")
	local eventFolder = mapFolder and mapFolder:FindFirstChild("Event")
	local interact = eventFolder and eventFolder:FindFirstChild("Interact")
	if interact and interact:IsA("BasePart") then
		return interact
	end

	-- Fallback: __MAP.Event.Interact (dynamic world map)
	local dynamicMap = workspace:FindFirstChild("__MAP")
	local dynEvent = dynamicMap and dynamicMap:FindFirstChild("Event")
	local dynInteract = dynEvent and dynEvent:FindFirstChild("Interact")
	if dynInteract and dynInteract:IsA("BasePart") then
		return dynInteract
	end

	return nil
end

local function onTouched(otherPart)
	local character = otherPart.Parent
	if not character then return end

	local player = Players:GetPlayerFromCharacter(character)
	if not player then return end

	-- Debounce: 10 seconds per player
	if debounce[player] then return end
	debounce[player] = true

	-- Fire the RemoteEvent to this specific player
	remoteEvent:FireClient(player, EVENT_ID)

	task.delay(10, function()
		debounce[player] = nil
	end)
end

local function setupInteractPart(part)
	if part and part:IsA("BasePart") then
		part.Touched:Connect(onTouched)
	end
end

-- Setup existing part
local interactPart = findInteractPart()
if interactPart then
	setupInteractPart(interactPart)
end

-- Watch for the part being added/rebuilt
workspace.DescendantAdded:Connect(function(descendant)
	if descendant:IsA("BasePart") and descendant.Name == "Interact" then
		local parent = descendant.Parent
		if parent and parent.Name == "Event" then
			setupInteractPart(descendant)
		end
	end
end)