--[[
	© DestructionSimulator [2025]
	CarpetController — Client-side controller for toggling Flying Carpet with 'Q' keybind.
--]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Audio = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Audio"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remotesFolder = workspace:WaitForChild("__THINGS"):WaitForChild("__REMOTES")
local toggleCarpetRemote = remotesFolder:WaitForChild("ToggleCarpet")

local function playErrorSound()
	if Audio and Audio.Play then
		Audio.Play(101618216035709, playerGui, 1, 1.0)
	end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	
	if input.KeyCode == Enum.KeyCode.Q then
		local rebirthCount = player:GetAttribute("Rebirth") or 0
		if rebirthCount >= 1 then
			toggleCarpetRemote:FireServer()
		else
			playErrorSound()
			if _G.Message and _G.Message.New then
				_G.Message.New("You must reach Level 60 and perform your first Rebirth to unlock the Flying Carpet!", false, "Carpet Locked")
			end
		end
	end
end)

--print("[CarpetController] Client Flying Carpet Controller initialized! Press 'Q' to ride after Rebirth!")
