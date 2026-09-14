--[[
	© DestructionSimulator [2026]
	Server/AdminCommands — Architecture fully matching ItalianBrainrotSimulator (addCommand schema)
	Equivalences:
	- Coins = Cash
	- Gems/Diamonds = Contracts
	Usage example: /e cash me 999  OR  /e cash kalidrios 999
]]--

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Library = require(ReplicatedStorage:WaitForChild("Library"))
while not Library.IsLoaded() do
	task.wait()
end

local Saving = require(ServerScriptService:WaitForChild("Library"):WaitForChild("Saving"))

local RemotesFolder = workspace:WaitForChild("__THINGS"):WaitForChild("__REMOTES")
local NotificationEvent = RemotesFolder:FindFirstChild("NotificationEvent") or Instance.new("RemoteEvent")
NotificationEvent.Name = "NotificationEvent"
NotificationEvent.Parent = RemotesFolder

local OpenAdminHelpEvent = RemotesFolder:FindFirstChild("OpenAdminHelp") or Instance.new("RemoteEvent")
OpenAdminHelpEvent.Name = "OpenAdminHelp"
OpenAdminHelpEvent.Parent = RemotesFolder

local AdminCommandInvokeRemote = RemotesFolder:FindFirstChild("AdminCommandInvoke") or Instance.new("RemoteFunction")
AdminCommandInvokeRemote.Name = "AdminCommandInvoke"
AdminCommandInvokeRemote.Parent = RemotesFolder

local GetAdminCommandsRemote = RemotesFolder:FindFirstChild("GetAdminCommands") or Instance.new("RemoteFunction")
GetAdminCommandsRemote.Name = "GetAdminCommands"
GetAdminCommandsRemote.Parent = RemotesFolder

local IsAdminRemote = RemotesFolder:FindFirstChild("IsAdmin") or Instance.new("RemoteFunction")
IsAdminRemote.Name = "IsAdmin"
IsAdminRemote.Parent = RemotesFolder

local function notification(player, text, isSuccess)
	if isSuccess == nil then isSuccess = true end
	print("[AdminCommands] Notification for " .. (player and player.Name or "System") .. ": " .. text)
	if player then
		NotificationEvent:FireClient(player, text, isSuccess)
	end
end

local TextChatService = game:GetService("TextChatService")

local ADMIN_USERS = {
	[561445931] = true, -- Developer / kalidrios
	[1037898275229020250] = true,
	[game.CreatorId] = true,
}

local function isPlayerAdmin(player)
	if not player then return false end
	if RunService:IsStudio() then return true end
	if player.UserId == game.CreatorId or ADMIN_USERS[player.UserId] == true then
		return true
	end
	if player:GetAttribute("IsAdmin") == true then
		return true
	end
	-- If published under a Group or Community group, check if player has rank >= 100
	local checkGroups = { game.CreatorId, 1105415251 }
	for _, gId in ipairs(checkGroups) do
		if gId and typeof(gId) == "number" and gId > 0 then
			local success, rank = pcall(function()
				return player:GetRankInGroup(gId)
			end)
			if success and rank and (rank >= 100 or rank == 255) then
				return true
			end
		end
	end
	return false
end

local function checkPermissions(player, permTypes)
	return isPlayerAdmin(player)
end

local function getPlayerParts(plr)
	if not plr or not plr:IsA("Player") then return nil end
	local character = plr.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if humanoid and hrp then
			return character, humanoid, hrp
		end
	end
	return nil
end

local function getPlrByDisplay(name)
	name = string.gsub(name, "@", "")
	for _, v in ipairs(Players:GetPlayers()) do
		if string.lower(v.DisplayName) == string.lower(name) or string.lower(v.Name) == string.lower(name) then
			return v
		end
	end
	return nil
end

-- ==================== COMMAND SYSTEM (IBS REPLICATED) ====================

local commands = {}

local function setupCommand(cmdData)
	return {
		["cmds"] = { cmdData.cmd },
		["desc"] = cmdData.desc or "No description",
		["permissions"] = cmdData.perms or { "Admins" },
		["developers"] = cmdData.devs or {},
		["arguments"] = cmdData.arguments or {},
		["permtype"] = cmdData.type or { 1 },
		["commandFunction"] = cmdData["function"],
		["neededValues"] = cmdData.neededValues or {},
	}
