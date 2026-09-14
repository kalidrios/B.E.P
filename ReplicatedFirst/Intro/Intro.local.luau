--[[

	Re-designed late November 2024 by Kalidrios
	Modified to use loading bar instead of dots
	
	The loading sequence and intro animation. Preloads assets, confirms save, displays ban timers, and has a cute little animation.
	
--]]


--- Settings
local _AUTOSKIP = false --- Skip the intro during real sessions
local _STUDIOSKIP = false --- Skip the intro during studio sessions

--- References
local runService = game:GetService("RunService")
local contentProvider = game:GetService("ContentProvider")
local isStudio = runService:IsStudio()
local _SKIP = (isStudio and _STUDIOSKIP or _AUTOSKIP)

--- Variables
local done = false
local playerGui
local sound
local gui
local gameGuis = {}
local _L
--
local frame
local logo
local loading
local loadingFill
local fade
local enabledSkip = false
local skipUsed = false

-- Loading bar settings
local MAX_STAGES = 5
local currentStage = 0
local loadingBasePos = nil -- Will store the original position
local waveAnimationRunning = false

------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------


function Init()
	--- Remove default loading screen
	game.ReplicatedFirst:RemoveDefaultLoadingScreen()

	--- Change core GUI properties (remove topbar, chat, etc.)
	playerGui = game.Players.LocalPlayer:WaitForChild("PlayerGui")
	playerGui:SetTopbarTransparency(0)
	game.StarterGui:SetCoreGuiEnabled("All", false)
	HideGameInterface()

	--- Deploy gui
	gui = script.Parent:WaitForChild("IntroGui")
	gui.Name = "__INTRO"
	gui.Parent = ((not _SKIP) and playerGui or nil)

	--- Wait for intro audio
	sound = script.Parent:WaitForChild("IntroSound")

	--- Wait for gui children
	frame = gui:WaitForChild("Frame")
	logo = frame:WaitForChild("Logo")
	loading = frame:WaitForChild("Loading")
	loadingFill = loading:WaitForChild("Background"):WaitForChild("Fill")
	fade = frame:WaitForChild("Fade")

	--- Preload gui assets (and yield until done so)
	local loadSuccess = {}
	contentProvider:PreloadAsync({sound.SoundId, logo.Image}, function(id, status)
		table.insert(loadSuccess, {id, Enum.AssetFetchStatus.Success == status})
	end)

	local _t = tick()
	while (#loadSuccess < 2) and (tick() - _t < 2) do  runService.RenderStepped:Wait()  end --- max 2 seconds
	if #loadSuccess < 2 then
		warn("Intro error #2: Time exceeded for intro assets preload")
	end
end


function Intro()
	local function PlaySound()
		sound:Play()
	end

	--- Logo pop in
	local function LogoPopIn()
		local goalSize = logo.Size
		local startSize = UDim2.new(goalSize.X.Scale * 0.6, goalSize.X.Offset * 0.6, goalSize.Y.Scale * 0.6, goalSize.Y.Offset * 0.6)
		logo.ImageTransparency = 0.2
		logo.Size = startSize
		logo.Visible = true

		FastTween(logo, {Size = goalSize, ImageTransparency = 0}, {0.66, "Back", "Out"})
	end

	--- Loading bar pop in
	local function LoadingPopIn()
		loadingBasePos = loading.Position
		loading.Position = UDim2.new(loadingBasePos.X.Scale, loadingBasePos.X.Offset, loadingBasePos.Y.Scale + 0.05, loadingBasePos.Y.Offset)
		loadingFill.Size = UDim2.new(0, 0, 1, 0)
		loading.Visible = true

		FastTween(loading, {Position = loadingBasePos}, {0.8, "Expo", "Out"})

		-- Start wave animation
		waveAnimationRunning = true
		coroutine.wrap(function()
			while waveAnimationRunning and loading and loading.Parent do
				local wave = math.sin(tick() * 3) * 0.008 -- Subtle wave
				local baseY = loadingBasePos.Y.Scale
				loading.Position = UDim2.new(loadingBasePos.X.Scale, loadingBasePos.X.Offset, baseY + wave, loadingBasePos.Y.Offset)
				runService.RenderStepped:Wait()
			end
		end)()
	end


	PlaySound()
	LogoPopIn()
	LoadingPopIn()
end


function UpdateProgress(stage)
	if _SKIP then return end

	currentStage = stage
	local progress = stage / MAX_STAGES
	FastTween(loadingFill, {Size = UDim2.new(progress, 0, 1, 0)}, {0.4, "Sine", "Out"})
end


function Load()
	--[[
		
		Loading has 5 unique stages
		
		Stage 1:
			Wait for game:IsLoaded to return true (capped at waiting 1 second)
			
		Stage 2:
			Wait for character to load
			
		Stage 3:
			Wait for assets (skippable)
		
		Stage 4:
			Wait for player's save (or ban status)
		
		Stage 5:
			Wait for _L (framework init)
		
	--]]

	----------------------------------------------------------------

	local function Stage1()
		--- Wait for game to init (max yield is 1 second)
		local _t = tick()
		while not game:IsLoaded() and (tick() - _t < 1) do  runService.RenderStepped:Wait()  end
		if not game:IsLoaded() then
			warn("Intro error #1: Time exceeded for IsLoaded()")
		end
	end


	local function Stage2()
		local player = game.Players.LocalPlayer
		while ((not player) or (not player.Character) or (not player.Character:FindFirstChild("Humanoid"))) do
			runService.RenderStepped:Wait()
		end
	end


	local function Stage3()
		if _SKIP then
			return
		end

		--- Skip button (if assets are taking too long to load)
		local skip = frame:WaitForChild("Skip")

		local function HideSkipButton()
			skipUsed = true
			-- Move loading bar back down
			loadingBasePos = UDim2.new(loadingBasePos.X.Scale, loadingBasePos.X.Offset, 0.8, loadingBasePos.Y.Offset)
			FastTween(loading, {Position = loadingBasePos}, {0.5, "Sine", "InOut"})
			skip.Visible = false
		end

		local function SkipButton()
			enabledSkip = true

			local cacheSize = skip.Size
			skip.Size = UDim2.new(skip.Size.X.Scale * 0.7, skip.Size.X.Offset * 0.7, skip.Size.Y.Scale * 0.7, skip.Size.Y.Offset * 0.7)
			skip.Visible = true

			-- Move loading bar up to make room for skip button
			loadingBasePos = UDim2.new(loadingBasePos.X.Scale, loadingBasePos.X.Offset, 0.748, loadingBasePos.Y.Offset)
			FastTween(loading, {Position = loadingBasePos}, {0.3, "Sine", "Out"})
			FastTween(skip, {Size = cacheSize}, {0.6, "Back", "Out"})

			skip.MouseButton1Up:Connect(function()
				if not skipUsed then
					HideSkipButton()
				end
			end)
		end

		--- Load assets
		local _t = tick()
		local loadedAssets = false
		coroutine.wrap(function()
			pcall(function()
				-- Adapted for DestructionSimulator:
				local savedInstances = {}
				local waitForMap = game.Workspace:WaitForChild("Map", 99999999)
				table.insert(savedInstances, waitForMap:WaitForChild("Spawn", 99999999))
				game:GetService("ContentProvider"):PreloadAsync(savedInstances)
				loadedAssets = true
			end)
		end)()
		while (not loadedAssets) and (tick() - _t <= 10) and (not skipUsed) do
			if tick() - _t >= 3.5 and (not enabledSkip) then
				SkipButton()
			end
			runService.RenderStepped:Wait()
		end

		if enabledSkip and (not skipUsed) then
			HideSkipButton()
		end
	end


	local function Stage4()
		local saveWaitTick = tick()
		local confirmedSave, isBanned, bannedTimer
		local remote = game.Workspace:WaitForChild("__THINGS"):WaitForChild("__REMOTES"):WaitForChild("intro")

		--- Wait for save
		while (not confirmedSave) and (tick() - saveWaitTick) < 60 do
			--- Ask server if save is confirmed loaded
			confirmedSave, isBanned, bannedTimer = remote:InvokeServer(true)

			if isBanned then
				Banned(bannedTimer)
				return
			end

			--- Retry
			if not confirmedSave then
				wait(0.5)
			end
		end

		if not confirmedSave then
			Error()
			return
		end
	end


	local function Stage5()
		local showingNotice = false
		local function ShowNotice()
			showingNotice = true
		end

		--- add back core gui (but keep Backpack disabled - custom toolbar is used)
		game.StarterGui:SetCoreGuiEnabled("All", true)
		game.StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)

		_G.IntroDone = true

		-- Adapted for DestructionSimulator:
		_L = require(game.ReplicatedStorage:WaitForChild("Library"))

		local _t = tick()
		while (not _L.IsLoaded()) do
			if (not showingNotice) and (tick() - _t) >= 3 then
				ShowNotice()
			end
			runService.RenderStepped:Wait()
		end
	end

	----------------------------------------------------------------

	--print("[Intro] Running Stage 1")
	Stage1()  if done then return end  UpdateProgress(1)
	--print("[Intro] Running Stage 2")
	Stage2()  if done then return end  UpdateProgress(2)
	--print("[Intro] Running Stage 3")
	Stage3()  if done then return end  UpdateProgress(3)
	--print("[Intro] Running Stage 4")
	Stage4()  if done then return end  UpdateProgress(4)
	--print("[Intro] Running Stage 5")
	Stage5()  if done then return end  UpdateProgress(5)
	--print("[Intro] All Stages Complete!")
