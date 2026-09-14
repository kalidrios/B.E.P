--[[
	© DestructionSimulator [2025]
	Server/SettingsService — Handles player settings changes, toggles and sliders.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Library = require(ReplicatedStorage:WaitForChild("Library"))
while not Library.Loaded do
	game:GetService("RunService").Heartbeat:Wait()
end

local Shared = Library.Shared
local Network = Library.Network
local Saving = Library.Saving

local function isValidNumber(val)
	if typeof(val) ~= "number" then return false end
	if val ~= val then return false end -- NaN check
	if val == math.huge or val == -math.huge then return false end -- Infinity check
	return true
end

Network.Invoked("Toggle Setting").OnInvoke = function(player, setting)
	local save = Saving.GetPlayerData(player)
	if not save then
		return false, nil, nil
	end

	local info = Shared.SettingsInfo[setting]
	if not info then
		return nil, nil, nil
	end

	local settingType = info.settingType
	if settingType ~= "Toggle" and settingType ~= "Selector" then
		return nil, "Invalid type!", nil
	end

	local options = info.options
	if not options then
		return nil, nil, nil
	end

	local default = info.default or 1
	if save.Settings[setting] == nil then
		save.Settings[setting] = default
	end

	local previousValue = save.Settings[setting]
	if save.Settings[setting] == #options then
		save.Settings[setting] = 1
	else
		save.Settings[setting] += 1
	end

	Network.Fire(player, "Setting Changed", setting, save.Settings[setting])
	return true, nil, save.Settings[setting]
end

Network.Invoked("Slider Setting").OnInvoke = function(player, setting, range)
	local save = Saving.GetPlayerData(player)
	if not save then
		return false, nil, nil
	end

	local info = Shared.SettingsInfo[setting]
	if not info then
		return nil, nil, nil
	end

	local settingType = info.settingType
	if settingType ~= "Slider" then
		return nil, "Invalid type!", nil
	end

	-- Input sanitization for Slider: NaN, Infinite, Type check (M4)
	if not isValidNumber(range) then
		warn(string.format("[SettingsService] Invalid range value (%s) sent by %s for setting %s", tostring(range), player.Name, tostring(setting)))
		return nil, "Invalid number value", nil
	end

	local default = info.default or 0.5
	if save.Settings[setting] == nil then
		save.Settings[setting] = default
	end

	local min, max = info.min or 0, info.max or 1
	if not min or not max then
		return nil, nil, nil
	end

	if range > max or range < min then
		warn(string.format("[SettingsService] Out-of-bounds range value (%.2f) sent by %s for setting %s (min: %.2f, max: %.2f)", range, player.Name, tostring(setting), min, max))
		return nil, "Value out of bounds", nil
	end

	save.Settings[setting] = range

	Network.Fire(player, "Setting Changed", setting, range)
	return true, nil, save.Settings[setting]
end
