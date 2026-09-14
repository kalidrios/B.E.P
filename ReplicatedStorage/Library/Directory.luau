--[[
	© DestructionSimulator [2025]
	Directory — Central loader for all Directory configurations
	Loads weapons, skills, upgrades, areas, etc., dynamically from ReplicatedStorage.Directory
]]--

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DirectoryLoader = require(ReplicatedStorage:WaitForChild("DirectoryLoader"))

local Directory = {}

local function loadCategoryFolder(categoryTable, folder)
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("ModuleScript") then
			local success, data = pcall(require, child)
			if success then
				categoryTable[child.Name] = data
			else
				warn("Failed to load Directory module: " .. child:GetFullName() .. " - Error: " .. tostring(data))
			end
		elseif child:IsA("Folder") then
			local subTable = categoryTable[child.Name] or {}
			categoryTable[child.Name] = subTable
			loadCategoryFolder(subTable, child)
		end
	end
end

for _, categoryFolder in ipairs(DirectoryLoader:GetChildren()) do
	if categoryFolder:IsA("Folder") then
		local categoryName = categoryFolder.Name
		Directory[categoryName] = {}
		loadCategoryFolder(Directory[categoryName], categoryFolder)
	end
end

return Directory
