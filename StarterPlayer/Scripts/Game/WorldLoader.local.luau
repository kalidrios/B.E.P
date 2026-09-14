--[[
	© DestructionSimulator [2025]
	Game/WorldLoader — Client-side world loading controller matching ItalianBrainrotSimulator (IBS)

	Supports independent multi-world presence:
	- Teleporting only affects the LocalPlayer.
	- Displays LoadingScreen, keeps character safely in current world while loading,
	  waits for foundational assets (PlayerSpawn, Grass, Walls) in workspace.__MAP[worldName],
	  applies lighting locally, teleports to the world spawn, and dismisses LoadingScreen.
]]--

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local RemotesFolder = workspace:WaitForChild("__THINGS"):WaitForChild("__REMOTES")
local RequestWorldRemote = RemotesFolder:WaitForChild("RequestWorld")

local WorldLoader = {}
_G.WorldLoader = WorldLoader
WorldLoader.Current = nil

-- Client-side spawn lookup: reads the PlayerSpawn parts directly from MAP.PlayerSpawn
local function getSpawnCFrame(worldFolder)
	if not worldFolder then
		local container = workspace:FindFirstChild("__MAP")
		worldFolder = container and (container:FindFirstChild("Spawn") or container:GetChildren()[1] or container)
	end
	if not worldFolder then return nil end

	local map = worldFolder:FindFirstChild("MAP") or worldFolder
	local playerSpawnFolder = map:FindFirstChild("PlayerSpawn")

	if playerSpawnFolder then
		local spawnParts = playerSpawnFolder:GetChildren()
		if #spawnParts == 0 then
			playerSpawnFolder:WaitForChild("Spawn", 3)
			spawnParts = playerSpawnFolder:GetChildren()
		end

		if #spawnParts > 0 then
			local chosen = spawnParts[math.random(1, #spawnParts)]
			if chosen:IsA("BasePart") then
				return chosen.CFrame + Vector3.new(0, 3, 0)
			end
		end
	end

	return worldFolder:GetPivot() + Vector3.new(0, 10, 0)
end

-- Fast tween helper
local function fastTween(target, properties, duration, style, direction)
	local info = TweenInfo.new(
		duration or 0.5,
		style or Enum.EasingStyle.Sine,
		direction or Enum.EasingDirection.Out
	)
	local tween = TweenService:Create(target, info, properties)
	tween:Play()
	return tween
end

-- Controls LoadingScreen UI lifecycle and animations
local function showLoadingScreen()
	local screen = PlayerGui:FindFirstChild("LoadingScreen")
	if not screen then
		local template = StarterGui:FindFirstChild("LoadingScreen")
		if template then
			screen = template:Clone()
			screen.Parent = PlayerGui
		end
	end

	if not screen then return nil end

	local frame = screen:FindFirstChild("Frame")
	if not frame then return nil end

	local logo = frame:FindFirstChild("Logo")
	local loading = frame:FindFirstChild("Loading")
	local bg = loading and loading:FindFirstChild("Background")
	local fill = bg and bg:FindFirstChild("Fill")
	local fade = frame:FindFirstChild("Fade")
	local skip = frame:FindFirstChild("Skip")
	local notice = frame:FindFirstChild("Notice")

	if skip then skip.Visible = false end
	if notice then notice.Visible = false end

	screen.Enabled = true
	frame.Position = UDim2.new(0.5, 0, 0.5, 0)
	if fade then
		fade.Position = UDim2.new(0, 0, 1, 0)
		fade.Visible = false
	end

	-- Logo Pop-In
	if logo then
		local originalLogoSize = UDim2.new(0.123, 45, 0.172, 45)
		logo.Size = UDim2.new(originalLogoSize.X.Scale * 0.6, originalLogoSize.X.Offset * 0.6, originalLogoSize.Y.Scale * 0.6, originalLogoSize.Y.Offset * 0.6)
		logo.ImageTransparency = 0.2
		logo.Visible = true
		fastTween(logo, { Size = originalLogoSize, ImageTransparency = 0 }, 0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end

	-- Loading Bar Pop-In & Wave
	local waveRunning = true
	if loading and fill then
		local loadingBasePos = UDim2.new(0.5, 0, 0.8, -5)
		loading.Position = UDim2.new(loadingBasePos.X.Scale, loadingBasePos.X.Offset, loadingBasePos.Y.Scale + 0.05, loadingBasePos.Y.Offset)
		fill.Size = UDim2.new(0, 0, 1, 0)
		loading.Visible = true

		fastTween(loading, { Position = loadingBasePos }, 0.6, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)

		task.spawn(function()
			while waveRunning and loading.Parent and screen.Enabled do
				local wave = math.sin(tick() * 3) * 0.008
				loading.Position = UDim2.new(loadingBasePos.X.Scale, loadingBasePos.X.Offset, loadingBasePos.Y.Scale + wave, loadingBasePos.Y.Offset)
				RunService.RenderStepped:Wait()
			end
		end)
	end

	local function setProgress(pct)
		if fill then
			fastTween(fill, { Size = UDim2.new(math.clamp(pct, 0, 1), 0, 1, 0) }, 0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
		end
	end

	local function dismiss()
		waveRunning = false
		if fade then
			fade.Visible = true
			local ft = fastTween(fade, { Position = UDim2.new(0, 0, 0, 0) }, 0.4, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
			ft.Completed:Wait()
		end

		local st = fastTween(frame, { Position = UDim2.new(0.5, 0, -2, 0) }, 0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		st.Completed:Wait()
		screen.Enabled = false
	end

	return {
		setProgress = setProgress,
		dismiss = dismiss,
	}
end

function WorldLoader.Load(worldName, skipRequest)
	if not worldName or typeof(worldName) ~= "string" then
		warn("[WorldLoader] Invalid world name")
		return false, "Invalid world name"
	end

	-- 1. Anchor character in current location while loading so player never falls into the void
	local Character = Player.Character or Player.CharacterAdded:Wait()
	local HumanoidRootPart = Character:WaitForChild("HumanoidRootPart", 10)
	local Humanoid = Character:WaitForChild("Humanoid", 10)
	if HumanoidRootPart then
		HumanoidRootPart.Anchored = true
	end

	-- 2. Show LoadingScreen with matching animation
	local loadingUI = nil
	if _G.IntroDone ~= false then
		loadingUI = showLoadingScreen()
		if loadingUI then
			loadingUI.setProgress(0.15)
		end
	end

	-- 3. Request world move on the server
	if not skipRequest then
		if loadingUI then loadingUI.setProgress(0.35) end
		local success, err = RequestWorldRemote:InvokeServer(worldName)
		if not success then
			if HumanoidRootPart then
				HumanoidRootPart.Anchored = false
			end
			if loadingUI then loadingUI.dismiss() end
			warn("[WorldLoader] Server rejected world request: " .. worldName .. " (" .. tostring(err) .. ")")
			return false, err or "Could not travel to world."
		end
	end

	if loadingUI then loadingUI.setProgress(0.55) end

	-- 4. Wait for the target world folder inside workspace.__MAP. Never fall
	-- back to the bare container: teleporting to the container pivot would
	-- drop the player into whatever world happens to sit at the origin.
	local container = workspace:WaitForChild("__MAP", 30)
	local worldFolder = container and (container:WaitForChild(worldName, 15) or container:FindFirstChild(worldName))
	if not worldFolder then
		if HumanoidRootPart then HumanoidRootPart.Anchored = false end
		if loadingUI then loadingUI.dismiss() end
		warn("[WorldLoader] Timed out waiting for world: " .. worldName)
		return false, "World replication timeout"
	end

	-- 5. Wait for essential foundational elements ONLY (PlayerSpawn, Grass/Ground, Walls)
	local innerMap = worldFolder:WaitForChild("MAP", 15) or worldFolder

	local playerSpawn = innerMap:WaitForChild("PlayerSpawn", 10)
	if playerSpawn then
		playerSpawn:WaitForChild("Spawn", 3)
	end

	if not innerMap:FindFirstChild("Grass") and not innerMap:FindFirstChild("Ground") then
		pcall(function() innerMap:WaitForChild("Grass", 2) end)
	end

	if not innerMap:FindFirstChild("Walls") then
		pcall(function() innerMap:WaitForChild("Walls", 2) end)
	end

	if loadingUI then loadingUI.setProgress(0.85) end

	-- 6. Apply Lighting Locally
	local LIGHTING = worldFolder:FindFirstChild("LIGHTING")
		or innerMap:FindFirstChild("LIGHTING")
		or worldFolder:FindFirstChild("Lighting")

	if LIGHTING then
		for _, child in ipairs(Lighting:GetChildren()) do
			if not child:GetAttribute("Permanent") and child.Name ~= "EggBlur" and not child:IsA("Script") and not child:IsA("LocalScript") then
				child:Destroy()
			end
		end

		for _, child in ipairs(LIGHTING:GetChildren()) do
			if child:IsA("PostEffect") or child:IsA("Atmosphere") or child:IsA("Sky") or child:IsA("Clouds") then
				local clone = child:Clone()
				clone.Name = "__WORLDFX"
				clone.Parent = Lighting
			end
		end

		local Settings = LIGHTING:FindFirstChild("Settings")
		if Settings then
			for _, child in ipairs(Settings:GetChildren()) do
				pcall(function()
					Lighting[child.Name] = child.Value
				end)
			end
		end
	end

	-- 7. Find spawn CFrame directly from worldFolder.MAP.PlayerSpawn
	local targetCFrame = getSpawnCFrame(worldFolder)

	if targetCFrame then
		pcall(function()
			Player:RequestStreamAroundAsync(targetCFrame.Position)
		end)
	end

	-- 8. Position character and unanchor
	local freshChar = Player.Character or Player.CharacterAdded:Wait()
	local freshHRP = freshChar:WaitForChild("HumanoidRootPart", 10)
	local freshHumanoid = freshChar:WaitForChild("Humanoid", 10)

	if targetCFrame then
		freshChar:PivotTo(targetCFrame)
	end
	if freshHRP then
		freshHRP.AssemblyLinearVelocity = Vector3.new()
		freshHRP.AssemblyAngularVelocity = Vector3.new()
		freshHRP.Anchored = false
	end
	if freshHumanoid then
		freshHumanoid.PlatformStand = false
	end

	WorldLoader.Current = worldName

	-- 9. Complete progress and dismiss LoadingScreen
	if loadingUI then
		loadingUI.setProgress(1.0)
		task.wait(0.15)
		loadingUI.dismiss()
	end

	return true
end

-- Teleport character to their world's PlayerSpawn on spawn/respawn
Player.CharacterAdded:Connect(function(character)
	task.spawn(function()
		local hrp = character:WaitForChild("HumanoidRootPart", 10)
		local currentWorldName = Player:GetAttribute("World") or WorldLoader.Current or "Spawn"
		local container = workspace:FindFirstChild("__MAP")
		local worldFolder = container and (container:FindFirstChild(currentWorldName) or container:GetChildren()[1] or container)
		if worldFolder and hrp then
			local spawnTarget = getSpawnCFrame(worldFolder)
			if spawnTarget then
				character:PivotTo(spawnTarget)
				hrp.AssemblyLinearVelocity = Vector3.new()
				hrp.AssemblyAngularVelocity = Vector3.new()
			end
		end
	end)
end)

-- Load initial world on join
task.spawn(function()
	task.wait(0.2)
	local initialWorld = Player:GetAttribute("World") or "Spawn"
	if not WorldLoader.Current then
		WorldLoader.Load(initialWorld)
	end
end)

return WorldLoader