end

local function addCommand(cmdData)
	table.insert(commands, setupCommand(cmdData))
end

local function getCmd(cmdName)
	cmdName = string.lower(cmdName)
	for _, v in ipairs(commands) do
		for _, alias in ipairs(v.cmds) do
			if string.lower(alias) == cmdName then
				return v
			end
		end
	end
	return nil
end

-- ==================== COMMAND FUNCTIONS ====================

-- CASH (coins)
local function giveCash(plr, amount)
	amount = tonumber(amount) or 1000
	local profile = Saving.GetPlayerData(plr)
	if not profile then return false, "Profile not loaded." end
	
	profile.Currency.Coins = math.max(0, (profile.Currency.Coins or 0) + amount)
	plr:SetAttribute("Coins", profile.Currency.Coins)
	return true
end

-- CONTRACTS (gems/diamonds)
local function giveContracts(plr, amount)
	amount = tonumber(amount) or 100
	local profile = Saving.GetPlayerData(plr)
	if not profile then return false, "Profile not loaded." end
	
	profile.Currency.Gems = math.max(0, (profile.Currency.Gems or 0) + amount)
	plr:SetAttribute("Gems", profile.Currency.Gems)
	return true
end

-- BLOCKS
local function setBlocks(plr, amount)
	amount = tonumber(amount) or 50
	local profile = Saving.GetPlayerData(plr)
	if not profile then return false, "Profile not loaded." end
	
	if not profile.Storage then profile.Storage = { Amount = 0, Max = 100 } end
	profile.Storage.Amount = math.clamp(amount, 0, profile.Storage.Max or 99999)
	plr:SetAttribute("Blocks", profile.Storage.Amount)
	return true
end

-- MAXBLOCKS
local function setMaxBlocks(plr, amount)
	amount = tonumber(amount) or 500
	local profile = Saving.GetPlayerData(plr)
	if not profile then return false, "Profile not loaded." end
	
	if not profile.Storage then profile.Storage = { Amount = 0, Max = 100 } end
	profile.Storage.Max = amount
	plr:SetAttribute("MaxBlocks", profile.Storage.Max)
	return true
end

-- LEVEL / LEVELUP
local function giveLevel(plr, amount)
	amount = tonumber(amount) or 1
	local profile = Saving.GetPlayerData(plr)
	if not profile then return false, "Profile not loaded." end
	
	local currentXP = profile.Experience or 0
	local function getLevelFromXP(xp)
		xp = math.max(0, xp or 0)
		local lvl = 1
		while true do
			local needed = math.floor(100 * (lvl ^ 1.35))
			if xp < needed then
				break
			else
				lvl = lvl + 1
			end
		end
		return lvl
	end
	
	local currentLvl = getLevelFromXP(currentXP)
	local targetLvl = math.max(1, currentLvl + amount)
	
	-- Calculate exact XP required for targetLvl
	local targetXP = math.floor(100 * ((targetLvl - 1) ^ 1.35))
	profile.Experience = targetXP
	plr:SetAttribute("Experience", targetXP)
	return true
end

-- WALKSPEED
local function setSpeed(plr, speed)
	speed = tonumber(speed) or 32
	local char, hum = getPlayerParts(plr)
	if not hum then return false, "Humanoid not found." end
	hum.WalkSpeed = speed
	return true
end

-- JUMPPOWER
local function setJump(plr, jump)
	jump = tonumber(jump) or 100
	local char, hum = getPlayerParts(plr)
	if not hum then return false, "Humanoid not found." end
	hum.UseJumpPower = true
	hum.JumpPower = jump
	return true
end

-- KILL
local function killPlr(plr)
	local char, hum = getPlayerParts(plr)
	if not hum then return false, "Humanoid not found." end
	hum.Health = 0
	return true
end

