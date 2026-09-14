--[[
	© Modded 99 [2024] - [2025]
]]--

local ReplicatedStorage = game:GetService("ReplicatedStorage")

if game:GetService("RunService"):IsServer() and not ReplicatedStorage:FindFirstChild("Directory") then
	local dirFolder = workspace:FindFirstChild("Directory")
	if dirFolder then
		dirFolder.Parent = ReplicatedStorage
	end
end

return ReplicatedStorage:WaitForChild("Directory", 99999999)