--[[
	© DestructionSimulator [2025]
	ShopController — Client-side controller for the Gear Shop.
	Handles category selection, left/right item cycling, viewport rendering, and purchase requests.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local assets = ReplicatedStorage:WaitForChild("Assets")

local WindowManager = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Client"):WaitForChild("UIFramework"):WaitForChild("WindowManager"))
local ShopConfig = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("ShopConfig"))
local InventoryUtil = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Modules"):WaitForChild("InventoryUtil"))
local ViewportUtil = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Client"):WaitForChild("ViewportUtil"))
local Audio = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Audio"))
local FormatNumber = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Functions"):WaitForChild("FormatNumber"))

local remotes = workspace:WaitForChild("__THINGS"):WaitForChild("__REMOTES")
local getPlayerDataRemote = remotes:WaitForChild("GetPlayerData")
local buyItemRemote = remotes:WaitForChild("BuyItem")
local equipRemote = remotes:WaitForChild("EquipItem")

_G.ErrorSoundId = 101618216035709
_G.PurchaseSoundId = 102314941670514

local function playErrorSound()
	if Audio and Audio.Play then
		Audio.Play(_G.ErrorSoundId, playerGui, 1, 1.0)
	end
end

local function playPurchaseSound()
	if Audio and Audio.Play then
		Audio.Play(_G.PurchaseSoundId, playerGui, 1, 1.0)
	end
end

local isTempRed = false

-- GUI References
local gearShopScreen = playerGui:WaitForChild("GearShop", 15) or playerGui:WaitForChild("GearShop")
local gearShopGui = gearShopScreen:WaitForChild("Frame")
local mainFrame = gearShopGui:WaitForChild("Main")
local toolFilters = mainFrame:WaitForChild("Tool"):WaitForChild("Normal")

local typesFrame = mainFrame:WaitForChild("Types")
local leftButton = typesFrame:WaitForChild("Left")
local rightButton = typesFrame:WaitForChild("Right")

local normalFrame = typesFrame:WaitForChild("Normal")
local gearIcon = normalFrame:WaitForChild("GearIcon")
local priceFrame = normalFrame:WaitForChild("Frame")
local priceLabel = priceFrame:WaitForChild("Price")
local buyButton = normalFrame:WaitForChild("Buy")
local buyButtonText = buyButton:WaitForChild("TextLabel")
local damageLabel = gearIcon:WaitForChild("Damage")
local balanceLabel = mainFrame:WaitForChild("Balance"):WaitForChild("Value")

-- State Variables
local function getCurrentWorldName(): string
	return player:GetAttribute("World") or "Spawn"
end

local currentCategory = "Launcher"
local currentIndex = 1
local itemsList = ShopConfig.GetItems(currentCategory, getCurrentWorldName())

local playerData = {
	Coins = 0,
	Weapons = {},
	Backpacks = {},
	EquippedBackpack = "SmallBag"
}

local spinConnection = nil
local currentCloneModel = nil

----------------------------------------------------------------------
-- Shop World Background Gradient Helper
----------------------------------------------------------------------
local function updateShopWorldGradient()
	if not gearShopGui then return end
	local bg = gearShopGui:FindFirstChild("Bg")
	if not bg then return end
	local design = bg:FindFirstChild("Design") or bg:FindFirstChild("Disign")
	if not design then return end

	local worldName = getCurrentWorldName()
	local gradientFolder = assets:FindFirstChild("UI")
		and assets.UI:FindFirstChild("Gradient")
		and assets.UI.Gradient:FindFirstChild("GearShop")

	local worldGradient = gradientFolder and (gradientFolder:FindFirstChild(worldName) or gradientFolder:FindFirstChild("Spawn"))
	if not worldGradient then return end

	-- Remove any previous world gradient
	for _, child in ipairs(design:GetChildren()) do
		if child.Name == "ShopWorldGradient" then
			child:Destroy()
		end
	end

	-- Clone and apply matching gradient
	local newGradient = worldGradient:Clone()
	newGradient.Name = "ShopWorldGradient"
	newGradient.Parent = design
end

----------------------------------------------------------------------
-- Viewport Rendering Helper
----------------------------------------------------------------------
local function createViewport(model, parent, category)
	if not ViewportUtil or not model then return nil end
	return ViewportUtil.Create(model, parent, category)
end

----------------------------------------------------------------------
-- Get Model Helper
----------------------------------------------------------------------
local function getModel(category, name)
	if not ViewportUtil then return nil end
	return ViewportUtil.GetModel(category, name)
end

----------------------------------------------------------------------
-- Check ownership & equipped status
----------------------------------------------------------------------
local function isOwned(category, name)
	return InventoryUtil.OwnsBaseEquipment(playerData, category, name)
end

local function isEquipped(category, name)
	return InventoryUtil.IsEquipped(player, category, name)
end

----------------------------------------------------------------------
-- Update Selected Item View
----------------------------------------------------------------------
local function updateSelectedItem()
	if spinConnection then
		spinConnection:Disconnect()
		spinConnection = nil
	end

	-- Clean old viewports
	for _, child in ipairs(gearIcon:GetChildren()) do
		if child:IsA("ViewportFrame") then
			child:Destroy()
		end
	end

	local item = itemsList[currentIndex]
	if not item then return end

	-- Update Carousel navigation button colors
	if currentIndex == 1 then
		leftButton.ImageColor3 = Color3.fromRGB(180, 180, 180)
	else
		leftButton.ImageColor3 = Color3.fromRGB(255, 255, 255)
	end

	if currentIndex == #itemsList then
		rightButton.ImageColor3 = Color3.fromRGB(180, 180, 180)
	else
		rightButton.ImageColor3 = Color3.fromRGB(255, 255, 255)
	end

	-- Update Stats text
	if currentCategory == "Launcher" then
		damageLabel.Text = string.format("Reload: %.1fs", item.Reload)
	elseif currentCategory == "Bomb" then
		damageLabel.Text = string.format("Blast: %d", item.BlastRadius)
	elseif currentCategory == "BackPack" then
		damageLabel.Text = string.format("Cap: %d", item.Capacity)
	end

	-- Update price display
	priceLabel.Text = FormatNumber(item.Price)

	-- Update model viewport
	local model = getModel(currentCategory, item.Name)
	if model then
		currentCloneModel = createViewport(model, gearIcon, currentCategory)
	end

	-- Update buy button text/state
	if isTempRed then return end

	local owned = isOwned(currentCategory, item.Name)
	local equipped = isEquipped(currentCategory, item.Name)

	if equipped then
		buyButtonText.Text = "EQUIPPED"
		buyButton.BackgroundColor3 = Color3.fromRGB(150, 150, 150)
		buyButton.ImageColor3 = Color3.fromRGB(150, 150, 150)
	elseif owned then
		buyButtonText.Text = "EQUIP"
		buyButton.BackgroundColor3 = Color3.fromRGB(255, 255, 0) -- Yellow (255, 255, 0) after purchased
		buyButton.ImageColor3 = Color3.fromRGB(255, 255, 0)
	else
		buyButtonText.Text = "BUY"
		buyButton.BackgroundColor3 = Color3.fromRGB(0, 170, 0) -- Normal color (0, 170, 0)
		buyButton.ImageColor3 = Color3.fromRGB(0, 170, 0)
	end
end

----------------------------------------------------------------------
-- Fetch player data from server
----------------------------------------------------------------------
local function refreshPlayerData()
	local worldName = getCurrentWorldName()
	itemsList = ShopConfig.GetItems(currentCategory, worldName)
	if currentIndex > #itemsList then
		currentIndex = math.max(1, #itemsList)
	end

	local success, data = pcall(function()
		return getPlayerDataRemote:InvokeServer()
	end)
	if success and data then
		playerData = data
		balanceLabel.Text = FormatNumber(playerData.Coins)
	end
	updateSelectedItem()
end

----------------------------------------------------------------------
-- Category switching
----------------------------------------------------------------------
local function selectCategoryTab(categoryName)
	currentCategory = categoryName
	local worldName = getCurrentWorldName()
	itemsList = ShopConfig.GetItems(currentCategory, worldName)
	currentIndex = 1

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

	updateSelectedItem()
end

----------------------------------------------------------------------
-- Hook Events
----------------------------------------------------------------------

-- Category Tabs
for _, button in ipairs(toolFilters:GetChildren()) do
	if button:IsA("GuiButton") then
		button.Activated:Connect(function()
			selectCategoryTab(button.Name)
		end)
	end
end

-- Carousel Navigation
leftButton.Activated:Connect(function()
	if not itemsList or #itemsList == 0 then return end
	if currentIndex > 1 then
		currentIndex = currentIndex - 1
		updateSelectedItem()
	end
end)

rightButton.Activated:Connect(function()
	if not itemsList or #itemsList == 0 then return end
	if currentIndex < #itemsList then
		currentIndex = currentIndex + 1
		updateSelectedItem()
	end
end)

-- Buy/Equip Button
buyButton.Activated:Connect(function()
	local item = itemsList[currentIndex]
	if not item then return end

	local owned = isOwned(currentCategory, item.Name)
	local equipped = isEquipped(currentCategory, item.Name)

	if equipped then return end

	if owned then
		-- Equip it
		equipRemote:FireServer(currentCategory, item.Name)
		task.wait(0.1)
		refreshPlayerData()
	else
		-- Client check: no money
		local coins = (playerData and playerData.Coins) or (player:GetAttribute("Coins") or 0)
		if coins < item.Price then
			playErrorSound() -- Plays 101618216035709
			
			isTempRed = true
			buyButton.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
			buyButton.ImageColor3 = Color3.fromRGB(255, 0, 0)
			
			-- Display popup message with OK button instructing player to sell blocks to Collector
			if _G.Message and _G.Message.New then
				_G.Message.New("You do not have enough money! Sell more blocks to the Collector to get more coins.", false, "Not Enough Coins")
			end
			
			task.delay(2, function()
				isTempRed = false
				if buyButton and buyButton.Parent then
					buyButton.BackgroundColor3 = Color3.fromRGB(0, 170, 0)
					buyButton.ImageColor3 = Color3.fromRGB(0, 170, 0)
					updateSelectedItem()
				end
			end)
			return
		end

		-- Buy it
		local result = buyItemRemote:InvokeServer(currentCategory, item.Name)
		if result and result.Success then
			playPurchaseSound() -- Plays 102314941670514
			
			-- Set button color to Yellow (255, 255, 0) after purchased
			buyButton.BackgroundColor3 = Color3.fromRGB(255, 255, 0)
			buyButton.ImageColor3 = Color3.fromRGB(255, 255, 0)
			
			refreshPlayerData()
		else
			local errMsg = result and result.Error or "Purchase failed."
			warn("[ShopController] " .. errMsg)
			
			playErrorSound() -- Plays 101618216035709
			
			isTempRed = true
			buyButton.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
			buyButton.ImageColor3 = Color3.fromRGB(255, 0, 0)
			
			if _G.Message and _G.Message.New then
				_G.Message.New("You do not have enough money! Sell more blocks to the Collector to get more coins.", false, "Not Enough Coins")
			end
			
			task.delay(2, function()
				isTempRed = false
				if buyButton and buyButton.Parent then
					buyButton.BackgroundColor3 = Color3.fromRGB(0, 170, 0)
					buyButton.ImageColor3 = Color3.fromRGB(0, 170, 0)
					updateSelectedItem()
				end
			end)
		end
	end
end)

-- Listen to player attribute changes for instant loadout updates
player.AttributeChanged:Connect(function(attr)
	if attr == "EquippedLauncher" or attr == "EquippedBomb" then
		updateSelectedItem()
	elseif attr == "Coins" then
		balanceLabel.Text = FormatNumber(player:GetAttribute("Coins") or 0)
	elseif attr == "World" then
		local worldName = getCurrentWorldName()
		itemsList = ShopConfig.GetItems(currentCategory, worldName)
		currentIndex = 1
		updateShopWorldGradient()
		updateSelectedItem()
	end
end)

-- Refresh data when Shop opens
gearShopGui.Parent.Changed:Connect(function(prop)
	if prop == "Enabled" and gearShopGui.Parent.Enabled then
		local worldName = getCurrentWorldName()
		itemsList = ShopConfig.GetItems(currentCategory, worldName)
		if currentIndex > #itemsList then
			currentIndex = 1
		end
		updateShopWorldGradient()
		refreshPlayerData()
	end
end)

-- Initial select
selectCategoryTab("Launcher")
updateShopWorldGradient()
refreshPlayerData()
