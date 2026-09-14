local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DefaultStats =
	require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Modules"):WaitForChild("DefaultStats"))

local GlobalLocks = require(
	ReplicatedStorage:WaitForChild("Library")
		:WaitForChild("Client")
		:WaitForChild("UIFramework")
		:WaitForChild("GlobalLocks")
)
local FormatNumber = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Functions"):WaitForChild("FormatNumber"))

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local tweenInfo = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local tweenInfoIn = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.In)

local function getHUDPositions(mainGui)
	local positions = {}

	local leftFrame = mainGui:FindFirstChild("Left")
	if leftFrame then
		positions[leftFrame] = {
			returnPos = leftFrame.Position,
			hidePos = UDim2.new(
				0,
				-leftFrame.AbsoluteSize.X - 20,
				leftFrame.Position.Y.Scale,
				leftFrame.Position.Y.Offset
			),
		}
	end

	local topFrame = mainGui:FindFirstChild("Top")
	if topFrame then
		positions[topFrame] = {
			returnPos = topFrame.Position,
			hidePos = UDim2.new(
				topFrame.Position.X.Scale,
				topFrame.Position.X.Offset,
				0,
				-topFrame.AbsoluteSize.Y - 20
			),
		}
	end

	local dropFrame = mainGui:FindFirstChild("Drop")
	if dropFrame then
		positions[dropFrame] = {
			returnPos = dropFrame.Position,
			hidePos = UDim2.new(
				dropFrame.Position.X.Scale,
				dropFrame.Position.X.Offset,
				0,
				-dropFrame.AbsoluteSize.Y - 20
			),
		}
	end

	return positions
end

local function applyHUDVisibility(isUnlocked)
	local mainGui = playerGui:FindFirstChild("Main")
	if not mainGui then
		return
	end

	local positions = getHUDPositions(mainGui)

	for frame, posData in pairs(positions) do
		if isUnlocked then
			TweenService:Create(frame, tweenInfo, { Position = posData.returnPos }):Play()
		else
			TweenService:Create(frame, tweenInfoIn, { Position = posData.hidePos }):Play()
		end
	end
end

GlobalLocks.HideHUD.OnLockChanged:Connect(function(isUnlocked)
	applyHUDVisibility(isUnlocked)
end)

task.spawn(function()
	applyHUDVisibility(GlobalLocks.HideHUD:IsUnlocked())
end)

----------------------------------------------------------------------
-- Currency & Storage HUD Display
----------------------------------------------------------------------
local mainGui = playerGui:WaitForChild("Main", 15) or playerGui:WaitForChild("Main")
local mainFrame = mainGui:WaitForChild("Frame")
local status = mainFrame:WaitForChild("Status")
local blocksFrame = status:FindFirstChild("Blocks")
local cashFrame = status:FindFirstChild("Cash")
local contractFrame = status:FindFirstChild("Contracts")

local Debris = game:GetService("Debris")

local function formatAssetId(assetId)
	if not assetId or assetId == "" then
		return ""
	end
	local strId = tostring(assetId)
	if not string.find(strId, "://") then
		return "rbxassetid://" .. strId
	end
	return strId
end

local function updateHUDText()
	local coins = localPlayer:GetAttribute("Coins") or 0
	local gems = localPlayer:GetAttribute("Gems") or 0
	local contracts = localPlayer:GetAttribute("Contracts") or gems
	local blocks = localPlayer:GetAttribute("Blocks") or 0
	local defaultMax = (DefaultStats and DefaultStats.Storage and DefaultStats.Storage.Max) or 100
	local maxBlocks = localPlayer:GetAttribute("MaxBlocks") or defaultMax

	if blocksFrame then
		local valueLabel = blocksFrame:FindFirstChild("Value")
		if valueLabel then
			valueLabel.Text = string.format("%s/%s", FormatNumber(blocks), FormatNumber(maxBlocks))
		end
	end

	if cashFrame then
		local valueLabel = cashFrame:FindFirstChild("Value")
		if valueLabel then
			valueLabel.Text = FormatNumber(coins)
		end
	end

	if contractFrame then
		local valueLabel = contractFrame:FindFirstChild("Value")
		if valueLabel then
			valueLabel.Text = FormatNumber(contracts)
		end
	end
