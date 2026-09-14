--[[
	TutorialController.local.luau
	Handles initial tutorial flow with dynamic multi-resolution GUI adaptation:
	1. Connects Beam from local player to Workspace.__Guide_Beam.FirstBeam immediately at spawn.
	2. Listens for when the player touches FirstBeam.
	3. Upon touch, checks if the player has a Launcher (Tool) equipped:
	   - If NOT equipped: Enables StarterGui.Tutorial ("Equip Launcher") with dynamic resolution masks.
	   - Once equipped (or if already equipped): Hides Tutorial GUI and shows GuideArrow on FirstArrow.
	4. Detects shooting (Tool.Activated) -> Removes GuideArrow and connects Beam to random Orb.
	5. Fills backpack -> Prompts "Sell your Blocks!" with resolution-calibrated dialog masks.
	6. Sells blocks -> Connects Beam to SecondBeam (GearShop area).
	7. Opens GearShop -> Step-by-step resolution-calibrated highlights:
	   - Step 1: Click Backpack tab
	   - Step 2: Click Right arrow (Next Item)
	   - Step 3: Click Buy button
	8. StarterBooster popup sequence.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local Assets = ReplicatedStorage:WaitForChild("Assets")
local Billboards = Assets:WaitForChild("Billboards", 15)
local TutorialFolder = Billboards and Billboards:WaitForChild("TutorialArrow", 15)

local BeamAsset = TutorialFolder and (TutorialFolder:WaitForChild("TutorialBeam", 15) or TutorialFolder:WaitForChild("Beam", 15))
local GuideArrowAsset = TutorialFolder and TutorialFolder:WaitForChild("GuideArrow", 15)

local Audio = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Audio"))
local TUTORIAL_LAYOUTS = require(script.Parent:WaitForChild("TutorialLayouts"))

-- Fail loud instead of hanging forever on a missing/renamed asset
if not BeamAsset or not GuideArrowAsset then
	warn("[Tutorial] Missing assets in ReplicatedStorage.Assets.Billboards.TutorialArrow (TutorialBeam/GuideArrow) — tutorial disabled")
	return
end

----------------------------------------------------------------------
-- State & Variables
----------------------------------------------------------------------
local activeBeam = nil
local playerAttachment = nil
local activeGuideArrow = nil
local touchConnection = nil
local currentStepName = nil
local currentHeaderText = nil

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
local function getTutorialGui()
	return playerGui:WaitForChild("Tutorial", 10)
end

local function getDeviceCategory()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
	local isTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

	local w = math.max(vp.X, vp.Y)
	local h = math.min(vp.X, vp.Y)
	local aspect = w / math.max(1, h)

	if isTouch then
		-- iPhone 6 Plus (736x414 ~1.778) and iPhone 7 (667x375 ~1.778)
		if (w <= 750 or h <= 420) and aspect < 1.85 then
			return "STANDARD_OR_IPHONE_CLASSIC"
		elseif aspect <= 1.68 then
			-- Tablets / iPads (~4:3 = 1.33, ~16:10 = 1.6)
			return "TABLET"
		else
			-- Modern Mobiles / Widescreen (~19.5:9 = 2.16, ~20:9 = 2.22)
			return "MOBILE_WIDESCREEN"
		end
	else
		-- PC / Console / Laptop
		if w >= 1600 and aspect >= 1.70 then
			return "FULL_HD"
		else
			return "STANDARD_OR_IPHONE_CLASSIC"
		end
	end
end

local function hideAllMasks()
	local tutorialGui = getTutorialGui()
	if not tutorialGui then return end

	for i = 1, 4 do
		local sh = tutorialGui:FindFirstChild("SH" .. i)
		if sh then
			sh.Visible = false
		end
	end

	local highlight = tutorialGui:FindFirstChild("ScreenHighlight")
	if highlight then
		highlight.Visible = false
	end

	local pointer = tutorialGui:FindFirstChild("Pointer")
	if pointer then
		pointer.Visible = false
	end
end

local function applyStepLayout(stepName, headerText)
	currentStepName = stepName
	if headerText ~= nil then
		currentHeaderText = headerText
	end

	local tutorialGui = getTutorialGui()
	if not tutorialGui then return end

	local stepData = TUTORIAL_LAYOUTS[stepName]
	if not stepData then return end

	local category = getDeviceCategory()
	local layout = stepData[category] or stepData["UNIVERSAL"] or stepData["STANDARD_OR_IPHONE_CLASSIC"] or stepData["FULL_HD"]
	if not layout then return end

	-- Header
	local header = tutorialGui:FindFirstChild("Header")
	if header then
		if currentHeaderText ~= nil then
			header.Text = currentHeaderText
		end
		if layout.Header then
			header.Position = layout.Header.Position
			header.Size = layout.Header.Size
			header.AnchorPoint = layout.Header.AnchorPoint
			header.Visible = (header.Text ~= "")
		end
		local subHeader = header:FindFirstChild("Header")
		if subHeader and layout.HeaderHeader then
			subHeader.Position = layout.HeaderHeader.Position
			subHeader.Size = layout.HeaderHeader.Size
			subHeader.AnchorPoint = layout.HeaderHeader.AnchorPoint
			subHeader.Visible = (header.Text ~= "")
		end
	end

	-- Masks (SH1, SH2, SH3, SH4)
	for i = 1, 4 do
		local sh = tutorialGui:FindFirstChild("SH" .. i)
		local shLayout = layout["SH" .. i]
		if sh and shLayout then
			sh.Visible = true
			sh.Position = shLayout.Position
			sh.Size = shLayout.Size
			sh.AnchorPoint = shLayout.AnchorPoint
			sh.BackgroundTransparency = 0.5
			sh.ZIndex = 1
		end
	end

	-- Pointer
	local pointer = tutorialGui:FindFirstChild("Pointer")
	if pointer and layout.Pointer then
		pointer.Visible = true
		pointer.Position = layout.Pointer.Position
		pointer.Size = layout.Pointer.Size
		pointer.AnchorPoint = layout.Pointer.AnchorPoint
		pointer.Rotation = layout.Pointer.Rotation or -90
		pointer.ZIndex = 2
	end

	-- ScreenHighlight
	local highlight = tutorialGui:FindFirstChild("ScreenHighlight")
	if highlight and layout.ScreenHighlight then
		highlight.Visible = true
		highlight.Position = layout.ScreenHighlight.Position
		highlight.Size = layout.ScreenHighlight.Size
		highlight.AnchorPoint = layout.ScreenHighlight.AnchorPoint
		highlight.ZIndex = 0
	end

	tutorialGui.Enabled = true
end

local function hideTutorialGui()
	currentStepName = nil
	currentHeaderText = nil
	local tutorialGui = getTutorialGui()
	if tutorialGui then
		tutorialGui.Enabled = false
		hideAllMasks()
	end
end

-- Re-apply active tutorial layout whenever resolution or viewport changes
local function onViewportSizeChanged()
	if currentStepName then
		local tutorialGui = getTutorialGui()
		if tutorialGui and tutorialGui.Enabled then
			applyStepLayout(currentStepName, currentHeaderText)
		end
	end
end

if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(onViewportSizeChanged)
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(onViewportSizeChanged)
	end
end)

local function getTargetPart(folderName, partName)
	local folder = workspace:FindFirstChild(folderName) or (workspace:FindFirstChild("__MAP") and workspace.__MAP:FindFirstChild(folderName))
	if folder then
		return folder:FindFirstChild(partName)
	end
	return nil
end

local function waitForTargetPart(folderName, partName, timeout)
	timeout = timeout or 10
	local deadline = os.clock() + timeout

	while os.clock() < deadline do
		local part = getTargetPart(folderName, partName)
		if part then
			return part
		end
		task.wait(0.2)
	end

	warn(string.format("[Tutorial] Timed out waiting for %s.%s (Workspace/__MAP)", folderName, partName))
	return nil
end

local function waitForWorldLoad(timeout)
	timeout = timeout or 20
	local deadline = os.clock() + timeout

	while os.clock() < deadline do
		if workspace:FindFirstChild("__MAP") then
			return true
		end
		task.wait(0.2)
	end

	warn("[Tutorial] Timed out waiting for the world to load (__MAP)")
	return false
end

local function ensureAttachment(part)
	if not part then return nil end
	local att = part:FindFirstChild("TutorialAttachment")
	if not att then
		att = Instance.new("Attachment")
		att.Name = "TutorialAttachment"
		att.Position = Vector3.new(0, 0, 0)
		att.Parent = part
	end
	return att
end

local function showGuideArrow(targetPart)
	if activeGuideArrow then
		activeGuideArrow:Destroy()
		activeGuideArrow = nil
	end

	local hrp = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	playerAttachment = hrp:FindFirstChild("TutorialPlayerAttachment")
	if not playerAttachment then
		playerAttachment = Instance.new("Attachment")
		playerAttachment.Name = "TutorialPlayerAttachment"
		playerAttachment.Parent = hrp
	end

	local targetAtt = ensureAttachment(targetPart)
	if not targetAtt then return end

	activeGuideArrow = GuideArrowAsset:Clone()
	activeGuideArrow.Name = "ActiveTutorialGuideArrow"
	activeGuideArrow.Adornee = targetPart
	activeGuideArrow.Enabled = true
	activeGuideArrow.Parent = targetPart
end

local function connectBeamToTarget(character, targetPart)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp or not targetPart then return end

	local playerAtt = hrp:FindFirstChild("TutorialPlayerAttachment") or Instance.new("Attachment", hrp)
	playerAtt.Name = "TutorialPlayerAttachment"

	local targetAtt = ensureAttachment(targetPart)
	if not targetAtt then return end

	if activeBeam then
		activeBeam:Destroy()
		activeBeam = nil
	end

	activeBeam = BeamAsset:Clone()
	activeBeam.Name = "ActiveTutorialBeam"
	activeBeam.Attachment0 = playerAtt
	activeBeam.Attachment1 = targetAtt
	activeBeam.Enabled = true
	activeBeam.Parent = character
end

----------------------------------------------------------------------
-- Main Tutorial Controller
----------------------------------------------------------------------
local hasCompletedMainTutorial = false
local hasCompletedLevel30Tutorial = false

local function startTutorialProcess(character)
	-- Guard against multiple runs per session
	if hasCompletedMainTutorial then return end

	-- Wait until player attributes are replicated
	if localPlayer:GetAttribute("Coins") == nil and localPlayer:GetAttribute("TutorialCompleted") == nil then
		local start = os.clock()
		while os.clock() - start < 10 do
			task.wait(0.2)
			if localPlayer:GetAttribute("Coins") ~= nil or localPlayer:GetAttribute("TutorialCompleted") ~= nil then
				break
			end
		end
	end

	-- Check if player has completed main tutorial before or progressed past early stage
	if localPlayer:GetAttribute("TutorialCompleted") == true then
		hasCompletedMainTutorial = true
		hideTutorialGui()
		return
	end

	local coins = localPlayer:GetAttribute("Coins") or 0
	if coins >= 100 then
		hasCompletedMainTutorial = true
		localPlayer:SetAttribute("TutorialCompleted", true)
		hideTutorialGui()
		return
	end

	if not waitForWorldLoad(20) then
		return
	end

	----------------------------------------------------------------------
	-- PHASE 1: FirstBeam & Launcher Equip
	----------------------------------------------------------------------
	local firstBeamPart = waitForTargetPart("__Guide_Beam", "FirstBeam", 15)
	if not firstBeamPart then
		return
	end

	-- 1. Connect Beam to FirstBeam immediately at spawn
	connectBeamToTarget(character, firstBeamPart)

	-- 2. Wait until player touches FirstBeam
	local touchedFirstBeam = false
	if touchConnection then
		touchConnection:Disconnect()
	end

	touchConnection = firstBeamPart.Touched:Connect(function(hit)
		if hit and hit:IsDescendantOf(character) then
			touchedFirstBeam = true
		end
	end)

	while character and character.Parent and not touchedFirstBeam do
		task.wait(0.1)
	end

	if touchConnection then
		touchConnection:Disconnect()
		touchConnection = nil
	end

	-- 3. Touch FirstBeam: Destroy Beam and show GuideArrow on FirstArrow
	if activeBeam then
		activeBeam:Destroy()
		activeBeam = nil
	end

	local firstArrowPart = waitForTargetPart("__Guide_Arrow", "FirstArrow", 10)
	if firstArrowPart then
		showGuideArrow(firstArrowPart)
	end

	-- 4. Check if Launcher (Tool) is equipped
	local hasEquippedTool = character:FindFirstChildOfClass("Tool") ~= nil

	if not hasEquippedTool then
		applyStepLayout("EQUIP_LAUNCHER", "Equip Launcher")

		-- Wait until tool is equipped
		while character and character.Parent and not character:FindFirstChildOfClass("Tool") do
			task.wait(0.2)
		end
	end

	-- 5. Tool is now equipped -> Hide prompt UI
	if character and character.Parent then
		hideTutorialGui()
	end

	-- 6. Detect tool activation (shooting) -> Destroy FirstArrow
	local equippedTool = character:FindFirstChildOfClass("Tool")
	if equippedTool then
		local hasFired = false
		local conn
		conn = equippedTool.Activated:Connect(function()
			hasFired = true
			if conn then conn:Disconnect() end
		end)

		while character and character.Parent and not hasFired do
			task.wait(0.1)
		end
	end

	-- 7. Turn OFF FirstArrow upon shooting
	if activeGuideArrow then
		activeGuideArrow:Destroy()
		activeGuideArrow = nil
	end

	-- 8. Wait 1 second for Orbs to finish spawning, then pick a random Orb
	task.wait(1.0)

	local orbsFolder = workspace:FindFirstChild("__THINGS") and workspace.__THINGS:FindFirstChild("Orbs")
	local availableOrbs = {}

	if orbsFolder then
		for _, child in ipairs(orbsFolder:GetChildren()) do
			if child:IsA("BasePart") then
				table.insert(availableOrbs, child)
			end
		end
	end

	if #availableOrbs == 0 and orbsFolder then
		task.wait(1.0)
		for _, child in ipairs(orbsFolder:GetChildren()) do
			if child:IsA("BasePart") then
				table.insert(availableOrbs, child)
			end
		end
	end

	if #availableOrbs > 0 then
		local randomOrb = availableOrbs[math.random(1, #availableOrbs)]
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if hrp and randomOrb and randomOrb.Parent then
			local playerAtt = hrp:FindFirstChild("TutorialPlayerAttachment") or Instance.new("Attachment", hrp)
			playerAtt.Name = "TutorialPlayerAttachment"

			local orbAtt = randomOrb:FindFirstChild("TutorialOrbAttachment")
			if not orbAtt then
				orbAtt = Instance.new("Attachment")
				orbAtt.Name = "TutorialOrbAttachment"
				orbAtt.Parent = randomOrb
			end

			activeBeam = BeamAsset:Clone()
			activeBeam.Name = "TutorialOrbBeam"
			activeBeam.Attachment0 = playerAtt
			activeBeam.Attachment1 = orbAtt
			activeBeam.Enabled = true
			activeBeam.Parent = character
		end
	end

	----------------------------------------------------------------------
	-- PHASE 2: Wait until Bag is Full, then prompt to Sell Blocks
	----------------------------------------------------------------------
	local function isBagFull()
		local cur = localPlayer:GetAttribute("Blocks") or (localPlayer:GetAttribute("StorageAmount") or 0)
		local max = localPlayer:GetAttribute("MaxBlocks") or (localPlayer:GetAttribute("StorageMax") or 100)
		return cur >= max
	end

	-- Wait until player fills their backpack
	while character and character.Parent and not isBagFull() do
		task.wait(0.3)
	end

	-- Destroy the previous Orb beam once bag is full
	if activeBeam then
		activeBeam:Destroy()
		activeBeam = nil
	end

	-- Display "Sell your Blocks!" with resolution-calibrated layout
	applyStepLayout("SELL_BLOCKS", "Sell your Blocks!")

	-- Also listen for Message dialog OK/Yes buttons to hide UI immediately when clicked
	local messageScreen = playerGui:FindFirstChild("Message")
	local messageFrame = messageScreen and messageScreen:FindFirstChild("Frame")
	local msgOkBtn = messageFrame and messageFrame:FindFirstChild("Ok")
	local msgYesBtn = messageFrame and messageFrame:FindFirstChild("Yes")

	local msgClicked = false
	local msgConns = {}

	local function onMsgClicked()
		msgClicked = true
		hideTutorialGui()
		for _, c in ipairs(msgConns) do c:Disconnect() end
		msgConns = {}
	end

	if msgOkBtn then table.insert(msgConns, msgOkBtn.Activated:Connect(onMsgClicked)) end
	if msgYesBtn then table.insert(msgConns, msgYesBtn.Activated:Connect(onMsgClicked)) end

	-- Wait until player sells their blocks
	while character and character.Parent do
		local curBlocks = localPlayer:GetAttribute("Blocks") or (localPlayer:GetAttribute("StorageAmount") or 0)
		if curBlocks == 0 then
			break
		end
		task.wait(0.2)
	end

	for _, c in ipairs(msgConns) do c:Disconnect() end

	-- Hide Tutorial UI completely after selling
	hideTutorialGui()

	-- Activate Beam to SecondBeam (GearShop area)
	local secondBeamPart = waitForTargetPart("__Guide_Beam", "SecondBeam", 10)
	local hrp = character:FindFirstChild("HumanoidRootPart")

	if secondBeamPart and hrp then
		local playerAtt = hrp:FindFirstChild("TutorialPlayerAttachment") or Instance.new("Attachment", hrp)
		playerAtt.Name = "TutorialPlayerAttachment"

		local targetAtt = ensureAttachment(secondBeamPart)
		if targetAtt then
			activeBeam = BeamAsset:Clone()
			activeBeam.Name = "TutorialSecondBeam"
			activeBeam.Attachment0 = playerAtt
			activeBeam.Attachment1 = targetAtt
			activeBeam.Enabled = true
			activeBeam.Parent = character
		end
	end

	----------------------------------------------------------------------
	-- PHASE 3: GearShop Purchase Sequence (Resolution-Calibrated Steps)
	----------------------------------------------------------------------
	local gearShopScreen = playerGui:WaitForChild("GearShop", 15)
	if not gearShopScreen then
		warn("[Tutorial] PlayerGui.GearShop not found — tutorial aborted")
		return
	end
	local gearShopFrame = gearShopScreen:WaitForChild("Frame", 15)
	if not gearShopFrame then
		warn("[Tutorial] GearShop.Frame not found — tutorial aborted")
		return
	end

	local function isGearShopOpen()
		return gearShopScreen.Enabled and gearShopFrame.Visible
	end

	-- Wait until player walks to SecondBeam area and opens GearShop
	while character and character.Parent and not isGearShopOpen() do
		task.wait(0.2)
	end

	-- Deactivate SecondBeam when GearShop opens
	if activeBeam then
		activeBeam:Destroy()
		activeBeam = nil
	end

	-- Step 3.1: Backpack Tab (Etapa C)
	applyStepLayout("SHOP_BACKPACK", "")

	local mainFrame = gearShopFrame:FindFirstChild("Main")
	local toolNormal = mainFrame and mainFrame:FindFirstChild("Tool") and mainFrame.Tool:FindFirstChild("Normal")
	local backpackButton = toolNormal and toolNormal:FindFirstChild("BackPack")

	local categorySelected = false
	if backpackButton then
		local conn
		conn = backpackButton.MouseButton1Click:Connect(function()
			categorySelected = true
			if conn then conn:Disconnect() end
		end)
	end

	while character and character.Parent and not categorySelected and isGearShopOpen() do
		task.wait(0.2)
	end

	-- Step 3.2: Next Item Arrow Right (Etapa D)
	if isGearShopOpen() then
		applyStepLayout("SHOP_RIGHT", "")
	end

	local typesFrame = mainFrame and mainFrame:FindFirstChild("Types")
	local rightButton = typesFrame and typesFrame:FindFirstChild("Right")

	local itemCycled = false
	if rightButton then
		local conn
		conn = rightButton.MouseButton1Click:Connect(function()
			itemCycled = true
			if conn then conn:Disconnect() end
		end)
	end

	while character and character.Parent and not itemCycled and isGearShopOpen() do
		task.wait(0.2)
	end

	-- Step 3.3: Buy Button (Etapa E)
	if isGearShopOpen() then
		applyStepLayout("SHOP_BUY", "")
	end

	local normalFrame = typesFrame and typesFrame:FindFirstChild("Normal")
	local buyButton = normalFrame and normalFrame:FindFirstChild("Buy")

	local buyClicked = false
	if buyButton then
		local conn
		conn = buyButton.Activated:Connect(function()
			buyClicked = true
			hideTutorialGui() -- Hide UI immediately on click
			if conn then conn:Disconnect() end
		end)
	end

	-- Wait until player purchases a backpack or clicks buy button
	local function hasPurchasedBackpack()
		if buyClicked then return true end
		local ownedBps = localPlayer:GetAttribute("Backpacks")
		if ownedBps and #ownedBps > 1 then return true end
		local curMax = localPlayer:GetAttribute("MaxBlocks") or (localPlayer:GetAttribute("StorageMax") or 100)
		return curMax > 100
	end

	while character and character.Parent and not hasPurchasedBackpack() and isGearShopOpen() do
		task.wait(0.2)
	end

	-- TUTORIAL COMPLETED!
	hasCompletedMainTutorial = true
	localPlayer:SetAttribute("TutorialCompleted", true)
	hideTutorialGui()

	local remotesFolder = workspace:FindFirstChild("__THINGS") and workspace.__THINGS:FindFirstChild("__REMOTES")
	local completeRemote = remotesFolder and remotesFolder:FindFirstChild("CompleteTutorial")
	if completeRemote then
		completeRemote:FireServer("Main")
	end

	-- Wait until player CLOSES GearShop
	while character and character.Parent and isGearShopOpen() do
		task.wait(0.2)
	end

	-- Trigger StarterBooster UI popup
	local starterBoosterGui = playerGui:FindFirstChild("StarterBooster")
	if starterBoosterGui then
		_G.ImportantWindow = starterBoosterGui
		starterBoosterGui.Enabled = true

		local clickConn
		local function dismissBooster()
			if clickConn then
				clickConn:Disconnect()
				clickConn = nil
			end
			starterBoosterGui.Enabled = false
			if _G.ImportantWindow == starterBoosterGui then
				_G.ImportantWindow = nil
			end

			-- Play booster sound (respects SFX settings)
			if Audio and Audio.Play then
				Audio.Play(140147432730406, playerGui, 1, 1.0)
			end

			-- Enable 2x Magnet attribute
			localPlayer:SetAttribute("StarterBoostActive", true)

			local function getNormalSpeed()
				local success, Save = pcall(function()
					return require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Client"):WaitForChild("Save"))
				end)
				local save = success and Save and Save.Get()
				local runFasterLevel = (save and save.UpgradesOwned and save.UpgradesOwned.RunFaster) or 0
				return 24 + (runFasterLevel * 2)
			end

			-- Apply 2x WalkSpeed (Base 24 * 2 = 48 studs/s, scaled with upgrades)
			local hum = character:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.WalkSpeed = getNormalSpeed() * 2
			end

			local speedConn
			speedConn = localPlayer.CharacterAdded:Connect(function(newChar)
				if not localPlayer:GetAttribute("StarterBoostActive") then
					speedConn:Disconnect()
					return
				end
				local newHum = newChar:WaitForChild("Humanoid", 5)
				if newHum then
					newHum.WalkSpeed = getNormalSpeed() * 2
				end
			end)

			-- Timer for 30 minutes (1800s)
			task.delay(1800, function()
				localPlayer:SetAttribute("StarterBoostActive", nil)
				if speedConn then speedConn:Disconnect() end
				local curChar = localPlayer.Character
				local curHum = curChar and curChar:FindFirstChildOfClass("Humanoid")
				if curHum then
					curHum.WalkSpeed = getNormalSpeed()
				end
			end)
		end

		clickConn = UserInputService.InputBegan:Connect(function(input, gpe)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dismissBooster()
			end
		end)
	end
end

----------------------------------------------------------------------
-- Character Lifecycle Listeners
----------------------------------------------------------------------
local function onCharacterAdded(character)
	task.wait(0.5)
	task.spawn(function()
		startTutorialProcess(character)
	end)
end

if localPlayer.Character then
	task.spawn(function()
		onCharacterAdded(localPlayer.Character)
	end)
end

localPlayer.CharacterAdded:Connect(onCharacterAdded)