end


function ShowMessage()
	local notice = frame:WaitForChild("Notice")
	notice:WaitForChild("Frame")

	--- fade out the intro screen
	fade.Visible = true
	local tween = FastTween(fade, {Position = UDim2.new(0, 0, 0, 0)}, {0.7, "Linear"})
	tween.Completed:Wait()

	wait(.5) --- dramatic pause!!

	waveAnimationRunning = false -- Stop wave animation
	loading.Visible = false
	logo.Visible = false
	notice.Visible = true
	FastTween(fade, {Position = UDim2.new(0, 0, 1, 0)}, {0.7, "Linear"})

	return notice
end


function Error()
	done = true

	local notice = ShowMessage()
	notice.Frame.Button.Visible = true
	notice.Frame.Desc.Text = "An unknown error has occurred. Do you want to try re-joining?"
	notice.Frame.TimeLeft.Visible = false
	notice.Frame.Title.Text = "Error"

	local deb = false
	notice.Frame.Button.MouseButton1Down:Connect(function()
		if not deb then
			deb = true
			game:GetService("TeleportService"):Teleport(game.PlaceId, game.Players.LocalPlayer) --- force player to re-join
			deb = false
		end
	end)
end


function Banned(timer)
	done = true

	local notice = ShowMessage()
	notice.Frame.Button.Visible = false
	notice.Frame.Desc.Text = "You've been banned from playing on this account. If you believe this was an accident, appeal on our Discord."
	notice.Frame.TimeLeft.Visible = true
	notice.Frame.TimeLeft.Text = "Time Left: " .. (timer or "Forever")
	notice.Frame.Title.Text = "Banned"
