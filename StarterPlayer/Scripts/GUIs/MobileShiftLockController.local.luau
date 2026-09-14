local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local camera = workspace.CurrentCamera
local isLocked = false
local rmbHolding = false

local TEXTURE_OFF = "rbxasset://textures/ui/TouchControls/ShiftLockOff.png"
local TEXTURE_ON  = "rbxasset://textures/ui/TouchControls/ShiftLockOn.png"
local CENTER_CURSOR_PNG = "rbxasset://textures/ui/mouse_lock_cursor.png" -- Built-in Roblox ShiftLock reticle 

local mainGui = playerGui:WaitForChild("Main", 15) or playerGui:WaitForChild("Main")
local centerCursor = nil

if mainGui then
	centerCursor = mainGui:FindFirstChild("ShiftLockCenterCursor")
	if not centerCursor then
		centerCursor = Instance.new("ImageLabel")
		centerCursor.Name = "ShiftLockCenterCursor"
		centerCursor.Size = UDim2.new(0, 32, 0, 32)
		centerCursor.AnchorPoint = Vector2.new(0.5, 0.5)
		centerCursor.Position = UDim2.new(0.5, 0, 0.5, 0)
		centerCursor.BackgroundTransparency = 1
		centerCursor.Image = CENTER_CURSOR_PNG
		centerCursor.Visible = false
		centerCursor.ZIndex = 100
		centerCursor.Parent = mainGui
	end
end

local function updateVisibility(btn)
	local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	if isMobile and btn then
		btn.Visible = true
	end
end

local shiftLockBtn = mainGui and mainGui:FindFirstChild("ShiftLock", true)

local function toggleLock(btn)
	isLocked = not isLocked
	
	local targetBtn = btn or shiftLockBtn
	if targetBtn and targetBtn:IsA("ImageButton") then
		targetBtn.Image = isLocked and TEXTURE_ON or TEXTURE_OFF
	end

	if centerCursor then
		centerCursor.Visible = isLocked
	end
end

RunService.RenderStepped:Connect(function()
	local active = isLocked or rmbHolding
	if not active then return end

	local character = player.Character
	if not character then return end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if hrp and humanoid and humanoid.Health > 0 then
		local lookVector = camera.CFrame.LookVector
		local targetCFrame = CFrame.new(hrp.Position, hrp.Position + Vector3.new(lookVector.X, 0, lookVector.Z))
		hrp.CFrame = hrp.CFrame:Lerp(targetCFrame, 0.35)
	end
end)

-- PC Key 'C' toggle functionality for ShiftLock
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.C then
		toggleLock(shiftLockBtn)
	end
end)

-- GUI Setup
if shiftLockBtn and shiftLockBtn:IsA("ImageButton") then
	shiftLockBtn.Image = TEXTURE_OFF
	updateVisibility(shiftLockBtn)

	shiftLockBtn.Activated:Connect(function()
		toggleLock(shiftLockBtn)
	end)

	UserInputService.LastInputTypeChanged:Connect(function()
		updateVisibility(shiftLockBtn)
	end)
end
