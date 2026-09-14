--[[
	GUILoader.luau — Manages transferring GUI assets to PlayerGui for client loading.
]]--

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local GUILoader = {}

if RunService:IsServer() then
	local StarterGui = game:GetService("StarterGui")
	local guiStorageFolder = Instance.new("Folder")
	guiStorageFolder.Name = "__GUI"

	for _, guiElement in pairs(StarterGui:GetChildren()) do
		guiElement.Parent = guiStorageFolder
	end

	StarterGui.ChildAdded:Connect(function(newGuiElement)
		newGuiElement.Parent = guiStorageFolder
	end)

	guiStorageFolder.Parent = ReplicatedStorage
	return GUILoader
else
	local timeoutSeconds = RunService:IsStudio() and 30 or 99999999
	local localPlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui", timeoutSeconds)
	local guiStorageFolder = ReplicatedStorage:WaitForChild("__GUI", timeoutSeconds)

	if guiStorageFolder and localPlayerGui then
		for _, guiElement in ipairs(guiStorageFolder:GetChildren()) do
			guiElement.Parent = localPlayerGui
		end

		guiStorageFolder.ChildAdded:Connect(function(newGuiElement)
			newGuiElement.Parent = localPlayerGui
		end)
	end

	return GUILoader
end