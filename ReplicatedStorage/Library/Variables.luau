--[[
	© DestructionSimulator [2025]
	Library/Variables — Game-wide client/shared state variables
]]--

local countedLock = require(game.ReplicatedStorage.Library.Modules.CountedLock)
local Variables = {
	["ServerClosing"] = false,
	["HideProgressUI"] = false,
	["HideGoalsUI"] = false,
	["DisableInfoOverlay"] = false,
	["IsUsingFreecam"] = false,
	["IsRebirthing"] = false,
	["IsRankingUp"] = false,
	["Locks"] = {
		["HideUI"] = countedLock.new(),
		["HideUIAllowNotifications"] = countedLock.new(),
		["DisableNotifications"] = countedLock.new(),
		["DisableTouchControls"] = countedLock.new(),
		["DisableTeleporting"] = countedLock.new(),
	},
	["Desktop"] = true,
	["Mobile"] = false,
	["Console"] = false,
	["VR"] = false,
	["Platform"] = "Desktop",
	["Chatting"] = false,
	["Typing"] = false,
	["Orientation"] = Enum.ScreenOrientation.LandscapeSensor,
	["Portrait"] = false,
	["Landscape"] = true,
	["SafeAreaInsets"] = {
		["left"] = 0,
		["top"] = 0,
		["right"] = 0,
		["bottom"] = 0,
	},
	["NotchSide"] = {
		["None"] = true,
		["Left"] = false,
		["Right"] = false,
	},
	["MessageOpen"] = false,
}

return Variables
