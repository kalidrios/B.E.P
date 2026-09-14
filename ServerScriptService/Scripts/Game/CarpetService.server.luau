--[[
	© DestructionSimulator [2025]
	CarpetService — Server-side manager for spawning and equipping Flying Carpets unlocked via Rebirth.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Library = require(ReplicatedStorage:WaitForChild("Library"))
while not Library.IsLoaded() do
	task.wait()
end

local remotesFolder = workspace:WaitForChild("__THINGS"):WaitForChild("__REMOTES")
local toggleCarpetRemote = remotesFolder:FindFirstChild("ToggleCarpet")
if not toggleCarpetRemote then
	toggleCarpetRemote = Instance.new("RemoteEvent")
	toggleCarpetRemote.Name = "ToggleCarpet"
	toggleCarpetRemote.Parent = remotesFolder
end

local activeCarpetModels = {}

local function removeCarpet(player)
	if activeCarpetModels[player] then
		if activeCarpetModels[player].Model and activeCarpetModels[player].Model.Parent then
			activeCarpetModels[player].Model:Destroy()
		end
		activeCarpetModels[player] = nil
	end
	
	local character = player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			local profile = Library.Saving.GetPlayerData(player)
			local runFasterLevel = profile and profile.UpgradesOwned and profile.UpgradesOwned.RunFaster or 0
			local boostMult = player:GetAttribute("StarterBoostActive") and 2 or 1
			humanoid.WalkSpeed = (24 + runFasterLevel * 2) * boostMult
		end
	end
	player:SetAttribute("UsingCarpet", false)
end

local function spawnCarpet(player)
	-- Authoritative Rebirth check via Server Save data (anti-exploit H1)
	local profile = Library.Saving.GetPlayerData(player)
	local rebirthCount = (profile and profile.Rebirth) or 0
	if rebirthCount < 1 then
		warn("[CarpetService] Player " .. player.Name .. " attempted to use Carpet without Rebirth 1!")
		removeCarpet(player)
		return
	end
	
	local character = player.Character
	if not character then return end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not rootPart or not humanoid then return end
	
	removeCarpet(player)
	
	-- Load carpet asset template
	local carpetFolder = ReplicatedStorage:FindFirstChild("Directory") and ReplicatedStorage.Directory:FindFirstChild("Carpet")
	local originalFolder = carpetFolder and carpetFolder:FindFirstChild("Original")
	local carpetDataModule = originalFolder and originalFolder:FindFirstChild("Carpet Data (Original)")
	
	local carpetModel = nil
	if originalFolder then
		carpetModel = originalFolder:FindFirstChildWhichIsA("Model") or originalFolder:FindFirstChildWhichIsA("BasePart")
	end
	
	if not carpetModel then
		-- Fallback procedural carpet platform if model is absent
		local part = Instance.new("Part")
		part.Name = "OriginalCarpet"
		part.Size = Vector3.new(4, 0.4, 6)
		part.Material = Enum.Material.Fabric
		part.Color = Color3.fromRGB(180, 40, 40)
		part.CanCollide = false
		carpetModel = part
	else
		carpetModel = carpetModel:Clone()
	end
	
	carpetModel.Name = "EquippedCarpet"
	
	local primaryPart = carpetModel:IsA("Model") and (carpetModel.PrimaryPart or carpetModel:FindFirstChildWhichIsA("BasePart")) or carpetModel
	if carpetModel:IsA("Model") and not carpetModel.PrimaryPart then
		carpetModel.PrimaryPart = primaryPart
	end
	
	if not primaryPart then return end
	
	primaryPart.CanCollide = false
	primaryPart.Anchored = false
	primaryPart.CFrame = rootPart.CFrame * CFrame.new(0, -2.8, 0)
	
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = rootPart
	weld.Part1 = primaryPart
	weld.Parent = primaryPart
	
	carpetModel.Parent = character
	activeCarpetModels[player] = { Model = carpetModel }
	
	humanoid.WalkSpeed = 35 -- Fast floating speed!
	player:SetAttribute("UsingCarpet", true)
	
	--print("[CarpetService] Successfully spawned Flying Carpet for " .. player.Name)
end

-- Listen for carpet toggles
toggleCarpetRemote.OnServerEvent:Connect(function(player, active)
	if active then
		spawnCarpet(player)
	else
		removeCarpet(player)
	end
end)

Players.PlayerRemoving:Connect(removeCarpet)

--print("[CarpetService] Server Carpet Service initialized!")
