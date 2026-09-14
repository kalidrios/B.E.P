--[[
	© DestructionSimulator [2025]
	InventoryController — Client-side inventory management.
	Handles displaying owned weapons/backpacks, equipping weapons/backpacks, and viewport previews.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local assets = ReplicatedStorage:WaitForChild("Assets")

local InventoryUtil = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Modules"):WaitForChild("InventoryUtil"))
local ViewportUtil = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Client"):WaitForChild("ViewportUtil"))
local Audio = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Audio"))

local inventoryScreen = playerGui:WaitForChild("Inventory", 15) or playerGui:WaitForChild("Inventory")
local inventoryGui = inventoryScreen:WaitForChild("Frame"):WaitForChild("Main")
local toolFilters = inventoryGui:WaitForChild("Tool"):WaitForChild("Normal")
local typesGrid = inventoryGui:WaitForChild("Types"):WaitForChild("Normal")
local skinsGrid = inventoryGui:WaitForChild("Skins"):WaitForChild("Normal")
local skinsLayout = skinsGrid:WaitForChild("UIGridLayout", 5)
if skinsLayout then
	skinsLayout.SortOrder = Enum.SortOrder.LayoutOrder
end
local typesScroll = inventoryGui:WaitForChild("Types")
local skinsScroll = inventoryGui:WaitForChild("Skins")
local uiInventory = assets:WaitForChild("UI", 5) and assets.UI:WaitForChild("Inventory", 5)
local typesTemplate = uiInventory
	and (
		uiInventory:FindFirstChild("TypesTemplate")
		or uiInventory:FindFirstChild("TypeTemplate")
		or uiInventory:FindFirstChild("Offer")
	)
local skinsTemplate = uiInventory
	and (
		uiInventory:FindFirstChild("SkinsTemplate")
		or uiInventory:FindFirstChild("Skin")
		or uiInventory:FindFirstChild("Offer")
	)
local raritysFolder = (assets:FindFirstChild("UI") and assets.UI:FindFirstChild("Gradient") and assets.UI.Gradient:FindFirstChild("Raritys"))
	or (assets:FindFirstChild("UI") and (assets.UI:FindFirstChild("Raritys") or assets.UI:FindFirstChild("Rarities")))

local WindowManager = require(
	ReplicatedStorage:WaitForChild("Library")
		:WaitForChild("Client")
		:WaitForChild("UIFramework")
		:WaitForChild("WindowManager")
)
local ShopConfig = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("ShopConfig"))
local SkinMath = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Modules"):WaitForChild("SkinMath"))
local InfoOverlay =
	require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Client"):WaitForChild("InfoOverlay"))

local remotes = Workspace:WaitForChild("__THINGS"):WaitForChild("__REMOTES")
local equipRemote = remotes:FindFirstChild("EquipItem")
if not equipRemote then
	equipRemote = Instance.new("RemoteEvent")
	equipRemote.Name = "EquipItem"
	equipRemote.Parent = remotes
end
local getPlayerDataRemote = remotes:WaitForChild("GetPlayerData")

local currentCategory = nil
local currentType = nil
local searchQuery = ""
-- Re-entry guard: onOpen can fire twice for a single open (ScreenGui.Enabled
-- and Frame.Visible both change) and populateTypes yields on InvokeServer;
-- two concurrent renders duplicate every skin row. Every render bumps the
-- token and any older render aborts as soon as it notices it is stale.
local renderToken = 0
local equippedItems = { Launcher = nil, Bomb = nil, BackPack = nil }

local searchFrame = inventoryGui:FindFirstChild("Search")
local searchInput = searchFrame and (searchFrame:FindFirstChild("Query") or searchFrame:FindFirstChildOfClass("TextBox"))
local deleteSelectBtn = searchFrame and (searchFrame:FindFirstChild("DeleteSelect") or searchFrame:FindFirstChild("Delete Select"))
local deleteBtn = searchFrame and searchFrame:FindFirstChild("Delete")
local backBtn = searchFrame and searchFrame:FindFirstChild("Back")

local isDeleteMode = false
local selectedDeleteUids = {}

local playerData = {
	Weapons = {},
	Backpacks = {},
	EquippedBackpack = "SmallBag",
}

local mainGui = playerGui:WaitForChild("Main")
local toolbar = mainGui:WaitForChild("Frame"):WaitForChild("Toolbar")

local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local function updateInventoryLayouts()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local viewport = camera.ViewportSize
	local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

	local preset = "PC"
	if isMobile then
		if viewport.X >= 1150 or viewport.Y >= 800 then
			preset = "Notebook"
		else
			preset = "Mobile"
		end
	else
		if viewport.X < 1650 then
			preset = "Notebook"
		else
			preset = "PC"
		end
	end

	local tGrid = inventoryGui:FindFirstChild("Types") and inventoryGui.Types:FindFirstChild("Normal")
	local sGrid = inventoryGui:FindFirstChild("Skins") and inventoryGui.Skins:FindFirstChild("Normal")

	if tGrid then
		local gridLayout = tGrid:FindFirstChildOfClass("UIGridLayout")
		local uiPadding = tGrid:FindFirstChildOfClass("UIPadding")
			or (tGrid.Parent and tGrid.Parent:FindFirstChildOfClass("UIPadding"))

		if gridLayout then
			if preset == "Mobile" then
				gridLayout.CellPadding = UDim2.new(0, 15, 0, 20)
				gridLayout.CellSize = UDim2.new(0, 50, 0, 50)
				if uiPadding then
					uiPadding.PaddingLeft = UDim.new(0, 10)
				end
			elseif preset == "Notebook" then -- 1280 & 1366
				gridLayout.CellPadding = UDim2.new(0, 20, 0, 30)
				gridLayout.CellSize = UDim2.new(0, 100, 0, 100)
				if uiPadding then
					uiPadding.PaddingLeft = UDim.new(0, 18)
				end
			else -- PC (>1650)
				gridLayout.CellPadding = UDim2.new(0, 20, 0, 30)
				gridLayout.CellSize = UDim2.new(0, 110, 0, 110)
				if uiPadding then
					uiPadding.PaddingLeft = UDim.new(0, 23)
				end
			end
		end
	end

	if sGrid then
		local gridLayout = sGrid:FindFirstChildOfClass("UIGridLayout")
		local uiPadding = sGrid:FindFirstChildOfClass("UIPadding")
			or (sGrid.Parent and sGrid.Parent:FindFirstChildOfClass("UIPadding"))

		if gridLayout then
			if preset == "Mobile" then
				gridLayout.CellPadding = UDim2.new(0, 20, 0, 15)
				gridLayout.CellSize = UDim2.new(0, 74, 0, 74)
				if uiPadding then
					uiPadding.PaddingLeft = UDim.new(0, 10)
				end
			elseif preset == "Notebook" then -- 1280 & 1366
				gridLayout.CellPadding = UDim2.new(0, 20, 0, 30)
				gridLayout.CellSize = UDim2.new(0, 100, 0, 100)
				if uiPadding then
					uiPadding.PaddingLeft = UDim.new(0, 18)
				end
			else -- PC (>1650)
				gridLayout.CellPadding = UDim2.new(0, 20, 0, 30)
				gridLayout.CellSize = UDim2.new(0, 125, 0, 120)
				if uiPadding then
					uiPadding.PaddingLeft = UDim.new(0, 10)
				end
			end
		end
	end
end

Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateInventoryLayouts)
task.defer(updateInventoryLayouts)

