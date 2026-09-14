--[[
	© DestructionSimulator [2025]
	AreaInfoController — Client-side controller for area level requirement signs and doors.
	Updates SurfaceGuis on Infor parts and collision state on Walls.Level parts based on player level.
--]]--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Player = Players.LocalPlayer

local Library = require(ReplicatedStorage:WaitForChild("Library"))
while not Library.IsLoaded() do
	task.wait()
end

local Directory = Library.Directory
local LevelModule = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Modules"):WaitForChild("LevelModule"))

local function getPlayerLevel()
	local levelAttr = Player:GetAttribute("Level")
	if levelAttr and levelAttr > 1 then return levelAttr end
	local exp = Player:GetAttribute("Experience") or 0
	local levelFromExp = LevelModule.GetLevelDataFromXP(exp)
	return (levelFromExp and levelFromExp > 0) and levelFromExp or 1
end

local function updateAreaState(areaFolder)
	if not areaFolder or not (areaFolder:IsA("Folder") or areaFolder:IsA("Model")) then return end
	local areaName = areaFolder.Name
	
	local currentWorld = Player:GetAttribute("World") or "Spawn"
	local areaConfig = nil
	local areasDict = Directory and Directory.Areas
	if areasDict then
		local worldAreas = areasDict[currentWorld] or areasDict.Spawn or areasDict
		if worldAreas and typeof(worldAreas) == "table" then
			areaConfig = worldAreas[areaName]
			if not areaConfig then
				local normalizedSearch = string.lower(string.gsub(areaName, "%s+", ""))
				for name, config in pairs(worldAreas) do
					if typeof(config) == "table" then
						local configName = string.lower(string.gsub(config.Name or name, "%s+", ""))
						local configDisplay = string.lower(string.gsub(config.DisplayName or "", "%s+", ""))
						if configName == normalizedSearch or configDisplay == normalizedSearch then
							areaConfig = config
							break
						end
					end
				end
			end
		end
	end
	
	-- Fallback if Directory not populated yet
	local reqLevel = 1
	if areaConfig then
		reqLevel = areaConfig.RequiredLevel or areaConfig.LevelRequired or areaConfig.Level or areaConfig.ReqLevel or 1
	else
		local num = tonumber(string.match(areaName, "%d+"))
		if num then
			if num <= 6 then
				reqLevel = num * 10
			else
				reqLevel = 75 + (num - 7) * 25
			end
		end
	end
	
	local playerLevel = getPlayerLevel()
	-- Beginner safety: Area 1 (Spawn starter zone) is always open so Level 1 players can enter and progress
	local isStarterArea = (areaConfig and (areaConfig.Order == 1)) or areaName == "Area 1" or areaName == "Area1"
	local hasLevel = playerLevel >= reqLevel or isStarterArea
	
	-- 1. Update Infor/Info SurfaceGui
	local infor = areaFolder:FindFirstChild("Infor", true) or areaFolder:FindFirstChild("Info", true)
	if infor then
		local surfaceGuis = {}
		if infor:IsA("SurfaceGui") then
			table.insert(surfaceGuis, infor)
		end
		for _, sg in ipairs(infor:GetDescendants()) do
			if sg:IsA("SurfaceGui") then
				table.insert(surfaceGuis, sg)
			end
		end
		
		for _, surfaceGui in ipairs(surfaceGuis) do
			local openClose = surfaceGui:FindFirstChild("Open/Close", true) or surfaceGui:FindFirstChild("Status", true)
			local openCloseShadow = surfaceGui:FindFirstChild("Open/CloseShadow", true)
			
			if hasLevel then
				if openClose then
					openClose.Text = "OPEN"
					openClose.TextColor3 = Color3.fromRGB(0, 255, 127)
				end
				if openCloseShadow then
					openCloseShadow.Text = "OPEN"
				end
			else
				if openClose then
					openClose.Text = "CLOSE"
					openClose.TextColor3 = Color3.fromRGB(216, 58, 43)
				end
				if openCloseShadow then
					openCloseShadow.Text = "CLOSE"
				end
			end
			
			local levelText = surfaceGui:FindFirstChild("LevelText", true) or surfaceGui:FindFirstChild("ReqLevel", true)
			local levelTextShadow = surfaceGui:FindFirstChild("LevelTextShadow", true)
			local textString = "Level " .. tostring(reqLevel) .. " Required"
			
			if levelText then levelText.Text = textString end
			if levelTextShadow then levelTextShadow.Text = textString end
		end
	end
	
	-- 2. Update Walls.Level collision & transparency
	local walls = areaFolder:FindFirstChild("Walls", true)
	if walls then
		for _, child in ipairs(walls:GetChildren()) do
			if child:IsA("BasePart") then
				local childName = string.lower(child.Name)
				if childName == "level" or string.find(childName, "gate") or string.find(childName, "door") or string.find(childName, "wall") then
					child.CanCollide = not hasLevel
				end
			end
		end
	end
	
	local directLevelPart = areaFolder:FindFirstChild("Level", true)
	if directLevelPart and directLevelPart:IsA("BasePart") and directLevelPart.Parent and string.lower(directLevelPart.Parent.Name) == "walls" then
		directLevelPart.CanCollide = not hasLevel
	end
end

local function getAreasFolders()
	local folders = {}
	local areas = workspace:FindFirstChild("Areas")
	if areas then
		table.insert(folders, areas)
	end
	local map = workspace:FindFirstChild("__MAP")
	if map then
		local mapAreas = map:FindFirstChild("Areas")
		if mapAreas then
			table.insert(folders, mapAreas)
		end
		local mapMap = map:FindFirstChild("MAP")
		if mapMap then
			local mapMapAreas = mapMap:FindFirstChild("Areas")
			if mapMapAreas then
				table.insert(folders, mapMapAreas)
			end
		end
	end
	return folders
end

local function updateAllAreas()
	local folders = getAreasFolders()
	for _, folder in ipairs(folders) do
		for _, areaFolder in ipairs(folder:GetChildren()) do
			pcall(updateAreaState, areaFolder)
		end
	end
end

-- Hook events on the direct parent folders
local activeHooks = {}
local function hookAreasFolder(folder)
	if activeHooks[folder] then return end
	activeHooks[folder] = true
	
	folder.ChildAdded:Connect(function(child)
		task.wait(0.1)
		pcall(updateAreaState, child)
	end)
	
	for _, child in ipairs(folder:GetChildren()) do
		pcall(updateAreaState, child)
	end
end

local function scanAndHookFolders()
	local folders = getAreasFolders()
	for _, folder in ipairs(folders) do
		hookAreasFolder(folder)
	end
end

-- Hook new folders under workspace or __MAP
workspace.ChildAdded:Connect(function(child)
	if child.Name == "Areas" and child:IsA("Folder") then
		task.wait(0.1)
		hookAreasFolder(child)
	elseif child.Name == "__MAP" then
		task.wait(0.1)
		scanAndHookFolders()
	end
end)

Player.AttributeChanged:Connect(function(attr)
	if attr == "Experience" or attr == "Level" then
		updateAllAreas()
	end
end)

-- Periodically refresh as a safety net
task.spawn(function()
	while true do
		scanAndHookFolders()
		pcall(updateAllAreas)
		task.wait(1.5)
	end
end)

-- Initial run
task.spawn(function()
	task.wait(1)
	scanAndHookFolders()
	updateAllAreas()
end)

--print("[AreaInfoController] Area Info Controller initialized successfully!")
