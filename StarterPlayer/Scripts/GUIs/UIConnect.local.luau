local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WindowManager = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Client"):WaitForChild("UIFramework"):WaitForChild("WindowManager"))
local GlobalLocks = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Client"):WaitForChild("UIFramework"):WaitForChild("GlobalLocks"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local mainGui = playerGui:WaitForChild("Main", 15) or playerGui:WaitForChild("Main")
GlobalLocks.HideHUD.OnLockChanged:Connect(function(isUnlocked)
	mainGui.Enabled = isUnlocked
end)
local leftFrame = mainGui:WaitForChild("Frame"):WaitForChild("Left")

-- Sell Teleport binding
local sellFrame = mainGui:WaitForChild("Frame"):WaitForChild("Sell")
local tpBtn = sellFrame:WaitForChild("Tp")

local function teleportToSell()
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local currentWorld = player:GetAttribute("World") or "Spawn"
	local map = workspace:FindFirstChild("__MAP") or workspace:FindFirstChild("MAP") or workspace
	local worldFolder = map:FindFirstChild(currentWorld) or map

	local targetTpPart = nil
	local closestDist = math.huge

	-- 1. Search in current world folder
	for _, desc in ipairs(worldFolder:GetDescendants()) do
		if desc.Name == "Sell" and (desc:IsA("Model") or desc:IsA("Folder") or desc:IsA("BasePart")) then
			local tp = desc:FindFirstChild("Teleport") or desc:FindFirstChild("Interact") or (desc:IsA("BasePart") and desc) or desc:FindFirstChildWhichIsA("BasePart", true)
			if tp and tp:IsA("BasePart") then
				local d = (hrp.Position - tp.Position).Magnitude
				if d < closestDist then
					closestDist = d
					targetTpPart = tp
				end
			end
		end
	end

	-- 2. Fallback search across workspace
	if not targetTpPart then
		for _, desc in ipairs(workspace:GetDescendants()) do
			if desc.Name == "Sell" and (desc:IsA("Model") or desc:IsA("Folder") or desc:IsA("BasePart")) then
				local tp = desc:FindFirstChild("Teleport") or desc:FindFirstChild("Interact") or (desc:IsA("BasePart") and desc) or desc:FindFirstChildWhichIsA("BasePart", true)
				if tp and tp:IsA("BasePart") then
					local d = (hrp.Position - tp.Position).Magnitude
					if d < closestDist then
						closestDist = d
						targetTpPart = tp
					end
				end
			end
		end
	end

	if targetTpPart then
		hrp.CFrame = targetTpPart.CFrame + Vector3.new(0, 3, 0)
	end
end
_G.TeleportToSell = teleportToSell

tpBtn.Activated:Connect(teleportToSell)

local UserInputService = game:GetService("UserInputService")

local Audio = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Audio"))
local TweenService = game:GetService("TweenService")

local function playClickSound(btn)
	if Audio and Audio.Play then
		Audio.Play("rbxassetid://87485609714706", btn, 1.0, 0.4)
	end
end

local function addButtonHover(btn)
	if not btn or not btn:IsA("GuiButton") then return end

	local uiScale = btn:FindFirstChildOfClass("UIScale")
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Parent = btn
	end
	
	local originalRotation = btn.Rotation
	
	btn.MouseEnter:Connect(function()
		TweenService:Create(uiScale, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = 1.1}):Play()
		TweenService:Create(btn, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Rotation = originalRotation + 5}):Play()
	end)
	
	btn.MouseLeave:Connect(function()
		TweenService:Create(uiScale, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = 1.0}):Play()
		TweenService:Create(btn, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Rotation = originalRotation}):Play()
	end)

	btn.Activated:Connect(function()
		playClickSound(btn)
	end)
end

local exclusiveShopBtn = leftFrame:WaitForChild("ExclusiveShop")
local inventoryBtn = leftFrame:WaitForChild("Inventory")
local rebirthBtn = leftFrame:WaitForChild("Rebirth")
local tradeBtn = leftFrame:FindFirstChild("Trade") or leftFrame:FindFirstChild("Trading") or leftFrame:WaitForChild("Trade")
local logbookBtn = leftFrame:WaitForChild("Logbook")

