local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function updateConsoleElements()
	local isGamepad = UserInputService:GetGamepadConnected(Enum.UserInputType.Gamepad1)
		or (UserInputService:GetLastInputType() == Enum.UserInputType.Gamepad1)

	for _, desc in ipairs(playerGui:GetDescendants()) do
		if desc:IsA("GuiObject") and (desc.Name == "Console" or string.find(desc.Name, "Console")) then
			desc.Visible = isGamepad
		end
	end
end

task.spawn(function()
	task.wait(1)
	updateConsoleElements()
end)

UserInputService.GamepadConnected:Connect(updateConsoleElements)
UserInputService.GamepadDisconnected:Connect(updateConsoleElements)
UserInputService.LastInputTypeChanged:Connect(function(lastInputType)
	local isGamepad = (lastInputType == Enum.UserInputType.Gamepad1)
	for _, desc in ipairs(playerGui:GetDescendants()) do
		if desc:IsA("GuiObject") and (desc.Name == "Console" or string.find(desc.Name, "Console")) then
			desc.Visible = isGamepad
		end
	end
end)

playerGui.DescendantAdded:Connect(function(desc)
	if desc:IsA("GuiObject") and (desc.Name == "Console" or string.find(desc.Name, "Console")) then
		local isGamepad = UserInputService:GetGamepadConnected(Enum.UserInputType.Gamepad1)
			or (UserInputService:GetLastInputType() == Enum.UserInputType.Gamepad1)
		desc.Visible = isGamepad
	end
end)