local function clearGrid(grid)
	for _, child in ipairs(grid:GetChildren()) do
		if not child:IsA("UIPadding") and not child:IsA("UIGridLayout") and not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
end

local function createViewport(model, parent, category)
	return ViewportUtil.Create(model, parent, category)
end

local function updateToolbarIcon(category, model, skinName)
	local slotName = (category == "Launcher") and "ROCKET" or (category == "Bomb") and "BOMB" or nil
	if not slotName then
		return
	end

	local slotFrame = toolbar:FindFirstChild(slotName)
	if slotFrame then
		local imageFrame = slotFrame:FindFirstChild("Frame")
		if imageFrame then
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

			local previewModel = model:Clone()
			if skinName and skinName ~= "Default" then
				local dirFolder = ReplicatedStorage:WaitForChild("Directory")
				local success, skinConfig = pcall(function()
					return require(
						dirFolder
							:WaitForChild("Skins")
							:WaitForChild(category)
							:WaitForChild(model.Name)
							:WaitForChild(skinName)
					)
				end)
				if success and skinConfig and skinConfig.textureId then
					for _, part in ipairs(previewModel:GetDescendants()) do
						if part:IsA("MeshPart") then
							part.TextureID = "rbxassetid://" .. skinConfig.textureId
						elseif part:IsA("SpecialMesh") then
							part.TextureId = "rbxassetid://" .. skinConfig.textureId
						elseif part:IsA("Texture") or part:IsA("Decal") then
							part.Texture = "rbxassetid://" .. skinConfig.textureId
						end
					end
				end
			end

			createViewport(previewModel, viewportContainer, category)
			previewModel:Destroy()

			local vpf = viewportContainer:FindFirstChildOfClass("ViewportFrame")
			if vpf then
				vpf.ZIndex = 5
			end
		end

		local toolNameLabel = slotFrame:FindFirstChild("toolName")
		if toolNameLabel then
			toolNameLabel.Text = model.Name
		end
	end
