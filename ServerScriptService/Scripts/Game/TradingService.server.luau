--[[

     THIS WAS ORIGINALLY SCRIPTED BY Velvet GAMES

--]]

--------|     Setting     |--------

local RunService = game:GetService("RunService")

--------|     Library     |--------
local _L = require(game.ReplicatedStorage:WaitForChild("Library"))
while not _L.Loaded do
	RunService.Heartbeat:Wait()
end

--------|    Reference    |--------

-- REMOTE BOOTSTRAP: Network remotes are created LAZILY on first use. Remotes
-- that only ever travel server->client (e.g. "Trade Recieved") would not
-- exist until the first trade invite, but the client listeners register at
-- join and give up after ~15s — so invites sent later were silently never
-- delivered (receiver got no accept prompt). Registering the names here
-- forces every server->client remote to exist at server start.
for _, remoteName in ipairs({
	"Trade Recieved",
	"Update Trade Invites Open",
	"Trade Ignored",
	"Trade Processed",
	"Trade Cancelled",
	"Init Trade",
	"Update Trade",
	"Send Message",
	-- Listened by the client but never fired by this port; registered so the
	-- client listener setup stops retrying/warning forever.
	"Trade Errored",
	"Trade Sent Chat Result",
}) do
	_L.Network.Fired(remoteName)
end

--------|    Variables    |--------
local trades = {}

local MAX_TRADE_HISTORY = 25

-- Hard cap on skins per player profile (inventory limit).
local MAX_SKINS = 100

local function EnsureTradeHistory(save)
	if not save then
		return nil
	end

	if type(save.TradeHistory2) ~= "table" then
		save.TradeHistory2 = {}
	end

	return save.TradeHistory2
end

-- Fields SkinUI.Create actually needs to render a history skin. Keeping only
-- these (instead of every scalar on the live skin) trims the TradeHistory2
-- DataStore payload: 25 entries x up to 200 skins per trade.
local HISTORY_SKIN_FIELDS = { "uid", "UID", "id", "ID", "category", "Category", "itemName", "ItemName", "fl", "Float" }

local function CopyTradeItems(items)
	local copy = {}
	for _, item in ipairs(items or {}) do
		if type(item) == "table" then
			local itemCopy = {}
			for _, key in ipairs(HISTORY_SKIN_FIELDS) do
				if item[key] ~= nil then
					itemCopy[key] = item[key]
				end
			end
			table.insert(copy, itemCopy)
		else
			table.insert(copy, item)
		end
	end
	return copy
end

local function FireTradeHistoryChanged(player)
	_L.Signal.Fire("Stat Changed", player, "TradeHistory2")
	_L.Signal.Fire("Stat Changed", player, "TradingHistory2")
end

local function ValidateAction(player, actionType, cooldown)
	if not player or not player.Parent then return false end
	local attr = "LastAction_" .. tostring(actionType)
	local last = player:GetAttribute(attr)
	local now = os.clock()
	if last and (now - last) < cooldown then return false end
	player:SetAttribute(attr, now)
	return true
end

_L.Network.Invoked("Rate Trade").OnInvoke = function(player, userId, timestamp, tradeType, rate)
	-- Strict typing: nil/invalid values used to slip through loose matchers and
	-- hit whatever history entry happened to be first.
	if typeof(userId) ~= "number" or typeof(timestamp) ~= "number" or typeof(rate) ~= "boolean" then
		return false, "Invalid rating request."
	end

	if not ValidateAction(player, "RateTrade", 1.0) then
		return false, "You are rating too fast!"
	end

	local save = _L.Saving.GetPlayerData(player)
	local history = EnsureTradeHistory(save)
	if not history then
		return false, "Could not find your save."
	end

	local matchedEntry = nil
	for _, log in ipairs(history) do
		if log.u == userId and log.ts == timestamp and (tradeType == nil or log.t == tradeType) then
			matchedEntry = log
			break
		end
	end

	if not matchedEntry then
		return false, "Trade history entry was not found."
	end

	-- One-time rating: without this guard a player could flip a partner's
	-- reputation indefinitely by re-invoking the remote.
	if matchedEntry.r ~= nil then
		return false, "You already rated this trade."
	end

	matchedEntry.r = rate

	-- Stamp the received rating into the partner's own history entry (or_ is
	-- what GetTradeRating aggregates). If the partner is offline the stamp is
	-- deferred: onPlayerAddedRatings reconciles pending ratings when the
	-- partner later joins a server where the rater is still present.
	local partnerPlayer = game.Players:GetPlayerByUserId(userId)
	if partnerPlayer and partnerPlayer.Parent then
		local partnerHistory = EnsureTradeHistory(_L.Saving.GetPlayerData(partnerPlayer))
		if partnerHistory then
			for _, partnerLog in ipairs(partnerHistory) do
				if partnerLog.u == player.UserId and partnerLog.ts == timestamp then
					partnerLog.or_ = rate
					break
				end
			end
		end
		FireTradeHistoryChanged(partnerPlayer)
	end

	-- No explicit SaveData here: each rating would otherwise perform two
	-- synchronous full-profile SetAsync writes, and a spammed remote would
	-- burn the DataStore request budget. The auto-save loop persists it.
	FireTradeHistoryChanged(player)
	print(string.format("[Trade Server] ⭐ %s rated trade with User %s as %s", player.Name, tostring(userId), rate and "POSITIVE" or "NEGATIVE"))
	return true
end

-- Deferred rating reconciliation: when a player joins, copy any pending
-- outgoing ratings (r) from co-present players' histories into their own
-- history as received ratings (or_). Idempotent (or_ is only written when
-- nil) and bounded by the 25-entry history cap.
local function onPlayerAddedRatings(player)
	task.spawn(function()
		local deadline = os.clock() + 60
		while not player:FindFirstChild("__LOADED") do
			if not player.Parent or os.clock() > deadline then
				return
			end
			task.wait(1)
		end

		local incomingHistory = EnsureTradeHistory(_L.Saving.GetPlayerData(player))
		if not incomingHistory then
			return
		end

		local stamped = false
		for _, otherPlayer in ipairs(game.Players:GetPlayers()) do
			if otherPlayer ~= player then
				local otherSave = _L.Saving.GetPlayerData(otherPlayer)
				local otherHistory = otherSave and otherSave.TradeHistory2
				if otherHistory then
					for _, otherLog in ipairs(otherHistory) do
						if otherLog.u == player.UserId and otherLog.r ~= nil then
							for _, incomingLog in ipairs(incomingHistory) do
								if incomingLog.u == otherPlayer.UserId and incomingLog.ts == otherLog.ts and incomingLog.or_ == nil then
									incomingLog.or_ = otherLog.r
									stamped = true
									break
								end
							end
						end
					end
				end
			end
		end

		if stamped then
			FireTradeHistoryChanged(player)
		end
	end)
end

_L.Signal.Fired("Player Added"):connect(onPlayerAddedRatings)
for _, p in ipairs(game.Players:GetPlayers()) do
	task.spawn(onPlayerAddedRatings, p)
end

local function GetCoins(playerProfile)
	if not playerProfile then
		return 0
	end
	if playerProfile.Currency and playerProfile.Currency.Coins then
		return playerProfile.Currency.Coins
	end
	return playerProfile.Coins or 0
end

local function AddCoins(playerProfile, amount)
	if not playerProfile then
		return
	end
	if playerProfile.Currency then
		playerProfile.Currency.Coins = (playerProfile.Currency.Coins or 0) + amount
	else
		playerProfile.Coins = (playerProfile.Coins or 0) + amount
	end
end

-- Contracts live in TWO keys for legacy reasons (root `Contracts` and
-- `Currency.Contracts`). GameInit's replication loop historically read
-- `Currency.Contracts` first while this service only mutated the root key,
-- so after a trade the HUD stayed frozen on the old value even though the
-- save was correct. Every contract mutation MUST go through SetContracts so
-- both keys and the replicated attribute stay in sync.
local function GetContracts(playerProfile)
	if not playerProfile then
		return 0
	end
	return math.max(playerProfile.Contracts or 0, (playerProfile.Currency and playerProfile.Currency.Contracts) or 0)
end

local function SetContracts(player, playerProfile, value)
	if not playerProfile then
		return
	end
	playerProfile.Contracts = value
	if not playerProfile.Currency then
		playerProfile.Currency = {}
	end
	playerProfile.Currency.Contracts = value
	if player and player.Parent then
		player:SetAttribute("Contracts", value)
	end
end

