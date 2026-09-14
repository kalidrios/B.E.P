local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local SocialService = game:GetService("SocialService")

local Library = require(ReplicatedStorage:WaitForChild("Library"))
local Audio = Library.Audio
local WindowManager = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Client"):WaitForChild("UIFramework"):WaitForChild("WindowManager"))

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local Assets = ReplicatedStorage:WaitForChild("Assets")
local Billboards = Assets:WaitForChild("Billboards")
local InteractBillboardTemplate = Billboards:WaitForChild("Interact")

-- Dynamic resolution: __MAP and Interactive may be rebuilt during world transitions
local function getInteractiveFolder()
	local mapFolder = workspace:FindFirstChild("__MAP")
	if not mapFolder then return nil end
	return mapFolder:FindFirstChild("Interactive")
		or (mapFolder:FindFirstChild("MAP") and mapFolder.MAP:FindFirstChild("Interactive"))
		or mapFolder:FindFirstChild("Interactive", true)
end

local RemotesFolder = workspace:WaitForChild("__THINGS"):WaitForChild("__REMOTES")
local SellBlocksRemote = RemotesFolder:WaitForChild("SellBlocks")

-- Configuration mapping for nice labels
local CONFIGS = {
	["RentUrSkins"] = { label = "Rent Skins" },
	["GearShop"] = { label = "Gear Shop" },
	["Sell"] = { label = "Sell Items" },
	["CaseShop"] = { label = "Case Shop" },
	["Teleport"] = { label = "Travel" },
	["TesterPlace"] = { label = "Tester Place" },
}

local triggerInteraction

local EventConfig
pcall(function()
	EventConfig = require(ReplicatedStorage:WaitForChild("Directory"):WaitForChild("Event"):WaitForChild("EventConfig"))
end)

local EVENT_DEFAULT_ID = (EventConfig and EventConfig.EventId) or "5882426026797171320"
local lastEventPromptTime = 0

local function promptEventFollow(eventId)
	eventId = eventId or EVENT_DEFAULT_ID
	local now = os.clock()
	if now - lastEventPromptTime < 4 then return end
	lastEventPromptTime = now
	pcall(function()
		SocialService:PromptRsvpToEventAsync(tostring(eventId))
	end)
end

local function hookEventTouch(interactPart, model)
	if not interactPart or not interactPart:IsA("BasePart") then return end
	if interactPart:GetAttribute("EventTouchHooked") then return end
	interactPart:SetAttribute("EventTouchHooked", true)

	interactPart.Touched:Connect(function(hit)
		local char = hit and hit:FindFirstAncestorOfClass("Model")
		if char and char == Player.Character then
			local eventId = (model and model:GetAttribute("EventId")) or interactPart:GetAttribute("EventId") or EVENT_DEFAULT_ID
			promptEventFollow(eventId)
		end
	end)
end

local lastTesterPlacePromptTime = 0
local function hookTesterPlaceTouch(interactPart, model)
	if not interactPart or not interactPart:IsA("BasePart") then return end
	if interactPart:GetAttribute("TesterPlaceTouchHooked") then return end
	interactPart:SetAttribute("TesterPlaceTouchHooked", true)

	interactPart.Touched:Connect(function(hit)
		local char = hit and hit:FindFirstAncestorOfClass("Model")
		if char and char == Player.Character then
			local now = os.clock()
			if now - lastTesterPlacePromptTime < 4 then return end
			lastTesterPlacePromptTime = now
			if triggerInteraction then
				triggerInteraction(model)
			end
		end
	end)
end

-- Active state
local activeInteractPart = nil
local activeBillboard = nil
local activeConnections = {}

-- Get the correct button icon depending on device
local function getInteractIcon()
	local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	if isMobile then
		return "rbxassetid://71234693148787" -- Tap icon
	else
		return "rbxassetid://126145584133990" -- E Key icon
	end
end

-- Play a quick UI click sound (respects user SFX setting)
local function playClickSound(soundId)
	local save = Library.Save and Library.Save.Get()
	if save and save.Settings and save.Settings.InteractClicks == 2 then
		return
	end
	local audioModule = Audio or Library.Audio
	if audioModule and audioModule.Play then
		audioModule.Play(soundId, nil, 1, 0.5)
	end
