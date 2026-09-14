--[[
	© DestructionSimulator [2025]
	ExclusiveShopController — Client-side controller for the ExclusiveShop UI, upgrades, and gamepasses.
	Case unboxing & inspection are cleanly delegated to UnboxingController.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")
local TextChatService = game:GetService("TextChatService")

local Player = Players.LocalPlayer
local playerGui = Player:WaitForChild("PlayerGui")

local Library = require(ReplicatedStorage:WaitForChild("Library"))
while not Library.IsLoaded() do
	task.wait()
end
local Save = Library.Save
local Audio = Library.Audio

local ProductsConfig = require(ReplicatedStorage:WaitForChild("Directory"):WaitForChild("Products"):WaitForChild("Products"))
local GamepassesConfig = require(ReplicatedStorage:WaitForChild("Directory"):WaitForChild("Gamepasses"):WaitForChild("Gamepasses"))
local WindowManager = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Client"):WaitForChild("UIFramework"):WaitForChild("WindowManager"))

-- UI References
local exclusiveShopGui = playerGui:WaitForChild("ExclusiveShop", 15) or playerGui:WaitForChild("ExclusiveShop")
local mainFrame = exclusiveShopGui:WaitForChild("Frame"):WaitForChild("Main")
local container = mainFrame:WaitForChild("Container")

local gamepassesFrame = container:WaitForChild("Gamepasses"):WaitForChild("Container")
local magnetBtn = gamepassesFrame:WaitForChild("Magnet")
local runFasterBtn = gamepassesFrame:WaitForChild("RunFaster")
local elitePackBtn = container:WaitForChild("Gamepasses"):WaitForChild("ElitePack")

local boxesFrame = container:WaitForChild("Boxes"):WaitForChild("Container")

-- Audio setup (Respects user SFX setting via Library.Audio)
local clickSoundId = 87485609714706
local purchaseSoundId = 102314941670514

local function playClickSound()
	if Audio and Audio.Play then
		Audio.Play(clickSoundId, script, 1)
	end
end

local function playPurchaseSound()
	if Audio and Audio.Play then
		Audio.Play(purchaseSoundId, playerGui, 1, 1.0)
	end
end

local function addShopButtonHover(btn)
	local uiScale = btn:FindFirstChildOfClass("UIScale")
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Parent = btn
	end

	btn.MouseEnter:Connect(function()
		TweenService:Create(uiScale, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = 1.05}):Play()
	end)

	btn.MouseLeave:Connect(function()
		TweenService:Create(uiScale, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = 1.0}):Play()
	end)
end

----------------------------------------------------------------------
-- TextChatService Chat Tag Hook
----------------------------------------------------------------------
pcall(function()
	TextChatService.OnIncomingMessage = function(message)
		local sourcePlayer = message.TextSource and Players:GetPlayerByUserId(message.TextSource.UserId)
		if sourcePlayer then
			if sourcePlayer:GetAttribute("Elite") then
				local properties = Instance.new("TextChatMessageProperties")
				properties.PrefixText = "<font color='#FFDF00'><b>[Elite]</b></font> " .. message.PrefixText
				return properties
			end
		end
	end
end)

----------------------------------------------------------------------
-- Price and Info Fetching Helper
----------------------------------------------------------------------
local productInfoCache = {}
local function fetchRobuxPrice(productId, infoType)
	if productId == 0 then return "???" end
	infoType = infoType or Enum.InfoType.Product
	local cacheKey = tostring(infoType.Name) .. "_" .. tostring(productId)
	if productInfoCache[cacheKey] then return productInfoCache[cacheKey] end

	local success, info = pcall(function()
		return MarketplaceService:GetProductInfo(productId, infoType)
	end)
	if success and info and info.PriceInRobux then
		productInfoCache[cacheKey] = tostring(info.PriceInRobux)
		return productInfoCache[cacheKey]
	end
	return "???"
end

