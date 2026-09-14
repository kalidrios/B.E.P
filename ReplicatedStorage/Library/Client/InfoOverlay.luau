--[[
	InfoOverlay.luau — Displays item tooltip popups (info cards) for hover events in Destruction Simulator.
	Integrated with the custom skin float, rarity gradient, and modular block system.
]]--

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")

local Library = require(ReplicatedStorage:WaitForChild("Library"))
local Functions = Library.Functions
local Variables = Library.Variables
local Assets = ReplicatedStorage:WaitForChild("Assets")

local InfoOverlayAssets = Assets.UI.InfoOverlay
local BlocksFolder = InfoOverlayAssets:WaitForChild("Blocks")
local GuiInset = GuiService:GetGuiInset()

local currentOverlayInstance = nil
local cachedBlockModules = {}
local activeEventConnections = {}
local InfoOverlayGui = nil

local InfoOverlayController = {}

-- Spawns or updates tooltip overlay attached to a UI element
function InfoOverlayController.Add(targetElement, ...)
	if currentOverlayInstance then
		InfoOverlayController.Remove()
	end

	local baseCardTemplate = InfoOverlayAssets:FindFirstChild("Base")
	if not baseCardTemplate then
		return
	end

	local overlayCard = baseCardTemplate:Clone()
	local calculatedMaxWidth = 0
	local verticalDirection = "Down"

	local blockDefinitions = { ... }
	for blockOrderIndex, blockArgs in ipairs(blockDefinitions) do
		local blockName = blockArgs[1]
		local blockTemplate = BlocksFolder:FindFirstChild(blockName)
		if not blockTemplate then
			continue
		end

		local blockClone = blockTemplate:Clone()
		local modulesFolder = BlocksFolder:FindFirstChild("Modules")
		local blockModuleFolder = modulesFolder and modulesFolder:FindFirstChild(blockName)

		local blockScript = (blockModuleFolder and blockModuleFolder:FindFirstChild("code"))
			or (modulesFolder and modulesFolder:FindFirstChild(blockName) and modulesFolder[blockName]:IsA("ModuleScript") and modulesFolder[blockName])
			or (blockClone:FindFirstChild("settings") and blockClone.settings:FindFirstChild("code"))
			or blockClone:FindFirstChild("code")

		if blockScript then
			coroutine.wrap(function()
				local blockHandler = cachedBlockModules[blockName] or require(blockScript)
				cachedBlockModules[blockName] = blockHandler
				blockHandler(blockClone, unpack(blockArgs))
			end)()
		end

		blockClone.LayoutOrder = blockOrderIndex * 100
		blockClone.Parent = overlayCard.Frame.Blocks

		local settingsConfig = blockClone:FindFirstChild("settings")
		if not settingsConfig then
			continue
		end

		local boundsVector = settingsConfig:GetAttribute("boundsX") or Vector2.new(65, 260)
		local minWidth = boundsVector.X
		local maxWidth = boundsVector.Y
		local maxChildContentWidth = 0
		local totalTextHeight = 0
		local totalOtherHeight = 0

		for _, childObject in ipairs(blockClone:GetChildren()) do
			if not childObject:IsA("GuiObject") or not childObject.Visible then
				continue
			end
			if childObject:IsA("TextLabel") or childObject:IsA("TextButton") then
				if childObject.Size.X.Scale == 0 then
					continue
				end
				local textConstraint = Vector2.new(maxWidth * childObject.Size.X.Scale, 1000)
				local renderedTextSize = TextService:GetTextSize(
					childObject.ContentText,
					childObject.TextSize,
					childObject.Font,
					textConstraint
				) + Vector2.new(4, 1)
				maxChildContentWidth = math.max(renderedTextSize.X, maxChildContentWidth)
				totalTextHeight = totalTextHeight + math.max(renderedTextSize.Y, blockClone.AbsoluteSize.Y)
				childObject.Size = UDim2.new(0, renderedTextSize.X, 0, renderedTextSize.Y)
				continue
			end
			if childObject.Size.X.Scale == 0 then
				continue
			end
			totalOtherHeight = totalOtherHeight + childObject.AbsoluteSize.Y
		end

		local horizontalLayout = blockClone:FindFirstChildOfClass("UIListLayout")
		if horizontalLayout and horizontalLayout.FillDirection == Enum.FillDirection.Horizontal then
			maxChildContentWidth = math.max(horizontalLayout.AbsoluteContentSize.X, maxChildContentWidth)
		end

		local gridLayout = blockClone:FindFirstChildOfClass("UIGridLayout")
		if gridLayout then
			totalTextHeight = math.max(gridLayout.AbsoluteContentSize.Y, totalTextHeight)
		end

		blockClone.Size = UDim2.new(1, 0, 0, totalTextHeight + totalOtherHeight)
		local clampedWidth = math.clamp(maxChildContentWidth, minWidth, maxWidth)
		calculatedMaxWidth = math.max(clampedWidth, calculatedMaxWidth)
	end

	local blocksContainerPadding = overlayCard.Frame.Blocks:FindFirstChildOfClass("UIPadding")
	local blocksListLayout = overlayCard.Frame.Blocks:FindFirstChildOfClass("UIListLayout")
	if blocksListLayout then
		blocksListLayout:ApplyLayout()
	end

	local paddingX = blocksContainerPadding and (blocksContainerPadding.PaddingLeft.Offset + blocksContainerPadding.PaddingRight.Offset) or 0
	local paddingY = blocksContainerPadding and (blocksContainerPadding.PaddingTop.Offset + blocksContainerPadding.PaddingBottom.Offset) or 0
	local totalContentHeight = blocksListLayout and blocksListLayout.AbsoluteContentSize.Y or 0

	overlayCard.Size = UDim2.new(0, calculatedMaxWidth + paddingX, 0, totalContentHeight + paddingY)
	overlayCard.UIScale.Scale = (1 - (1 - math.min(Functions.ResolutionScale(), 1)) / 1.5) * 0.9

	if not InfoOverlayGui then
		InfoOverlayGui = Instance.new("ScreenGui")
		InfoOverlayGui.DisplayOrder = 100
		InfoOverlayGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
		InfoOverlayGui.ResetOnSpawn = false
		InfoOverlayGui.Name = "InfoOverlay"
		InfoOverlayGui.Parent = Players.LocalPlayer.PlayerGui
	end

	overlayCard.Parent = InfoOverlayGui
	currentOverlayInstance = overlayCard

	-- Determine rarity from block arguments
	local activeRarityName = nil
	for _, blockArgs in ipairs(blockDefinitions) do
		if blockArgs[1] == "Rarity" and blockArgs[2] then
			activeRarityName = blockArgs[2]
			break
		end
	end

	-- Apply dynamic gradient based on skin rarity
	if activeRarityName then
		local gradientFolder = Assets.UI:FindFirstChild("Gradient")
		local raritysFolder = (gradientFolder and gradientFolder:FindFirstChild("Raritys")) or Assets.UI:FindFirstChild("Raritys")
		local rarityGradients = raritysFolder and raritysFolder:FindFirstChild("InfoOverlay")
		local rarityGradient = rarityGradients and rarityGradients:FindFirstChild(activeRarityName)

		if rarityGradient then
			local cardStroke = overlayCard.Frame:FindFirstChildOfClass("UIStroke")
			if cardStroke then
				cardStroke.Color = Color3.new(1, 1, 1)
				local clonedGradient = rarityGradient:Clone()
				clonedGradient.Parent = cardStroke

				if activeRarityName == "Legendary" or activeRarityName == "Convert" then
					coroutine.wrap(function()
						while overlayCard and overlayCard.Parent do
							clonedGradient.Rotation = os.clock() * 250
							RunService.RenderStepped:Wait()
						end
					end)()
				end
			end

			if rarityGradient.Color and #rarityGradient.Color.Keypoints > 0 then
				local initialColor = rarityGradient.Color.Keypoints[1].Value
				if overlayCard:FindFirstChild("pointer") and overlayCard.pointer:FindFirstChild("pointer") then
					overlayCard.pointer.pointer.ImageColor3 = initialColor
				end
			end
		end
	end

	-- Smooth positioning loop tracking cursor or selected GUI element
	coroutine.wrap(function()
		local mouse = Players.LocalPlayer:GetMouse()
		local currentCamera = workspace.CurrentCamera

		while overlayCard and overlayCard.Parent do
			local mouseX = mouse.X
			local mouseY = mouse.Y
			local cardWidth = overlayCard.AbsoluteSize.X
			local cardHeight = overlayCard.AbsoluteSize.Y
			local viewportWidth = currentCamera.ViewportSize.X - GuiInset.X
			local viewportHeight = currentCamera.ViewportSize.Y - GuiInset.Y

			if Variables.Console then
				mouseX = targetElement.AbsolutePosition.X + targetElement.AbsoluteSize.X * 0.5
				mouseY = targetElement.AbsolutePosition.Y + targetElement.AbsoluteSize.Y * 0.5
			end

			if mouseY + cardHeight + 10 < viewportHeight then
				verticalDirection = "Down"
			elseif mouseY - cardHeight - 10 > 0 then
				verticalDirection = "Up"
			end

			local maxX = viewportWidth - cardWidth
			local maxY = viewportHeight + (verticalDirection == "Down" and -cardHeight or cardHeight)
			local targetX = mouseX + 10
			local targetY = mouseY + (verticalDirection == "Down" and 10 or -10)

			overlayCard.AnchorPoint = Vector2.new(0, (verticalDirection == "Down") and 0 or 1)
			overlayCard.Position = UDim2.new(0, math.clamp(targetX, 0, maxX), 0, math.clamp(targetY, 0, maxY))
			RunService.RenderStepped:Wait()
		end
	end)()

	-- Hover boundary tracking / dismissal
	coroutine.wrap(function()
		local mouse = Players.LocalPlayer:GetMouse()
		local isSurfaceElement = targetElement:GetAttribute("SurfaceElement")

		if isSurfaceElement then
			local leaveConn = nil
			leaveConn = targetElement.MouseLeave:Connect(function()
				InfoOverlayController.Remove()
				if leaveConn then
					leaveConn:Disconnect()
				end
			end)
			return
		end

		while overlayCard and overlayCard.Parent do
			local mouseX = mouse.X
			local mouseY = mouse.Y
			local elemPosX = targetElement.AbsolutePosition.X
			local elemPosY = targetElement.AbsolutePosition.Y
			local elemWidth = targetElement.AbsoluteSize.X
			local elemHeight = targetElement.AbsoluteSize.Y

			if not Variables.Console then
				if (mouseX < elemPosX) or (mouseX > elemPosX + elemWidth) or (mouseY < elemPosY) or (mouseY > elemPosY + elemHeight) then
					InfoOverlayController.Remove()
				end
			elseif GuiService.SelectedObject ~= targetElement then
				InfoOverlayController.Remove()
			end
			RunService.RenderStepped:Wait()
		end
	end)()

	-- Mobile tap dismiss handler
	if Variables.Mobile then
		local clickStartTime = tick()
		local mobileTapConn = nil
		mobileTapConn = targetElement.MouseButton1Up:Connect(function()
			if mobileTapConn then
				mobileTapConn:Disconnect()
			end
			if tick() - clickStartTime < 0.5 then
				InfoOverlayController.Remove()
			end
		end)
		table.insert(activeEventConnections, mobileTapConn)
	end
end

-- Dismisses active tooltip overlay
function InfoOverlayController.Remove()
	if currentOverlayInstance then
		for _, connection in ipairs(activeEventConnections) do
			if typeof(connection) == "RBXScriptConnection" then
				connection:Disconnect()
			end
		end
		activeEventConnections = {}
		currentOverlayInstance:Destroy()
		currentOverlayInstance = nil
	end
end

return InfoOverlayController