end

local rng = Random.new()

local FormatNumber = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Functions"):WaitForChild("FormatNumber"))

local function formatNumber(n)
	return FormatNumber(n)
end

local function playPopUpEffect(amount)
	local popUp = ReplicatedStorage.Assets.Billboards:FindFirstChild("PopUp")
	if not popUp then return end
	
	local clone = popUp:Clone()
	clone.Parent = PlayerGui:FindFirstChild("Main") or PlayerGui:FindFirstChildOfClass("ScreenGui")
	
	local valueLabel = clone:FindFirstChild("Value")
	if valueLabel then
		valueLabel.Text = "+$0"
		valueLabel.TextTransparency = 0
		-- Apply CashGradient from ReplicatedStorage.Assets.Ui.Gradient
		local uiFolder = ReplicatedStorage.Assets:FindFirstChild("Ui") or ReplicatedStorage.Assets:FindFirstChild("UI")
		local gradientFolder = uiFolder and uiFolder:FindFirstChild("Gradient")
		local cashGradient = gradientFolder and (gradientFolder:FindFirstChild("CashGradient") or gradientFolder:FindFirstChild("CashGradiant") or gradientFolder:FindFirstChildWhichIsA("UIGradient"))
		
		if cashGradient then
			valueLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
			local oldGrad = valueLabel:FindFirstChildOfClass("UIGradient")
			if oldGrad then oldGrad:Destroy() end
			local cloneGradient = cashGradient:Clone()
			cloneGradient.Parent = valueLabel
		else
			valueLabel.TextColor3 = Color3.fromRGB(85, 170, 0) -- Cash Green fallback
		end

		local stroke = valueLabel:FindFirstChild("Stroke")
		if stroke then stroke.Transparency = 0 end
		
		-- Count up animation starting from 50% of the amount
		local startVal = math.floor(amount * 0.5)
		local duration = 0.5
		local steps = 12
		task.spawn(function()
			for i = 1, steps do
				local t = i / steps
				local progress = t * (2 - t) -- Easing out quad
				local currentVal = math.floor(startVal + (amount - startVal) * progress)
				valueLabel.Text = "+$" .. formatNumber(currentVal)
				task.wait(duration / steps)
			end
			valueLabel.Text = "+$" .. formatNumber(amount)
		end)
	end
	
	local imageLabel = clone:FindFirstChild("Image")
	if imageLabel then
		imageLabel.Image = "rbxassetid://88042139468762"
		imageLabel.ImageTransparency = 0
		imageLabel.Visible = true
	end
	
	local targetSize = clone.Size
	clone.Size = UDim2.fromScale(0, 0)
	
	-- Position with a slight random offset near the center to avoid overlapping
	local randomOffset = UDim2.fromScale(
		0.5 + rng:NextNumber(-0.06, 0.06),
		0.5 + rng:NextNumber(-0.06, 0.06)
	)
	clone.Position = randomOffset
	
	-- Pop in animation
	local tweenInfoPop = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(clone, tweenInfoPop, { Size = targetSize }):Play()
	
	-- Wait before float up and fade out
	task.delay(0.6, function()
		local tweenInfoFade = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		
		-- Float up target
		local floatPosition = UDim2.fromScale(
			clone.Position.X.Scale,
			clone.Position.Y.Scale - 0.15
		)
		
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

-- Perform the interaction (open GUI, etc.)
triggerInteraction = function(model)
	local guiName = model.Name
	if guiName == "Sell" then
		local result = SellBlocksRemote:InvokeServer()
		local audioModule = Audio or Library.Audio
		if result and result.blocksSold and result.blocksSold > 0 then
			if audioModule and audioModule.Play then
				audioModule.Play(87162589426939, nil, 1, 0.7) -- Cash sell transaction sound
			end
			
			local interactPart = model:FindFirstChild("Interact")
			
			-- 1. Spawn orbs flying out of the Sell interact part
			if interactPart and _G.SpawnSellOrbs then
				local orbCount = math.clamp(result.blocksSold, 5, 20)
				_G.SpawnSellOrbs(interactPart.Position, orbCount)
			end
			
			-- 2. Emit money Effects from the Money attachment
			local moneyTemplate = ReplicatedStorage.Assets.Effects:FindFirstChild("Money")
			if moneyTemplate and interactPart then
				local effect = moneyTemplate:Clone()
				effect.Parent = interactPart
				for _, emitter in ipairs(effect:GetDescendants()) do
					if emitter:IsA("ParticleEmitter") then
						emitter:Emit(emitter:GetAttribute("EmitCount") or 15)
					end
				end
				Debris:AddItem(effect, 3)
			end
			
			-- 3. Show screen PopUp feedback with the earned cash amount
			if result.cashEarned then
				playPopUpEffect(result.cashEarned)
			end
		else
			if audioModule and audioModule.Play then
				audioModule.Play(101618216035709, nil, 1, 0.5) -- Error sound (no blocks to sell)
			end
		end
		return
	end

	if guiName == "TesterPlace" or model.Name == "TesterPlace" or (model.Parent and model.Parent.Name == "TesterPlace") then
		task.spawn(function()
			local confirm = true
			if _G.Message and _G.Message.New then
				confirm = _G.Message.New("Would you like to travel to Tester Place?", true, "Travel")
			end
			if confirm then
				local TeleportService = game:GetService("TeleportService")
				local placeId = model:GetAttribute("PlaceId") or 88456767102569

				playClickSound(86741954558061)

				-- Request teleport through server authority first
				local remotesFolder = workspace:FindFirstChild("__THINGS") and workspace.__THINGS:FindFirstChild("__REMOTES")
				local teleportRemote = remotesFolder and remotesFolder:FindFirstChild("TeleportToPlace")
				if teleportRemote and teleportRemote:IsA("RemoteFunction") then
					local ok, err = pcall(function()
						return teleportRemote:InvokeServer(placeId)
					end)
					if ok and err == true then
						return
					end
				end

				-- Fallback to client-side teleport
				local success, err = pcall(function()
					TeleportService:Teleport(placeId, Player)
				end)
				if not success and err then
					warn("[TesterPlace] Teleport failed: " .. tostring(err))
					if _G.Message and _G.Message.New then
						_G.Message.New("Teleport failed: " .. tostring(err), false, "Travel Failed")
					end
				end
			end
		end)
		return
	end

	if guiName == "Event" or model.Name == "Event" or (model.Parent and model.Parent.Name == "Event") then
		local eventId = model:GetAttribute("EventId") or (model.Parent and model.Parent:GetAttribute("EventId")) or EVENT_DEFAULT_ID
		promptEventFollow(eventId)
		return
	end

	if guiName == "Teleport" or (model.Parent and model.Parent.Name == "Teleport") or model.Name == "UGC_Sandbox" then
		task.spawn(function()
			local targetWorld = model:GetAttribute("World")
				or model:GetAttribute("TargetWorld")
				or model:GetAttribute("Destination")

			if not targetWorld or targetWorld == "" or targetWorld == "__MAP" or targetWorld == "MAP" or targetWorld == "Teleport" or targetWorld == "Portal" then
				if model.Name ~= "Teleport" and model.Name ~= "__MAP" and model.Name ~= "MAP" and model.Name ~= "Interactive" and model.Name ~= "Portal" then
					targetWorld = model.Name
				elseif model:FindFirstChild("Magic") then
					targetWorld = "Magic"
				elseif model:FindFirstChild("Spawn") then
					targetWorld = "Spawn"
				elseif model.Parent and model.Parent.Name ~= "Teleport" and model.Parent.Name ~= "__MAP" and model.Parent.Name ~= "MAP" and model.Parent.Name ~= "Interactive" then
					targetWorld = model.Parent.Name
				else
					targetWorld = "Magic"
				end
			end

			-- Server-side verified UGC Claim prompt
			if targetWorld == "UGC_Sandbox" or targetWorld == "UGC" then
				local isEligible = Player:GetAttribute("UGC_Eligible_76844588440579") or false
				local rebirths = Player:GetAttribute("Rebirth") or 0
				-- ClaimUGCGate CONSUMES 15 Rebirths to unlock the vault, so players who
				-- already paid can be sitting at lower Rebirths. The persisted vault flag
				-- (restored on join by GameInit) counts as qualification too.
				local ownsVault = Player:GetAttribute("OwnsUGCVault") or false

				if not isEligible and not ownsVault and rebirths < 15 then
					_G.Message.New("You need at least 15 Rebirths to qualify for the UGC Reward!", false, "UGC Locked")
					return
				end

				-- Requirement: join our Community Group (1105415251). The old
				-- "favorite the game/UGC" step was REMOVED -- Roblox exposes no API to
				-- verify a favorite, so it silently blocked legitimate players from
				-- claiming. The group check IS verifiable and is re-enforced server-side
				-- in UGCAuthService (RequestUGCPrompt), which is the real authority.
				local isInCommunity = false
				local groupOk, groupRes = pcall(function()
					return Player:IsInGroup(1105415251)
				end)
				if groupOk then isInCommunity = groupRes end

				if not isInCommunity then
					_G.Message.New("Please Join our Community Group (ID: 1105415251) to qualify for the UGC Reward!", false, "Community Required")
					return
				end

				local confirm = _G.Message.New(
					"Would you like to open the UGC Purchase prompt? (Requirements satisfied!)",
					true,
					"Claim UGC Item"
				)
				if confirm then
					local remotesFolder = workspace:WaitForChild("__THINGS"):WaitForChild("__REMOTES")
					local promptRemote = remotesFolder:FindFirstChild("RequestUGCPrompt")
					if promptRemote then
						promptRemote:FireServer(76844588440579)
					end
				end
				return
			end

			local dirWorlds = ReplicatedStorage:FindFirstChild("Directory") and ReplicatedStorage.Directory:FindFirstChild("Worlds")
			local worldModule = dirWorlds and (dirWorlds:FindFirstChild(targetWorld) or dirWorlds:FindFirstChild(model.Name))
			local worldConfig = nil
			if worldModule and worldModule:IsA("ModuleScript") then
				pcall(function()
					worldConfig = require(worldModule)
				end)
			end

			if worldConfig and targetWorld ~= "Spawn" then
				if worldConfig.Disabled then
					_G.Message.New("This world is currently coming soon!", false, "World Locked")
					return
				end

				local rebirths = Player:GetAttribute("Rebirth") or 0
				if (worldConfig.RequiredRebirths or 0) > 0 and rebirths < worldConfig.RequiredRebirths then
					_G.Message.New(string.format("You need Rebirth %d or higher to travel to %s!", worldConfig.RequiredRebirths, worldConfig.DisplayName or targetWorld), false, "Rebirth Required")
					return
				end

				local level = Player:GetAttribute("Level") or 1
				if (worldConfig.RequiredLevel or 0) > 0 and level < worldConfig.RequiredLevel then
					_G.Message.New(string.format("You need Level %d or higher to travel to %s!", worldConfig.RequiredLevel, worldConfig.DisplayName or targetWorld), false, "Level Required")
					return
				end
			end

			local displayName = (worldConfig and worldConfig.DisplayName) or targetWorld
			local confirm = _G.Message.New(
				"Would you like to travel to " .. displayName .. "?",
				true,
				"Travel"
			)
			if confirm and _G.WorldLoader then
				local ok, err = _G.WorldLoader.Load(targetWorld)
				if not ok and err then
					_G.Message.New(tostring(err), false, "Travel Failed")
				end
			end
		end)
		return
	end

	playClickSound(86741954558061) -- Play click release sound
	
	-- Map model names to their corresponding ScreenGui names when they differ
	local guiLookup = guiName
	if guiName == "CaseShop" then
		guiLookup = "ExclusiveShop"
	end

	local targetGui = PlayerGui:FindFirstChild(guiLookup) 
		or PlayerGui:FindFirstChild(guiLookup .. "Gui") 
		or PlayerGui:FindFirstChild(string.gsub(guiLookup, " ", ""))
	
	if targetGui and targetGui:IsA("ScreenGui") then
		WindowManager.Open(targetGui)
	else
		print("[InteractController] Interacted with: " .. guiName .. " (No GUI Screen found)")
	end
end

-- Create and show the billboard above the Interact part
-- Create and show the billboard above the Interact part
local function showBillboard(interactPart)
	if activeBillboard or not interactPart then return end
	
	local model = interactPart:FindFirstAncestorOfClass("Model") or interactPart.Parent
	if not model or model.Name == "Event" or (model.Parent and model.Parent.Name == "Event") then
		return
	end
	
	local config = CONFIGS[model.Name]
		or (model.Parent and CONFIGS[model.Parent.Name])
		or { label = model.Name }
	
	local billboard = InteractBillboardTemplate:Clone()
	local button = billboard:WaitForChild("Button")
	local label = button:WaitForChild("Label")
	local icon = button:WaitForChild("Back"):WaitForChild("Icon")
	
	-- Setup content
	label.Text = config.label or "Interact"
	icon.Image = getInteractIcon()
	
	-- Premium animations: Pop-in scale transition
	local targetSize = billboard.Size
	billboard.Size = UDim2.new(0, 0, 0, 0)
	billboard.Adornee = interactPart
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 60
	billboard.StudsOffset = Vector3.new(0, 0.5, 0)
	billboard.Enabled = true
	billboard.Parent = PlayerGui
	
	TweenService:Create(billboard, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = targetSize
	}):Play()
	
	activeBillboard = billboard
	
	-- Button interactions
	local btnPressed = false
	
	local function onPressDown()
		if btnPressed then return end
		btnPressed = true
		playClickSound(87485609714706) -- Click press sound
		
		TweenService:Create(button.Back, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.new(0.85, 0, 0.85, 0)
		}):Play()
	end
	
	local function onPressUp()
		if not btnPressed then return end
		btnPressed = false
		
		TweenService:Create(button.Back, TweenInfo.new(0.2, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {
			Size = UDim2.new(1, 0, 1, 0)
		}):Play()
		
		triggerInteraction(model)
	end
	
	local function onActivated()
		playClickSound(87485609714706) -- Click press sound
		button.Back.Size = UDim2.new(0.85, 0, 0.85, 0)
		TweenService:Create(button.Back, TweenInfo.new(0.2, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {
			Size = UDim2.new(1, 0, 1, 0)
		}):Play()
		triggerInteraction(model)
	end
	
	table.insert(activeConnections, button.Activated:Connect(onActivated))
	
	-- Support E key on Desktop
	table.insert(activeConnections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.KeyCode == Enum.KeyCode.E then
			onPressDown()
		end
	end))
	
	table.insert(activeConnections, UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.E then
			onPressUp()
		end
	end))