----------------------------------------------------------------------
-- UI Refreshing
----------------------------------------------------------------------
local function refreshShopUI()
	local playerData = Save.Get(nil, true) -- Fetch fresh copy
	if not playerData then return end

	local upgrades = playerData.UpgradesOwned or {}

	-- 1. Refresh Magnet
	local magnetLevel = upgrades.Magnet or 0
	local magnetBar = magnetBtn:WaitForChild("Progress"):WaitForChild("Bar")
	TweenService:Create(magnetBar, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.new(magnetLevel * 0.2, 0, 1, 0)
	}):Play()

	local magnetPriceLabel = magnetBtn:WaitForChild("Price"):WaitForChild("Robux")
	local magnetRobuxIcon = magnetBtn.Price:WaitForChild("RobuxIcon")

	if magnetLevel >= 5 then
		magnetPriceLabel.Text = "MAX"
		magnetRobuxIcon.Visible = false
	else
		local nextProd = ProductsConfig["Magnet" .. (magnetLevel + 1)]
		local priceText = fetchRobuxPrice(nextProd and nextProd.ID or 0)
		magnetPriceLabel.Text = priceText
		magnetRobuxIcon.Visible = (priceText ~= "???")
	end

	-- 2. Refresh RunFaster
	local runFasterLevel = upgrades.RunFaster or 0
	local runFasterBar = runFasterBtn:WaitForChild("Progress"):WaitForChild("Bar")
	TweenService:Create(runFasterBar, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.new(runFasterLevel * 0.2, 0, 1, 0)
	}):Play()

	local runFasterPriceLabel = runFasterBtn:WaitForChild("Price"):WaitForChild("Robux")
	local runFasterRobuxIcon = runFasterBtn.Price:WaitForChild("RobuxIcon")

	if runFasterLevel >= 5 then
		runFasterPriceLabel.Text = "MAX"
		runFasterRobuxIcon.Visible = false
	else
		local nextProd = ProductsConfig["RunFaster" .. (runFasterLevel + 1)]
		local priceText = fetchRobuxPrice(nextProd and nextProd.ID or 0)
		runFasterPriceLabel.Text = priceText
		runFasterRobuxIcon.Visible = (priceText ~= "???")
	end

	-- 3. Refresh ElitePack
	local ownsElite = upgrades.ElitePack == true
	local elitePriceLabel = elitePackBtn:WaitForChild("Price"):WaitForChild("Robux")
	local eliteRobuxIcon = elitePackBtn.Price:WaitForChild("RobuxIcon")

	if ownsElite then
		elitePriceLabel.Text = "Owned"
		eliteRobuxIcon.Visible = false
	else
		local elitePass = GamepassesConfig["ElitePack"]
		local priceText = fetchRobuxPrice(elitePass and elitePass.ID or 0, Enum.InfoType.GamePass)
		elitePriceLabel.Text = priceText
		eliteRobuxIcon.Visible = (priceText ~= "???")
	end
end

----------------------------------------------------------------------
-- Event Binding
----------------------------------------------------------------------

-- 1. Upgrade purchases handler
local function promptUpgrade(category)
	local playerData = Save.Get(nil, true)
	if not playerData then return end
	local upgrades = playerData.UpgradesOwned or {}

	local level = upgrades[category] or 0
	if level >= 5 then
		if _G.Message and _G.Message.New then
			_G.Message.New("You have already reached the maximum tier for this upgrade!")
		end
		return
	end

	local prodName = category .. (level + 1)
	local config = ProductsConfig[prodName]
	local prodId = config and config.ID or 0

	if prodId ~= 0 then
		MarketplaceService:PromptProductPurchase(Player, prodId)
	else
		if _G.Message and _G.Message.New then
			_G.Message.New(string.format("Configure the Product ID for %s in Products.luau to buy this upgrade!", prodName))
		end
	end
end

magnetBtn.Activated:Connect(function()
	playClickSound()
	promptUpgrade("Magnet")
end)

runFasterBtn.Activated:Connect(function()
	playClickSound()
	promptUpgrade("RunFaster")
end)

elitePackBtn.Activated:Connect(function()
	playClickSound()
	local playerData = Save.Get()
	if playerData and playerData.UpgradesOwned and playerData.UpgradesOwned.ElitePack then
		if _G.Message and _G.Message.New then
			_G.Message.New("You already own the Elite Pack!")
		end
		return
	end

	local elitePass = GamepassesConfig["ElitePack"]
	local passId = elitePass and elitePass.ID or 0

	if passId ~= 0 then
		MarketplaceService:PromptGamePassPurchase(Player, passId)
	else
		if _G.Message and _G.Message.New then
			_G.Message.New("Configure the Gamepass ID for ElitePack in Gamepasses.luau to buy this package!")
		end
	end
end)

-- After a product/gamepass purchase, play victory sound and refresh UI
MarketplaceService.PromptProductPurchaseFinished:Connect(function(_, _, wasPurchased)
	if not wasPurchased then return end
	playPurchaseSound()
	task.spawn(function()
		for _ = 1, 3 do
			task.wait(1.5)
			Save.Get(nil, true)
			refreshShopUI()
		end
	end)
end)

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(_, _, wasPurchased)
	if not wasPurchased then return end
	playPurchaseSound()
	task.spawn(function()
		for _ = 1, 3 do
			task.wait(1.5)
			Save.Get(nil, true)
			refreshShopUI()
		end
	end)
end)

addShopButtonHover(magnetBtn)
addShopButtonHover(runFasterBtn)
addShopButtonHover(elitePackBtn)

-- 2. Box purchases handler (Delegates to UnboxingController for Case Inspection & Roulette Spin)
local function getUnboxingController()
	if _G.UnboxingController then return _G.UnboxingController end
	local start = os.clock()
	while not _G.UnboxingController and (os.clock() - start < 5) do
		task.wait(0.1)
	end
	return _G.UnboxingController
end