local exclusiveShopGui = playerGui:WaitForChild("ExclusiveShop")
local inventoryGui = playerGui:WaitForChild("Inventory")
local rebirthGui = playerGui:WaitForChild("Rebirth")
local gearShopGui = playerGui:WaitForChild("GearShop")
local tradeGui = playerGui:FindFirstChild("Trade") or playerGui:FindFirstChild("Trading") or playerGui:WaitForChild("Trade")
local settingsGui = playerGui:WaitForChild("Settings")
local logbookGui = playerGui:WaitForChild("Logbook")

local settingsBtn = leftFrame:FindFirstChild("Settings") or leftFrame:FindFirstChild("Options") or leftFrame:FindFirstChild("SettingsButton") or leftFrame:FindFirstChild("OptionsButton")

-- Console Keybinds: ButtonX (Sell Teleport), ButtonY (Toggle Inventory), ButtonB (Close Windows)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.ButtonX then
		teleportToSell()
	elseif input.KeyCode == Enum.KeyCode.ButtonY then
		if WindowManager.ActiveWindow == inventoryGui then
			WindowManager.Close()
		else
			WindowManager.Open(inventoryGui)
		end
	elseif input.KeyCode == Enum.KeyCode.ButtonB then
		if WindowManager.ActiveWindow then
			WindowManager.Close()
		end
	end
end)

addButtonHover(exclusiveShopBtn)
addButtonHover(inventoryBtn)
addButtonHover(rebirthBtn)
addButtonHover(logbookBtn)
addButtonHover(tpBtn)
if settingsBtn then
	addButtonHover(settingsBtn)
end
if tradeBtn then
	addButtonHover(tradeBtn)
end

exclusiveShopBtn.Activated:Connect(function()
	WindowManager.Open(exclusiveShopGui)
end)

inventoryBtn.Activated:Connect(function()
	WindowManager.Open(inventoryGui)
end)

rebirthBtn.Activated:Connect(function()
	WindowManager.Open(rebirthGui)
end)

logbookBtn.Activated:Connect(function()
	WindowManager.Open(logbookGui)
end)

if settingsBtn and settingsGui then
	settingsBtn.Activated:Connect(function()
		WindowManager.Open(settingsGui)
	end)
end

if tradeBtn and tradeGui then
	local frame = tradeGui:FindFirstChild("Frame")
	if frame then
		local oldUiScale = frame:FindFirstChildOfClass("UIScale")
		if oldUiScale then
			oldUiScale:Destroy()
		end
	end
	tradeBtn.Activated:Connect(function()
		tradeGui.Enabled = not tradeGui.Enabled
	end)
end

local exclusiveShopClose = exclusiveShopGui:WaitForChild("Frame"):WaitForChild("Close")
addButtonHover(exclusiveShopClose)
exclusiveShopClose.Activated:Connect(function()
	WindowManager.Close()
end)

local inventoryClose = inventoryGui:WaitForChild("Frame"):WaitForChild("Close")
addButtonHover(inventoryClose)
inventoryClose.Activated:Connect(function()
	WindowManager.Close()
end)

local rebirthClose = rebirthGui:WaitForChild("Frame"):WaitForChild("Close")
addButtonHover(rebirthClose)
rebirthClose.Activated:Connect(function()
	WindowManager.Close()
end)

local gearShopClose = gearShopGui:WaitForChild("Frame"):WaitForChild("Close")
addButtonHover(gearShopClose)
gearShopClose.Activated:Connect(function()
	WindowManager.Close()
end)

if settingsGui then
	local frame = settingsGui:FindFirstChild("Frame")
	local closeBtn = frame and frame:FindFirstChild("Close")
	if closeBtn then
		addButtonHover(closeBtn)
		closeBtn.Activated:Connect(function()
			WindowManager.Close()
		end)
	end
end

if logbookGui then
	local frame = logbookGui:FindFirstChild("Frame")
	local closeBtn = frame and frame:FindFirstChild("Close")
	if closeBtn then
		addButtonHover(closeBtn)
		closeBtn.Activated:Connect(function()
			WindowManager.Close()
		end)
	end
end

if tradeGui then
	local frame = tradeGui:FindFirstChild("Frame")
	local playerList = frame and frame:FindFirstChild("PlayerList")
	local closeBtn = playerList and playerList:FindFirstChild("Close")
	if closeBtn then
		addButtonHover(closeBtn)
		closeBtn.Activated:Connect(function()
			tradeGui.Enabled = false
		end)
	end
end