end

local function isEquipped(category, name)
	if category == "Launcher" then
		return player:GetAttribute("EquippedLauncher") == name
	elseif category == "Bomb" then
		return player:GetAttribute("EquippedBomb") == name
	elseif category == "BackPack" then
		return playerData.EquippedBackpack == name
	end
	return false
end

local function refreshEquippedIndicators()
	-- Update typesGrid items
	for _, child in ipairs(typesGrid:GetChildren()) do
		if child:IsA("GuiObject") then
			local lbl = child:FindFirstChild("Equipped")
			if lbl then
				local itemName = string.gsub(child.Name, "_Type$", "")
				lbl.Visible = isEquipped(currentCategory, itemName)
			end
		end
	end

	-- Update skinsGrid items
	for _, child in ipairs(skinsGrid:GetChildren()) do
		if child:IsA("GuiObject") then
			local lbl = child:FindFirstChild("Equipped")
			if lbl then
				local split = string.split(child.Name, "::")
				if #split == 2 then
					local weaponName = split[1]
					local skinID = split[2]

					local isWeaponEquipped = isEquipped(currentCategory, weaponName)
					if isWeaponEquipped then
						if
							playerData.EquippedSkins
							and playerData.EquippedSkins[currentCategory]
							and playerData.EquippedSkins[currentCategory][weaponName]
						then
							lbl.Visible = (playerData.EquippedSkins[currentCategory][weaponName].ID == skinID)
						else
							lbl.Visible = (skinID == "Default")
						end
					else
						lbl.Visible = false
					end
				else
					lbl.Visible = false
				end
			end
		end
	end
end

local function playErrorSound()
	if Audio and Audio.Play then
		Audio.Play(101618216035709, playerGui, 1, 1.0)
	end
end

local function isOwned(category, name)
	return InventoryUtil.OwnsBaseEquipment(playerData, category, name)
end

local function equipItem(category, modelName, model, skinName)
	-- Master validation check via single source of truth
	local canEquip, err = InventoryUtil.CanEquip(playerData, category, modelName, skinName)
	if not canEquip then
		playErrorSound()
		if _G.Message and _G.Message.New then
			_G.Message.New(
				err or ("You must purchase the " .. modelName .. " in the GearShop first to equip this!"),
				false,
				"GearShop Required"
			)
		end
		return
	end

	if category == "BackPack" then
		local newCapacity = InventoryUtil.GetBackpackCapacity(modelName)

		if playerData.Storage and playerData.Storage.Amount > newCapacity then
			local msg = "You have "
				.. playerData.Storage.Amount
				.. " blocks but this bag only holds "
				.. newCapacity
				.. ".\nYou will lose "
				.. (playerData.Storage.Amount - newCapacity)
				.. " blocks.\nSwitch anyway?"
			local confirm = _G.Message and _G.Message.New(msg, true, "Warning")
			if not confirm then
				return
			end
		end
	end

	-- Synchronous local attribute update for 0ms UI delay
	if category == "Launcher" then
		player:SetAttribute("EquippedLauncher", modelName)
	elseif category == "Bomb" then
		player:SetAttribute("EquippedBomb", modelName)
	elseif category == "BackPack" then
		playerData.EquippedBackpack = modelName
	end

	if not playerData.EquippedSkins then
		playerData.EquippedSkins = {}
	end
	if not playerData.EquippedSkins[category] then
		playerData.EquippedSkins[category] = {}
	end
	playerData.EquippedSkins[category][modelName] = { ID = skinName or "Default" }

	currentType = modelName

	-- Fire server remote
	equipRemote:FireServer(category, modelName, skinName or "Default")

	-- Update toolbar icon
	if model then
		updateToolbarIcon(category, model, skinName or "Default")
	end

	-- Instant visual refresh across both grids
	refreshEquippedIndicators()
