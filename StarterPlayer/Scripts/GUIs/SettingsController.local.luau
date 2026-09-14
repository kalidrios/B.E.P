--[[
	© DestructionSimulator [2025]
	SettingsController — Client-side settings GUI controller.
	Dynamically builds settings list based on Shared.SettingsInfo,
	animates toggles, handles sliders/selectors, and manages local physics filtering.
]]--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Library = require(ReplicatedStorage:WaitForChild("Library"))
while not Library.Loaded do
	game:GetService("RunService").Heartbeat:Wait()
end

local Shared = Library.Shared
local Network = Library.Network
local Save = Library.Save
local GUIFX = Library.GUIFX
local Audio = Library.Audio
local WindowManager = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Client"):WaitForChild("UIFramework"):WaitForChild("WindowManager"))

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local SettingsGui = PlayerGui:WaitForChild("Settings", 15) or PlayerGui:WaitForChild("Settings")
local Frame = SettingsGui:WaitForChild("Frame")
local Main = Frame:WaitForChild("Main")
local Items = Main:WaitForChild("Items")

local toggleTemplate = Items:WaitForChild("Toggle")
local sliderTemplate = Items:WaitForChild("Slider")
local selectorTemplate = Items:WaitForChild("Selector")
local categoryTemplate = Items:WaitForChild("Category")

toggleTemplate.Visible = false
sliderTemplate.Visible = false
selectorTemplate.Visible = false
categoryTemplate.Visible = false

local function updateToggleButton(element, settingName, value)
	local optionBtn = element.Toggle.Option
	local label = optionBtn:FindFirstChild("TextLabel")
	local colorFrame = optionBtn:FindFirstChild("Frame")
	
	local settingInfo = Shared.SettingsInfo[settingName]
	local optionText = settingInfo.options[value] or (value == 1 and "On" or "Off")
	if label then
		label.Text = optionText
	end
	
	if colorFrame then
		if value == 1 then
			colorFrame.BackgroundColor3 = Color3.fromRGB(0, 170, 0) -- Green
		else
			colorFrame.BackgroundColor3 = Color3.fromRGB(250, 0, 0) -- Red
		end
	end

	-- Slide position animation (On = right, Off = left)
	local targetPos = (value == 1) and UDim2.new(0.7, 0, 0.5, 0) or UDim2.new(0.3, 0, 0.5, 0)
	optionBtn.Position = targetPos
end

local function updateSliderButton(element, settingName, value)
	local button = element.Slider.Buton
	local settingInfo = Shared.SettingsInfo[settingName]
	local min = settingInfo.min or 0
	local max = settingInfo.max or 1
	local percent = (value - min) / (max - min)
	button.Position = UDim2.new(0.05 + percent * 0.9, 0, 0.5, 0)
end

local function updateSelectorButton(element, settingName, value)
	local optionBtn = element.Toggle.Option
	local label = optionBtn:FindFirstChild("TextLabel")
	local colorFrame = optionBtn:FindFirstChild("Frame")
	
	local settingInfo = Shared.SettingsInfo[settingName]
	local optionText = settingInfo.options[value] or tostring(value)
	if label then
		label.Text = optionText
	end
	
	if colorFrame then
		local colorName = settingInfo.colors and settingInfo.colors[value]
		if colorName == "RedGradient" or colorName == "Red" then
			colorFrame.BackgroundColor3 = Color3.fromRGB(250, 0, 0) -- Red
		else
			colorFrame.BackgroundColor3 = Color3.fromRGB(0, 170, 0) -- Green
		end
	end
end

local function setupSlider(button, settingName)
	local dragging = false
	local bar = button.Parent -- Slider (Frame)
	
	local function updateSliderPosition()
		local mousePos = LocalPlayer:GetMouse().X
		local barPositionX = bar.AbsolutePosition.X
		local barWidth = bar.AbsoluteSize.X
		local fraction = math.clamp((mousePos - barPositionX) / barWidth, 0, 1)
		
		local percent = 0.05 + fraction * 0.9
		button.Position = UDim2.new(percent, 0, 0.5, 0)
		
		local settingInfo = Shared.SettingsInfo[settingName]
		local min = settingInfo.min or 0
		local max = settingInfo.max or 1
		local value = min + (max - min) * fraction
		
		local save = Save.Get()
		if save then
			save.Settings[settingName] = value
		end
		
		-- Fire signal to notify of real-time update
		Library.Signal.Fire("Setting Slider Update", settingName, value)
	end
	
	button.MouseButton1Down:Connect(function()
		dragging = true
		
		local inputEndedConn
		inputEndedConn = UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragging = false
				inputEndedConn:Disconnect()
				
				-- Invoke server to save the value
				local save = Save.Get()
				if save then
					local val = save.Settings[settingName]
					Network.Invoke("Slider Setting", settingName, val)
				end
			end
		end)
		
		task.spawn(function()
			while dragging do
				updateSliderPosition()
				RunService.Heartbeat:Wait()
			end
		end)
	end)
end