-- GOD
local function godPlr(plr)
	local char, hum = getPlayerParts(plr)
	if not hum then return false, "Humanoid not found." end
	if hum.MaxHealth == math.huge then
		hum.MaxHealth = 100
		hum.Health = 100
	else
		hum.MaxHealth = math.huge
		hum.Health = math.huge
	end
	return true
end

-- TELEPORT / GOTO
local function tpPlr(speaker, targetPlr)
	local char, hum, hrp = getPlayerParts(speaker)
	local tChar, tHum, tHrp = getPlayerParts(targetPlr)
	if not hrp or not tHrp then return false, "Positioning error." end
	hrp.CFrame = tHrp.CFrame * CFrame.new(0, 0, 3)
	return true
end

-- WORLD
local function tpWorld(plr, worldName)
	if not worldName then return false, "World name missing." end
	local worldsFolder = workspace:FindFirstChild("Areas") or workspace:FindFirstChild("Worlds")
	if worldsFolder then
		local worldObj = worldsFolder:FindFirstChild(worldName, true)
		if worldObj then
			local char, hum, hrp = getPlayerParts(plr)
			if hrp then
				local targetCFrame = worldObj:IsA("Model") and worldObj:GetPivot() or worldObj.CFrame
				hrp.CFrame = targetCFrame + Vector3.new(0, 5, 0)
				return true
			end
		end
	end
	return false, "World not found."
end

-- RESET
local function resetData(plr)
	local profile = Saving.GetPlayerData(plr)
	if profile then
		local default = Saving.GetDefaultData()
		for k in pairs(profile) do profile[k] = nil end
		for k, v in pairs(default) do profile[k] = v end
		
		plr:SetAttribute("Coins", profile.Currency.Coins)
		plr:SetAttribute("Gems", profile.Currency.Gems)
		plr:SetAttribute("Blocks", profile.Storage.Amount)
		plr:SetAttribute("MaxBlocks", profile.Storage.Max)
		
		local char, hum = getPlayerParts(plr)
		if hum then hum.Health = 0 end
		return true
	end
	return false
end

-- HIDELEADERBOARD
local function hideLeaderboard(plr)
	local profile = Saving.GetPlayerData(plr)
	if not profile then return false, "Profile not loaded." end
	profile.HideFromLeaderboard = not profile.HideFromLeaderboard
	local stateStr = profile.HideFromLeaderboard and "HIDDEN from" or "VISIBLE on"
	notification(plr, "✅ Leaderboard privacy updated: You are now " .. stateStr .. " the leaderboard!")
	return true
end

-- KICK
local function kickPlr(plr)
	plr:Kick("Kicked by admin command.")
	return true
end

-- SHUTDOWN
local function shutdownServer()
	task.spawn(function()
		for _, p in ipairs(Players:GetPlayers()) do
			p:Kick("Server Shutdown.")
		end
	end)
	return true
end

-- ANNOUNCE
local function announceMsg(msgTable)
	local msg = table.concat(msgTable, " ")
	if msg == "" then return false end
	for _, p in ipairs(Players:GetPlayers()) do
		notification(p, "[ANNOUNCEMENT] " .. msg)
	end
	return true
end

-- ==================== REGISTER COMMANDS (IBS FORMAT) ====================

-- CASH / COINS
addCommand({
	["cmd"] = "cash",
	["desc"] = "Give Cash to player!";
	["perms"] = { "Admins" },
	["arguments"] = { { "Player", nil, "Player" }, { "Number", nil, "Amount" } },
	["type"] = { 1 },
	["function"] = giveCash,
	["neededValues"] = {
		["plr"] = { needed = true, placement = 1 },
		["sL"] = { { needed = true, placement = 2, index = 4 } },
		["s"] = {}
	}
})

addCommand({
	["cmd"] = "coins",
	["desc"] = "Give Cash to player (alias for cash)!";
	["perms"] = { "Admins" },
	["arguments"] = { { "Player", nil, "Player" }, { "Number", nil, "Amount" } },
	["type"] = { 1 },
	["function"] = giveCash,
	["neededValues"] = {
		["plr"] = { needed = true, placement = 1 },
		["sL"] = { { needed = true, placement = 2, index = 4 } },
		["s"] = {}
	}
})