end

local function updateWorldStatusVisuals()
	if not blocksFrame then return end
	local currentWorld = localPlayer:GetAttribute("World") or "Spawn"

	local uiFolder = ReplicatedStorage:FindFirstChild("UI")
		or (ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("UI"))
	local gradientFolder = uiFolder and uiFolder:FindFirstChild("Gradient")
	local blocksGradFolder = gradientFolder and gradientFolder:FindFirstChild("Blocks")

	-- Update Status Icon Image
	local iconLabel = blocksFrame:FindFirstChild("Icon")
	if iconLabel and iconLabel:IsA("ImageLabel") then
		if currentWorld == "Magic" then
			iconLabel.Image = "rbxassetid://114046103719772"
		else
			iconLabel.Image = "rbxassetid://113137643980619"
		end
	end

	-- Update Status Value UIGradient
	local valueLabel = blocksFrame:FindFirstChild("Value")
	if valueLabel and blocksGradFolder then
		local worldFolder = blocksGradFolder:FindFirstChild(currentWorld) or blocksGradFolder:FindFirstChild("Spawn")
		local targetGrad = nil
		if currentWorld == "Magic" and worldFolder then
			targetGrad = worldFolder:FindFirstChild("StatusGalaxyBlock")
		elseif worldFolder then
			targetGrad = worldFolder:FindFirstChild("StatusBlock")
		end

		if targetGrad then
			local oldGrad = valueLabel:FindFirstChildOfClass("UIGradient")
			if oldGrad then
				oldGrad:Destroy()
			end
			local gradClone = targetGrad:Clone()
			gradClone.Parent = valueLabel
		end
	end
end

local rng = Random.new()

local function playCustomPopUpEffect(text, imageId, gradientName, yOffset, countUpTarget, holdDuration)
	local popUp = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Billboards"):FindFirstChild("PopUp")
	if not popUp then
		return
	end

	local clone = popUp:Clone()
	clone.Parent = playerGui:FindFirstChild("Main") or playerGui:FindFirstChildOfClass("ScreenGui")

	local valueLabel = clone:FindFirstChild("Value")
	if valueLabel then
		valueLabel.Text = (countUpTarget and "+0") or text
		valueLabel.TextTransparency = 0

		local uiFolder = ReplicatedStorage:FindFirstChild("UI")
			or (ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("UI"))
		local gradientFolder = uiFolder and uiFolder:FindFirstChild("Gradient")

		local targetGrad = gradientFolder and gradientFolder:FindFirstChild(gradientName)
		if targetGrad then
			valueLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
			local oldGrad = valueLabel:FindFirstChildOfClass("UIGradient")
			if oldGrad then
				oldGrad:Destroy()
			end
			local gradClone = targetGrad:Clone()
			gradClone.Parent = valueLabel
		else
			if gradientName == "StarGradient" or gradientName == "ContractGradient" then
				valueLabel.TextColor3 = Color3.fromRGB(207, 207, 103) -- Gold color fallback
			else
				valueLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
			end
		end

		local stroke = valueLabel:FindFirstChild("Stroke")
		if stroke then
			stroke.Transparency = 0
		end

		if countUpTarget and type(countUpTarget) == "number" then
			local startVal = math.floor(countUpTarget * 0.5)
			local duration = 0.5
			local steps = 12
			task.spawn(function()
				for i = 1, steps do
					local t = i / steps
					local progress = t * (2 - t)
					local currentVal = math.floor(startVal + (countUpTarget - startVal) * progress)
					valueLabel.Text = "+" .. FormatNumber(currentVal)
					task.wait(duration / steps)
				end
				valueLabel.Text = "+" .. FormatNumber(countUpTarget)
			end)
		end
	end

	local imageLabel = clone:FindFirstChild("Image")
	if imageLabel then
		imageLabel.Image = formatAssetId(imageId)
		imageLabel.ImageTransparency = 0
		imageLabel.Visible = true
	end

	local targetSize = clone.Size
	clone.Size = UDim2.fromScale(0, 0)

	local randomOffset =
		UDim2.fromScale(0.5 + rng:NextNumber(-0.04, 0.04), 0.5 + (yOffset or 0) + rng:NextNumber(-0.03, 0.03))
	clone.Position = randomOffset

	-- Pop in animation
	local tweenInfoPop = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(clone, tweenInfoPop, { Size = targetSize }):Play()

	-- Wait before float up and fade out (holdDuration defaults to 0.7s)
	task.delay(holdDuration or 0.7, function()
		local tweenInfoFade = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local floatPosition = UDim2.fromScale(clone.Position.X.Scale, clone.Position.Y.Scale - 0.18)

		TweenService:Create(clone, tweenInfoFade, { Position = floatPosition }):Play()

		if valueLabel then
			TweenService:Create(valueLabel, tweenInfoFade, { TextTransparency = 1 }):Play()
			local stroke = valueLabel:FindFirstChild("Stroke")
			if stroke then
				TweenService:Create(stroke, tweenInfoFade, { Transparency = 1 }):Play()
			end
		end

		if imageLabel then
			TweenService:Create(imageLabel, tweenInfoFade, { ImageTransparency = 1 }):Play()
		end

		TweenService:Create(clone, tweenInfoFade, { BackgroundTransparency = 1 }):Play()

		task.delay(0.9, function()
			clone:Destroy()
		end)
	end)