local function GetSkin(skinUid)
	if not skinUid then
		return nil
	end
	local targetUidStr = tostring(skinUid)
	for _, player in ipairs(game.Players:GetPlayers()) do
		local profile = _L.Saving.GetPlayerData(player)
		if profile and profile.Skins then
			for _, skin in ipairs(profile.Skins) do
				local uid = skin.uid or skin.UID
				if uid and tostring(uid) == targetUidStr then
					return skin, player
				end
			end
		end
	end
	return nil
end

local function IsSkinTradeable(skin)
	if not skin then
		return false
	end
	local category = skin.Category or skin.category or ""
	local itemName = skin.ItemName or skin.itemName or ""
	local skinId = skin.ID or skin.id or ""

	local skins = _L.Directory and _L.Directory.Skins
	if skins then
		local catTable = skins[category]
		if not catTable then
			for k, v in pairs(skins) do
				if string.lower(k) == string.lower(category) then
					catTable = v
					break
				end
			end
		end

		if catTable and type(catTable) == "table" then
			local itemTable = catTable[itemName]
			if not itemTable then
				for k, v in pairs(catTable) do
					if string.lower(k) == string.lower(itemName) then
						itemTable = v
						break
					end
				end
			end

			if itemTable and type(itemTable) == "table" then
				local skinConfig = itemTable[skinId]
				if not skinConfig then
					for k, v in pairs(itemTable) do
						if string.lower(k) == string.lower(skinId) then
							skinConfig = v
							break
						end
					end
				end

				if skinConfig and type(skinConfig) == "table" then
					if skinConfig.tradeble == false or skinConfig.tradable == false or skinConfig.tradeable == false or skinConfig.Tradeable == false or skinConfig.Tradeble == false then
						return false
					end
				end
			end
		end
	end
	return true
end

local function DeleteSkin(skinUid)
	local skin, player = GetSkin(skinUid)
	if not skin or not player then
		return false
	end
	local profile = _L.Saving.GetPlayerData(player)
	if not profile or not profile.Skins then
		return false
	end

	for index, skinEntry in ipairs(profile.Skins) do
		if skinEntry.uid == skinUid or skinEntry.UID == skinUid then
			table.remove(profile.Skins, index)

			if profile.EquippedSkins then
				for category, categorySkins in pairs(profile.EquippedSkins) do
					for weaponName, skinData in pairs(categorySkins) do
						if type(skinData) == "table" and (skinData.UID == skinUid or skinData.uid == skinUid) then
							categorySkins[weaponName] = nil
						end
					end
				end
			end
			return true
		end
	end
	return false
end

local function GiveSkin(player, skinData)
	local profile = _L.Saving.GetPlayerData(player)
	if not profile then
		return false
	end
	profile.Skins = profile.Skins or {}

	-- Inventory limit: never exceed MAX_SKINS skins per player
	if type(skinData) ~= "table" or #profile.Skins >= MAX_SKINS then
		warn("[Trading] GiveSkin rejected for " .. player.Name .. " (limit " .. MAX_SKINS .. " or bad skinData)")
		return false
	end

	local newUID = game:GetService("HttpService"):GenerateGUID(false)
	table.insert(profile.Skins, {
		ID = skinData.ID or skinData.id,
		id = skinData.id or skinData.ID,
		Category = skinData.Category or skinData.category,
		category = skinData.category or skinData.Category,
		ItemName = skinData.ItemName or skinData.itemName,
		itemName = skinData.itemName or skinData.ItemName,
		Float = skinData.Float or skinData.fl or 0.5,
		fl = skinData.fl or skinData.Float or 0.5,
		uid = newUID,
		UID = newUID,
	})
	return true
end

--------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------

local function GetByPlyr(player)
	for tradeId, tradeData in pairs(trades) do
		if tradeData.sender == player or tradeData.target == player then
			return tradeData, tostring(tradeId)
		end
	end
	return nil
end

_G.GetByPlyr = GetByPlyr

_G.Friends = {}
local function iterPageItems(pages)
	return coroutine.wrap(function()
		local pagenum = 1
		while true do
			for _, item in ipairs(pages:GetCurrentPage()) do
				coroutine.yield(item, pagenum)
			end
			if pages.IsFinished then
				break
			end
			pages:AdvanceToNextPageAsync()
			pagenum = pagenum + 1
		end
	end)
end

local function onPlayerAddedFriends(player)
	pcall(function()
		local friendPages = game.Players:GetFriendsAsync(player.UserId)
		local usernames = {}

		for item, pageNo in iterPageItems(friendPages) do
			table.insert(usernames, item.Id)
		end
		if player and player.Parent then
			_G.Friends[tostring(player.UserId)] = usernames
		end
	end)
end

_L.Signal.Fired("Player Added"):connect(onPlayerAddedFriends)
for _, p in ipairs(game.Players:GetPlayers()) do
	task.spawn(onPlayerAddedFriends, p)
end

game.Players.PlayerRemoving:Connect(function(player)
	_G.Friends[tostring(player.UserId)] = nil
end)

local WL = {}
for i, v in pairs({ "id", "uid", "idt", "s", "nk", "l", "snk", "hc", "powers", "merchData", "g", "r", "dm", "sh" }) do
	WL[v] = true
end

local TradingTemplate = {
	sender = nil,
	target = nil,
	targetReady = false,
	senderReady = false,
	targetConfirmed = false,
	senderConfirmed = false,
	confirmStage = false,
	processing = false,
	counter = 0,
	lastCounter = 0,
	senderItems = {
		skins = {},
		contracts = 0,
		coins = 0,
	},
	targetItems = {
		skins = {},
		contracts = 0,
		coins = 0,
	},
	messages = {},
	confirmTick = 0,
}

local PlayerTradeStates = {}

local function onPlayerAddedInfo(player)
	PlayerTradeStates[tostring(player.UserId)] = { os.clock(), false }
end

_L.Signal.Fired("Player Added"):connect(onPlayerAddedInfo)
for _, p in ipairs(game.Players:GetPlayers()) do
	onPlayerAddedInfo(p)
end

game.Players.PlayerRemoving:Connect(function(player)
	PlayerTradeStates[tostring(player.UserId)] = nil
end)

local function GetTradingTimer(player)
	if not player or not player.Parent then return false end
	if game:GetService("RunService"):IsStudio() then
		return true
	end
	if PlayerTradeStates[tostring(player.UserId)] then
		local elapsed = os.clock() - PlayerTradeStates[tostring(player.UserId)][1]
		return elapsed >= 10
	end
	return true
end

local function CheckBro(player, isInit)
	if not (player and player.Parent and player:IsDescendantOf(game.Players)) then
		return false
	end
	if not _L.Saving.GetPlayerData(player) then
		return false
	end
	if GetByPlyr(player) and isInit then
		return false
	end
	return true
end

local function Get(tradeId)
	return trades[tostring(tradeId)]
end

local function GetPartners(tradeId)
	local trade = Get(tradeId)
	if not trade then
		return
	end
	return trade.sender, trade.target
end

local function CheckTrade(tradeId)
	local partnerA, partnerB = GetPartners(tradeId)
	if not (CheckBro(partnerA) and CheckBro(partnerB)) then
		return
	end
	if not Get(tradeId) then
		return
	end
	return true
end

local function NotifyPartners(tradeId, message, eventName, customPartners)
	local function send(player)
		task.spawn(function()
			pcall(function()
				_L.Network.Fire((eventName or "Send Message"), player, (message == true and true) or tostring(message))
			end)
		end)
	end
	local trade = Get(tradeId)
	if customPartners and customPartners[1] and customPartners[2] then
		send(customPartners[1])
		send(customPartners[2])
	else
		if (not trade) or (not CheckTrade(tradeId)) then
			return false
		end
		send(trade.sender)
		send(trade.target)
	end
	return true
end

local function SendPartners(tradeId, eventName, onComplete, ...)
	local args = { ... }
	local function send(player)
		pcall(function()
			_L.Network.Fire(eventName, player, unpack(args))
		end)
	end
	local trade = Get(tradeId)
	if (not trade) or (not CheckTrade(tradeId)) then
		return false
	end
	send(trade.sender)
	send(trade.target)
	onComplete()
	return true
end

local function ForceStopTrade(tradeId, reason)
	if trades[tostring(tradeId)] then
		if reason == "/" then
			SendPartners(tradeId, "Trade Processed", function()
				trades[tostring(tradeId)] = nil
			end, "/")
		else
			warn(tostring(reason))
			SendPartners(tradeId, "Trade Processed", function()
				trades[tostring(tradeId)] = nil
			end, false)
		end
		trades[tostring(tradeId)] = nil
	end