end

-- Hide and destroy the billboard
local function hideBillboard()
	if not activeBillboard then return end
	
	local billboard = activeBillboard
	activeBillboard = nil
	
	-- Disconnect events
	for _, conn in ipairs(activeConnections) do
		conn:Disconnect()
	end
	activeConnections = {}
	
	-- Premium animations: Pop-out scale transition
	local tween = TweenService:Create(billboard, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
		Size = UDim2.new(0, 0, 0, 0)
	})
	tween:Play()
	tween.Completed:Connect(function()
		billboard:Destroy()
	end)
end

-- Main proximity loop
task.spawn(function()
	while true do
		task.wait(0.1)
		
		local character = Player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		
		if hrp then
			local myPos = hrp.Position
			local closestPart = nil
			local minDistance = 16 -- Range threshold: 16 studs
			
			local mapFolder = workspace:FindFirstChild("__MAP")
			local testerPlace = workspace:FindFirstChild("TesterPlace")
				or (mapFolder and mapFolder:FindFirstChild("TesterPlace", true))

			if not mapFolder and not testerPlace then
				if activeInteractPart then
					hideBillboard()
					activeInteractPart = nil
				end
				continue
			end

			local candidateRoots = {}
			if testerPlace and not table.find(candidateRoots, testerPlace) then
				table.insert(candidateRoots, testerPlace)
			end

			if mapFolder then
				local knownNames = { "Interactive", "Teleport", "Teleports", "Portals", "Portal", "Travel", "Events", "Event", "TesterPlace" }
				for _, name in ipairs(knownNames) do
					for _, folder in ipairs(mapFolder:GetDescendants()) do
						if folder.Name == name and (folder:IsA("Folder") or folder:IsA("Model")) then
							if not table.find(candidateRoots, folder) then
								table.insert(candidateRoots, folder)
							end
						end
					end
				end

				local innerMap = mapFolder:FindFirstChild("MAP") or mapFolder
				for _, child in ipairs(innerMap:GetChildren()) do
					if child:IsA("Model") and (CONFIGS[child.Name] or child:FindFirstChild("Interact") or child:FindFirstChild("Teleport") or child:FindFirstChild("Pad")) then
						if not table.find(candidateRoots, child) then
							table.insert(candidateRoots, child)
						end
					end
				end
			end

			for _, root in ipairs(candidateRoots) do
				local items = root:IsA("Model") and { root } or root:GetChildren()
				for _, item in ipairs(items) do
					local interactPart = nil
					if item:IsA("BasePart") then
						interactPart = item
					elseif item:IsA("Model") then
						interactPart = item:FindFirstChild("Interact")
							or item:FindFirstChild("Pad")
							or item:FindFirstChild("Hitbox")
							or item:FindFirstChild("Teleport")
							or item:FindFirstChild("Portal")
							or item.PrimaryPart
							or item:FindFirstChildWhichIsA("BasePart")
					end

					if interactPart and interactPart:IsA("BasePart") then
						local model = interactPart:FindFirstAncestorOfClass("Model") or interactPart.Parent
						if model and (model.Name == "Event" or (model.Parent and model.Parent.Name == "Event")) then
							hookEventTouch(interactPart, model)
							local dist = (interactPart.Position - myPos).Magnitude
							if dist < 8 then
								local eventId = model:GetAttribute("EventId") or interactPart:GetAttribute("EventId") or EVENT_DEFAULT_ID
								promptEventFollow(eventId)
							end
						elseif model and (model.Name == "TesterPlace" or (model.Parent and model.Parent.Name == "TesterPlace")) then
							hookTesterPlaceTouch(interactPart, model)
							local dist = (interactPart.Position - myPos).Magnitude
							if dist < minDistance then
								closestPart = interactPart
								minDistance = dist
							end
						else
							local dist = (interactPart.Position - myPos).Magnitude
							if dist < minDistance then
								closestPart = interactPart
								minDistance = dist
							end
						end
					end
				end
			end
			
			if closestPart then
				if activeInteractPart ~= closestPart then
					hideBillboard()
					activeInteractPart = closestPart
					showBillboard(closestPart)
				end
			else
				if activeInteractPart then
					hideBillboard()
					activeInteractPart = nil
				end
			end
		else
			if activeInteractPart then
				hideBillboard()
				activeInteractPart = nil
			end
		end
	end
end)