end

local function playBlockPopUpEffect(amount)
	local popUp = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Billboards"):FindFirstChild("PopUp")
	if not popUp then
		return
	end

	local clone = popUp:Clone()
	clone.Parent = playerGui:FindFirstChild("Main") or playerGui:FindFirstChildOfClass("ScreenGui")

	local currentWorld = localPlayer:GetAttribute("World") or "Spawn"

	local valueLabel = clone:FindFirstChild("Value")
	if valueLabel then
		valueLabel.Text = "+0"
		valueLabel.TextTransparency = 0

		-- Replace any existing UIGradient under Value with the world-specific BlockPopUp Gradient
		local uiFolder = ReplicatedStorage:FindFirstChild("UI")
			or (ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("UI"))
		local gradientFolder = uiFolder and uiFolder:FindFirstChild("Gradient")
		local blocksGradFolder = gradientFolder and gradientFolder:FindFirstChild("Blocks")
		local worldFolder = blocksGradFolder and (blocksGradFolder:FindFirstChild(currentWorld) or blocksGradFolder:FindFirstChild("Spawn"))
		
		local blockGrad = nil
		if currentWorld == "Magic" and worldFolder then
			blockGrad = worldFolder:FindFirstChild("GalaxyBlockPopUp")
		elseif worldFolder then
			blockGrad = worldFolder:FindFirstChild("BlockPopUp")
		end

		if blockGrad then
			valueLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
			local oldGrad = valueLabel:FindFirstChildOfClass("UIGradient")
			if oldGrad then
				oldGrad:Destroy()
			end
			local gradClone = blockGrad:Clone()
			gradClone.Parent = valueLabel
		else
			valueLabel.TextColor3 = Color3.fromRGB(0, 148, 216) -- Blocks Blue fallback
		end

		local stroke = valueLabel:FindFirstChild("Stroke")
		if stroke then
			stroke.Transparency = 0
		end

		-- Count up animation starting from 50% of the amount
		local startVal = math.floor(amount * 0.5)
		local duration = 0.5
		local steps = 12
		task.spawn(function()
			for i = 1, steps do
				local t = i / steps
				local progress = t * (2 - t) -- Easing out quad
				local currentVal = math.floor(startVal + (amount - startVal) * progress)
				valueLabel.Text = "+" .. FormatNumber(currentVal)
				task.wait(duration / steps)
			end
			valueLabel.Text = "+" .. FormatNumber(amount)
		end)
	end

	local imageLabel = clone:FindFirstChild("Image")
	if imageLabel then
		if currentWorld == "Magic" then
			imageLabel.Image = "rbxassetid://84318022435447"
		else
			imageLabel.Image = "rbxassetid://121224340290545"
		end
		imageLabel.ImageTransparency = 0
		imageLabel.Visible = true
	end

	local targetSize = clone.Size
	clone.Size = UDim2.fromScale(0, 0)

	-- Position with a slight random offset near the center to avoid overlapping
	local randomOffset = UDim2.fromScale(0.5 + rng:NextNumber(-0.06, 0.06), 0.5 + rng:NextNumber(-0.06, 0.06))
	clone.Position = randomOffset

	-- Pop in animation
	local tweenInfoPop = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(clone, tweenInfoPop, { Size = targetSize }):Play()

	-- Wait before float up and fade out
	task.delay(0.6, function()
		local tweenInfoFade = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

		-- Float up target
		local floatPosition = UDim2.fromScale(clone.Position.X.Scale, clone.Position.Y.Scale - 0.15)

		TweenService:Create(clone, tweenInfoFade, { Position = floatPosition }):Play()

		if valueLabel then
			TweenService:Create(valueLabel, tweenInfoFade, { TextTransparency = 1 }):Play()
			local stroke = valueLabel:FindFirstChild("Stroke")
			if stroke then
				TweenService:Create(stroke, tweenInfoFade, { Transparency = 1 }):Play()
			end
		end

		if imageLabel then
			TweenService:Create(imageLabel, tweenInfoFade, { ImageTransparency = 1 }):Play()
		end

		TweenService:Create(clone, tweenInfoFade, { BackgroundTransparency = 1 }):Play()

		task.wait(0.8)
		clone:Destroy()
	end)
