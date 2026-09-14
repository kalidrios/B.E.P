--[[
	Shared/Variables/init.luau — Game configuration & constants for Destruction Simulator
]]--

local SharedVariables = {}

-- Game Identity
SharedVariables.GameName = "DestructionSimulator"
SharedVariables.GameVersion = "0.1.0"

-- Game IDs
SharedVariables.GameIds = {
	Production = math.huge,
	Staging = math.huge,
	Development = math.huge,
}

SharedVariables.LocalPlaceIds = {
	Main = 73057732767661,
	UGCVault = 88456767102569,
}

SharedVariables.PlaceIds = {
	[SharedVariables.GameIds.Production] = {
		Main = 73057732767661,
		UGCVault = 88456767102569,
	},
	[SharedVariables.GameIds.Development] = {
		Main = 73057732767661,
		UGCVault = 88456767102569,
	},
	[SharedVariables.GameIds.Staging] = {
		Main = 73057732767661,
		UGCVault = 88456767102569,
	},
}

-- Computed flags
SharedVariables.GameId = (game.GameId ~= 0) and game.GameId or SharedVariables.GameIds.Development
SharedVariables.IsMain = (game.PlaceId == 73057732767661)
SharedVariables.IsTradingPlaza = false
SharedVariables.IsDevelopment = (SharedVariables.GameId == SharedVariables.GameIds.Development)
SharedVariables.IsProduction = (SharedVariables.GameId == SharedVariables.GameIds.Production)

-- Environment & Place IDs (Identical to ItalianBrainrotSimulator: Libray/Shared/Variables.luau)
local UGCVaultID = 88456767102569

SharedVariables.IsVoiceTradingPlaza = false
SharedVariables.IsProTradingPlaza = false
SharedVariables.IsHardcore = false
SharedVariables.IsUGCVault = (game.PlaceId == UGCVaultID)

-- Destruction-specific config
SharedVariables.DestructibleRespawnTime = 10 -- seconds
SharedVariables.MaxDestructiblesPerZone = 50
SharedVariables.BaseDestroyPower = 1
SharedVariables.TradeRatingRequirement = 5

-- Settings UI definitions
SharedVariables.SettingsInfo = {
	Music = {
		title = "Music",
		settingType = "Slider",
		min = 0,
		max = 1,
		default = 1,
		sort = 100,
		category = "Sound",
	},
	SFX = {
		title = "SFX",
		settingType = "Slider",
		min = 0,
		max = 1,
		default = 1,
		sort = 200,
		category = "Sound",
	},
	ExplosionVolume = {
		title = "Explosion Volume",
		settingType = "Slider",
		min = 0,
		max = 1,
		default = 0.5,
		sort = 250,
		category = "Sound",
	},
	InteractClicks = {
		title = "Interact Button Clicks",
		settingType = "Toggle",
		options = { "On", "Off" },
		default = 1,
		sort = 280,
		category = "Sound",
	},
	Notifications = {
		title = "Notifications",
		settingType = "Toggle",
		options = { "On", "Off" },
		sort = 300,
		category = "Sound",
	},
	PerformanceMode = {
		title = "Performance Mode",
		settingType = "Selector",
		options = { "Low", "Medium", "High" },
		default = 2,
		sort = 400,
		category = "Performance",
	},
	ShowMyDestruction = {
		title = "View My Destruction",
		settingType = "Toggle",
		options = { "On", "Off" },
		sort = 500,
		category = "Performance",
	},
	ShowOtherDestruction = {
		title = "View Other's Destruction",
		settingType = "Toggle",
		options = { "On", "Off" },
		sort = 600,
		category = "Performance",
	},
	ShowMyVFX = {
		title = "View My VFX",
		settingType = "Toggle",
		options = { "On", "Off" },
		sort = 700,
		category = "Performance",
	},
	ShowOtherVFX = {
		title = "View Other's VFX",
		settingType = "Toggle",
		options = { "On", "Off" },
		sort = 800,
		category = "Performance",
	},
	Trading = {
		title = "Trading",
		settingType = "Selector",
		options = { "All", "Friends", "Disabled" },
		default = 1,
		sort = 900,
		category = "Trading",
	},
}

-- Shared assets
SharedVariables.SharedAssets = {}

return SharedVariables
