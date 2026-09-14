--[[
	© DestructionSimulator [2025]
	UnboxingController — Client-side controller for Case Inspection and Roulette Spin (ScreenGui.Spin).
	Handles case drop inspection, 60 FPS roulette spin animation, sound synchronization, and win screen.
]]--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local Player = Players.LocalPlayer
local playerGui = Player:WaitForChild("PlayerGui")

local Library = require(ReplicatedStorage:WaitForChild("Library"))
while not Library.IsLoaded() do
	task.wait()
end

local Network = Library.Network
local Audio = Library.Audio
local ShopConfig = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("ShopConfig"))
local InfoOverlay = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Client"):WaitForChild("InfoOverlay"))
local WindowManager = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Client"):WaitForChild("UIFramework"):WaitForChild("WindowManager"))
local ViewportUtil = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Client"):WaitForChild("ViewportUtil"))
local FormatNumber = Library.Functions.FormatNumber or require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Functions"):WaitForChild("FormatNumber"))

-- UI References for ScreenGui.Spin
local caseInspectGui = playerGui:WaitForChild("Spin", 15) or playerGui:WaitForChild("Spin")
local inspectFrame = caseInspectGui:WaitForChild("Frame")

local caseFrame = inspectFrame:WaitForChild("Case")
local caseMain = caseFrame:WaitForChild("Main")
local caseTitle = caseMain:WaitForChild("Title")
local caseIcon = caseMain:WaitForChild("SideIcon")
local casePriceVal = caseMain:WaitForChild("Price"):WaitForChild("Value")
local caseTypesGrid = caseMain:WaitForChild("Types"):WaitForChild("Normal")
local caseBuyBtn = caseMain:WaitForChild("Buy")
local caseBackBtn = caseMain:FindFirstChild("Back") or caseMain:WaitForChild("Back")
local caseCloseBtn = caseFrame:WaitForChild("Close")

local unboxingFrame = inspectFrame:WaitForChild("Unboxing")
local unboxingLine = unboxingFrame:WaitForChild("Line")
local unboxingContainer = unboxingFrame:WaitForChild("Container")

local skinWinBtn = inspectFrame:WaitForChild("SkinWin")

local uiAssets = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("UI")
local gradientFolder = uiAssets:WaitForChild("Gradient", 5) or uiAssets:FindFirstChild("Gradient")
local raritysFolder = (gradientFolder and (gradientFolder:WaitForChild("Raritys", 5) or gradientFolder:FindFirstChild("Raritys")))
	or uiAssets:WaitForChild("Raritys", 5)
	or uiAssets:FindFirstChild("Raritys")

local raritySortOrder = {
	Basic = 80,
	IndustrialGrade = 70,
	MilSpec = 60,
	Restricted = 50,
	Legendary = 40,
	Convert = 30,
	Secret = 20,
	Delux = 10,
}

local clickSoundId = 87485609714706
local spinSoundId = 90584352448447
local buySoundId = 102314941670514

local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")

local spinTickPool = {}
for i = 1, 3 do
	local snd = Instance.new("Sound")
	snd.Name = "SpinTick_" .. i
	snd.SoundId = "rbxassetid://" .. spinSoundId
	snd.Volume = 0.65
	snd.PlaybackSpeed = 1
	snd.Parent = SoundService
	table.insert(spinTickPool, snd)
end
local spinTickIdx = 1