end

local function Update(tradeId)
	local trade = Get(tradeId)
	if not trade then
		return false
	end
	if not CheckTrade(tradeId) then
		return false
	end

	-- Package skin metadata directly into trade.skinsData so partner clients render skins instantly with 0 ms delay
	trade.skinsData = trade.skinsData or {}
	local function cacheSkins(player, items)
		if not items or not items.skins then return end
		local profile = _L.Saving.GetPlayerData(player)
		if not profile or not profile.Skins then return end
		for _, skinUid in ipairs(items.skins) do
			local uidStr = tostring(skinUid)
			if not trade.skinsData[uidStr] then
				for _, skin in ipairs(profile.Skins) do
					if tostring(skin.uid or skin.UID) == uidStr then
						trade.skinsData[uidStr] = {
							id = skin.id or skin.ID,
							ID = skin.ID or skin.id,
							category = skin.category or skin.Category,
							Category = skin.Category or skin.category,
							itemName = skin.itemName or skin.ItemName,
							ItemName = skin.ItemName or skin.itemName,
							Float = skin.Float or skin.fl or 0.5,
							fl = skin.fl or skin.Float or 0.5,
							uid = uidStr,
							UID = uidStr,
						}
						break
					end
				end
			end
		end
	end

	cacheSkins(trade.sender, trade.senderItems)
	cacheSkins(trade.target, trade.targetItems)

	-- Prune metadata for skins that left both offers so the replicated payload
	-- does not grow unbounded across long trading sessions.
	local uidsInOffer = {}
	for _, items in ipairs({ trade.senderItems, trade.targetItems }) do
		if items and items.skins then
			for _, skinUid in ipairs(items.skins) do
				uidsInOffer[tostring(skinUid)] = true
			end
		end
	end
	for uidStr in pairs(trade.skinsData) do
		if not uidsInOffer[uidStr] then
			trade.skinsData[uidStr] = nil
		end
	end

	-- Monotonic version: client-side "Get Trade" safety poll uses it to never
	-- overwrite fresher pushed state with a stale snapshot (flicker guard).
	trade.version = (trade.version or 0) + 1

	local function send(player)
		_L.Network.Fire("Update Trade", player, tostring(tradeId), Get(tradeId))
	end
	send(trade.sender)
	send(trade.target)
	return true
end

local function SafelyUpdate(tradeId)
	if not Update(tradeId) then
		ForceStopTrade(tradeId, "Something went wrong while updating the trade partners")
		return false
	end
	return true
end

local function DeepCopy(original)
	local copy = {}
	for k, v in pairs(original) do
		if type(v) == "table" then
			v = DeepCopy(v)
		end
		copy[k] = v
	end
	return copy
end

local function Initialize(player, targetPlayer)
	if (not GetByPlyr(player)) and (not GetByPlyr(targetPlayer)) then
		if not (CheckBro(player, true) and CheckBro(targetPlayer, true) and player.UserId ~= targetPlayer.UserId) then
			return
		end
		if not PlayerTradeStates[tostring(player.UserId)] then
			PlayerTradeStates[tostring(player.UserId)] = { os.clock(), false }
		end
		if not PlayerTradeStates[tostring(targetPlayer.UserId)] then
			PlayerTradeStates[tostring(targetPlayer.UserId)] = { os.clock(), false }
		end

		-- Library.Functions exposes DeepCopy (there is no CloneTable in this
		-- codebase; calling it crashed Initialize and the trade window never
		-- opened for either player).
		local trade = _L.Functions.DeepCopy(TradingTemplate)
		if not (trade and trade.senderItems) then
			return
		end
		local tradeId = _L.Functions.GenerateUID()

		trade.sender = player
		trade.target = targetPlayer
		trade.id = tostring(tradeId)
		trade["messages"] = {}

		trades[tradeId] = trade

		_L.Network.Fire("Init Trade", player, tradeId, trades[tradeId])
		_L.Network.Fire("Init Trade", targetPlayer, tradeId, trades[tradeId])

		PlayerTradeStates[tostring(player.UserId)][2] = true
		PlayerTradeStates[tostring(targetPlayer.UserId)][2] = true

		return trades[tradeId], tradeId
	end
end

local function FigureOutOfferString(player)
	local trade, tradeId = GetByPlyr(player)
	if not trade then
		return
	end
	if trade.sender == player then
		return "senderItems"
	end
	if trade.target == player then
		return "targetItems"
	end
	return
end

local function FigureOutSenderData(player)
	local trade, tradeId = GetByPlyr(player)
	if not trade then
		return
	end
	if trade.sender == player then
		return "sender"
	end
	if trade.target == player then
		return "target"
	end
	return
end

local function FigureSendMessage(player)
	local trade, tradeId = GetByPlyr(player)
	if not trade then
		return
	end
	if trade.sender == player then
		return "messages"
	end
	return
end