-- Server->player UGC feedback channel. UGCAuthService (server) cannot use
-- _G.Message (client-only), so it fires UGCNotifyMessage; show it as a modal.
task.spawn(function()
	local ok, notifyRemote = pcall(function()
		return RemotesFolder:WaitForChild("UGCNotifyMessage", 20)
	end)
	if ok and notifyRemote then
		notifyRemote.OnClientEvent:Connect(function(text, title)
			if _G.Message and _G.Message.New then
				_G.Message.New(tostring(text), false, tostring(title or "UGC"))
			end
		end)
	end
end)

-- Listener for UGCGranted: Triggered ONLY after server confirms UGC grant
local hasPromptedFeedbackThisSession = false
task.spawn(function()
	local ok, ugcGrantedRemote = pcall(function()
		return RemotesFolder:WaitForChild("UGCGranted", 20)
	end)
	if ok and ugcGrantedRemote then
		ugcGrantedRemote.OnClientEvent:Connect(function(assetId)
			if hasPromptedFeedbackThisSession then return end
			hasPromptedFeedbackThisSession = true

			-- Short delay so the player reads the UGC Claimed modal
			task.wait(1.5)

			local SocialService = game:GetService("SocialService")
			pcall(function()
				SocialService:PromptFeedbackSubmissionAsync()
			end)
		end)
	end
end)

--print(" Proximity InteractController initialized.")