local function playRouletteTick()
	local snd = spinTickPool[spinTickIdx]
	spinTickIdx = (spinTickIdx % #spinTickPool) + 1
	snd.TimePosition = 0
	snd:Play()
end

local buySound = Instance.new("Sound")
buySound.Name = "BoxBuySound"
buySound.SoundId = "rbxassetid://" .. buySoundId
buySound.Volume = 1.0
buySound.PlaybackSpeed = 1
buySound.Parent = SoundService

local function playBuySound()
	if buySound then
		buySound.TimePosition = 0
		buySound:Play()
	elseif Audio and Audio.Play then
		Audio.Play(buySoundId, SoundService, 1, 1.0)
	end
end

task.spawn(function()
	ContentProvider:PreloadAsync({ buySound, unpack(spinTickPool) })
end)

local function playClickSound()
	if Audio and Audio.Play then
		Audio.Play(clickSoundId, script, 1)
	end
end

----------------------------------------------------------------------
-- Box Pool & Pyramid Generation
----------------------------------------------------------------------
local BOX_NAMES = {
	"Essential Core", "Essential Vanguard", "Essential Bastion",
	"Forge Core", "Forge Vanguard", "Forge Bastion",
	"Elite Core", "Elite Vanguard", "Elite Bastion",
}

local SKIN_RARITIES_MAP = {
	["Safari"] = "Basic",
	["Boreal Forest"] = "Basic",
	["Sand Dune"] = "IndustrialGrade",
	["Urban DDPTA"] = "MilSpec",
	["Neo Fade"] = "Restricted",
	["Pit Viber"] = "Legendary",
	["Gungnir"] = "Convert",
	["Elite Build"] = "Delux",
}

local BOX_ITEMS = {}

local function buildBoxPyramid(possibleSkins, rng)
	local byRarity = {
		Basic = {}, IndustrialGrade = {}, MilSpec = {},
		Restricted = {}, Legendary = {}, Convert = {}, Delux = {},
	}
	for _, skin in ipairs(possibleSkins) do
		table.insert(byRarity[skin.Rarity], skin)
	end

	for rarity, list in pairs(byRarity) do
		for i = #list, 2, -1 do
			local j = rng:NextInteger(1, i)
			list[i], list[j] = list[j], list[i]
		end
	end

	local selected = {}
	local function take(rarity, count)
		local list = byRarity[rarity]
		for i = 1, math.min(count, #list) do
			table.insert(selected, table.remove(list, 1))
		end
	end

	take("Basic", 5)
	take("IndustrialGrade", 4)
	take("MilSpec", 3)
	take("Restricted", 2)

	if #byRarity.Convert > 0 then
		take("Convert", 1)
	elseif #byRarity.Delux > 0 then
		take("Delux", 1)
	else
		take("Legendary", 1)
	end

	local remainingRarities = { "Basic", "IndustrialGrade", "MilSpec", "Restricted", "Legendary", "Covert", "Delux" }
	while #selected < 15 do
		local added = false
		for _, rarity in ipairs(remainingRarities) do
			if byRarity[rarity] and #byRarity[rarity] > 0 then
				table.insert(selected, table.remove(byRarity[rarity], 1))
				added = true
				break
			end
		end
		if not added then break end
	end

	return selected
end

local function initializeBoxes()
	local rng = Random.new(12345)

	local allWeapons = {}
	for _, item in ipairs(ShopConfig.Launcher) do
		table.insert(allWeapons, { Category = "Launcher", Name = item.Name })
	end
	for _, item in ipairs(ShopConfig.Bomb) do
		table.insert(allWeapons, { Category = "Bomb", Name = item.Name })
	end

	for i = #allWeapons, 2, -1 do
		local j = rng:NextInteger(1, i)
		allWeapons[i], allWeapons[j] = allWeapons[j], allWeapons[i]
	end

	local allBackpacks = {}
	for _, bp in ipairs(ShopConfig.BackPack) do
		table.insert(allBackpacks, bp.Name)
	end

	for i = #allBackpacks, 2, -1 do
		local j = rng:NextInteger(1, i)
		allBackpacks[i], allBackpacks[j] = allBackpacks[j], allBackpacks[i]
	end

	for idx, boxName in ipairs(BOX_NAMES) do
		local weaponsCount = (idx <= 6) and 4 or 6
		local boxWeapons = {}
		for _ = 1, weaponsCount do
			if #allWeapons > 0 then
				table.insert(boxWeapons, table.remove(allWeapons, 1))
			end
		end

		local possibleSkins = {}
		for _, w in ipairs(boxWeapons) do
			for skinName, rarity in pairs(SKIN_RARITIES_MAP) do
				table.insert(possibleSkins, {
					ItemName = w.Name,
					Category = w.Category,
					ID = skinName,
					Rarity = rarity,
				})
			end
		end

		local weaponSkins = buildBoxPyramid(possibleSkins, rng)

		local specialBps = {}
		local bp1 = allBackpacks[((idx-1)*2) % #allBackpacks + 1]
		local bp2 = allBackpacks[((idx-1)*2 + 1) % #allBackpacks + 1]
		table.insert(specialBps, bp1)
		table.insert(specialBps, bp2)

		BOX_ITEMS[boxName] = {
			WeaponSkins = weaponSkins,
			SpecialBackpacks = specialBps,
		}
	end
end

initializeBoxes()

local function applyRarityGradient(template, rarityName)
	local rarityGrad = template:FindFirstChild("RarityGradient")
	if rarityGrad then
		for _, child in ipairs(rarityGrad:GetChildren()) do
			if child:IsA("UIGradient") then child:Destroy() end
		end
		local grad = raritysFolder:FindFirstChild(rarityName)
			or (rarityName == "Covert" and raritysFolder:FindFirstChild("Convert"))
			or (rarityName == "Convert" and raritysFolder:FindFirstChild("Covert"))
		if grad and grad:IsA("UIGradient") then
			grad:Clone().Parent = rarityGrad
		end
	end
end

----------------------------------------------------------------------
-- Unboxing Controller State
----------------------------------------------------------------------
local UnboxingController = {}

local activeBoxName = ""
local activeBoxImage = ""
local activeBoxPrice = 0
local isPurchasingBox = false
local currentBackCallback = nil

--- Plays the CS:GO style roulette spin animation
local function playBoxOpeningSpin(result)
	caseFrame.Visible = false
	unboxingFrame.Visible = true
	skinWinBtn.Visible = false
	unboxingLine.BackgroundTransparency = 0

	for _, child in ipairs(unboxingContainer:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	task.wait()

	local selectedSlot = nil
	local selectedSlotIndex = 1
	local template = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("UI"):WaitForChild("Spin"):WaitForChild("SkinUnboxing")

	local frameWidth = unboxingFrame.AbsoluteSize.X
	if frameWidth <= 0 then
		frameWidth = (unboxingFrame.Parent and unboxingFrame.Parent.AbsoluteSize.X > 0) and unboxingFrame.Parent.AbsoluteSize.X or 600
	end
	local slotWidth = math.floor(frameWidth * 0.22)
	local slotSpacing = math.clamp(math.floor(frameWidth * 0.015), 6, 12)

	for idx, slotData in ipairs(result.SpinSlots) do
		local newSlot = template:Clone()
		newSlot.Size = UDim2.new(0, slotWidth, 0.88, 0)

		local rarityName = (slotData.Rarity == "Special") and "Secret" or slotData.Rarity
		newSlot.SkinName.Text = slotData.ID
		newSlot.LayoutOrder = slotData.LayoutOrder or idx
		newSlot.Visible = true

		applyRarityGradient(newSlot, rarityName)

		local GearIcon = newSlot:FindFirstChild("GearIcon")
		if GearIcon then
			local secretLbl = GearIcon:FindFirstChild("Secret")
			if secretLbl then
				secretLbl.Visible = (rarityName == "Secret")
			end

			if rarityName ~= "Secret" then
				local baseModel = ViewportUtil.GetModel(slotData.Category, slotData.ItemName)
				if baseModel then
					local previewModel = baseModel:Clone()
					local success, skinConfig = pcall(function()
						return require(ReplicatedStorage:WaitForChild("Directory"):WaitForChild("Skins"):WaitForChild(slotData.Category):WaitForChild(slotData.ItemName):WaitForChild(slotData.ID))
					end)
					if success and skinConfig and skinConfig.textureId then
						for _, part in ipairs(previewModel:GetDescendants()) do
							if part:IsA("MeshPart") then
								part.TextureID = "rbxassetid://" .. skinConfig.textureId
							elseif part:IsA("Mesh") or part:IsA("SpecialMesh") then
								part.TextureId = "rbxassetid://" .. skinConfig.textureId
							elseif part:IsA("Texture") or part:IsA("Decal") then
								part.Texture = "rbxassetid://" .. skinConfig.textureId
							end
						end
					end
					ViewportUtil.Create(previewModel, GearIcon, slotData.Category)
					previewModel:Destroy()
				end
			else
				for _, child in ipairs(GearIcon:GetChildren()) do
					if child ~= secretLbl then child:Destroy() end
				end
			end
		end

		if slotData.IsSelected then
			newSlot.Name = "SelectedSlot"
			selectedSlot = newSlot
			selectedSlotIndex = idx
		end
		newSlot.Parent = unboxingContainer
	end

	if not selectedSlot then
		warn("[UnboxingController] No selected slot found in spin data!")
		unboxingFrame.Visible = false
		caseFrame.Visible = true
		return
	end

	local pageLayout = unboxingContainer:FindFirstChildOfClass("UIPageLayout")
	if pageLayout then
		pageLayout:Destroy()
	end

	local listLayout = unboxingContainer:FindFirstChildOfClass("UIListLayout")
	if not listLayout then
		listLayout = Instance.new("UIListLayout")
		listLayout.Parent = unboxingContainer
	end
	listLayout.FillDirection = Enum.FillDirection.Horizontal
	listLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, slotSpacing)

	unboxingContainer.AnchorPoint = Vector2.new(0, 0.5)
	unboxingContainer.Size = UDim2.new(0, (#result.SpinSlots + 2) * (slotWidth + slotSpacing), 0.9, 0)

	local lineCenterX = math.floor(frameWidth * 0.505)
	local startX = math.floor(lineCenterX - slotWidth / 2)
	local targetX = math.floor(lineCenterX - ((selectedSlotIndex - 1) * (slotWidth + slotSpacing) + slotWidth / 2))

	unboxingContainer.Position = UDim2.new(0, startX, 0.5, 0)

	local pitch = slotWidth + slotSpacing
	local lastSlotPassed = 0
	local spinConnection = nil
	spinConnection = RunService.RenderStepped:Connect(function()
		if not unboxingContainer or not unboxingContainer.Parent or not unboxingFrame.Visible then
			if spinConnection then
				spinConnection:Disconnect()
				spinConnection = nil
			end
			return
		end
		local currentX = unboxingContainer.Position.X.Offset
		local dist = startX - currentX
		local currentSlotPassed = math.floor((dist + pitch * 0.5) / pitch)
		if currentSlotPassed > lastSlotPassed then
			lastSlotPassed = currentSlotPassed
			playRouletteTick()
		end
	end)

	local spinTween = TweenService:Create(
		unboxingContainer,
		TweenInfo.new(4.2, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0, targetX, 0.5, 0) }
	)
	spinTween:Play()

	spinTween.Completed:Connect(function()
		if spinConnection then
			spinConnection:Disconnect()
			spinConnection = nil
		end

		for _, slot in ipairs(unboxingContainer:GetChildren()) do
			if slot:IsA("GuiObject") and slot ~= selectedSlot then
				TweenService:Create(slot, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 1}):Play()
				local gear = slot:FindFirstChild("GearIcon")
				if gear then
					TweenService:Create(gear, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {ImageTransparency = 1}):Play()
					local vpf = gear:FindFirstChildOfClass("ViewportFrame")
					if vpf then
						TweenService:Create(vpf, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {ImageTransparency = 1}):Play()
					end
				end
				local nameLbl = slot:FindFirstChild("SkinName")
				if nameLbl then
					TweenService:Create(nameLbl, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {TextTransparency = 1}):Play()
				end
			end
		end

		TweenService:Create(unboxingLine, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 1}):Play()

		task.wait(1.5)

		-- Switch to SkinWin frame
		unboxingFrame.Visible = false
		skinWinBtn.Visible = true

		local wonRarity = (result.Rarity == "Special") and "Secret" or result.Rarity
		skinWinBtn.SkinName.Text = result.ItemName .. " | " .. result.ID
		applyRarityGradient(skinWinBtn, wonRarity)

		local winGear = skinWinBtn:WaitForChild("GearIcon")
		local secretLbl = winGear:FindFirstChild("Secret")
		if secretLbl then
			secretLbl.Visible = (wonRarity == "Secret")
		end

		for _, child in ipairs(winGear:GetChildren()) do
			if child:IsA("ViewportFrame") then
				child:Destroy()
			end
		end

		local winModelClone = nil
		local modelSpinConnection = nil

		if wonRarity ~= "Secret" then
			local baseModel = ViewportUtil.GetModel(result.Category, result.ItemName)
			if baseModel then
				local previewModel = baseModel:Clone()
				local success, skinConfig = pcall(function()
					return require(ReplicatedStorage:WaitForChild("Directory"):WaitForChild("Skins"):WaitForChild(result.Category):WaitForChild(result.ItemName):WaitForChild(result.ID))
				end)
				if success and skinConfig and skinConfig.textureId then
					for _, part in ipairs(previewModel:GetDescendants()) do
						if part:IsA("MeshPart") then
							part.TextureID = "rbxassetid://" .. skinConfig.textureId
						elseif part:IsA("Mesh") or part:IsA("SpecialMesh") then
							part.TextureId = "rbxassetid://" .. skinConfig.textureId
						elseif part:IsA("Texture") or part:IsA("Decal") then
							part.Texture = "rbxassetid://" .. skinConfig.textureId
						end
					end
				end
				winModelClone = ViewportUtil.Create(previewModel, winGear, result.Category)
				previewModel:Destroy()

				if winModelClone then
					modelSpinConnection = RunService.RenderStepped:Connect(function(dt)
						if winModelClone.Parent then
							winModelClone:PivotTo(CFrame.Angles(0, dt * 2, 0) * winModelClone:GetPivot())
						end
					end)
				end
			end
		else
			for _, child in ipairs(winGear:GetChildren()) do
				if child ~= secretLbl then child:Destroy() end
			end
		end

		local multMin = 1
		local multMax = 1
		if wonRarity ~= "Secret" then
			local success, skinConfig = pcall(function()
				return require(ReplicatedStorage:WaitForChild("Directory"):WaitForChild("Skins"):WaitForChild(result.Category):WaitForChild(result.ItemName):WaitForChild(result.ID))
			end)
			if success and skinConfig then
				multMin = skinConfig.MultMin or 1
				multMax = skinConfig.MultMax or 1
			end
		end

		local blockDefs = {
			{ "Title", result.ID, wonRarity },
			{ "Nickname", result.ItemName },
			{ "RAP", 0 },
			{ "OwnerCount", "???" },
			{ "Rarity", wonRarity },
		}
		table.insert(blockDefs, { "Power", result.Float, multMin, multMax })

		local hoverEnterConn, hoverLeaveConn
		hoverEnterConn = skinWinBtn.MouseEnter:Connect(function()
			InfoOverlay.Add(skinWinBtn, unpack(blockDefs))
		end)
		hoverLeaveConn = skinWinBtn.MouseLeave:Connect(function()
			InfoOverlay.Remove()
		end)

		local clickConn
		clickConn = skinWinBtn.Activated:Connect(function()
			playClickSound()

			clickConn:Disconnect()
			hoverEnterConn:Disconnect()
			hoverLeaveConn:Disconnect()
			if modelSpinConnection then
				modelSpinConnection:Disconnect()
			end
			InfoOverlay.Remove()

			skinWinBtn.Visible = false
			caseFrame.Visible = true
		end)
	end)
end

--- Opens the Case Inspection modal for a given case
function UnboxingController.InspectBox(boxName: string, boxImage: string, boxPrice: number, onBackCallback: (() -> ())?)
	currentBackCallback = onBackCallback
	WindowManager.Open(caseInspectGui)
	_G.ImportantWindow = caseInspectGui
	caseFrame.Visible = true
	unboxingFrame.Visible = false
	skinWinBtn.Visible = false

	caseTitle.Text = boxName
	caseIcon.Image = boxImage
	casePriceVal.Text = FormatNumber(boxPrice)

	for _, child in ipairs(caseTypesGrid:GetChildren()) do
		if child:IsA("GuiObject") and not child:IsA("UIGridLayout") then
			child:Destroy()
		end
	end

	local boxContent = BOX_ITEMS[boxName]
	if not boxContent then return end

	-- Render Weapon Skins
	for _, skin in ipairs(boxContent.WeaponSkins) do
		local slot = ReplicatedStorage.Assets.UI.Spin.SkinsTemplate:Clone()
		slot.Name = skin.ItemName .. "::" .. skin.ID

		local levelLbl = slot:FindFirstChild("Level")
		if levelLbl then levelLbl.Text = skin.ID end

		slot.LayoutOrder = raritySortOrder[skin.Rarity] or 90
		applyRarityGradient(slot, skin.Rarity)

		local GearIcon = slot:FindFirstChild("GearIcon")
		if GearIcon then
			local secretLbl = GearIcon:FindFirstChild("Secret")
			if secretLbl then secretLbl.Visible = false end

			local baseModel = ViewportUtil.GetModel(skin.Category, skin.ItemName)
			if baseModel then
				local previewModel = baseModel:Clone()
				local success, skinConfig = pcall(function()
					return require(ReplicatedStorage:WaitForChild("Directory"):WaitForChild("Skins"):WaitForChild(skin.Category):WaitForChild(skin.ItemName):WaitForChild(skin.ID))
				end)
				if success and skinConfig and skinConfig.textureId then
					for _, part in ipairs(previewModel:GetDescendants()) do
						if part:IsA("MeshPart") then
							part.TextureID = "rbxassetid://" .. skinConfig.textureId
						elseif part:IsA("Mesh") or part:IsA("SpecialMesh") then
							part.TextureId = "rbxassetid://" .. skinConfig.textureId
						elseif part:IsA("Texture") or part:IsA("Decal") then
							part.Texture = "rbxassetid://" .. skinConfig.textureId
						end
					end
				end
				ViewportUtil.Create(previewModel, GearIcon, skin.Category)
				previewModel:Destroy()
			end
		end
		slot.Parent = caseTypesGrid
	end

	-- Render Special Backpacks
	for _, bpName in ipairs(boxContent.SpecialBackpacks) do
		local slot = ReplicatedStorage.Assets.UI.Spin.SkinsTemplate:Clone()
		slot.Name = bpName .. "::Secret"

		local levelLbl = slot:FindFirstChild("Level")
		if levelLbl then levelLbl.Text = "Secret" end

		slot.LayoutOrder = raritySortOrder["Secret"] or 20
		applyRarityGradient(slot, "Secret")

		local GearIcon = slot:FindFirstChild("GearIcon")
		if GearIcon then
			local secretLbl = GearIcon:FindFirstChild("Secret")
			if secretLbl then secretLbl.Visible = true end

			for _, child in ipairs(GearIcon:GetChildren()) do
				if child ~= secretLbl then child:Destroy() end
			end
		end
		slot.Parent = caseTypesGrid
	end

	activeBoxName = boxName
	activeBoxImage = boxImage
	activeBoxPrice = boxPrice
	isPurchasingBox = false
end

-- Buy Box button handler
caseBuyBtn.Activated:Connect(function()
	if isPurchasingBox or activeBoxName == "" then return end
	playClickSound()

	local boxName = activeBoxName
	local boxPrice = activeBoxPrice

	local confirm = _G.Message.New(string.format("Open the %s Box for %d Contracts?", boxName, boxPrice), true)
	if confirm then
		isPurchasingBox = true

		local success, result = Network.Invoke("BuyBox", boxName)
		if success then
			playBuySound()
			task.wait(0.15)
			playBoxOpeningSpin(result)
		else
			_G.Message.New(result or "Failed to open box!")
		end
		isPurchasingBox = false
	end
end)

-- Back and Close button handlers
if caseBackBtn then
	caseBackBtn.Activated:Connect(function()
		playClickSound()
		caseInspectGui.Enabled = false
		if currentBackCallback then
			currentBackCallback()
			currentBackCallback = nil
		else
			WindowManager.Close()
			_G.ImportantWindow = nil
		end
	end)
end

caseCloseBtn.Activated:Connect(function()
	playClickSound()
	caseInspectGui.Enabled = false
	WindowManager.Close()
	_G.ImportantWindow = nil
	currentBackCallback = nil
end)

_G.UnboxingController = UnboxingController
return UnboxingController