local function buildUI()
	-- Clean up previous cloned items
	for _, child in ipairs(Items:GetChildren()) do
		if child.Name ~= "Toggle" and child.Name ~= "Slider" and child.Name ~= "Selector" and child.Name ~= "Category" and child.Name ~= "UIListLayout" and child.Name ~= "UIPadding" then
			child:Destroy()
		end
	end
	
	local save = Save.Get()
	if not save then return end
	
	local categories = {"Sound", "Performance", "Trading"}
	local currentOrder = 1
	
	for _, categoryName in ipairs(categories) do
		-- Count settings in this category
		local catSettings = {}
		for settingName, info in pairs(Shared.SettingsInfo) do
			if info.category == categoryName then
				table.insert(catSettings, {name = settingName, info = info})
			end
		end
		
		-- Only create header if there are settings in this category
		if #catSettings > 0 then
			local header = categoryTemplate:Clone()
			header.Name = "CategoryHeader"
			header.Text = string.upper(categoryName)
			header.LayoutOrder = currentOrder
			header.Visible = true
			header.Parent = Items
			currentOrder = currentOrder + 1
			
			table.sort(catSettings, function(a, b)
				return (a.info.sort or 999) < (b.info.sort or 999)
			end)
			
			for _, data in ipairs(catSettings) do
				local settingName = data.name
				local info = data.info
				if not save.Settings then
					save.Settings = {}
				end
				local value = save.Settings[settingName]
				if value == nil then
					value = info.default or (info.settingType == "Slider" and 0.5 or 1)
					save.Settings[settingName] = value
				end
				
				local clone
				if info.settingType == "Toggle" then
					clone = toggleTemplate:Clone()
					clone.SettingName.Text = info.title
					
					local optionBtn = clone.Toggle.Option
					updateToggleButton(clone, settingName, value)
					
					if GUIFX and GUIFX.ButtonFX then
						GUIFX.ButtonFX(optionBtn)
					end
					
					optionBtn.Activated:Connect(function()
						if Audio and Audio.Play then
							Audio.Play("rbxassetid://14901495465", script, 1, 0.5)
						end
						local currentValue = save.Settings[settingName] or 1
						local nextValue = (currentValue == 1) and 2 or 1
						save.Settings[settingName] = nextValue
						updateToggleButton(clone, settingName, nextValue)
						Library.Signal.Fire("Setting Changed", settingName, nextValue)
						
						task.spawn(function()
							local success, err, finalVal = Network.Invoke("Toggle Setting", settingName)
							if success then
								save.Settings[settingName] = finalVal
								updateToggleButton(clone, settingName, finalVal)
								Library.Signal.Fire("Setting Changed", settingName, finalVal)
							else
								save.Settings[settingName] = currentValue
								updateToggleButton(clone, settingName, currentValue)
								Library.Signal.Fire("Setting Changed", settingName, currentValue)
							end
						end)
					end)
					
				elseif info.settingType == "Slider" then
					clone = sliderTemplate:Clone()
					clone.SettingName.Text = info.title
					
					local button = clone.Slider.Buton
					updateSliderButton(clone, settingName, value)
					
					if GUIFX and GUIFX.ButtonFX then
						GUIFX.ButtonFX(button)
					end
					setupSlider(button, settingName)
					
				elseif info.settingType == "Selector" then
					clone = selectorTemplate:Clone()
					clone.SettingName.Text = info.title
					
					local optionBtn = clone.Toggle.Option
					updateSelectorButton(clone, settingName, value)
					
					if GUIFX and GUIFX.ButtonFX then
						GUIFX.ButtonFX(optionBtn)
					end
					
					optionBtn.Activated:Connect(function()
						if Audio and Audio.Play then
							Audio.Play("rbxassetid://14901495465", script, 1, 0.5)
						end
						local currentValue = save.Settings[settingName] or 1
						local nextValue = currentValue + 1
						if nextValue > #info.options then
							nextValue = 1
						end
						save.Settings[settingName] = nextValue
						updateSelectorButton(clone, settingName, nextValue)
						Library.Signal.Fire("Setting Changed", settingName, nextValue)
						
						task.spawn(function()
							local success, err, finalVal = Network.Invoke("Toggle Setting", settingName)
							if success then
								save.Settings[settingName] = finalVal
								updateSelectorButton(clone, settingName, finalVal)
								Library.Signal.Fire("Setting Changed", settingName, finalVal)
							else
								save.Settings[settingName] = currentValue
								updateSelectorButton(clone, settingName, currentValue)
								Library.Signal.Fire("Setting Changed", settingName, currentValue)
							end
						end)
					end)
				end
				
				if clone then
					clone.Name = settingName
					clone.LayoutOrder = currentOrder
					clone.Visible = true
					clone.Parent = Items
					currentOrder = currentOrder + 1
				end
			end
		end
	end
	
	-- Update scrolling size
	local uiListLayout = Items:FindFirstChildOfClass("UIListLayout")
	local uiPadding = Items:FindFirstChildOfClass("UIPadding")
	if uiListLayout then
		uiListLayout:ApplyLayout()
		local paddingSize = uiPadding and (uiPadding.PaddingTop.Offset + uiPadding.PaddingBottom.Offset) or 0
		Items.CanvasSize = UDim2.new(0, 0, 0, uiListLayout.AbsoluteContentSize.Y + paddingSize + 20)
	end
end

-- Close Button Connection
local closeBtn = Frame:WaitForChild("Close")
closeBtn.Activated:Connect(function()
	WindowManager.Close()
end)

SettingsGui:GetPropertyChangedSignal("Enabled"):Connect(function()
	if SettingsGui.Enabled then
		buildUI()
	end
end)
if SettingsGui.Enabled then
	buildUI()
end

-- NOTE: Destruction rendering architecture (server-owned real physics):
-- 1. The SERVER is the single owner of destruction: it validates the explosion,
--    unanchors the REAL blocks, applies impulse and schedules deletion (3s/5s/7s
--    batches). Debris keeps CanCollide ENABLED so blocks land on the map instead
--    of falling through the floor into the void.
-- 2. The client spawns NO clones/fakes and never re-anchors anything — it only
--    renders VFX/sounds and receives the replicated physics.
-- 3. Settings here (PerformanceMode, VFX toggles, volume) are read dynamically
--    by RocketController per explosion.
