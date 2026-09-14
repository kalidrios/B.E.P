--[[
	© DestructionSimulator [2025]
	LogbookController — Client-side controller for the Logbook / Index.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local assets = ReplicatedStorage:WaitForChild("Assets")

local Library = require(ReplicatedStorage:WaitForChild("Library"))
while not Library.IsLoaded() do
	task.wait()
end

local WindowManager = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Client"):WaitForChild("UIFramework"):WaitForChild("WindowManager"))
local ShopConfig = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("ShopConfig"))
local InventoryUtil = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Modules"):WaitForChild("InventoryUtil"))
local ViewportUtil = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Client"):WaitForChild("ViewportUtil"))

local remotes = workspace:WaitForChild("__THINGS"):WaitForChild("__REMOTES")
local getPlayerDataRemote = remotes:WaitForChild("GetPlayerData")

-- UI References
local logbookGui = playerGui:WaitForChild("Logbook", 15) or playerGui:WaitForChild("Logbook")
local mainFrame = logbookGui:WaitForChild("Frame"):WaitForChild("Main")
local toolFilters = mainFrame:WaitForChild("Tool"):WaitForChild("Normal")

local typesFrame = mainFrame:WaitForChild("Types")
local normalList = typesFrame:WaitForChild("Normal")

local progressFrame = mainFrame:WaitForChild("Progress")
local progressBar = progressFrame:WaitForChild("Bar")
local percentLabel = mainFrame:WaitForChild("Percent")

local typeTemplate = assets:WaitForChild("UI"):WaitForChild("Logbook"):WaitForChild("TypeTemplate")

-- State Variables
local currentCategory = "Launcher"
local playerData = {
	Weapons = {},
	Backpacks = {}
}

----------------------------------------------------------------------
-- Get Model Helper
----------------------------------------------------------------------
local function getModel(category, name)
	return ViewportUtil.GetModel(category, name)
end

----------------------------------------------------------------------
-- Check ownership status
----------------------------------------------------------------------
local function isOwned(category, name)
	return InventoryUtil.OwnsBaseEquipment(playerData, category, name)
end

----------------------------------------------------------------------
-- Viewport Rendering Helper
----------------------------------------------------------------------
local function createViewport(model, parent, category)
	return ViewportUtil.Create(model, parent, category)
end

----------------------------------------------------------------------
-- Get Progress calculation
----------------------------------------------------------------------
local function getCollectionProgress()
	local total = 0
	local owned = 0
	
	-- Launcher
	for _, item in ipairs(ShopConfig.Launcher or {}) do
		total = total + 1
		if isOwned("Launcher", item.Name) then
			owned = owned + 1
		end
	end
	
	-- Bomb
	for _, item in ipairs(ShopConfig.Bomb or {}) do
		total = total + 1
		if isOwned("Bomb", item.Name) then
			owned = owned + 1
		end
	end
	
	-- BackPack
	for _, item in ipairs(ShopConfig.BackPack or {}) do
		total = total + 1
		if isOwned("BackPack", item.Name) then
			owned = owned + 1
		end
	end
	
	return owned, total
end

----------------------------------------------------------------------
-- Rebuild Items Grid
----------------------------------------------------------------------
local function rebuildItemsGrid()
	-- Clean up previous items
	for _, child in ipairs(normalList:GetChildren()) do
		if not child:IsA("UIGridLayout") and not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
	
	local items = ShopConfig[currentCategory] or {}
	for _, item in ipairs(items) do
		local clone = typeTemplate:Clone()
		clone.Name = item.Name
		clone.TypeName.Text = item.Name
		clone.LayoutOrder = item.LayoutOrder or 1
		
		local gearIcon = clone:FindFirstChild("GearIcon")
		local lockedLabel = gearIcon and gearIcon:FindFirstChild("Locked")
		
		local owned = isOwned(currentCategory, item.Name)
		if owned then
			if lockedLabel then lockedLabel.Visible = false end
			
			local model = getModel(currentCategory, item.Name)
			if model and gearIcon then
				createViewport(model, gearIcon, currentCategory)
			end
		else
			if lockedLabel then lockedLabel.Visible = true end
		end
		
		clone.Visible = true
		clone.Parent = normalList
	end
	
	-- Update CanvasSize of scrolling frame
	local uiGridLayout = normalList:FindFirstChildOfClass("UIGridLayout")
	if uiGridLayout then
		uiGridLayout:ApplyLayout()
		local rows = math.ceil(#items / uiGridLayout.FillDirectionMaxCells)
		local height = rows * (uiGridLayout.CellSize.Y.Offset + uiGridLayout.CellPadding.Y.Offset) + 50
		typesFrame.CanvasSize = UDim2.new(0, 0, 0, height)
	end
end

----------------------------------------------------------------------
-- Update Progress visual
----------------------------------------------------------------------
local function updateProgress()
	local owned, total = getCollectionProgress()
	local fraction = total > 0 and (owned / total) or 0
	percentLabel.Text = string.format("%d%%", math.floor(fraction * 100))
	
	TweenService:Create(progressBar, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.new(fraction, 0, 1, 0)
	}):Play()
end

----------------------------------------------------------------------
-- Select Category Tab
----------------------------------------------------------------------
local function selectCategoryTab(categoryName)
	currentCategory = categoryName
	
	for _, button in ipairs(toolFilters:GetChildren()) do
		if button:IsA("GuiButton") then
			local img = button:FindFirstChild("Image")
			if img and img:IsA("ImageLabel") then
				if button.Name == categoryName then
					img.ImageColor3 = Color3.fromRGB(255, 255, 255)
				else
					img.ImageColor3 = Color3.fromRGB(180, 180, 180)
				end
			end
		end
	end
	
	rebuildItemsGrid()
end

----------------------------------------------------------------------
-- Fetch player data from server
----------------------------------------------------------------------
local function refreshPlayerData()
	local success, data = pcall(function()
		return getPlayerDataRemote:InvokeServer()
	end)
	if success and data then
		playerData = data
	end
	
	updateProgress()
	rebuildItemsGrid()
end

----------------------------------------------------------------------
-- Initialization & Connections
----------------------------------------------------------------------
for _, button in ipairs(toolFilters:GetChildren()) do
	if button:IsA("GuiButton") then
		button.Activated:Connect(function()
			selectCategoryTab(button.Name)
		end)
	end
end

logbookGui:GetPropertyChangedSignal("Enabled"):Connect(function()
	if logbookGui.Enabled then
		selectCategoryTab(currentCategory)
		refreshPlayerData()
	end
end)
