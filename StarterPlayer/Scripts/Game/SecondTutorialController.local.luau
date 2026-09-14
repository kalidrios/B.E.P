--[[
	© DestructionSimulator [2025]
	Game/SecondTutorialController — Standalone Second Tutorial & Guide System

	Handles the secondary milestone guide tutorial (Beam / Guide Arrow to ThirdBeam).
	Runs once in a player's lifetime and permanently persists in DataStore.
	Rewards the player with +30 minutes of StarterBooster (2x Speed & 2x Magnet).
]]--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")
local Audio = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Audio"))

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

-- Assets
local Assets = ReplicatedStorage:WaitForChild("Assets")
local Billboards = Assets:WaitForChild("Billboards")
local TutorialFolder = Billboards:WaitForChild("TutorialArrow", 15)

local BeamAsset = TutorialFolder and (TutorialFolder:FindFirstChild("TutorialBeam") or TutorialFolder:FindFirstChild("Beam"))
local GuideArrowAsset = TutorialFolder and TutorialFolder:FindFirstChild("GuideArrow")

-- Remotes
local RemotesFolder = workspace:WaitForChild("__THINGS"):WaitForChild("__REMOTES")
local CompleteTutorialRemote = RemotesFolder:WaitForChild("CompleteTutorial", 15)

local hasCompletedGuide = false
local activeBeam = nil
local activeArrow = nil
local speedConn = nil

-- Helper to find target beam/arrow part in Workspace or __MAP
local function findTargetPart(folderName, partName)
	local folder = workspace:FindFirstChild(folderName)
	if folder then
		local p = folder:FindFirstChild(partName)
		if p and p:IsA("BasePart") then return p end
	end

	local activeMap = workspace:FindFirstChild("__MAP")
	if activeMap then
		local innerMap = activeMap:FindFirstChild("MAP") or activeMap
		local f = innerMap:FindFirstChild(folderName)
		if f then
			local p = f:FindFirstChild(partName)
			if p and p:IsA("BasePart") then return p end
		end
	end

	return nil
end

local function ensureAttachment(part)
	local att = part:FindFirstChild("GuideAttachment")
	if not att then
		att = Instance.new("Attachment")
		att.Name = "GuideAttachment"
		att.Parent = part
	end
	return att
end

local function getPlayerLevel()
	local levelAttr = localPlayer:GetAttribute("Level")
	if levelAttr and levelAttr > 1 then return levelAttr end
	local exp = localPlayer:GetAttribute("Experience") or 0
	local LevelModule = ReplicatedStorage:FindFirstChild("Library") and ReplicatedStorage.Library:FindFirstChild("Modules") and ReplicatedStorage.Library.Modules:FindFirstChild("LevelModule")
	if LevelModule then
		local levelFromExp = require(LevelModule).GetLevelDataFromXP(exp)
		return (levelFromExp and levelFromExp > 0) and levelFromExp or 1
	end
	return 1
end

local function grantStarterBooster(character)
	local starterBoosterGui = playerGui:FindFirstChild("StarterBooster")
	if not starterBoosterGui then
		local template = game:GetService("StarterGui"):FindFirstChild("StarterBooster")
		if template then
			starterBoosterGui = template:Clone()
			starterBoosterGui.Parent = playerGui
		end
	end

	if not starterBoosterGui then return end

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

		-- Play booster activation sound (respects SFX settings)
		if Audio and Audio.Play then
			Audio.Play(140147432730406, playerGui, 1, 1.0)
		end

		-- Enable 2x Magnet & Speed boost attributes
		localPlayer:SetAttribute("StarterBoostActive", true)

		local function getNormalSpeed()
			local success, Save = pcall(function()
				return require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Client"):WaitForChild("Save"))
			end)
			local save = success and Save and Save.Get()
			local runFasterLevel = (save and save.UpgradesOwned and save.UpgradesOwned.RunFaster) or 0
			return 24 + (runFasterLevel * 2)
		end

		local hum = character and character:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.WalkSpeed = getNormalSpeed() * 2
		end

		if speedConn then speedConn:Disconnect() end
		speedConn = localPlayer.CharacterAdded:Connect(function(newChar)
			if not localPlayer:GetAttribute("StarterBoostActive") then
				if speedConn then speedConn:Disconnect() end
				return
			end
			local newHum = newChar:WaitForChild("Humanoid", 5)
			if newHum then
				newHum.WalkSpeed = getNormalSpeed() * 2
			end
		end)

		-- 30 minutes boost duration (1800 seconds)
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