end



function Revert()
	done = true

	for _, v in ipairs(gameGuis) do
		v.Enabled = true
	end

	--- fade out the intro screen
	fade.Visible = true
	local tween = FastTween(fade, {Position = UDim2.new(0, 0, 0, 0)}, {0.7, "Linear"})
	tween.Completed:Wait()

	--- bye bye + cleanup
	waveAnimationRunning = false -- Stop wave animation
	local tween = FastTween(frame, {Position = UDim2.new(0.5, 0, -2, 0)}, {1, "Quad", "Out"})
	tween.Completed:Wait()
	_G.IntroCompleted = true
	gui:Destroy()
end


------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------


function HideGameInterface()
	local function Loop()
		for _, v in ipairs(playerGui:GetChildren()) do
			if v.ClassName == "ScreenGui" or v.ClassName == "BillboardGui" or v.ClassName == "SurfaceGui" then
				if v.Enabled and v.Name ~= "__INTRO" and v.Name ~= "Dex" then
					table.insert(gameGuis, v)
					v.Enabled = false
				end		
			end
		end
	end

	--- Runs a constant loop looking for game guis and disabling them  
	coroutine.wrap(function()
		while (not done) do
			Loop()
			runService.Heartbeat:Wait()
		end
	end)()
end


------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------


--- Function from _L
function FastTween(_entity, tweenGoals, tweenInfoRaw, delayTime)
	--- Allow for multipule instances
	if type(_entity) ~= "table" then  _entity = {_entity}  end

	--- Variables
	local tweens = {}

	--- iterate through each instance
	for _, entity in ipairs(_entity) do
		if tweenInfoRaw == nil then
			--- No tweenInfo provided. Use the default one!
			tweenInfoRaw = {
				1,
				Enum.EasingStyle.Linear,
				Enum.EasingDirection.Out,
			}
		else
			--- Check (2nd) tween arguments and fix/fill them
			if tweenInfoRaw[2] == nil then
				--- No easing style provided. Use default one!
				tweenInfoRaw[2] = Enum.EasingStyle.Sine

			elseif type(tweenInfoRaw[2]) == "string" then
				--- Easing style provided string not enum. Convert!
				if string.lower(tweenInfoRaw[2]) == "expo" then
					tweenInfoRaw[2] = Enum.EasingStyle.Exponential
				else
					tweenInfoRaw[2] = Enum.EasingStyle[tweenInfoRaw[2]]
				end
			end

			--- Check (3rd) tween arguments and fix/fill them
			if tweenInfoRaw[3] == nil then
				--- No easing direction provided. Use default one!
				tweenInfoRaw[3] = Enum.EasingDirection.InOut

			elseif type(tweenInfoRaw[3]) == "string" then
				--- Easing direction provided string not enum. Convert!
				tweenInfoRaw[3] = Enum.EasingDirection[tweenInfoRaw[3]]
			end
		end

		--- Create tween
		local tweenInfo = TweenInfo.new(unpack(tweenInfoRaw))
		local tweenGoals = tweenGoals
		local tween = game:GetService("TweenService"):Create(entity, tweenInfo, tweenGoals)

		coroutine.wrap(function()
			if delayTime then
				wait(delayTime)
			end

			--- Play tween
			tween:Play()
		end)()

		--- Add tween to list of tweens that will be returned
		table.insert(tweens, tween)
	end

	--
	return unpack(tweens)
end


------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------


Init()

if not _SKIP then
	Intro()
end

Load()

if not done then
	Revert()
end