-- CONTRACTS / GEMS
addCommand({
	["cmd"] = "contracts",
	["desc"] = "Give Contracts (Gems) to player!";
	["perms"] = { "Admins" },
	["arguments"] = { { "Player", nil, "Player" }, { "Number", nil, "Amount" } },
	["type"] = { 1 },
	["function"] = giveContracts,
	["neededValues"] = {
		["plr"] = { needed = true, placement = 1 },
		["sL"] = { { needed = true, placement = 2, index = 4 } },
		["s"] = {}
	}
})

addCommand({
	["cmd"] = "gems",
	["desc"] = "Give Contracts to player (alias)!";
	["perms"] = { "Admins" },
	["arguments"] = { { "Player", nil, "Player" }, { "Number", nil, "Amount" } },
	["type"] = { 1 },
	["function"] = giveContracts,
	["neededValues"] = {
		["plr"] = { needed = true, placement = 1 },
		["sL"] = { { needed = true, placement = 2, index = 4 } },
		["s"] = {}
	}
})

-- BLOCKS
addCommand({
	["cmd"] = "blocks",
	["desc"] = "Set player inventory blocks!";
	["perms"] = { "Admins" },
	["arguments"] = { { "Player", nil, "Player" }, { "Number", nil, "Amount" } },
	["type"] = { 1 },
	["function"] = setBlocks,
	["neededValues"] = {
		["plr"] = { needed = true, placement = 1 },
		["sL"] = { { needed = true, placement = 2, index = 4 } },
		["s"] = {}
	}
})

-- MAXBLOCKS
addCommand({
	["cmd"] = "maxblocks",
	["desc"] = "Set player max block capacity!";
	["perms"] = { "Admins" },
	["arguments"] = { { "Player", nil, "Player" }, { "Number", nil, "Amount" } },
	["type"] = { 1 },
	["function"] = setMaxBlocks,
	["neededValues"] = {
		["plr"] = { needed = true, placement = 1 },
		["sL"] = { { needed = true, placement = 2, index = 4 } },
		["s"] = {}
	}
})

-- LEVELUP / LEVEL
addCommand({
	["cmd"] = "levelup",
	["desc"] = "Increase level for player (default +1 level)!";
	["perms"] = { "Admins" },
	["arguments"] = { { "Player", nil, "Player" }, { "Number", nil, "Amount" } },
	["type"] = { 1 },
	["function"] = giveLevel,
	["neededValues"] = {
		["plr"] = { needed = true, placement = 1 },
		["sL"] = { { needed = true, placement = 2, index = 4 } },
		["s"] = {}
	}
})

addCommand({
	["cmd"] = "level",
	["desc"] = "Increase level for player (alias for levelup)!";
	["perms"] = { "Admins" },
	["arguments"] = { { "Player", nil, "Player" }, { "Number", nil, "Amount" } },
	["type"] = { 1 },
	["function"] = giveLevel,
	["neededValues"] = {
		["plr"] = { needed = true, placement = 1 },
		["sL"] = { { needed = true, placement = 2, index = 4 } },
		["s"] = {}
	}
})

-- SPEED
addCommand({
	["cmd"] = "speed",
	["desc"] = "Set player walkspeed!";
	["perms"] = { "Admins" },
	["arguments"] = { { "Player", nil, "Player" }, { "Number", nil, "Speed" } },
	["type"] = { 1 },
	["function"] = setSpeed,
	["neededValues"] = {
		["plr"] = { needed = true, placement = 1 },
		["sL"] = { { needed = true, placement = 2, index = 4 } },
		["s"] = {}
	}
})

-- JUMP
addCommand({
	["cmd"] = "jump",
	["desc"] = "Set player jump power!";
	["perms"] = { "Admins" },
	["arguments"] = { { "Player", nil, "Player" }, { "Number", nil, "Power" } },
	["type"] = { 1 },
	["function"] = setJump,
	["neededValues"] = {
		["plr"] = { needed = true, placement = 1 },
		["sL"] = { { needed = true, placement = 2, index = 4 } },
		["s"] = {}
	}
})

