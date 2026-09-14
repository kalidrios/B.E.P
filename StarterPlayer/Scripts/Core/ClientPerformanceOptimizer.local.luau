--[[
	© DestructionSimulator [2025]
	ClientPerformanceOptimizer — Dynamic client-side visual & lighting optimization.
	Reacts to player PerformanceMode without touching engine QualityLevel (0ms stutter).
]]--

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Library = require(ReplicatedStorage:WaitForChild("Library"))

local function applyPerformanceMode(perfMode)
	perfMode = tonumber(perfMode) or 2 -- 1: Low, 2: Medium, 3: High

	for _, child in ipairs(Lighting:GetChildren()) do
		if child:IsA("SunRaysEffect") or child:IsA("DepthOfFieldEffect") or child:IsA("BlurEffect") then
			child.Enabled = (perfMode >= 2)
		elseif child:IsA("BloomEffect") or child:IsA("ColorCorrectionEffect") then
			child.Enabled = true
		end
	end
end

-- Initialize when Library is loaded
task.spawn(function()
	while not Library.Loaded do
		task.wait()
	end

	local Save = Library.Save
	local save = Save and Save.Get()
	local initialPerf = save and save.Settings and save.Settings.PerformanceMode or 2
	applyPerformanceMode(initialPerf)

	-- Listen for dynamic setting updates
	if Library.Signal then
		Library.Signal.Connect("Setting Changed", function(settingName, value)
			if settingName == "PerformanceMode" then
				applyPerformanceMode(value)
			end
		end)
	end
end)

-- Handle dynamically added lighting post-effects
Lighting.ChildAdded:Connect(function(child)
	local Save = Library.Save
	local save = Save and Save.Get()
	local perfMode = save and save.Settings and save.Settings.PerformanceMode or 2

	if child:IsA("SunRaysEffect") or child:IsA("DepthOfFieldEffect") or child:IsA("BlurEffect") then
		child.Enabled = (perfMode >= 2)
	end
end)

-- Optimize workspace instances without breaking gameplay
Workspace.DescendantAdded:Connect(function(descendant)
	if descendant:IsA("WrapTarget") then
		descendant.Parent = nil
	elseif descendant:IsA("WrapLayer") then
		descendant.Enabled = false
	end
end)