end

player:GetAttributeChangedSignal("EquippedLauncher"):Connect(refreshEquippedIndicators)
player:GetAttributeChangedSignal("EquippedBomb"):Connect(refreshEquippedIndicators)

local function addSkinToGrid(modelName, model, category, skinData)
	-- In Delete Mode, hide Default skins completely (they cannot be deleted or count towards capacity)
	if isDeleteMode and skinData == nil then
		return
	end

	local skinTemplate = skinsTemplate:Clone()
	skinTemplate.Name = modelName .. "::" .. (skinData and skinData.ID or "Default")

	local levelText = skinTemplate:FindFirstChild("Level")
	if levelText then
		if skinData then
			levelText.Text = SkinMath.GetConditionShort(skinData.Float) .. " " .. skinData.ID
		else
			levelText.Text = "Default"
		end
	end

	-- Apply rarity gradient and sort order
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

	local rarityName = "Basic"
	if skinData then
		local dirFolder = ReplicatedStorage:WaitForChild("Directory")
		if dirFolder then
			local success, skinConfig = pcall(function()
				return require(
					dirFolder
						:WaitForChild("Skins")
						:WaitForChild(category)
						:WaitForChild(modelName)
						:WaitForChild(skinData.ID)
				)
			end)
			if success and skinConfig then
				rarityName = skinConfig.rarity or "Basic"
			end
		end
	end

	skinTemplate.LayoutOrder = skinData and (raritySortOrder[rarityName] or 90) or 0

	local rarityGrad = skinTemplate:FindFirstChild("RarityGradient")
	if rarityGrad then
		local grad = raritysFolder and (raritysFolder:FindFirstChild(rarityName)
			or (rarityName == "Covert" and raritysFolder:FindFirstChild("Convert"))
			or (rarityName == "Convert" and raritysFolder:FindFirstChild("Covert")))
		if grad and grad:IsA("UIGradient") then
			grad:Clone().Parent = rarityGrad
		end
	end

	local GearIcon = skinTemplate:FindFirstChild("GearIcon")
	if GearIcon then
		for _, c in ipairs(GearIcon:GetChildren()) do
			c:Destroy()
		end

		-- If it's a skin, apply texture to preview model
		local previewModel = model:Clone()
		if skinData then
			local dirFolder = ReplicatedStorage:WaitForChild("Directory")
			local success, skinConfig = pcall(function()
				return require(
					dirFolder
						:WaitForChild("Skins")
						:WaitForChild(category)
						:WaitForChild(modelName)
						:WaitForChild(skinData.ID)
				)
			end)
			if success and skinConfig and skinConfig.textureId then
				for _, part in ipairs(previewModel:GetDescendants()) do
					if part:IsA("MeshPart") then
						part.TextureID = "rbxassetid://" .. skinConfig.textureId
					elseif part:IsA("SpecialMesh") then
						part.TextureId = "rbxassetid://" .. skinConfig.textureId
					elseif part:IsA("Texture") or part:IsA("Decal") then
						part.Texture = "rbxassetid://" .. skinConfig.textureId
					end
				end
			end
		end

		local cloneModel = createViewport(previewModel, GearIcon, category)
		previewModel:Destroy()

		if cloneModel then
			local spinConnection = nil
			local baseCFrame = cloneModel:GetPivot()
			skinTemplate.MouseEnter:Connect(function()
				if not skinData then
					return
				end

				if Audio and Audio.Play then
					Audio.Play(6895079853, playerGui, 1, 0.5)
					Audio.Play(87727861079188, playerGui, 1, 0.2)
				end

				if not spinConnection then
					spinConnection = RunService.RenderStepped:Connect(function(dt)
						if cloneModel.Parent then
							cloneModel:PivotTo(CFrame.Angles(0, dt * 2, 0) * cloneModel:GetPivot())
						end
					end)
				end

				local multMin = 1
				local multMax = 1
				local rarityName = "Basic"
				if skinData then
					local success, skinConfig = pcall(function()
						return require(
							ReplicatedStorage:WaitForChild("Directory")
								:WaitForChild("Skins")
								:WaitForChild(category)
								:WaitForChild(modelName)
								:WaitForChild(skinData.ID)
						)
					end)
					if success and skinConfig then
						multMin = skinConfig.MultMin or 1
						multMax = skinConfig.MultMax or 1
						rarityName = skinConfig.rarity or "Basic"
					end
				end

				local blockDefs = {
					{ "Title", skinData and skinData.ID or "Default", rarityName },
					{ "Nickname", modelName },
					{ "RAP", skinData and skinData.RAP or 0 },
					{ "OwnerCount", skinData and skinData.Exists or "???" },
					{ "Rarity", rarityName },
				}
				if skinData then
					table.insert(blockDefs, { "Power", skinData.Float, multMin, multMax })
				end

				InfoOverlay.Add(skinTemplate, unpack(blockDefs))
			end)
			skinTemplate.MouseLeave:Connect(function()
				if not skinData then
					return
				end

				InfoOverlay.Remove()
				if spinConnection then
					spinConnection:Disconnect()
					spinConnection = nil
				end
				if cloneModel.Parent then
					cloneModel:PivotTo(baseCFrame)
				end
			end)
		end
	end

	local equippedLabel = skinTemplate:FindFirstChild("Equipped")
	if equippedLabel then
		local isSkinEquipped = false
		local isWeaponEquipped = isEquipped(category, modelName)

		if isWeaponEquipped then
			if skinData then
				if
					playerData.EquippedSkins
					and playerData.EquippedSkins[category]
					and playerData.EquippedSkins[category][modelName]
				then
					isSkinEquipped = (playerData.EquippedSkins[category][modelName].ID == skinData.ID)
				end
			else
				isSkinEquipped = not (
					playerData.EquippedSkins
					and playerData.EquippedSkins[category]
					and playerData.EquippedSkins[category][modelName]
				)
			end
		end

		equippedLabel.Visible = isSkinEquipped
	end

	local deleteOverlay = skinTemplate:FindFirstChild("Delete")
	if deleteOverlay then
		deleteOverlay.Visible = (isDeleteMode and skinData ~= nil and selectedDeleteUids[skinData.UID] == true)
	end

	local lockedIcon = skinTemplate:FindFirstChild("Locked")
	if lockedIcon and skinData then
		lockedIcon.Visible = (skinData.Locked == true or skinData.l == true)
	end

	skinTemplate.Activated:Connect(function()
		if isDeleteMode then
			if not skinData then return end
			if skinData.Locked == true or skinData.l == true then
				if _G.Message and _G.Message.New then
					_G.Message.New("This skin is locked! Unlock it first before deleting.", false, "Skin Locked")
				end
				return
			end

			-- Toggle selection
			if selectedDeleteUids[skinData.UID] then
				selectedDeleteUids[skinData.UID] = nil
				if deleteOverlay then
					deleteOverlay.Visible = false
				end
			else
				selectedDeleteUids[skinData.UID] = true
				if deleteOverlay then
					deleteOverlay.Visible = true
				end
			end

			if Audio and Audio.Play then
				Audio.Play(6895079853, playerGui, 1, 0.5)
			end
		else
			local skinName = skinData and skinData.ID or "Default"
			equipItem(category, modelName, model, skinName) -- Need to pass skinName to equipItem
		end
	end)

	if searchQuery ~= "" then
		local q = string.lower(searchQuery)
		local skinIDName = skinData and skinData.ID or "Default"
		local matchItem = string.find(string.lower(modelName), q, 1, true) ~= nil
		local matchSkin = string.find(string.lower(skinIDName), q, 1, true) ~= nil
		local matchRarity = string.find(string.lower(rarityName), q, 1, true) ~= nil
		if not (matchItem or matchSkin or matchRarity) then
			skinTemplate.Visible = false
		end
	end

	skinTemplate.Parent = skinsGrid