local function runSecondTutorial(character)
	-- Check if already completed in persistent data
	if hasCompletedGuide or localPlayer:GetAttribute("GuideCompleted") == true then
		hasCompletedGuide = true
		return
	end

	-- Wait until player reaches Level 20
	while character and character.Parent and not hasCompletedGuide do
		if localPlayer:GetAttribute("GuideCompleted") == true then
			hasCompletedGuide = true
			return
		end
		if getPlayerLevel() >= 20 then
			break
		end
		task.wait(1.0)
	end

	if not character or not character.Parent or hasCompletedGuide or localPlayer:GetAttribute("GuideCompleted") == true then
		return
	end

	-- Locate ThirdBeam destination part
	local targetPart = findTargetPart("__Guide_Beam", "ThirdBeam")
	if not targetPart then
		-- Search for any ThirdBeam part in Workspace
		targetPart = workspace:FindFirstChild("ThirdBeam", true)
	end

	if not targetPart then return end

	local hrp = character:WaitForChild("HumanoidRootPart", 10)
	if not hrp then return end

	local playerAtt = hrp:FindFirstChild("TutorialPlayerAttachment") or Instance.new("Attachment", hrp)
	playerAtt.Name = "TutorialPlayerAttachment"

	local targetAtt = ensureAttachment(targetPart)

	if BeamAsset and targetAtt then
		activeBeam = BeamAsset:Clone()
		activeBeam.Name = "ActiveSecondTutorialBeam"
		activeBeam.Attachment0 = playerAtt
		activeBeam.Attachment1 = targetAtt
		activeBeam.Enabled = true
		activeBeam.Parent = character
	end

	if GuideArrowAsset then
		activeArrow = GuideArrowAsset:Clone()
		activeArrow.Name = "ActiveSecondTutorialArrow"
		activeArrow.Adornee = targetPart
		activeArrow.AlwaysOnTop = true
		activeArrow.Enabled = true
		activeArrow.Parent = targetPart
	end

	-- Wait until player arrives / touches the target part
	local touched = false
	local touchConn = targetPart.Touched:Connect(function(hit)
		if hit and hit:IsDescendantOf(character) then
			touched = true
		end
	end)

	while character and character.Parent and not touched do
		if (hrp.Position - targetPart.Position).Magnitude <= 12 then
			touched = true
			break
		end
		task.wait(0.2)
	end

	if touchConn then
		touchConn:Disconnect()
		touchConn = nil
	end

	-- Cleanup guide visual assets
	if activeBeam then
		activeBeam:Destroy()
		activeBeam = nil
	end
	if activeArrow then
		activeArrow:Destroy()
		activeArrow = nil
	end

	-- Mark as completed locally and save persistently in server DataStore
	hasCompletedGuide = true
	localPlayer:SetAttribute("GuideCompleted", true)

	if CompleteTutorialRemote then
		CompleteTutorialRemote:FireServer("SecondTutorial")
	end

	-- Grant +30 minutes of StarterBooster
	grantStarterBooster(character)
end

-- Lifecycle handler
local function onCharacterAdded(character)
	task.wait(1.0)
	task.spawn(function()
		runSecondTutorial(character)
	end)
end

if localPlayer.Character then
	task.spawn(function()
		onCharacterAdded(localPlayer.Character)
	end)
end

localPlayer.CharacterAdded:Connect(onCharacterAdded)