end

----------------------------------------------------------------------
-- ItalianBrainrot Fireworks Rockets Implementation
----------------------------------------------------------------------
local fireworkColors = {
	Color3.fromRGB(255, 49, 49),
	Color3.fromRGB(255, 179, 55),
	Color3.fromRGB(255, 255, 53),
	Color3.fromRGB(105, 255, 79),
	Color3.fromRGB(70, 252, 255),
	Color3.fromRGB(193, 85, 255),
	Color3.fromRGB(255, 169, 225),
}

local function launchFireworkRocket(startCFrame)
	task.spawn(function()
		local col = fireworkColors[math.random(1, #fireworkColors)]
		local firework = Instance.new("Part")
		firework.CanCollide = false
		firework.Anchored = true
		firework.Transparency = 1
		firework.CFrame = startCFrame
		firework.Size = Vector3.new(0.2, 0.2, 0.2)
		firework.Name = "firework"
		firework.Parent = workspace:FindFirstChild("__DEBRIS") or workspace

		local cloneTrail = Instance.new("ParticleEmitter")
		cloneTrail.Name = "Firework-Trail"
		cloneTrail.Texture = "rbxassetid://81239262878757" --aqui
		cloneTrail.LightEmission = 0.5
		cloneTrail.LightInfluence = 0.5
		cloneTrail.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1, 0.05),
			NumberSequenceKeypoint.new(1, 0, 0),
		})
		cloneTrail.Transparency = NumberSequence.new(0, 0)
		cloneTrail.ZOffset = 0
		cloneTrail.EmissionDirection = Enum.NormalId.Top
		cloneTrail.Lifetime = NumberRange.new(0.4, 0.8)
		cloneTrail.Rate = 25
		cloneTrail.Rotation = NumberRange.new(0, 360)
		cloneTrail.RotSpeed = NumberRange.new(-200, 200)
		cloneTrail.Speed = NumberRange.new(3, 5)
		cloneTrail.SpreadAngle = Vector2.new(360, 360)
		cloneTrail.Acceleration = Vector3.new(0, -25, 0)
		cloneTrail.Drag = 20
		cloneTrail.LockedToPart = false
		cloneTrail.TimeScale = 1
		cloneTrail.Parent = firework

		local height = rng:NextNumber(8, 11)
		local targetCFrame = startCFrame + Vector3.new(0, height, 0)

		local tween = TweenService:Create(
			firework,
			TweenInfo.new(height / 10, Enum.EasingStyle.Linear),
			{ CFrame = targetCFrame }
		)
		tween:Play()
		tween.Completed:Wait()

		cloneTrail.Enabled = false

		local cloneBurst = Instance.new("ParticleEmitter")
		cloneBurst.Name = "Firework"
		cloneBurst.Texture = "rbxassetid://81239262878757"
		cloneBurst.LightEmission = 0.25
		cloneBurst.LightInfluence = 0.5
		cloneBurst.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.25, 0),
			NumberSequenceKeypoint.new(0.700344, 0.1875, 0),
			NumberSequenceKeypoint.new(1, 0, 0),
		})
		cloneBurst.Transparency = NumberSequence.new(0, 0)
		cloneBurst.ZOffset = 0
		cloneBurst.EmissionDirection = Enum.NormalId.Top
		cloneBurst.Lifetime = NumberRange.new(0.6, 1.2)
		cloneBurst.Rate = 10
		cloneBurst.Rotation = NumberRange.new(0, 360)
		cloneBurst.RotSpeed = NumberRange.new(-80, 80)
		cloneBurst.Speed = NumberRange.new(40, 40)
		cloneBurst.SpreadAngle = Vector2.new(360, 360)
		cloneBurst.Acceleration = Vector3.new(0, -3, 0)
		cloneBurst.Drag = 13
		cloneBurst.LockedToPart = true
		cloneBurst.TimeScale = 1
		cloneBurst.Color = ColorSequence.new(col)
		cloneBurst.Parent = firework
		cloneBurst:Emit(25)

		Debris:AddItem(firework, 4)
	end)