end

local function getModel(category, name)
	return ViewportUtil.GetModel(category, name)
end

local function populateSkins(modelName)
	renderToken = renderToken + 1
	clearGrid(skinsGrid)
	skinsScroll.CanvasPosition = Vector2.new(0, 0)
	currentType = modelName

	local model = getModel(currentCategory, modelName)
	if not model then
		return
	end

	-- Add Default skin
	addSkinToGrid(modelName, model, currentCategory, nil)

	-- Add owned skins for this item
	if playerData.Skins then
		for _, skinData in ipairs(playerData.Skins) do
			if skinData.Category == currentCategory and skinData.ItemName == modelName then
				addSkinToGrid(modelName, model, currentCategory, skinData)
			end
		end
	end
end

local function populateTypes(category)
	renderToken = renderToken + 1
	local myToken = renderToken

	clearGrid(typesGrid)
	clearGrid(skinsGrid)
	typesScroll.CanvasPosition = Vector2.new(0, 0)
	skinsScroll.CanvasPosition = Vector2.new(0, 0)
	currentCategory = category
	currentType = nil

	-- Fetch owned items from server
	local success, data = pcall(function()
		return getPlayerDataRemote:InvokeServer()
	end)
	-- While we yielded above, a newer render may have started (double onOpen,
	-- tab switch). If so, abort: continuing would add every row a second time.
	if myToken ~= renderToken then
		return
	end
	if success and data then
		playerData = data
	end

	local itemsList = ShopConfig[category]
	if not itemsList then
		return
	end

	for _, item in ipairs(itemsList) do
		local name = item.Name

		-- Only display base weapons that the player actually owns in the Types tab
		local owned = InventoryUtil.OwnsBaseEquipment(playerData, category, name)
		if not owned then
			continue
		end

		local model = getModel(category, name)
		if not model then
			continue
		end

		local typeTemplate = typesTemplate:Clone()
		typeTemplate.Name = name

		local levelText = typeTemplate:FindFirstChild("Level")
		if levelText then
			if category == "BackPack" then
				levelText.Text = "Backpack " .. name
			else
				levelText.Text = name
			end
		end

		local GearIcon = typeTemplate:FindFirstChild("GearIcon")
		if GearIcon then
			for _, c in ipairs(GearIcon:GetChildren()) do
				c:Destroy()
			end
			local cloneModel = createViewport(model, GearIcon, currentCategory)
			if cloneModel then
				local spinConnection = nil
				local baseCFrame = cloneModel:GetPivot()
				typeTemplate.MouseEnter:Connect(function()
					if not spinConnection then
						spinConnection = RunService.RenderStepped:Connect(function(dt)
							if cloneModel.Parent then
								cloneModel:PivotTo(CFrame.Angles(0, dt * 2, 0) * cloneModel:GetPivot())
							end
						end)
					end
				end)
				typeTemplate.MouseLeave:Connect(function()
					if spinConnection then
						spinConnection:Disconnect()
						spinConnection = nil
					end
					if cloneModel.Parent then
						cloneModel:PivotTo(baseCFrame)
					end
				end)
			end
		end

		local equippedLabel = typeTemplate:FindFirstChild("Equipped")
		local equipped = isEquipped(category, name)
		if equippedLabel then
			equippedLabel.Visible = equipped
		end

		typeTemplate.Activated:Connect(function()
			equipItem(category, name, model)
			populateSkins(name)
		end)

		typeTemplate.Parent = typesGrid

		if searchQuery ~= "" then
			local q = string.lower(searchQuery)
			if not string.find(string.lower(name), q, 1, true) then
				typeTemplate.Visible = false
			end
		end

		-- Add default skin to skins grid only if player actually owns the base weapon from GearShop
		if owned then
			addSkinToGrid(name, model, category, nil)
		end
	end

	-- Add all owned actual skins for this category
	if playerData.Skins then
		for _, skinData in ipairs(playerData.Skins) do
			if skinData.Category == category then
				local model = getModel(category, skinData.ItemName)
				if model then
					-- Verify ownership of base weapon implicitly by the fact they have the skin,
					-- but better to just render it if they own the skin.
					addSkinToGrid(skinData.ItemName, model, category, skinData)
				end
			end
		end
	end