-- KILL
addCommand({
	["cmd"] = "kill",
	["desc"] = "Kill a player!";
	["perms"] = { "Admins" },
	["arguments"] = { { "Player", nil, "Player" } },
	["type"] = { 1 },
	["function"] = killPlr,
	["neededValues"] = {
		["plr"] = { needed = true, placement = 1 },
		["sL"] = {},
		["s"] = {}
	}
})

-- GOD
addCommand({
	["cmd"] = "god",
	["desc"] = "Toggle god mode!";
	["perms"] = { "Admins" },
	["arguments"] = { { "Player", nil, "Player" } },
	["type"] = { 1 },
	["function"] = godPlr,
	["neededValues"] = {
		["plr"] = { needed = true, placement = 1 },
		["sL"] = {},
		["s"] = {}
	}
})

-- TP
local function giveSkin(targetPlayer, category, item, skinID)
	local profile = Saving.GetPlayerData(targetPlayer)
	if not profile then return false, "Profile not found" end
	if not profile.Skins then profile.Skins = {} end
	-- Inventory limit: keep admins within the same cap as normal grants
	if #profile.Skins >= 100 then return false, "Skin limit reached (100)" end
	local float = math.random()
	
	-- Remove quotes if they exist
	if category then category = string.gsub(category, '\"', '') end
	if item then item = string.gsub(item, '\"', '') end
	if skinID then skinID = string.gsub(skinID, '\"', '') end
	
	table.insert(profile.Skins, {
		ID = skinID,
		Category = category,
		ItemName = item,
		Float = float
	})
	
	return true
end

addCommand({
	["cmd"] = "skin",
	["desc"] = "Give Skin to player!";
	["perms"] = { "Admins" },
	["arguments"] = { { "Player", nil, "Player" }, { "String", nil, "Category" }, { "String", nil, "ItemName" }, { "String", nil, "SkinID" } },
	["type"] = { 1 },
	["function"] = giveSkin,
	["neededValues"] = {
		["plr"] = { needed = true, placement = 1 },
		["s"] = { { needed = true, placement = 2, index = 4 }, { needed = true, placement = 3, index = 5 }, { needed = true, placement = 4, index = 6 } }
	}
})

addCommand({
	["cmd"] = "tp",
	["desc"] = "Teleport to a player!";
	["perms"] = { "Admins" },
	["arguments"] = { { "Player", nil, "Speaker" }, { "Player", nil, "Target" } },
	["type"] = { 1 },
	["function"] = tpPlr,
	["neededValues"] = {
		["plr"] = { needed = true, placement = 2 },
		["sL"] = {},
		["s"] = {}
	}
})

-- WORLD
addCommand({
	["cmd"] = "world",
	["desc"] = "Teleport to a world area!";
	["perms"] = { "Admins" },
	["arguments"] = { { "Player", nil, "Player" }, { "String", nil, "World" } },
	["type"] = { 1 },
	["function"] = tpWorld,
	["neededValues"] = {
		["plr"] = { needed = true, placement = 1 },
		["sL"] = { { needed = true, placement = 2, index = 4 } },
		["s"] = {}
	}
})

-- RESET
addCommand({
	["cmd"] = "reset",
	["desc"] = "Reset player data!";
	["perms"] = { "Admins" },
	["arguments"] = { { "Player", nil, "Player" } },
	["type"] = { 1 },
	["function"] = resetData,
	["neededValues"] = {
		["plr"] = { needed = true, placement = 1 },
		["sL"] = {},
		["s"] = {}
	}
})

-- HIDELEADERBOARD
addCommand({
	["cmd"] = "hideleaderboard",
	["desc"] = "Toggle leaderboard privacy!";
	["perms"] = { "Admins" },
	["arguments"] = { { "Player", nil, "Player" } },
	["type"] = { 1 },
	["function"] = hideLeaderboard,
	["neededValues"] = {
		["plr"] = { needed = true, placement = 1 },
		["sL"] = {},
		["s"] = {}
	}
})