end

local function PlayFireworks(character)
	local upperTorso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("HumanoidRootPart")
	if not upperTorso then
		return
	end

	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://111951469482472"
	sound.Volume = 3.0
	sound.PlaybackSpeed = 1.2
	sound.RollOffMaxDistance = 1000
	sound.Parent = upperTorso
	sound:Play()
	Debris:AddItem(sound, 5)

	task.spawn(function()
		for i = 1, rng:NextInteger(8, 10) do
			if upperTorso and upperTorso.Parent then
				local startPos = upperTorso.CFrame + Vector3.new(rng:NextNumber(-4, 4), -2, rng:NextNumber(-4, 4))
				launchFireworkRocket(startPos)
			end
			task.wait(rng:NextNumber(0.25, 0.5))
		end
	end)
end

----------------------------------------------------------------------
-- Level Up Visual & Sound FX Listener
----------------------------------------------------------------------
local remotes = workspace:WaitForChild("__THINGS"):WaitForChild("__REMOTES")
local levelUpEvent = remotes:WaitForChild("LevelUpEvent", 10)

local function triggerLevelUpFX(newLevel, contractsGained)
	local character = localPlayer.Character
	if not character then
		return
	end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
		or character:FindFirstChild("UpperTorso")
		or character:FindFirstChild("Torso")
	if not rootPart then
		return
	end

	-- 1. Play SFX (Volume boosted to 3.5 and max distance 1000)
	task.spawn(function()
		local sound = Instance.new("Sound")
		sound.SoundId = "rbxassetid://81384934535976"
		sound.Volume = 3.5
		sound.RollOffMaxDistance = 1000
		sound.Parent = rootPart

		local conn
		conn = sound.Loaded:Connect(function()
			sound:Play()
			if conn then
				conn:Disconnect()
			end
		end)

		task.delay(1, function()
			if not sound.IsLoaded or sound.TimeLength == 0 then
				sound.SoundId = "rbxassetid://74665098405326"
				sound.Volume = 3.5
				sound.PlaybackSpeed = 1.25
				sound:Play()
			end
		end)
		Debris:AddItem(sound, 10)
	end)

	-- 2. Emit LevelUp particles attached to a synchronized Attachment
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local effects = assets and assets:FindFirstChild("Effects")
	local levelUpFolder = effects and effects:FindFirstChild("LevelUp")
	if not levelUpFolder then
		levelUpFolder = workspace:FindFirstChild("Particles") and workspace.Particles:FindFirstChild("LevelUp")
	end

	if levelUpFolder then
		local attachPart = character:FindFirstChild("UpperTorso")
			or character:FindFirstChild("HumanoidRootPart")
			or rootPart

		local attachment = Instance.new("Attachment")
		attachment.Name = "LevelUpAttachment"
		attachment.Position = Vector3.new(0, 1.2, 0)
		attachment.Parent = attachPart

		for _, child in ipairs(levelUpFolder:GetChildren()) do
			if child:IsA("ParticleEmitter") then
				local cloneEmitter = child:Clone()
				cloneEmitter.Parent = attachment
				cloneEmitter:Emit(20)
			end
		end

		Debris:AddItem(attachment, 5)
	end

	-- 3. ItalianBrainrot 3D Fireworks Launch Sequence
	PlayFireworks(character)

	-- 4. PopUp 1: Level Up text with StarGradient & image 101332174362668 (1.7s hold duration = 1s longer)
	playCustomPopUpEffect("Level Up", "101332174362668", "StarGradient", -0.06, nil, 1.7)

	-- 5. PopUp 2: Contracts Gained (+X) with ContractGradient & image 130103533864198 (1.7s hold duration = 1s longer)
	task.delay(0.35, function()
		playCustomPopUpEffect("", "130103533864198", "ContractGradient", 0.04, contractsGained, 1.7)
	end)
