--[[
	© DestructionSimulator [2025]
	ToolbarController — Client-side toolbar slot management.
	Handles hotkeys, selecting slots, and dynamically rendering weapon icons in the slots.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local StarterGui = game:GetService("StarterGui")
local assets = ReplicatedStorage:WaitForChild("Assets")
local ViewportUtil = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Client"):WaitForChild("ViewportUtil"))

-- Disable native Backpack
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

local mainGui = playerGui:WaitForChild("Main", 15) or playerGui:WaitForChild("Main")
local toolbar = mainGui:WaitForChild("Frame"):WaitForChild("Toolbar")

local remotes = workspace:WaitForChild("__THINGS"):WaitForChild("__REMOTES")

local TWEEN_INFO = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Slots configuration
local SLOTS = {
	{ name = "ROCKET", key = Enum.KeyCode.One },
	{ name = "BOMB", key = Enum.KeyCode.Two }
}

local activeSlot = nil
local cooldowns = {}

local function getUIScale(frame)
	local scale = frame:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = frame
	end
	return scale
end

local function getToolForSlot(slotName)
	if player.Character then
		for _, tool in ipairs(player.Character:GetChildren()) do
			if tool:IsA("Tool") and tool:GetAttribute("SlotName") == slotName then
				return tool, true
			end
		end
	end
	if player.Backpack then
		for _, tool in ipairs(player.Backpack:GetChildren()) do
			if tool:IsA("Tool") and tool:GetAttribute("SlotName") == slotName then
				return tool, false
			end
		end
	end
	return nil, false
end

local function unequipAllTools()
	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum:UnequipTools()
	else
		for _, tool in ipairs(char:GetChildren()) do
			if tool:IsA("Tool") then
				tool.Parent = player.Backpack
			end
		end
	end
end

local function setActiveSlotVisual(slotName, toolDisplayName)
	if activeSlot and activeSlot ~= slotName then
		local oldFrame = toolbar:FindFirstChild(activeSlot)
		if oldFrame then
			local oldImage = oldFrame:FindFirstChild("Frame")
			if oldImage then
				local oldArrow = oldImage:FindFirstChild("Arrow")
				if oldArrow then oldArrow.Visible = false end
			end
			local toolNameLabel = oldFrame:FindFirstChild("toolName")
			if toolNameLabel then toolNameLabel.Visible = false end
			TweenService:Create(getUIScale(oldFrame), TWEEN_INFO, { Scale = 1 }):Play()
		end
	end

	activeSlot = slotName
	local newFrame = toolbar:FindFirstChild(slotName)
	if newFrame then
		local newImage = newFrame:FindFirstChild("Frame")
		if newImage then
			local newArrow = newImage:FindFirstChild("Arrow")
			if newArrow then newArrow.Visible = true end
		end
		local toolNameLabel = newFrame:FindFirstChild("toolName")
		if toolNameLabel then
			toolNameLabel.Visible = true
			if toolDisplayName then
				toolNameLabel.Text = toolDisplayName
			end
		end
		TweenService:Create(getUIScale(newFrame), TWEEN_INFO, { Scale = 1.1 }):Play()
	end
end

local function clearActiveSlotVisual()
	if activeSlot then
		local oldFrame = toolbar:FindFirstChild(activeSlot)
		if oldFrame then
			local oldImage = oldFrame:FindFirstChild("Frame")
			if oldImage then
				local oldArrow = oldImage:FindFirstChild("Arrow")
				if oldArrow then oldArrow.Visible = false end
			end
			local toolNameLabel = oldFrame:FindFirstChild("toolName")
			if toolNameLabel then toolNameLabel.Visible = false end
			TweenService:Create(getUIScale(oldFrame), TWEEN_INFO, { Scale = 1 }):Play()
		end
		activeSlot = nil
	end
end

local function selectSlot(slotName)
	local tool, isAlreadyInHand = getToolForSlot(slotName)
	
	if activeSlot == slotName and isAlreadyInHand then
		-- Toggling off active slot
		unequipAllTools()
		clearActiveSlotVisual()
		return
	end

	if tool then
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then
			hum:EquipTool(tool)
		else
			unequipAllTools()
			if char then
				tool.Parent = char
			end
		end
		setActiveSlotVisual(slotName, tool:GetAttribute("ToolName") or tool.Name)
	end
end

local function createViewport(model, parent, category)
	return ViewportUtil.Create(model, parent, category)
end

local function updateSlotIcon(slotName, weaponName)
	local frame = toolbar:FindFirstChild(slotName)
	if not frame then return end
	
	local imageFrame = frame:FindFirstChild("Frame")
	if not imageFrame then return end
	
	local viewportContainer = imageFrame:FindFirstChild("ViewportContainer")
	if not viewportContainer then
		viewportContainer = Instance.new("Frame")
		viewportContainer.Name = "ViewportContainer"
		viewportContainer.Size = UDim2.fromScale(0.7, 0.7)
		viewportContainer.Position = UDim2.fromScale(0.5, 0.5)
		viewportContainer.AnchorPoint = Vector2.new(0.5, 0.5)
		viewportContainer.BackgroundTransparency = 1
		viewportContainer.ZIndex = 3
		viewportContainer.Parent = imageFrame
	end
	
	for _, child in ipairs(viewportContainer:GetChildren()) do
		child:Destroy()
	end
	
	-- Locate background image if any, and toggle its visibility
	local bgIcon = imageFrame:FindFirstChild("Icon") or imageFrame:FindFirstChild("ImageLabel")
	
	if not weaponName or weaponName == "" then
		if bgIcon then bgIcon.ImageTransparency = 0 end
		return
	end
	
	local category = (slotName == "ROCKET") and "Launcher" or "Bomb"
	local model
	if category == "Launcher" then
		model = assets.Launcher:FindFirstChild(weaponName)
	else
		model = assets.Bomb:FindFirstChild(weaponName)
	end
	
	if model then
		if bgIcon then bgIcon.ImageTransparency = 1 end
		createViewport(model, viewportContainer, category)
		local vpf = viewportContainer:FindFirstChildOfClass("ViewportFrame")
		if vpf then
			vpf.ZIndex = 5
		end
	else
		if bgIcon then bgIcon.ImageTransparency = 0 end
	end
end

-- Keyboard & click setup
for _, slotData in ipairs(SLOTS) do
	local frame = toolbar:FindFirstChild(slotData.name)
	if frame then
		local scale = getUIScale(frame)
		scale.Scale = 1
		
		local toolNameLabel = frame:FindFirstChild("toolName")
		if toolNameLabel then toolNameLabel.Visible = false end
		
		local cooldownLabel = frame:FindFirstChild("cooldown")
		if cooldownLabel then cooldownLabel.Visible = false end
		
		local image = frame:FindFirstChild("Frame")
		if image then
			local arrow = image:FindFirstChild("Arrow")
			if arrow then arrow.Visible = false end
			
			local btn = image:FindFirstChild("Button") or frame:FindFirstChild("Button", true)
			if btn then
				btn.Activated:Connect(function()
					selectSlot(slotData.name)
				end)
			end
		end
	end
end

local function reequipSlotIfActive(slotName, expectedToolName)
	task.spawn(function()
		local startTime = os.clock()
		local tool = nil
		-- Wait up to 3.0s for the tool to replicate and match expected name
		while os.clock() - startTime < 3.0 do
			local candidate = getToolForSlot(slotName)
			if candidate and (not expectedToolName or candidate.Name == expectedToolName or candidate:GetAttribute("ToolName") == expectedToolName) then
				tool = candidate
				break
			end
			task.wait(0.05)
		end
		
		if tool then
			local char = player.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if tool.Parent ~= char then
				if hum then
					hum:EquipTool(tool)
				else
					unequipAllTools()
					if char then
						tool.Parent = char
					end
				end
			end
			setActiveSlotVisual(slotName, tool:GetAttribute("ToolName") or tool.Name)
		end
	end)
end

-- Synchronize active slot visual directly with character tool inventory
local function setupCharacter(char)
	char.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			local slotName = child:GetAttribute("SlotName")
			if slotName then
				setActiveSlotVisual(slotName, child:GetAttribute("ToolName") or child.Name)
			end
		end
	end)

	char.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then
			task.defer(function()
				local currentEquipped = nil
				if player.Character then
					for _, c in ipairs(player.Character:GetChildren()) do
						if c:IsA("Tool") then
							currentEquipped = c
							break
						end
					end
				end
				if currentEquipped then
					local slotName = currentEquipped:GetAttribute("SlotName")
					if slotName then
						setActiveSlotVisual(slotName, currentEquipped:GetAttribute("ToolName") or currentEquipped.Name)
					end
				else
					clearActiveSlotVisual()
				end
			end)
		end
	end)

	-- Check if a tool was already equipped when character loaded
	task.defer(function()
		for _, c in ipairs(char:GetChildren()) do
			if c:IsA("Tool") then
				local slotName = c:GetAttribute("SlotName")
				if slotName then
					setActiveSlotVisual(slotName, c:GetAttribute("ToolName") or c.Name)
				end
				break
			end
		end
	end)
