local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local GlobalLocks = require(script.Parent.GlobalLocks)

local Audio = require(game.ReplicatedStorage:WaitForChild("Library"):WaitForChild("Audio"))

local WindowManager = {}
WindowManager.ActiveWindow = nil
WindowManager._hideHUDCleanup = nil

local depthBlur = Lighting:FindFirstChild("UIDepthBlur")
if not depthBlur then
	depthBlur = Instance.new("DepthOfFieldEffect")
	depthBlur.Name = "UIDepthBlur"
	depthBlur.FarIntensity = 0.75
	depthBlur.FocusDistance = 200
	depthBlur.InFocusRadius = 15
	depthBlur.NearIntensity = 0
	depthBlur.Enabled = false
	depthBlur.Parent = Lighting
end

function WindowManager.Open(guiObject)
	local Players = game:GetService("Players")
	local LocalPlayer = Players.LocalPlayer
	local playerGui = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui")
	local tradeGui = playerGui and (playerGui:FindFirstChild("Trade") or playerGui:FindFirstChild("Trading"))

	-- If an active trade session is in progress, block other windows
	if tradeGui and tradeGui.Enabled then
		local tradeFrame = tradeGui:FindFirstChild("Frame") and tradeGui.Frame:FindFirstChild("Trade")
		if tradeFrame and tradeFrame.Visible and guiObject ~= tradeGui then
			return
		end
	end

	if WindowManager.ActiveWindow == guiObject then return end

	if WindowManager.ActiveWindow then
		WindowManager.Close()
	end

	-- Window open sound
	if Audio and Audio.Play then
		Audio.Play("rbxassetid://87485609714706", nil, 1.1, 0.4)
	end

	WindowManager.ActiveWindow = guiObject

	local frame = guiObject:FindFirstChildOfClass("Frame")
	if not frame then return end

	guiObject.Enabled = true

	local uiScale = frame:FindFirstChildOfClass("UIScale")
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Parent = frame
	end

	uiScale.Scale = 0.85
	TweenService:Create(uiScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()

	depthBlur.Enabled = true
	TweenService:Create(depthBlur, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {FocusDistance = 10}):Play()
	
	local camera = workspace.CurrentCamera
	if not WindowManager._originalFOV then
		WindowManager._originalFOV = camera.FieldOfView
	end
	TweenService:Create(camera, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {FieldOfView = WindowManager._originalFOV + 20}):Play()

	if not WindowManager._hideHUDCleanup then
		WindowManager._hideHUDCleanup = GlobalLocks.HideHUD:ObtainLock()
	end
end

function WindowManager.Close()
	if not WindowManager.ActiveWindow then return end

	-- Window close sound
	if Audio and Audio.Play then
		Audio.Play("rbxassetid://87485609714706", nil, 0.9, 0.35)
	end

	local closingGui = WindowManager.ActiveWindow
	WindowManager.ActiveWindow = nil

	local frame = closingGui:FindFirstChildOfClass("Frame")
	if frame then
		local uiScale = frame:FindFirstChildOfClass("UIScale")
		if uiScale then
			TweenService:Create(uiScale, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Scale = 0.85}):Play()
		end
	end

	TweenService:Create(depthBlur, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {FocusDistance = 200}):Play()
	
	if WindowManager._originalFOV then
		TweenService:Create(workspace.CurrentCamera, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {FieldOfView = WindowManager._originalFOV}):Play()
	end

	task.delay(0.2, function()
		if closingGui then
			closingGui.Enabled = false
		end
		if not WindowManager.ActiveWindow then
			depthBlur.Enabled = false
			WindowManager._originalFOV = nil
		end
	end)

	if WindowManager._hideHUDCleanup then
		WindowManager._hideHUDCleanup()
		WindowManager._hideHUDCleanup = nil
	end
end

return WindowManager