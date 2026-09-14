--[[
	© DestructionSimulator [2025]
	MusicController — Client-side background music player.
	Loads playlist tracks from Directory.Worlds configuration and plays them sequentially.
]]--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

local Player = Players.LocalPlayer

local Library = require(ReplicatedStorage:WaitForChild("Library"))
while not Library.IsLoaded() do
	task.wait()
end
local Directory = Library.Directory

local currentMusicSound = nil
local currentMusicId = nil
local activePlaylist = {}
local currentSongIndex = 0

local Save = Library.Save
local function getMusicVolume()
	local volumeSetting = 0.5
	if Save and Save.Get then
		local save = Save.Get()
		if save and save.Settings and save.Settings.Music ~= nil then
			volumeSetting = save.Settings.Music
		end
	end
	return 0.25 * volumeSetting
end

local function stopMusic()
	if currentMusicSound then
		local soundToFade = currentMusicSound
		currentMusicSound = nil
		currentMusicId = nil
		
		-- Fade out and destroy
		local tween = TweenService:Create(soundToFade, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Volume = 0})
		tween:Play()
		tween.Completed:Connect(function()
			soundToFade:Stop()
			soundToFade:Destroy()
		end)
	end
end

local function playNextSong()
	if #activePlaylist == 0 then return end
	
	currentSongIndex = currentSongIndex + 1
	if currentSongIndex > #activePlaylist then
		currentSongIndex = 1
	end
	
	local songId = activePlaylist[currentSongIndex]
	if not songId then return end
	
	-- Stop current music first with fade
	stopMusic()
	
	currentMusicId = songId
	local sound = Instance.new("Sound")
	sound.Name = "BackgroundMusic_" .. tostring(songId)
	sound.SoundId = "rbxassetid://" .. tostring(songId)
	sound.Volume = 0
	sound.Looped = false -- Let script cycle to next song on finish
	sound.Parent = SoundService
	
	currentMusicSound = sound
	sound:Play()
	
	-- Fade in
	local targetVol = getMusicVolume()
	TweenService:Create(sound, TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Volume = targetVol}):Play()
	
	-- Wait for song to end to play the next one
	task.spawn(function()
		sound.Ended:Wait()
		if currentMusicSound == sound then
			playNextSong()
		end
	end)
end

local function loadWorldMusic(worldName)
	local worldConfig = Directory.Worlds and Directory.Worlds[worldName]
	local newPlaylist = (worldConfig and (worldConfig.Music or worldConfig.music)) or {}
	if #newPlaylist == 0 then
		-- Fallback default background music
		newPlaylist = { 85533156796296 }
	end
	
	-- Check if playlist actually changed
	local changed = (#newPlaylist ~= #activePlaylist)
	if not changed then
		for i, v in ipairs(newPlaylist) do
			if v ~= activePlaylist[i] then
				changed = true
				break
			end
		end
	end
	
	if changed then
		activePlaylist = newPlaylist
		currentSongIndex = 0
		stopMusic()
		if #activePlaylist > 0 then
			playNextSong()
		end
	end
end

-- Listen to world changes
Player:GetAttributeChangedSignal("World"):Connect(function()
	local newWorld = Player:GetAttribute("World")
	if newWorld then
		loadWorldMusic(newWorld)
	end
end)

-- Initial load: start background music after Intro loading screen finishes or fallback timeout
task.spawn(function()
	local timeout = 0
	while not _G.IntroCompleted and timeout < 40 do
		task.wait(0.1)
		timeout = timeout + 1
	end
	local initialWorld = Player:GetAttribute("World") or "Spawn"
	loadWorldMusic(initialWorld)
end)

-- Settings volume updates
Library.Signal.Fired("Setting Slider Update"):Connect(function(setting, value)
	if setting == "Music" then
		if currentMusicSound then
			currentMusicSound.Volume = 0.25 * value
		end
	end
end)

Library.Network.Fired("Setting Changed"):Connect(function(setting, value)
	if setting == "Music" then
		if currentMusicSound then
			currentMusicSound.Volume = 0.25 * value
		end
	end
end)
