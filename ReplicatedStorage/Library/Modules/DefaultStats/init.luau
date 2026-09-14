--[[
	© DestructionSimulator [2025]
	DefaultStats — Player data template
	
	DATA SCHEMA:
	- Weapons: array of {ID: string, Type: string, Float: number}
	  - Type can be: "LancaMisseis", "Minas"
	  - Float: random number between 0.000000 and 1.000000 (defined during creation)
	- Backpacks: array of strings with names of unlocked backpacks
	- Currency: Coins and Gems
	
	FAIL-FAST: This module does not use pcall. If the structure is wrong,
	the require() will fail and propagate the error to Saving → Library → Intro.
]]--

local DefaultStats = {
	-- === CURRENCY ===
	Currency = {
		Coins = 0,
		Gems = 0,
		Contracts = 0,
	},
	Contracts = 0,

	-- === WEAPONS INVENTORY ===
	-- Each weapon is a table: { ID = "uid", Type = "LancaMisseis"|"Minas", Float = 0.000000~1.000000 }
	Weapons = {
		{ ID = "Rocket Launcher", Type = "LancaMisseis", Float = 0.5 },
		{ ID = "Bomb", Type = "Minas", Float = 0.5 },
	},

	-- === BACKPACKS INVENTORY ===
	-- Array of unlocked backpack names
	Backpacks = { "SmallBag" },

	-- === SKINS INVENTORY ===
	-- Each skin: { ID = "Safari", Category = "Launcher", ItemName = "Starblaster", Float = 0.4523 }
	Skins = {},

	-- Equipped skins per item: { Launcher = { Starblaster = { ID = "Safari", Float = 0.4523 } }, Bomb = {}, BackPack = {} }
	EquippedSkins = {},


	-- Currently equipped backpack
	EquippedBackpack = "SmallBag",
	
	-- Backpack/storage capacity state
	Storage = {
		Amount = 0,
		Max = 100, -- Capacity derived from equipped SmallBag
	},

	-- === EQUIPPED WEAPON ===
	EquippedLauncher = "Rocket Launcher",
	EquippedBomb = "Bomb",
	EquippedWeapon = nil, -- ID of the equipped weapon

	-- === PROGRESSION ===
	Power = 1,
	Rebirth = 0,
	Experience = 0,
	DestructiblesDestroyed = 0,
	TutorialCompleted = false,
	GuideCompleted = false,
	OwnsUGCVault = false,

	-- === ZONES ===
	CurrentWorld = "Spawn",
	UnlockedZones = {
		Spawn = true,
	},
	-- Authoritative world unlock list (array) used by WorldService/RebirthService
	UnlockedWorlds = { "Spawn" },
	GateProgress = {},

	-- === UPGRADES ===
	UpgradesOwned = {},

	Settings = {
		Music = 0.5,
		SFX = 0.5,
		ExplosionVolume = 0.5,
		InteractClicks = 1,
		Notifications = 1,
		PerformanceMode = 2,
		ShowMyDestruction = 1,
		ShowOtherDestruction = 1,
		ShowMyVFX = 1,
		ShowOtherVFX = 1,
		Trading = 1,
	},

	-- === GENERAL INVENTORY ===
	Inventory = {
		Misc = {},
		Currency = {},
	},

	-- === STREAKS ===
	Streaks = {
		Login = {
			Streak = 0,
			Claimed = false,
			LastStreakTime = 0,
			LongestStreak = 0,
		},
	},

	-- === GAMEPASSES ===
	Gamepasses = {},
	Products = {},

	-- === STATISTICS ===
	Statistics = {},
	Achievements = {},

	-- === MISC VARIABLES ===
	MiscVars = {},
	TradeHistory2 = {},

	-- === SESSION / DATASTORE INTEGRITY ===
	FirstJoinTimestamp = -1e999,
	TotalSessions = 0,
	LastSaveTimestamp = 0,
	LastJoinTimestamp = 0,
	PlayingSession = false,
	SessionId = nil,
	SafeSaveToken = nil,
	LoginTime = nil,
	Age = 0,
	FirstLogin = true,
	HasPlayedBefore = false,
	Platform = "Desktop",
	RobuxSpent = 0,
	PaidPlayer = false,
	HideFromLeaderboard = false,
}

return DefaultStats