-- KICK
addCommand({
	["cmd"] = "kick",
	["desc"] = "Kick player from server!";
	["perms"] = { "Admins" },
	["arguments"] = { { "Player", nil, "Player" } },
	["type"] = { 1 },
	["function"] = kickPlr,
	["neededValues"] = {
		["plr"] = { needed = true, placement = 1 },
		["sL"] = {},
		["s"] = {}
	}
})

-- SHUTDOWN
addCommand({
	["cmd"] = "shutdown",
	["desc"] = "Shutdown server!";
	["perms"] = { "Admins" },
	["arguments"] = {},
	["type"] = { 1 },
	["function"] = shutdownServer,
	["neededValues"] = {
		["plr"] = { needed = false },
		["sL"] = {},
		["s"] = {}
	}
})

-- ANNOUNCE
addCommand({
	["cmd"] = "announce",
	["desc"] = "Broadcast global announcement!";
	["perms"] = { "Admins" },
	["arguments"] = { { "String", nil, "Message" } },
	["type"] = { 1 },
	["function"] = announceMsg,
	["neededValues"] = {
		["plr"] = { needed = false },
		["sL"] = {},
		["s"] = { all = true, needed = true, placement = 1 }
	}
})

-- HELP
local function helpCmd(player)
	if player then
		OpenAdminHelpEvent:FireClient(player)
	end
	return true
end

addCommand({
	["cmd"] = "help",
	["desc"] = "Toggle the admin commands help console (F4)!";
	["perms"] = { "Admins" },
	["arguments"] = {},
	["type"] = { 1 },
	["function"] = helpCmd,
	["neededValues"] = {
		["plr"] = { needed = true, user = true, placement = 1 },
		["sL"] = {},
		["s"] = {}
	}
})

-- ==================== DISPATCHER (IBS COMMIT LOGIC) ====================

local function commitCmdFunction(user, data, plrTarget, sL, s)
	local neededValues = data["neededValues"]
	local cmdFunction = data["commandFunction"]
	local nPLR, nSL, nS = neededValues["plr"], neededValues["sL"], neededValues["s"]

	local args = {}

	if nPLR and nPLR.needed and nPLR.placement then
		args[nPLR.placement] = plrTarget
	end

	if nSL then
		if nSL.all and nSL.needed then
			args[nSL.placement] = sL
		else
			for _, value in ipairs(nSL) do
				if value.needed then
					args[value.placement] = sL[value.index]
				end
			end
		end
	end

	if nS then
		if nS.all and nS.needed then
			-- Exclude prefix & command from string table
			local cleanedS = {}
			for i = 3, #s do table.insert(cleanedS, s[i]) end
			args[nS.placement] = cleanedS
		else
			for _, value in ipairs(nS) do
				if value.needed then
					args[value.placement] = s[value.index]
				end
			end
		end
	end

	-- For commands like /e tp speaker target
	if data.cmds[1] == "tp" then
		args = { user, plrTarget }
	end

	local success, err = cmdFunction(unpack(args))
	if success then
		notification(user, "✅ Successfully used command: " .. tostring(data.cmds[1]), true)
	else
		notification(user, err or "⚠️ Command failed: (Unknown error)", false)
	end
	return success, err
end