end

local function selectCategoryTab(categoryName)
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
	populateTypes(categoryName)
end

for _, button in ipairs(toolFilters:GetChildren()) do
	if button:IsA("GuiButton") then
		button.Activated:Connect(function()
			selectCategoryTab(button.Name)
		end)
	end
end

local inventoryScreenGui = inventoryGui.Parent.Parent

local function exitDeleteMode()
	isDeleteMode = false
	selectedDeleteUids = {}
	if deleteSelectBtn then deleteSelectBtn.Visible = true end
	if deleteBtn then deleteBtn.Visible = false end
	if backBtn then backBtn.Visible = false end
	if currentCategory then
		populateTypes(currentCategory)
	end
end

local function enterDeleteMode()
	isDeleteMode = true
	selectedDeleteUids = {}
	if deleteSelectBtn then deleteSelectBtn.Visible = false end
	if deleteBtn then deleteBtn.Visible = true end
	if backBtn then backBtn.Visible = true end
	if currentCategory then
		populateTypes(currentCategory)
	end
end

if deleteSelectBtn then
	deleteSelectBtn.Visible = true
	deleteSelectBtn.Activated:Connect(function()
		if Audio and Audio.Play then
			Audio.Play(6895079853, playerGui, 1, 0.5)
		end
		enterDeleteMode()
	end)