end

player.CharacterAdded:Connect(setupCharacter)
if player.Character then
	setupCharacter(player.Character)
end

-- Listen to player attribute changes for instant toolbar updates
player.AttributeChanged:Connect(function(attr)
	if attr == "EquippedLauncher" then
		local weaponName = player:GetAttribute("EquippedLauncher")
		updateSlotIcon("ROCKET", weaponName)
		reequipSlotIfActive("ROCKET", weaponName)
	elseif attr == "EquippedBomb" then
		local weaponName = player:GetAttribute("EquippedBomb")
		updateSlotIcon("BOMB", weaponName)
		reequipSlotIfActive("BOMB", weaponName)
	end
end)

-- Wait for initial attributes and populate
task.spawn(function()
	task.wait(0.5)
	updateSlotIcon("ROCKET", player:GetAttribute("EquippedLauncher"))
	updateSlotIcon("BOMB", player:GetAttribute("EquippedBomb"))
end)

-- Setup Cooldown receiver
local cooldownRemote = remotes:FindFirstChild("WeaponCooldownEvent")
if not cooldownRemote then
	cooldownRemote = Instance.new("BindableEvent")
	cooldownRemote.Name = "WeaponCooldownEvent"
	cooldownRemote.Parent = remotes
end

cooldownRemote.Event:Connect(function(slotName, duration)
	cooldowns[slotName] = tick() + duration
end)