local function processMessage(plr, msg)
	if not msg or typeof(msg) ~= "string" then return false, "Empty message" end
	local sL = string.split(string.lower(msg), " ")
	local s = string.split(msg, " ")
	
	local rawPrefix = sL[1]
	if not rawPrefix then return false, "No prefix" end

	local prefix = rawPrefix
	local cmd = sL[2]
	local target = s[3]

	-- Allow direct commands like /levelup, /levelup 5, /levelup me 5 as well as /e levelup me 5
	if rawPrefix ~= "/e" then
		local firstChar = string.sub(rawPrefix, 1, 1)
		if firstChar == "/" or firstChar == "!" or firstChar == ";" then
			cmd = string.sub(rawPrefix, 2)
			prefix = "/e"
			
			local param1 = s[2]
			local param2 = s[3]
			if param1 and tonumber(param1) then
				target = "me"
				sL = { "/e", cmd, "me", param1 }
				s = { "/e", cmd, "me", param1 }
			elseif param1 then
				target = param1
				sL = { "/e", cmd, target, param2 or "1" }
				s = { "/e", cmd, target, param2 or "1" }
			else
				target = "me"
				sL = { "/e", cmd, "me", "1" }
				s = { "/e", cmd, "me", "1" }
			end
		else
			-- Direct command string without slash e.g. "cash me 1000" or "help"
			cmd = rawPrefix
			prefix = "/e"
			local param1 = s[2]
			local param2 = s[3]
			if param1 and tonumber(param1) then
				target = "me"
				sL = { "/e", cmd, "me", param1 }
				s = { "/e", cmd, "me", param1 }
			elseif param1 then
				target = param1
				sL = { "/e", cmd, target, param2 or "1" }
				s = { "/e", cmd, target, param2 or "1" }
			else
				target = "me"
				sL = { "/e", cmd, "me", "1" }
				s = { "/e", cmd, "me", "1" }
			end
		end
	end

	if prefix ~= "/e" or not cmd or cmd == "" then
		return false, "Invalid format"
	end

	local cmdData = getCmd(cmd)
	if not cmdData then
		return false, "Unknown command: " .. tostring(cmd)
	end

	if not checkPermissions(plr, cmdData["permtype"]) then
		notification(plr, "⚠️ Command failed: (You cannot use this command)", false)
		return false, "Unauthorized"
	end

	local neededValues = cmdData["neededValues"]
	local nPLR = neededValues["plr"]
	
	if not nPLR or not nPLR.needed then
		return commitCmdFunction(plr, cmdData, nil, sL, s)
	end

	if nPLR.user then
		return commitCmdFunction(plr, cmdData, plr, sL, s)
	end

	if not target then
		target = "me"
	end

	local plrTarget = nil
	if target == "me" then
		plrTarget = plr
	elseif target == "all" then
		plrTarget = Players:GetPlayers()
	else
		plrTarget = getPlrByDisplay(target)
	end

	if not plrTarget then
		notification(plr, "⚠️ Command failed: (Could not find player)", false)
		return false, "Could not find player"
	end

	if type(plrTarget) == "table" then
		local allOk = true
		for _, v in ipairs(plrTarget) do
			local ok = commitCmdFunction(plr, cmdData, v, sL, s)
			if not ok then allOk = false end
		end
		return allOk
	else
		return commitCmdFunction(plr, cmdData, plrTarget, sL, s)
	end
end

-- Server remote bindings
AdminCommandInvokeRemote.OnServerInvoke = function(player, cmdText)
	if not isPlayerAdmin(player) then
		return false, "Unauthorized: You do not have admin permissions."
	end
	return processMessage(player, cmdText)
end

GetAdminCommandsRemote.OnServerInvoke = function(player)
	if not isPlayerAdmin(player) then
		return {}
	end
	local list = {}
	for _, v in ipairs(commands) do
		local argNames = {}
		if v.arguments then
			for _, arg in ipairs(v.arguments) do
				table.insert(argNames, arg[3] or arg[1] or "arg")
			end
		end
		table.insert(list, {
			cmd = v.cmds[1],
			aliases = v.cmds,
			desc = v.desc,
			args = argNames,
		})
	end
	return list
end

IsAdminRemote.OnServerInvoke = function(player)
	return isPlayerAdmin(player)
end

local function adminPlayer(plr)
	plr:SetAttribute("IsAdmin", isPlayerAdmin(plr))
	plr.Chatted:Connect(function(msg)
		processMessage(plr, msg)
	end)
end

for _, player in ipairs(Players:GetPlayers()) do
	adminPlayer(player)
end
Players.PlayerAdded:Connect(adminPlayer)

-- Support modern TextChatService (Roblox default in live published places)
pcall(function()
	TextChatService.MessageReceived:Connect(function(textChatMessage)
		local textSource = textChatMessage.TextSource
		if not textSource then return end
		local player = Players:GetPlayerByUserId(textSource.UserId)
		if player and isPlayerAdmin(player) then
			processMessage(player, textChatMessage.Text)
		end
	end)
end)