end

if levelUpEvent then
	levelUpEvent.OnClientEvent:Connect(function(newLevel, contractsGained)
		triggerLevelUpFX(newLevel, contractsGained)
	end)
end

----------------------------------------------------------------------
-- Rank / Level Progression UI (Main.Frame.Right.Rank)
----------------------------------------------------------------------
local rightFrame = mainFrame:FindFirstChild("Right")
local rankFrame = rightFrame and rightFrame:FindFirstChild("Rank")

local LevelModule =
	require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Modules"):WaitForChild("LevelModule"))

local function getLevelData(xp)
	return LevelModule.GetLevelDataFromXP(xp)
end

local function updateRankUI()
	if not rankFrame then
		return
	end

	local xp = localPlayer:GetAttribute("Experience") or 0
	local level, currentXP, targetXP, progress = getLevelData(xp)

	local levelLabel = rankFrame:FindFirstChild("Level")
	if levelLabel then
		levelLabel.Text = "Lvl " .. tostring(level)
	end

	local percentLabel = rankFrame:FindFirstChild("Percent")
	if percentLabel then
		percentLabel.Text = string.format("%d%%", math.floor(progress * 100))
	end

	local progressFrame = rankFrame:FindFirstChild("Progress")
	local barFrame = progressFrame and progressFrame:FindFirstChild("Bar")
	if barFrame then
		TweenService:Create(barFrame, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.new(progress, 0, 1, 0),
		}):Play()
	end
end

local lastBlocks = localPlayer:GetAttribute("Blocks") or 0

localPlayer.AttributeChanged:Connect(function(attr)
	if attr == "Coins" or attr == "Gems" or attr == "Blocks" or attr == "MaxBlocks" or attr == "Contracts" then
		updateHUDText()

		if attr == "Blocks" then
			local newBlocks = localPlayer:GetAttribute("Blocks") or 0
			local diff = newBlocks - lastBlocks
			if diff > 0 then
				playBlockPopUpEffect(diff)
			end
			lastBlocks = newBlocks
		end
	elseif attr == "Experience" or attr == "Level" or attr == "DestructiblesDestroyed" then
		updateRankUI()
	elseif attr == "World" then
		updateWorldStatusVisuals()
	end
end)

-- Initial update
updateWorldStatusVisuals()
updateHUDText()
updateRankUI()