for _, boxBtn in ipairs(boxesFrame:GetChildren()) do
	if boxBtn:IsA("TextButton") then
		addShopButtonHover(boxBtn)
		boxBtn.Activated:Connect(function()
			playClickSound()
			local boxName = boxBtn:GetAttribute("BoxName") or boxBtn.Name
			local priceText = boxBtn:FindFirstChild("Price") and boxBtn.Price:FindFirstChild("Value") and boxBtn.Price.Value.Text or "0"
			local price = tonumber(priceText) or 0
			local icon = boxBtn:FindFirstChild("Icon") or boxBtn:FindFirstChild("SideIcon") or boxBtn:FindFirstChildOfClass("ImageLabel")
			local imageId = icon and icon.Image or ""

			local unboxing = getUnboxingController()
			if unboxing and unboxing.InspectBox then
				exclusiveShopGui.Enabled = false
				unboxing.InspectBox(boxName, imageId, price, function()
					exclusiveShopGui.Enabled = true
					WindowManager.Open(exclusiveShopGui)
					_G.ImportantWindow = exclusiveShopGui
				end)
			else
				warn("[ExclusiveShopController] UnboxingController not available yet")
			end
		end)
	end
end

-- Refresh UI when shop opens
exclusiveShopGui:GetPropertyChangedSignal("Enabled"):Connect(function()
	if exclusiveShopGui.Enabled then
		refreshShopUI()
	end
end)

-- Initial UI setup on spawn
task.spawn(function()
	task.wait(1)
	refreshShopUI()
end)

----------------------------------------------------------------------
-- Layout Resolution Scaling (to eliminate blank gaps between frames)
----------------------------------------------------------------------
local originalValues = {}
local function getOriginalValue(instance, propertyName)
	if not originalValues[instance] then
		originalValues[instance] = {}
	end
	if originalValues[instance][propertyName] == nil then
		originalValues[instance][propertyName] = instance[propertyName]
	end
	return originalValues[instance][propertyName]
end

local function SizeFrame(frame)
	local rScale = Library.Functions.ResolutionScale()
	local totalSizeY = 1
	for _, child in ipairs(frame:GetChildren()) do
		if child.ClassName == "UIPadding" then
			local originalPaddingTop = getOriginalValue(child, "PaddingTop")
			local originalPaddingBottom = getOriginalValue(child, "PaddingBottom")
			child.PaddingTop = UDim.new(originalPaddingTop.Scale, originalPaddingTop.Offset * rScale)
			child.PaddingBottom = UDim.new(originalPaddingBottom.Scale, originalPaddingBottom.Offset * rScale)
			totalSizeY = totalSizeY + (child.PaddingTop.Offset + child.PaddingBottom.Offset)
			continue
		end

		if child.ClassName ~= "UIListLayout" and child.ClassName ~= "UIGridLayout" then
			continue
		end

		totalSizeY = totalSizeY + child.AbsoluteContentSize.Y

		if child.ClassName == "UIListLayout" then
			local originalPadding = getOriginalValue(child, "Padding")
			child.Padding = UDim.new(originalPadding.Scale, originalPadding.Offset * rScale)
		elseif child.ClassName == "UIGridLayout" then
			local originalCellPadding = getOriginalValue(child, "CellPadding")
			child.CellPadding = UDim2.new(originalCellPadding.X.Scale, originalCellPadding.X.Offset * rScale, originalCellPadding.Y.Scale, originalCellPadding.Y.Offset * rScale)
		end

		if child.ClassName == "UIGridLayout" and child:FindFirstChildOfClass("UIAspectRatioConstraint") then
			child.CellSize = UDim2.new(child.CellSize.X.Scale, child.CellSize.X.Offset, 0, child.AbsoluteCellSize.Y + 2)
		end
	end
	frame.Size = UDim2.new(frame.Size.X.Scale, frame.Size.X.Offset, 0, totalSizeY)
end

local function Scrollbar()
	local UIListLayout = container:FindFirstChildOfClass("UIListLayout")
	local UIPadding = container:FindFirstChildOfClass("UIPadding")
	if not UIListLayout then return end
	local paddingOffset = UIPadding and (UIPadding.PaddingTop.Offset + UIPadding.PaddingBottom.Offset) or 0
	local totalY = UIListLayout.AbsoluteContentSize.Y + paddingOffset
	container.CanvasSize = UDim2.new(0, 0, 0, totalY)
end

local function Scaling()
	if not exclusiveShopGui.Enabled then return end
	local isCompact = game.Workspace.CurrentCamera.ViewportSize.Y <= 1000
	local aspectConstraint = exclusiveShopGui.Frame:FindFirstChildOfClass("UIAspectRatioConstraint")
	if aspectConstraint then
		aspectConstraint.AspectRatio = isCompact and 1.6 or 1.2
	end

	local tabs = exclusiveShopGui.Frame:FindFirstChild("Tabs")
	if tabs then
		tabs.Size = isCompact and UDim2.new(0.075, 0, 0.6, 0) or UDim2.new(0.075, 0, 0.039, 0)
	end

	for _, child in ipairs(container:GetChildren()) do
		if not child:IsA("GuiObject") then continue end
		for _, subChild in ipairs(child:GetChildren()) do
			if subChild:FindFirstChildOfClass("UIListLayout") or subChild:FindFirstChildOfClass("UIGridLayout") then
				SizeFrame(subChild)
			end
		end
		SizeFrame(child)
	end
	Scrollbar()
end

task.spawn(function()
	while true do
		task.wait()
		pcall(Scaling)
	end
end)