-- TODO: HERE.
local function AddSkin(player, tradeId, skinId)
	local playerProfile = _L.Saving.GetPlayerData(player)
	if not playerProfile then
		return false, "Could not find save for player. This is crucial"
	end
	if not (PlayerTradeStates[tostring(player.UserId)] and PlayerTradeStates[tostring(player.UserId)][2]) then
		return false, "You cant add skins!"
	end
	local skin, ownerPlayer = GetSkin(tostring(skinId))
	local actualUid = skin and (skin.uid or skin.UID)
	if not (skin and actualUid and tostring(actualUid) == tostring(skinId) and ownerPlayer and ownerPlayer == player) then
		return false, "Could not add skin to trade because of failed ownership check"
	end
	if not IsSkinTradeable(skin) then
		return false, "This skin cannot be traded!"
	end
	local trade, id = GetByPlyr(player)
	if tostring(id) ~= tradeId then
		return false, "IDs were not the same"
	end
	if not trade or not id then
		return false, "Could not identify trade"
	end
	if trade.processing == true or trade.isProcess == true then
		return false, "Trade is processing"
	end

	if skin.l or skin.l == true then
		return false, "Skin is locked, unlock it first!"
	end

	local offer = FigureOutOfferString(player)
	if not offer then
		return false, "Could not figure out offer string"
	end
	if not trade[offer] then
		return false, "Offer string was invalid"
	end
	local uidStr = tostring(actualUid)
	if _L.Functions.SearchArray(trade[offer].skins, uidStr) then
		return false, "Skin is already in offer."
	end
	if #trade[offer].skins >= 30 then
		return false, "Your side is full"
	end
	table.insert(trade[offer].skins, uidStr)
	trade.senderReady = false
	trade.targetReady = false
	trade.targetConfirmed = false
	trade.senderConfirmed = false
	trade.confirmStage = false

	print(string.format("[Trade Server] %s ADDED skin UID %s to Trade %s (Total: %d skins in offer)", player.Name, uidStr, tostring(id), #trade[offer].skins))

	if not SafelyUpdate(id) then
		return false, "Trade could not safely update"
	end

	trade.counter = workspace:GetServerTimeNow() + 3
	trade.lastCounter = workspace:GetServerTimeNow()

	return true
end

_L.Network.Invoked("Send Trade Message").OnInvoke = function(player, tradeId, textMessage)
	local playerProfile = _L.Saving.GetPlayerData(player)
	local trade, id = GetByPlyr(player)
	if tostring(id) ~= tradeId then
		return false, "IDs were not the same"
	end

	if not trade or not id then
		return false, "Could not identify trade"
	end

	if trade.processing == true or trade.isProcess == true then
		return false, "Trade is processing"
	end

	if not playerProfile then
		return false, "No player data found"
	end

	if not textMessage or textMessage == "" then
		return false, "Please say anything first!"
	end

	-- Mirror the client-side cap server-side: without it a spammer can grow
	-- trade.messages (and every Update Trade payload) without bound.
	if #trade.messages >= 50 then
		return false, "This chat is now full! You can use default chat as a backup."
	end

	local filtered
	local success, err = pcall(function()
		filtered = _L.TextService:FilterStringAsync(textMessage, player.UserId)
		filtered = filtered:GetNonChatStringForBroadcastAsync()
	end)

	if not success or not filtered then
		if RunService:IsStudio() then
			filtered = textMessage
		else
			return nil, "Unable to filter your message. Try something else"
		end
	end

	trade.senderReady = false
	trade.targetReady = false
	trade.targetConfirmed = false
	trade.senderConfirmed = false
	trade.confirmStage = false

	if player == trade.sender then
		table.insert(trade.messages, { isSender = true, message = tostring(filtered) })
	elseif player == trade.target then
		table.insert(trade.messages, { isSender = false, message = tostring(filtered) })
	else
		return false, "Something went wrong, try again later"
	end

	if not SafelyUpdate(id) then
		return false, "Trade could not safely update"
	end

	return true
end

_L.Network.Invoked("Change Trade Contracts").OnInvoke = function(player, tradeId, amount)
	local playerProfile = _L.Saving.GetPlayerData(player)
	if not playerProfile then
		return false, "Could not find save for player. This is crucial"
	end

	if not (PlayerTradeStates[tostring(player.UserId)] and PlayerTradeStates[tostring(player.UserId)][2]) then
		return false, "You cant change contracts!"
	end

	local trade, id = GetByPlyr(player)
	if tostring(id) ~= tradeId then
		return false, "IDs were not the same"
	end

	if not trade or not id then
		return false, "Could not identify trade"
	end

	if trade.processing == true or trade.isProcess == true then
		return false, "Trade is processing"
	end

	local amountNumber = tonumber(amount)
	if not amountNumber then
		return false
	end

	local maxContracts = GetContracts(playerProfile)
	amountNumber = math.clamp(math.round(amountNumber), 0, maxContracts)

	local offer = FigureOutOfferString(player)
	if not (offer and trade[offer]) then
		return false, "Offer string is invalid"
	end
	trade[offer].contracts = amountNumber
	trade.senderReady = false
	trade.targetReady = false
	trade.targetConfirmed = false
	trade.senderConfirmed = false
	trade.confirmStage = false

	if not SafelyUpdate(id) then
		return false, "Trade could not safely update"
	end

	trade.counter = workspace:GetServerTimeNow() + 3
	trade.lastCounter = workspace:GetServerTimeNow()

	return true, amountNumber
end

_L.Network.Invoked("Change Trade Coins").OnInvoke = function(player, tradeId, amount)
	local playerProfile = _L.Saving.GetPlayerData(player)
	if not playerProfile then
		return false, "Could not find save for player. This is crucial"
	end

	if not (PlayerTradeStates[tostring(player.UserId)] and PlayerTradeStates[tostring(player.UserId)][2]) then
		return false, "You cant add cash!"
	end

	local trade, id = GetByPlyr(player)
	if tostring(id) ~= tradeId then
		return false, "IDs were not the same"
	end

	if not trade or not id then
		return false, "Could not identify trade"
	end

	if trade.processing == true or trade.isProcess == true then
		return false, "Trade is processing"
	end

	local amountNumber = tonumber(amount)
	if not amountNumber then
		return false
	end

	local maxCoins = GetCoins(playerProfile) or 0
	amountNumber = math.clamp(math.round(amountNumber), 0, maxCoins)

	local offer = FigureOutOfferString(player)
	if not (offer and trade[offer]) then
		return false, "Offer string is invalid"
	end
	trade[offer].coins = amountNumber
	trade.senderReady = false
	trade.targetReady = false
	trade.targetConfirmed = false
	trade.senderConfirmed = false
	trade.confirmStage = false

	if not SafelyUpdate(id) then
		return false, "Trade could not safely update"
	end

	trade.counter = workspace:GetServerTimeNow() + 3
	trade.lastCounter = workspace:GetServerTimeNow()

	return true, amountNumber
end

_L.Network.Invoked("Add Trade Skin").OnInvoke = AddSkin

_L.Network.Invoked("Get Trade").OnInvoke = function(player, sessionId)
	local trade = trades[tostring(sessionId)]
	if trade and (trade.sender == player or trade.target == player) then
		return trade
	end
	return nil
end

local function FigureOutDetails(player, tradeId)
	local trade = Get(tostring(tradeId))
	if not trade then
		return
	end
	if trade.target == player then
		return nil, trade.sender
	else
		return nil, trade.target
	end
end

_L.Network.Invoked("Remove Trade Skin").OnInvoke = function(player, tradeId, skinId)
	local playerProfile = _L.Saving.GetPlayerData(player)
	if not playerProfile then
		return false, "Could not find save for player. This is crucial"
	end
	if not (PlayerTradeStates[tostring(player.UserId)] and PlayerTradeStates[tostring(player.UserId)][2]) then
		return false, "You cant change skins!"
	end
	local skin, ownerPlayer = GetSkin(tostring(skinId))
	local actualUid = skin and (skin.uid or skin.UID)
	if not (skin and actualUid and tostring(actualUid) == tostring(skinId) and ownerPlayer and ownerPlayer == player) then
		return false, "Could not remove skin because of failed ownership check"
	end
	local trade, id = GetByPlyr(player)
	if not trade or not id then
		return false, "Could not identify trade"
	end
	if tostring(id) ~= tradeId then
		return false, "IDs were not the same"
	end
	if trade.processing == true or trade.isProcess == true then
		return false, "Trade is processing"
	end
	local offer = FigureOutOfferString(player)
	if not offer then
		return false, "Could not figure out offer string"
	end
	if not trade[offer] then
		return false, "Offer string was invalid"
	end
	if not _L.Functions.SearchArray(trade[offer].skins, tostring(skinId)) then
		return false, "Skin not in offer."
	end
	local removed = false
	for skinIndex = #trade[offer].skins, 1, -1 do
		if trade[offer].skins[skinIndex] == tostring(skinId) then
			table.remove(trade[offer].skins, skinIndex)
			removed = true
		end
	end
	trade.senderReady = false
	trade.targetReady = false
	trade.targetConfirmed = false
	trade.senderConfirmed = false
	trade.confirmStage = false

	if not removed then
		return false, "Failed to remove"
	end

	print(string.format("[Trade Server] %s REMOVED skin UID %s from Trade %s (Remaining: %d skins)", player.Name, tostring(skinId), tostring(id), #trade[offer].skins))

	if not SafelyUpdate(id) then
		return false, "Trade could not safely update"
	end
	return true
end

local function CorrectSkinIds(id)
	local trade = Get(id)
	if not (trade and trade.senderItems and trade.targetItems) then
		return
	end
	local f = true
	for i, v in pairs(trade.senderItems.skins) do
		local skin = GetSkin(tostring(v))
		if not skin or not IsSkinTradeable(skin) then
			f = false
			break
		end
	end
	if f then
		for i, v in pairs(trade.targetItems.skins) do
			local skin = GetSkin(tostring(v))
			if not skin or not IsSkinTradeable(skin) then
				f = false
				break
			end
		end
	end
	return f
end

local function ProcessTrade(tradeId)
	local timeStart = os.clock()
	local trade = Get(tradeId)
	if not trade then
		return
	end
	print(string.format("[Trade Server] ProcessTrade STARTED for Trade %s between %s and %s", tostring(tradeId), tostring(trade.sender and trade.sender.Name), tostring(trade.target and trade.target.Name)))
	if not CheckTrade(tradeId) then
		ForceStopTrade(tradeId, "PROCESSING: Something went wrong while checking the trade session")
		return
	end
	if not (trade.senderConfirmed and trade.targetConfirmed) then
		return
	end
	if not CorrectSkinIds(tostring(tradeId)) then
		ForceStopTrade(tradeId, "PROCESSING: Something went wrong while checking skins")
		return
	end
	local PleaseStopTrade
	local function InitializePlayerStats(player)
		local success, err = pcall(function()
			local playerProfile = _L.Saving.GetPlayerData(player)
			if not playerProfile then
				PleaseStopTrade = "No statistics for " .. tostring(player.Name)
				return
			end
			local offerKey = FigureOutOfferString(player)
			if not offerKey and tostring(offerKey) ~= "nil" then
				PleaseStopTrade = "Could not figure out offer string for " .. tostring(player.Name)
				return
			end
			if not (playerProfile.Contracts and playerProfile.Contracts >= trade[offerKey].contracts) then
				PleaseStopTrade = tostring(player.Name) .. " lacks contracts that were previously available"
				return
			end
			if not ((GetCoins(playerProfile)) >= (trade[offerKey].coins or 0)) then
				PleaseStopTrade = tostring(player.Name) .. " lacks cash that were previously available"
				return
			end

			if not PlayerTradeStates[tostring(player.UserId)] then
				PleaseStopTrade = "No player info for one of the two players"
				return
			end
			if not pcall(function()
				PlayerTradeStates[tostring(player.UserId)][2] = false
			end) then
				PleaseStopTrade = "Failed to set player info to false"
				return
			end
		end)
		if not success then
			PleaseStopTrade = "An error occurred during a trade: " .. tostring(err)
			return
		end
	end
	if (not trade.sender) or (not CheckBro(trade.sender)) or (not trade.target) or (not CheckBro(trade.target)) then
		ForceStopTrade(tradeId, "PROCESSING: Something went wrong while checking trading partners")
		return
	end

	InitializePlayerStats(trade.sender)
	if PleaseStopTrade then
		ForceStopTrade(tradeId, "PROCESSING: " .. tostring(PleaseStopTrade))
		return
	end
	InitializePlayerStats(trade.target)
	if PleaseStopTrade then
		ForceStopTrade(tradeId, "PROCESSING: " .. tostring(PleaseStopTrade))
		return
	end

	-- NOW OFFICIALLY PROCESSING
	trade.isProcess = true
	if not (trade.senderConfirmed and trade.targetConfirmed) then
		return
	end

	-- Give contracts
	local TradeContractsBySide = { -1, -1 }
	local function AddToContractsFrame(player, sideIndex)
		local playerProfile = _L.Saving.GetPlayerData(player)
		if not playerProfile then
			PleaseStopTrade = "No statistics for " .. tostring(player.Name)
			return
		end
		local offerKey = FigureOutOfferString(player)
		if not offerKey and tostring(offerKey) ~= "nil" then
			PleaseStopTrade = "Could not figure out offer string for " .. tostring(player.Name)
			return
		end
		if not (playerProfile.Contracts and playerProfile.Contracts >= trade[offerKey].contracts) then
			PleaseStopTrade = tostring(player.Name) .. " lacks contracts that were previously available"
			return
		end
		TradeContractsBySide[sideIndex] = trade[offerKey].contracts
	end

	AddToContractsFrame(trade.sender, 1)
	AddToContractsFrame(trade.target, 2)

	if PleaseStopTrade then
		ForceStopTrade(tradeId, "PROCESSING: " .. tostring(PleaseStopTrade))
		return
	end

	-- Cash transfer
	local TradeCashBySide = { -1, -1 }
	local function AddToCashFrame(player, sideIndex)
		local playerProfile = _L.Saving.GetPlayerData(player)
		if not playerProfile then
			PleaseStopTrade = "No statistics for " .. tostring(player.Name)
			return
		end
		local offerKey = FigureOutOfferString(player)
		if not offerKey and tostring(offerKey) ~= "nil" then
			PleaseStopTrade = "Could not figure out offer string for " .. tostring(player.Name)
			return
		end
		local playerCash = GetCoins(playerProfile)
		local offeredCash = trade[offerKey].coins or 0
		if playerCash < offeredCash then
			PleaseStopTrade = tostring(player.Name) .. " lacks cash that was previously available"
			return
		end
		TradeCashBySide[sideIndex] = offeredCash
	end

	AddToCashFrame(trade.sender, 1)
	AddToCashFrame(trade.target, 2)

	if PleaseStopTrade then
		ForceStopTrade(tradeId, "PROCESSING: " .. tostring(PleaseStopTrade))
		return
	end

	local TradeSkinsBySide = { -1, -1 }
	local NeedSlots = nil
	local function SayNah(customMessage)
		if
			not NotifyPartners(tradeId, (customMessage or "One of the players needs more inventory space. (Or needs at least 1 skin!)"))
		then
			return
		end
		trade.senderConfirmed = false
		trade.targetConfirmed = false
		trade.senderReady = false
		trade.targetReady = false
		trade.confirmStage = false

		trade.processing = false
		trade.isProcess = false
		pcall(function()
			PlayerTradeStates[tostring(trade.sender.UserId)][2] = true
		end)
		pcall(function()
			PlayerTradeStates[tostring(trade.target.UserId)][2] = true
		end)
		if not SafelyUpdate(tradeId) then
			return
		end
		return true
	end

	local function ConvertSkins(player, sideIndex)
		local playerProfile = _L.Saving.GetPlayerData(player)
		if not playerProfile then
			PleaseStopTrade = "No statistics for " .. tostring(player.Name)
			return
		end
		local offerKey = FigureOutOfferString(player)
		if not offerKey and tostring(offerKey) ~= "nil" then
			PleaseStopTrade = "Could not figure out offer string for " .. tostring(player.Name)
			return
		end
		TradeSkinsBySide[sideIndex] = {}
		for _, skinUid in pairs(trade[offerKey].skins) do
			local skin, ownerPlayer = GetSkin(tostring(skinUid))
			local actualUid = skin and (skin.uid or skin.UID)
			if not (skin and ownerPlayer == player and actualUid and tostring(actualUid) == tostring(skinUid)) then
				PleaseStopTrade = "A skin was invalid for " .. tostring(player.Name)
				return
			end
			local skinDataCopy = {}
			for key, val in pairs(skin) do
				skinDataCopy[tostring(key)] = val
			end
			skinDataCopy.uid = tostring(actualUid)
			skinDataCopy.UID = tostring(actualUid)
			table.insert(TradeSkinsBySide[sideIndex], skinDataCopy)
		end
	end

	ConvertSkins(trade.sender, 1)
	ConvertSkins(trade.target, 2)

	local function CheckSlots(player, sideIndex, oppositeSideIndex)
		local playerProfile = _L.Saving.GetPlayerData(player)
		if not playerProfile then
			PleaseStopTrade = "No statistics for " .. tostring(player.Name)
			return
		end
		local offerKey = FigureOutOfferString(player)
		if not offerKey and tostring(offerKey) ~= "nil" then
			PleaseStopTrade = "Could not figure out offer string for " .. tostring(player.Name)
			return
		end
		local incomingSkinCount = #TradeSkinsBySide[sideIndex]
		if incomingSkinCount > 0 then
			if (#playerProfile.Skins + incomingSkinCount) > 999999 then
				NeedSlots = true
			end
		end
	end

	CheckSlots(trade.sender, 2, 1)
	CheckSlots(trade.target, 1, 2)

	if PleaseStopTrade then
		ForceStopTrade(tradeId, "PROCESSING: " .. tostring(PleaseStopTrade))
		return
	end
	if NeedSlots then
		if not SayNah() then
			ForceStopTrade(tradeId, "Something went wrong while fixing trade")
			return
		else
			return
		end
	end

	local needStopContractTrade = false
	local function CheckContracts(player, sideIndex)
		local playerProfile = _L.Saving.GetPlayerData(player)
		if (not playerProfile) or not playerProfile.Contracts then
			PleaseStopTrade = "No statistics for " .. tostring(player.Name)
			return
		end
		local offerKey = FigureOutOfferString(player)
		if not offerKey and tostring(offerKey) ~= "nil" then
			PleaseStopTrade = "Could not figure out offer string for " .. tostring(player.Name)
			return
		end
		if (playerProfile.Contracts + TradeContractsBySide[sideIndex]) > 99999999 then
			needStopContractTrade = true
		end
	end

	CheckContracts(trade.sender, 2)
	CheckContracts(trade.target, 1)

	if PleaseStopTrade then
		ForceStopTrade(tradeId, "PROCESSING: " .. tostring(PleaseStopTrade))
		return
	end
	if needStopContractTrade then
		if not SayNah("One player does not have enough space for more contracts") then
			ForceStopTrade(tradeId, "Something went wrong while fixing CONTRACTS")
			return
		else
			return
		end
	end

	if PleaseStopTrade then
		ForceStopTrade(tradeId, "PROCESSING: " .. tostring(PleaseStopTrade))
		return
	end

	local currentTrade = Get(tradeId)
	if not currentTrade then
		return
	end
	if not CheckTrade(tradeId) then
		ForceStopTrade(tradeId, "PROCESSING: Something went wrong while checking the trade session")
		return
	end

	CheckSlots(trade.sender, 2, 1)
	CheckSlots(trade.target, 1, 2)

	if NeedSlots then
		ForceStopTrade(tradeId, "Need more slots [last check]")
		return
	end

	local function TakeContracts(player, sideIndex)
		local playerProfile = _L.Saving.GetPlayerData(player)
		if not playerProfile then
			PleaseStopTrade = "No save for player during contracts check"
			return
		end
		local offerKey = FigureOutOfferString(player)
		if not (offerKey and trade[offerKey]) then
			PleaseStopTrade = "Invalid offer string during contracts check"
			return
		end
		if GetContracts(playerProfile) < trade[offerKey].contracts then
			PleaseStopTrade = "Lacks contracts"
			return
		end
		SetContracts(player, playerProfile, GetContracts(playerProfile) - math.clamp(trade[offerKey].contracts, 0, 99999999999999999999999999999))
		return true
	end

	local function TakeCash(player, sideIndex)
		local playerProfile = _L.Saving.GetPlayerData(player)
		if not playerProfile then
			PleaseStopTrade = "No save for player during cash check"
			return
		end
		local offerKey = FigureOutOfferString(player)
		if not (offerKey and trade[offerKey]) then
			PleaseStopTrade = "Invalid offer string during cash check"
			return
		end
		local cashAmount = trade[offerKey].coins or 0
		if (GetCoins(playerProfile)) < cashAmount then
			PleaseStopTrade = "Lacks cash"
			return
		end
		AddCoins(playerProfile, -math.clamp(cashAmount, 0, 99999999999999999))
		return true
	end

	local function ValidateSkinsDeletable(player, sideIndex)
		local skinsList = TradeSkinsBySide[sideIndex]
		if type(skinsList) ~= "table" then
			return true
		end
		local profile = _L.Saving.GetPlayerData(player)
		if not profile then
			return false
		end
		for _, skinData in pairs(skinsList) do
			local actualUid = skinData and (skinData.uid or skinData.UID)
			if not actualUid then
				return false
			end
			local skin, owner = GetSkin(actualUid)
			if not skin or owner ~= player then
				return false
			end
		end
		return true
	end

	if not ValidateSkinsDeletable(trade.sender, 1) or not ValidateSkinsDeletable(trade.target, 2) then
		ForceStopTrade(tradeId, "Trade cancelled: one or more offered skins are no longer available. Nothing was removed.")
		return
	end

	do
		local function finalSkinCount(player, giveSideIndex, receiveSideIndex)
			local profile = _L.Saving.GetPlayerData(player)
			local current = (profile and profile.Skins) and #profile.Skins or 0
			return current - #TradeSkinsBySide[giveSideIndex] + #TradeSkinsBySide[receiveSideIndex]
		end
		if finalSkinCount(trade.sender, 1, 2) > MAX_SKINS
			or finalSkinCount(trade.target, 2, 1) > MAX_SKINS then
			ForceStopTrade(tradeId, "Trade cancelled: one of the players would exceed the skin limit (" .. MAX_SKINS .. ").")
			return
		end
	end

	if not TakeContracts(trade.sender, 1) then
		ForceStopTrade(tradeId, tostring(PleaseStopTrade or "Contracts take failure"))
		return
	end
	if not TakeContracts(trade.target, 2) then
		ForceStopTrade(tradeId, tostring(PleaseStopTrade or "Contracts take failure"))
		return
	end
	if not TakeCash(trade.sender, 1) then
		ForceStopTrade(tradeId, tostring(PleaseStopTrade or "Cash take failure"))
		return
	end
	if not TakeCash(trade.target, 2) then
		ForceStopTrade(tradeId, tostring(PleaseStopTrade or "Cash take failure"))
		return
	end
	if PleaseStopTrade then
		ForceStopTrade(tradeId, tostring(PleaseStopTrade))
		return
	end
	if (not trade.sender) or not trade.target then
		return
	end

	local TakeFailure = false
	local function Delete(player, sideIndex)
		if not _L.Saving.GetPlayerData(player) then
			PleaseStopTrade = "No save found during skin deletion"
			return
		end
		for _, skinData in pairs(TradeSkinsBySide[sideIndex]) do
			local actualUid = skinData and (skinData.uid or skinData.UID)
			if not actualUid then
				warn("NO UID")
				TakeFailure = true
				break
			end
			if not DeleteSkin(actualUid) then
				TakeFailure = true
				break
			end
		end
	end
	Delete(trade.sender, 1)
	if PleaseStopTrade then
		ForceStopTrade(tradeId, tostring(PleaseStopTrade))
		return
	end
	Delete(trade.target, 2)
	if PleaseStopTrade then
		ForceStopTrade(tradeId, tostring(PleaseStopTrade))
		return
	end

	if TakeFailure then
		local function Rollback(playerToRefund, sideIndex)
			local playerSave = _L.Saving.GetPlayerData(playerToRefund)
			if playerSave then
				local contractsAmt = TradeContractsBySide[sideIndex]
				local cashAmt = TradeCashBySide[sideIndex]
				if contractsAmt and contractsAmt > 0 then
					SetContracts(playerToRefund, playerSave, GetContracts(playerSave) + contractsAmt)
				end
				if cashAmt and cashAmt > 0 then
					AddCoins(playerSave, cashAmt)
				end
				-- Restore deleted skins back into inventory if they were deleted
				if TradeSkinsBySide[sideIndex] and type(TradeSkinsBySide[sideIndex]) == "table" then
					playerSave.Skins = playerSave.Skins or {}
					for _, skinData in pairs(TradeSkinsBySide[sideIndex]) do
						local actualUid = skinData.uid or skinData.UID
						local alreadyIn = false
						for _, s in ipairs(playerSave.Skins) do
							if (s.uid or s.UID) == actualUid then
								alreadyIn = true
								break
							end
						end
						if not alreadyIn then
							table.insert(playerSave.Skins, skinData)
						end
					end
				end
			end
		end
		Rollback(trade.sender, 1)
		Rollback(trade.target, 2)

		ForceStopTrade(tradeId, "Unfortunately, a skin failed to delete. Items and currencies have been refunded.")
		return
	end

	local contractsTransferred = 0
	if
		TradeContractsBySide[1] ~= -1
		and TradeContractsBySide[2] ~= -1
		and PleaseStopTrade == nil
		and TradeSkinsBySide[1] ~= -1
		and TradeSkinsBySide[2] ~= -1
	then
		-- Synchronous contracts grant
		local function GiveContractsToPlayer(player, sideIndex)
			local playerProfile = _L.Saving.GetPlayerData(player)
			if playerProfile then
				local amount = math.clamp(TradeContractsBySide[sideIndex] or 0, 0, 99999999)
				SetContracts(player, playerProfile, GetContracts(playerProfile) + amount)
				contractsTransferred = amount
			end
		end
		GiveContractsToPlayer(trade.sender, 2)
		GiveContractsToPlayer(trade.target, 1)

		-- Synchronous cash grant
		local function GiveCashToPlayer(player, sideIndex)
			local playerProfile = _L.Saving.GetPlayerData(player)
			if playerProfile then
				local cashToGive = TradeCashBySide[sideIndex] or 0
				if cashToGive > 0 then
					AddCoins(playerProfile, math.clamp(cashToGive, 0, 999999999999))
				end
			end
		end
		GiveCashToPlayer(trade.sender, 2)
		GiveCashToPlayer(trade.target, 1)

		local function RecordTradeHistory(player, isSender)
			local save = _L.Saving.GetPlayerData(player)
			if not save then
				ForceStopTrade(tradeId, "Failed to get player save")
				return
			end
			local tradeHistory = EnsureTradeHistory(save)

			local partnerPlayer = isSender == true and trade.target or trade.sender
			if not partnerPlayer then
				ForceStopTrade(tradeId, "Failed to get player data")
				return
			end

			local playerSide = isSender and 1 or 2
			local partnerSide = isSender and 2 or 1
			local yourSkins = TradeSkinsBySide[playerSide]
			local otherSkins = TradeSkinsBySide[partnerSide]
			local yourContracts = TradeContractsBySide[playerSide]
			local otherContracts = TradeContractsBySide[partnerSide]
			if not yourSkins or not otherSkins or not yourContracts or not otherContracts then
				ForceStopTrade(tradeId, "Something went wrong recording history")
				return
			end

			local yourCash = TradeCashBySide[playerSide]
			local otherCash = TradeCashBySide[partnerSide]

			table.insert(tradeHistory, {
				u = partnerPlayer.UserId,
				ts = os.time(),
				p = CopyTradeItems(yourSkins),
				pn = #yourSkins,
				op = CopyTradeItems(otherSkins),
				opn = #otherSkins,
				d = yourContracts,
				od = otherContracts,
				tk = yourCash or 0,
				otk = otherCash or 0,
				t = 0,
			})
			while #tradeHistory > MAX_TRADE_HISTORY do
				table.remove(tradeHistory, 1)
			end
			FireTradeHistoryChanged(player)
		end

		RecordTradeHistory(trade.sender, true)
		RecordTradeHistory(trade.target, false)

		local RegisteredIds = {}
		local FoundDuplicate = false

		local function CheckForDupes(sideIndex)
			for _, skinData in pairs(TradeSkinsBySide[sideIndex]) do
				if not (skinData.uid or skinData.UID) then
					warn("NO UID")
					PleaseStopTrade = "NO UID"
					break
				end
				local uidStr = tostring(skinData.uid or skinData.UID)
				if RegisteredIds[uidStr] then
					FoundDuplicate = true
					break
				end
				RegisteredIds[uidStr] = true
			end
		end
		CheckForDupes(1)
		CheckForDupes(2)
		if FoundDuplicate then
			ForceStopTrade(tradeId, "Unfortunately, a skin duplicated. No skins will be refunded (to prevent duping) 😢")
			return
		end
		if PleaseStopTrade then
			ForceStopTrade(tradeId, PleaseStopTrade)
			return
		end

		if (not trade.sender) or not trade.target then
			return
		end

		-- Synchronous skins grant
		local function GiveSkinsToPlayer(player, oppositeSideIndex)
			for _, skinData in pairs(TradeSkinsBySide[oppositeSideIndex]) do
				if skinData and type(skinData) == "table" and (skinData.id or skinData.ID) and (skinData.uid or skinData.UID) then
					GiveSkin(player, skinData)
				end
			end
		end
		GiveSkinsToPlayer(trade.sender, 2)
		GiveSkinsToPlayer(trade.target, 1)

		-- Asynchronous background Save
		task.spawn(function()
			if trade.sender and trade.sender.Parent then
				_L.Saving.SaveData(trade.sender, false)
			end
			if trade.target and trade.target.Parent then
				_L.Saving.SaveData(trade.target, false)
			end
		end)

		local function NotifyEquipChange(player, oppositeSideIndex)
			coroutine.wrap(function()
				for _, skinData in pairs(TradeSkinsBySide[oppositeSideIndex]) do
					if skinData.uid then
						_L.Signal.Fire("Force Change Target", skinData.uid)
					end
				end
			end)()
		end
		NotifyEquipChange(trade.sender, 2)
		NotifyEquipChange(trade.target, 1)

		SendPartners(tradeId, "Trade Processed", function()
			trades[tostring(tradeId)] = nil
		end, true)
		trades[tostring(tradeId)] = nil

		return true
	else
		ForceStopTrade(tradeId, "Something went wrong while giving currencies to players")
		return
	end
end

local function CheckProcessingState(tradeId)
	local trade = Get(tradeId)
	if not trade then
		return
	end

	if trade.senderReady and trade.targetReady then
		if not trade.confirmStage then
			trade.confirmStage = true
		end
	else
		trade.confirmStage = false
	end

	if trade.senderConfirmed and trade.targetConfirmed then
		trade.confirmTick = workspace:GetServerTimeNow()
		SafelyUpdate(tradeId)
		coroutine.wrap(function()
			local startTime = os.clock()
			local timeExpired = false
			while true do
				if not Get(tradeId) then
					break
				end
				if not (trade.senderConfirmed and trade.targetConfirmed) then
					break
				end
				if not CheckTrade(tradeId) then
					break
				end
				if os.clock() - startTime >= 4 then
					timeExpired = true
					break
				end
				_L.Heartbeat(3)
			end
			if timeExpired then
				local currentTrade = Get(tradeId)
				if not currentTrade then
					return
				end
				if not (trade.senderConfirmed and trade.targetConfirmed) then
					return
				end
				if not CheckTrade(tradeId) then
					return
				end
				trade.processing = true
				SafelyUpdate(tradeId)
				ProcessTrade(tostring(tradeId))
			end
		end)()
	else
		trade.confirmTick = nil
	end
end

_L.Network.Invoked("Ready Trade").OnInvoke = function(player, tradeId, counter)
	if not ValidateAction(player, "ReadyTrade", 0.1) then
		return false
	end
	local playerProfile = _L.Saving.GetPlayerData(player)
	if not playerProfile then
		return false, "Could not find save for player. This is crucial"
	end
	if not (PlayerTradeStates[tostring(player.UserId)] and PlayerTradeStates[tostring(player.UserId)][2]) then
		return false, "You cant ready up!"
	end
	local trade, id = GetByPlyr(player)
	if tostring(id) ~= tradeId then
		return false, "IDs were not the same"
	end
	if not trade or not id then
		return false, "Could not identify trade"
	end

	local senderKey = FigureOutSenderData(player)
	if not senderKey then
		return false, "Sender data was not valid"
	end
	local readyKey = senderKey .. "Ready"
	if trade[readyKey] then
		return false, "You are already readied!"
	end
	trade[readyKey] = true
	print(string.format("[Trade Server] %s set READY on Trade %s (senderReady=%s, targetReady=%s)", player.Name, tostring(id), tostring(trade.senderReady), tostring(trade.targetReady)))
	if not SafelyUpdate(id) then
		return false, "Could not safely update"
	end
	CheckProcessingState(id)
	return true
end

_L.Network.Invoked("Confirm Trade").OnInvoke = function(player, tradeId, counter)
	if not ValidateAction(player, "ConfirmTrade", 0.1) then
		return false
	end
	local playerProfile = _L.Saving.GetPlayerData(player)
	if not playerProfile then
		return false, "Could not find save for player. This is crucial"
	end
	if not (PlayerTradeStates[tostring(player.UserId)] and PlayerTradeStates[tostring(player.UserId)][2]) then
		return false, "You cant confirm!"
	end
	local trade, id = GetByPlyr(player)
	if tostring(id) ~= tradeId then
		return false, "IDs were not the same"
	end
	if not trade or not id then
		return false, "Could not identify trade"
	end

	local senderKey = FigureOutSenderData(player)
	if not senderKey then
		return false, "Sender data was not valid"
	end
	local confirmedKey = senderKey .. "Confirmed"
	if trade[confirmedKey] then
		return false, "You are already confirmed!"
	end
	trade[confirmedKey] = true
	print(string.format("[Trade Server] %s set CONFIRMED on Trade %s (senderConfirmed=%s, targetConfirmed=%s)", player.Name, tostring(id), tostring(trade.senderConfirmed), tostring(trade.targetConfirmed)))
	if not SafelyUpdate(id) then
		return false, "Could not safely update"
	end
	CheckProcessingState(id)
	return true
end

_L.Network.Invoked("Unconfirm Trade").OnInvoke = function(player, tradeId, counter)
	local playerProfile = _L.Saving.GetPlayerData(player)
	if not playerProfile then
		return false, "Could not find save for player. This is crucial"
	end
	if not (PlayerTradeStates[tostring(player.UserId)] and PlayerTradeStates[tostring(player.UserId)][2]) then
		return false, "You cant unconfirm!"
	end
	local trade, id = GetByPlyr(player)
	if tostring(id) ~= tradeId then
		return false, "IDs were not the same"
	end
	if not trade or not id then
		return false, "Could not identify trade"
	end
	local senderKey = FigureOutSenderData(player)
	if not senderKey then
		return false, "Sender data was not valid"
	end
	local confirmedKey = senderKey .. "Confirmed"
	if not trade[confirmedKey] then
		return false, "You are already unconfirmed!"
	end
	trade[confirmedKey] = false
	print(string.format("[Trade Server] %s set UNCONFIRMED on Trade %s", player.Name, tostring(id)))
	if not SafelyUpdate(id) then
		return false, "Could not safely update"
	end
	return true
end

_L.Network.Invoked("Unready Trade").OnInvoke = function(player, tradeId, counter)
	local playerProfile = _L.Saving.GetPlayerData(player)
	if not playerProfile then
		return false, "Could not find save for player. This is crucial"
	end
	if not (PlayerTradeStates[tostring(player.UserId)] and PlayerTradeStates[tostring(player.UserId)][2]) then
		return false, "You cant unready!"
	end
	local trade, id = GetByPlyr(player)
	if tostring(id) ~= tradeId then
		return false, "IDs were not the same"
	end
	if not trade or not id then
		return false, "Could not identify trade"
	end
	local senderKey = FigureOutSenderData(player)
	if not senderKey then
		return false, "Sender data was not valid"
	end
	local readyKey = senderKey .. "Ready"
	if not trade[readyKey] then
		return false, "You are already unreadied!"
	end
	trade[readyKey] = false
	print(string.format("[Trade Server] %s set UNREADIED on Trade %s", player.Name, tostring(id)))
	if not SafelyUpdate(id) then
		return false, "Could not safely update"
	end
	return true
end

_L.Signal.Fired("Skin Deleted"):connect(function(skinId, player)
	local trade, id = GetByPlyr(player)
	if trade and not trade.isProcess then
		local offerKey = FigureOutOfferString(player)
		if not (offerKey and trade[offerKey]) then
			ForceStopTrade(id, "Could not figure out trading")
			return
		end
		local playerName = tostring(player and player.Name or "Player")
		ForceStopTrade(id, "Forcibly stopped trade because " .. playerName .. " had a skin removed")
	end
end)

_L.Signal.Fired("Stat Changed"):connect(function(player, stat)
	if stat == "Contracts" or stat == "RobuxSpent" or stat == "OwnsTradingPlaza" then
		local trade, id = GetByPlyr(player)
		if trade then
			local playerProfile = _L.Saving.GetPlayerData(player)
			if not (playerProfile and playerProfile.Contracts) then
				ForceStopTrade(tostring(id), "No save for one player")
				return
			end
			local offerKey = FigureOutOfferString(player)
			if not (offerKey and trade[offerKey]) then
				ForceStopTrade(id, "Could not figure out trading")
				return
			end
			if trade[offerKey].contracts > playerProfile.Contracts then
				trade[offerKey].contracts = playerProfile.Contracts
				trade.senderReady = false
				trade.targetReady = false
				trade.senderConfirmed = false
				trade.targetConfirmed = false
				trade.confirmStage = false
				if not SafelyUpdate(id) then
					ForceStopTrade(id, "Could not safely update contracts")
					return
				end
			end
		end
	end
end)

local Invites = {}
local InviteCooldowns = {}

local function onPlayerAddedInvites(player)
	Invites[tostring(player.UserId)] = {}
	InviteCooldowns[tostring(player.UserId)] = {}
end

_L.Signal.Fired("Player Added"):connect(onPlayerAddedInvites)
for _, p in ipairs(game.Players:GetPlayers()) do
	onPlayerAddedInvites(p)
end

game.Players.PlayerRemoving:Connect(function(player)
	Invites[tostring(player.UserId)] = nil
	InviteCooldowns[tostring(player.UserId)] = nil
end)

_L.Network.Invoked("Get Invites Open").OnInvoke = function(player)
	return Invites[tostring(player.UserId)]
end

_L.Network.Invoked("Send Trade Invite").OnInvoke = function(player, targetPlayer)
	if not ValidateAction(player, "SendTradeInvite", 2.0) then
		return false
	end
	local playerProfile = _L.Saving.GetPlayerData(player)
	if not playerProfile then
		return false, "No file"
	end

	if not PlayerTradeStates[tostring(player.UserId)] then
		PlayerTradeStates[tostring(player.UserId)] = { os.clock(), false }
	end
	local elapsedSender = os.clock() - PlayerTradeStates[tostring(player.UserId)][1]

	if not GetTradingTimer(player) then
		return false,
			tostring(player.Name)
				.. " needs to wait "
				.. tostring(math.clamp(math.round(60 - elapsedSender), 0, 60))
				.. " seconds before trading."
	end

	local targetProfile = _L.Saving.GetPlayerData(targetPlayer)
	if not targetProfile then
		return false, "No file for other player"
	end

	if not PlayerTradeStates[tostring(targetPlayer.UserId)] then
		PlayerTradeStates[tostring(targetPlayer.UserId)] = { os.clock(), false }
	end
	local elapsedTarget = os.clock() - PlayerTradeStates[tostring(targetPlayer.UserId)][1]
	if not GetTradingTimer(targetPlayer) then
		return false,
			tostring(targetPlayer.Name)
				.. " needs to wait "
				.. tostring(math.clamp(math.round(60 - elapsedTarget), 0, 60))
				.. " seconds before trading."
	end

	if not (targetProfile.Settings and targetProfile.Settings.Trading) then
		return false, "Trading disabled by player"
	end
	if Get(targetPlayer) then
		return false, "This player is currently in a trade"
	end
	if not InviteCooldowns[tostring(player.UserId)] then
		InviteCooldowns[tostring(player.UserId)] = {}
	end
	if
		InviteCooldowns[tostring(player.UserId)][tostring(targetPlayer.UserId)]
		and os.clock() - InviteCooldowns[tostring(player.UserId)][tostring(targetPlayer.UserId)] < 15
	then
		return false, "Please do not send too many requests to this player."
	end

	InviteCooldowns[tostring(player.UserId)][tostring(targetPlayer.UserId)] = os.clock()

	if
		(targetProfile.Settings.Trading == 1)
		or not _G.Friends[tostring(targetPlayer.UserId)]
		or (
			targetProfile.Settings.Trading == 2
			and _G.Friends[tostring(targetPlayer.UserId)]
			and _L.Functions.SearchArray(_G.Friends[tostring(targetPlayer.UserId)], player.UserId)
		)
	then
		if not Invites[tostring(player.UserId)] then
			Invites[tostring(player.UserId)] = {}
		end
		Invites[tostring(player.UserId)][tostring(targetPlayer.UserId)] = true

		_L.Network.Fire("Update Trade Invites Open", player, Invites[tostring(player.UserId)])

		task.spawn(function()
			local inviteSentTime = os.clock()
			_L.Network.Fire("Trade Recieved", targetPlayer, player, { sender = player })

			local connection
			connection = _L.Network.Fired("Accept Trade Invite"):Connect(function(clientWhoFired, senderWhoInvited)
				if clientWhoFired == targetPlayer and senderWhoInvited == player then
					connection:Disconnect()
					task.spawn(function()
						if player and player.Parent and targetPlayer and targetPlayer.Parent then
							if os.clock() - inviteSentTime > 20 then
								return
							end

							if not CheckBro(player) then
								return
							end

							if not CheckBro(targetPlayer) then
								return
							end

							if Get(targetPlayer) then
								return
							end

							if GetTradingTimer(targetPlayer) ~= true or GetTradingTimer(player) ~= true then
								return
							end

							local senderSave = _L.Saving.GetPlayerData(player)
							if not (senderSave and senderSave.Settings and senderSave.Settings.Trading) then
								return
							end
							if Get(player) then
								return
							end
							if
								(senderSave.Settings.Trading ~= 2)
								or (
									senderSave.Settings.Trading == 2
									and _G.Friends
									and _G.Friends[tostring(targetPlayer.UserId)]
									and _L.Functions.SearchArray(_G.Friends[tostring(targetPlayer.UserId)], player.UserId)
								)
							then
								Initialize(player, targetPlayer)
							end
						end
					end)
				end
			end)

			task.delay(20, function()
				if connection then
					connection:Disconnect()
				end
				if player and player.Parent and Invites[tostring(player.UserId)] then
					Invites[tostring(player.UserId)][tostring(targetPlayer.UserId)] = nil
					_L.Network.Fire("Update Trade Invites Open", player, Invites[tostring(player.UserId)])
				end
			end)
		end)
		return true
	else
		return false, "You can't trade this player."
	end
end

_L.Network.Fired("Ignore Trade"):Connect(function(respondingPlayer, invitingPlayer)
	_L.Network.Fire("Trade Ignored", invitingPlayer, respondingPlayer)
end)

_L.Network.Invoked("Cancel Trade").OnInvoke = function(player, data)
	local trade, id = GetByPlyr(player)
	if not trade or not id then
		return false, "error"
	end

	if trade.processing == true or trade.isProcess == true then
		return false, "already processing"
	end

	if not (PlayerTradeStates[tostring(player.UserId)] and PlayerTradeStates[tostring(player.UserId)][2]) then
		return false, "You cant do actions"
	end

	local _, otherPlayer = FigureOutDetails(player, id)
	SendPartners(id, "Trade Cancelled", function()
		if not (PlayerTradeStates[tostring(player.UserId)] and PlayerTradeStates[tostring(player.UserId)][2]) then
			return
		end
		ForceStopTrade(id, false)
	end, id, otherPlayer or { DisplayName = "???" })
	return true
end

_L.Signal.Fired("Server Closing"):connect(function()
	for tradeId, tradeData in pairs(trades) do
		if not tradeData.processing then
			ForceStopTrade(tostring(tradeId), "Server closing")
		end
	end
end)

_L.Signal.Fired("Save Fail"):connect(function(player)
	local trade, id = GetByPlyr(player)
	if trade and id then
		ForceStopTrade(tostring(id), "One player failed to save")
	end
end)

while true do
	for tradeId, _ in pairs(trades) do
		if not CheckTrade(tradeId) then
			ForceStopTrade(tradeId, "A player that was in the trade is now unavailable")
		end
	end
	_L.Heartbeat(2)
end