end

if backBtn then
	backBtn.Visible = false
	backBtn.Activated:Connect(function()
		if Audio and Audio.Play then
			Audio.Play(6895079853, playerGui, 1, 0.5)
		end
		exitDeleteMode()
	end)
end

if deleteBtn then
	deleteBtn.Visible = false
	deleteBtn.Activated:Connect(function()
		if Audio and Audio.Play then
			Audio.Play(6895079853, playerGui, 1, 0.5)
		end

		if next(selectedDeleteUids) == nil then
			if _G.Message and _G.Message.New then
				_G.Message.New("Please select at least one skin to delete first!", false, "Delete Skins")
			end
			return
		end

		local count = 0
		local uidsList = {}
		for uid in pairs(selectedDeleteUids) do
			count += 1
			table.insert(uidsList, uid)
		end

		local confirmMsg = string.format("Are you sure you want to delete %d skin%s? This cannot be undone.", count, count > 1 and "s" or "")
		local confirmed = false
		if _G.Message and _G.Message.New then
			confirmed = _G.Message.New(confirmMsg, true, "Confirm Delete")
		else
			confirmed = true
		end

		if confirmed then
			local deleteRemote = remotes:FindFirstChild("DeleteSkins")
			local success, res = false, nil
			if deleteRemote and deleteRemote:IsA("RemoteFunction") then
				success, res = pcall(function()
					return deleteRemote:InvokeServer(uidsList)
				end)
			elseif Library.Network and Library.Network.Invoke then
				success, res = pcall(function()
					return Library.Network.Invoke("Delete Several Skins", uidsList)
				end)
			end

			if success and res then
				if Audio and Audio.Play then
					Audio.Play(87727861079188, playerGui, 1, 0.5)
				end

				exitDeleteMode()
			else
				if _G.Message and _G.Message.New then
					_G.Message.New(tostring(res or "Failed to delete skins!"), false, "Error")
				end
			end
		end
	end)
end

local function onOpen()
	updateInventoryLayouts()
	exitDeleteMode()
	selectCategoryTab(currentCategory or "Launcher")
end

inventoryScreenGui.Changed:Connect(function(prop)
	if prop == "Enabled" then
		if inventoryScreenGui.Enabled then
			onOpen()
		else
			exitDeleteMode()
		end
	end
end)

inventoryGui.Parent.Changed:Connect(function(prop)
	if prop == "Visible" then
		if inventoryGui.Parent.Visible then
			onOpen()
		else
			exitDeleteMode()
		end
	end
end)

if searchInput then
	searchInput:GetPropertyChangedSignal("Text"):Connect(function()
		searchQuery = searchInput.Text
		if currentCategory then
			populateTypes(currentCategory)
		end
	end)
end

-- Default tab
selectCategoryTab("Launcher")
