local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local Audio = {}

local function getSfxVolumeScale()
	if not RunService:IsClient() then return 1 end
	local success, Save = pcall(function()
		return require(game.ReplicatedStorage:WaitForChild("Library"):WaitForChild("Client"):WaitForChild("Save"))
	end)
	if success and Save and Save.Get then
		local save = Save.Get()
		if save and save.Settings and save.Settings.SFX ~= nil then
			return save.Settings.SFX
		end
	end
	return 1
end

--- Plays a sound. Automatically routes 2D sounds (nil, PlayerGui, or GUI objects) to SoundService.
function Audio.Play(soundId, parent, pitch, volume)
	if not soundId then return nil end

	-- Support picking a random sound from a list
	if type(soundId) == "table" then
		soundId = soundId[math.random(1, #soundId)]
	end

	local idStr = tostring(soundId)
	if not idStr:find("://") then
		idStr = "rbxassetid://" .. idStr
	end

	-- Determine target parent: 3D audio requires BasePart or Attachment, else route to SoundService for 2D audio
	local targetParent = SoundService
	if parent and typeof(parent) == "Instance" then
		if parent:IsA("BasePart") or parent:IsA("Attachment") then
			targetParent = parent
		elseif parent:IsA("Model") and parent.PrimaryPart then
			targetParent = parent.PrimaryPart
		end
	end

	local sound = Instance.new("Sound")
	sound.SoundId = idStr
	sound.PlaybackSpeed = pitch or 1
	sound.Volume = (volume or 0.5) * getSfxVolumeScale()
	sound.Parent = targetParent

	sound.Ended:Connect(function()
		sound:Destroy()
	end)

	if sound.IsLoaded then
		sound:Play()
	else
		local played = false
		sound.Loaded:Connect(function()
			if not played and sound and sound.Parent then
				played = true
				sound:Play()
			end
		end)
		task.delay(0.1, function()
			if not played and sound and sound.Parent then
				played = true
				sound:Play()
			end
		end)
	end

	-- Safety cleanup fallback to guarantee no sound memory leaks
	Debris:AddItem(sound, 10)
	return sound
end

return Audio