local function playReloadVFX(slotFrame)
	local imageFrame = slotFrame:FindFirstChild("Frame")
	if not imageFrame then return end
	
	local vfx = Instance.new("Frame")
	vfx.Name = "ReloadVFX"
	vfx.Size = UDim2.new(1, 0, 1, 0)
	vfx.Position = UDim2.new(0.5, 0, 0.5, 0)
	vfx.AnchorPoint = Vector2.new(0.5, 0.5)
	vfx.BackgroundColor3 = Color3.new(1, 1, 1)
	vfx.BackgroundTransparency = 0.3
	vfx.ZIndex = 10
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.2, 0)
	corner.Parent = vfx
	
	vfx.Parent = imageFrame
	
	local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(vfx, tweenInfo, {
		Size = UDim2.new(1.3, 0, 1.3, 0),
		BackgroundTransparency = 1
	})
	
	tween.Completed:Connect(function()
		vfx:Destroy()
	end)
	tween:Play()
end

RunService.RenderStepped:Connect(function()
	local currentTime = tick()
	for _, slotData in ipairs(SLOTS) do
		local endTime = cooldowns[slotData.name]
		local frame = toolbar:FindFirstChild(slotData.name)
		if frame then
			local cooldownLabel = frame:FindFirstChild("cooldown")
			if cooldownLabel then
				if endTime and currentTime < endTime then
					cooldownLabel.Visible = true
					cooldownLabel.Text = string.format("%.1f", math.max(0, endTime - currentTime))
				else
					if cooldownLabel.Visible == true then
						cooldownLabel.Visible = false
						playReloadVFX(frame)
					end
				end
			end
		end
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	for _, slotData in ipairs(SLOTS) do
		if input.KeyCode == slotData.key then
			selectSlot(slotData.name)
			break
		end
	end
end)
