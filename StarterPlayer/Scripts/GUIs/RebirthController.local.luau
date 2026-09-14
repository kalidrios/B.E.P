--[[
	© DestructionSimulator [2025]
	RebirthController — Client-side controller for the Rebirth GUI window.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local WindowManager = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Client"):WaitForChild("UIFramework"):WaitForChild("WindowManager"))
local Directory = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Directory"))
local Audio = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Audio"))

local remotesFolder = workspace:WaitForChild("__THINGS"):WaitForChild("__REMOTES")
local rebirthRemote = remotesFolder:WaitForChild("PerformRebirth")

local rebirthScreen = playerGui:WaitForChild("Rebirth", 15) or playerGui:WaitForChild("Rebirth")
local frame = rebirthScreen:WaitForChild("Frame")
local mainFrame = frame:WaitForChild("Main")

-- Elements inside Rebirth.Frame.Main
local itensFrame = mainFrame:WaitForChild("Itens", 5) or mainFrame:WaitForChild("Items", 5)
local requirementsFrame = mainFrame:WaitForChild("Requirements")
local reqLevelLabel = requirementsFrame:WaitForChild("CurrentLevel")
local rebirthActionButton = mainFrame:FindFirstChild("Rebirth", true) or mainFrame:FindFirstChild("Confirm", true)

local function playErrorSound()
	if Audio and Audio.Play then
		Audio.Play(101618216035709, playerGui, 1, 1.0)
	end
end

local function playSuccessSound()
	if Audio and Audio.Play then
		Audio.Play(102314941670514, playerGui, 1, 1.0)
	end
end

--- Update Rebirth GUI elements dynamically based on current player data & modular config
local function updateRebirthUI()
	local currentRebirth = player:GetAttribute("Rebirth") or 0
	local nextRebirthTier = currentRebirth + 1

	local rebirthCategory = Directory.Rebirths or Directory.Rebirth
	local rebirthsConfig = (rebirthCategory and rebirthCategory.Rebirths) or rebirthCategory
	local nextConfig = rebirthsConfig and rebirthsConfig[nextRebirthTier]
	local currentConfig = rebirthsConfig and rebirthsConfig[currentRebirth]

	-- Check if player is at Maximum Rebirth level (Rebirth 10 / No next config)
	if not nextConfig then
		-- When max level is reached:
		-- 1. Hide Itens frame
		if itensFrame then
			itensFrame.Visible = false
		end
		-- 2. Hide Main.Rebirth action button
		if rebirthActionButton then
			rebirthActionButton.Visible = false
		end
		-- 3. Show Requirements frame with "Maximum Level Reached"
		if requirementsFrame then
			requirementsFrame.Visible = true
		end
		if reqLevelLabel then
			reqLevelLabel.Text = "Maximum Level Reached"
		end
		return
	end

	-- Normal state: Show Itens, Requirements, and Rebirth button
	if itensFrame then
		itensFrame.Visible = true
	end
	if requirementsFrame then
		requirementsFrame.Visible = true
	end
	if rebirthActionButton then
		rebirthActionButton.Visible = true
	end

	-- Update Level Requirement Label: "Level X Required"
	if reqLevelLabel then
		reqLevelLabel.Text = string.format("Level %d Required", nextConfig.LevelRequired or 75)
	end

	-- Update Itens Frame Labels
	if itensFrame then
		-- 1. Rebirth Row
		local rebirthRow = itensFrame:FindFirstChild("Rebirth")
		if rebirthRow then
			local curLbl = rebirthRow:FindFirstChild("CurrentRebirth")
			local nxtLbl = rebirthRow:FindFirstChild("NextRebirth")
			if curLbl then curLbl.Text = string.format("Rebirth %d", currentRebirth) end
			if nxtLbl then nxtLbl.Text = string.format("Rebirth %d", nextRebirthTier) end
		end

		-- 2. Cash Multiplier Row ("1.2x Cash")
		local cashRow = itensFrame:FindFirstChild("Cash")
		if cashRow then
			local curLbl = cashRow:FindFirstChild("CurrentCash")
			local nxtLbl = cashRow:FindFirstChild("NextCash")
			local curMult = currentConfig and currentConfig.CashMultiplier or (1.0 + (currentRebirth * 0.2))
			local nxtMult = nextConfig.CashMultiplier or (1.0 + (nextRebirthTier * 0.2))

			if curLbl then curLbl.Text = string.format("%.1fx Cash", curMult) end
			if nxtLbl then nxtLbl.Text = string.format("%.1fx Cash", nxtMult) end
		end

		-- 3. Blocks Multiplier Row ("1.2x Blocks")
		local blocksRow = itensFrame:FindFirstChild("Blocks")
		if blocksRow then
			local curLbl = blocksRow:FindFirstChild("CurrentBlocks")
			local nxtLbl = blocksRow:FindFirstChild("NextBlocks")
			local curMult = currentConfig and currentConfig.BlocksMultiplier or (1.0 + (currentRebirth * 0.2))
			local nxtMult = nextConfig.BlocksMultiplier or (1.0 + (nextRebirthTier * 0.2))

			if curLbl then curLbl.Text = string.format("%.1fx Blocks", curMult) end
			if nxtLbl then nxtLbl.Text = string.format("%.1fx Blocks", nxtMult) end
		end
	end
end

-- Setup Rebirth Action Button
local function setupButton(btn)
	if not btn or not btn:IsA("GuiButton") then return end
	btn.Activated:Connect(function()
		local currentRebirth = player:GetAttribute("Rebirth") or 0
		local nextRebirthTier = currentRebirth + 1
		local rebirthCategory = Directory.Rebirths or Directory.Rebirth
		local rebirthsConfig = (rebirthCategory and rebirthCategory.Rebirths) or rebirthCategory
		local nextConfig = rebirthsConfig and rebirthsConfig[nextRebirthTier]

		if not nextConfig then
			playErrorSound()
			if _G.Message and _G.Message.New then
				_G.Message.New("You have already reached the Maximum Rebirth level!", false, "Max Rebirth")
			end
			return
		end

		local msg = string.format(
			"Are you sure you want to perform Rebirth %d? Your level, coins, and base weapons will reset, but you will keep all Skins & Contracts and earn %.1fx Cash & Blocks!",
			nextRebirthTier,
			nextConfig.CashMultiplier or 1.2
		)

		local confirm = _G.Message and _G.Message.New(msg, true, "Perform Rebirth")
		if confirm then
			local success, message = rebirthRemote:InvokeServer()
			if success then
				playSuccessSound()
				updateRebirthUI()
				if _G.Message and _G.Message.New then
					_G.Message.New(message or "Rebirth successful!", false, "Rebirth Success")
				end
				WindowManager.Close(rebirthScreen)
			else
				playErrorSound()
				if _G.Message and _G.Message.New then
					_G.Message.New(message or "Rebirth requirements not met!", false, "Rebirth Locked")
				end
			end
		end
	end)
end

if rebirthActionButton then
	setupButton(rebirthActionButton)
end

-- Connect attribute listeners for real-time UI updates & Exclamtion alert
local LevelModule = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Modules"):WaitForChild("LevelModule"))

local function updateExclamationIndicator()
	local mainGui = playerGui:FindFirstChild("Main") or playerGui:WaitForChild("Main", 5)
	local leftFrame = mainGui and mainGui:FindFirstChild("Frame") and mainGui.Frame:FindFirstChild("Left")
	local rebirthBtn = leftFrame and leftFrame:FindFirstChild("Rebirth")
	local exclam = rebirthBtn and (rebirthBtn:FindFirstChild("Exclamtion") or rebirthBtn:FindFirstChild("Exclamation"))

	if not exclam then return end

	local currentRebirth = player:GetAttribute("Rebirth") or 0
	local nextRebirthTier = currentRebirth + 1

	local rebirthCategory = Directory.Rebirths or Directory.Rebirth
	local rebirthsConfig = (rebirthCategory and rebirthCategory.Rebirths) or rebirthCategory
	local nextConfig = rebirthsConfig and rebirthsConfig[nextRebirthTier]

	if not nextConfig then
		exclam.Visible = false
		return
	end

	local xp = player:GetAttribute("Experience") or 0
	local currentLevel = LevelModule.GetLevelDataFromXP(xp)
	local reqLevel = nextConfig.LevelRequired or 75

	if currentLevel >= reqLevel then
		exclam.Visible = true
	else
		exclam.Visible = false
	end
end

local function refreshAllRebirthUI()
	updateRebirthUI()
	updateExclamationIndicator()
end

player:GetAttributeChangedSignal("Rebirth"):Connect(refreshAllRebirthUI)
player:GetAttributeChangedSignal("Experience"):Connect(refreshAllRebirthUI)

-- Initial UI render
refreshAllRebirthUI()
