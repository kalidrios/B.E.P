--[[
	Trading.local.luau — Client-side Trading Controller for Destruction Simulator
	Handles trade request list, trade window state, skins/weapons/bombs offering, currency, and confirmation.
]]--

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Library = ReplicatedStorage:WaitForChild("Library")
local Client = Library:WaitForChild("Client")
local LocalPlayer = Players.LocalPlayer

local PlayerGui = LocalPlayer:WaitForChild("PlayerGui", 30)
if not PlayerGui then
	warn("PlayerGui not found after 30 seconds. Trading script will not run.")
	return
end

-- Wait indefinitely: the Trade GUI is replicated via StarterGui/__GUI and
-- may arrive late on slow joins. A bounded wait + return would kill every
-- trade listener on this client (no accept prompt ever shows) instead of
-- just starting late.
local TradeScreenGui = PlayerGui:WaitForChild("Trade", 15) or PlayerGui:WaitForChild("Trading", 15) or PlayerGui:WaitForChild("Trade")
local MainFrame = TradeScreenGui:WaitForChild("Frame")
local oldUiScale = MainFrame:FindFirstChildOfClass("UIScale")
if oldUiScale then
	oldUiScale:Destroy()
end
local TradeFrame = MainFrame:WaitForChild("Trade")
local TradeBottomFrame = TradeFrame:FindFirstChild("TradeBottom")
if not TradeBottomFrame then
	warn("TradeBottom not found inside Trade frame. Trade search/grid features will be disabled.")
end



-- Core Library modules
local SaveModule = require(Client.Save)
local SharedModule = require(Library.Shared)
local FunctionsModule = require(Library.Functions)
local SignalModule = require(Library.Signal)
local GUIFXModule = require(Client.GUIFX)
local NetworkModule = require(Client.Network)
local MessageModule = require(Client.Message)
local DirectoryModule = require(Library.Directory)
local SkinCmdsModule = require(Client.SkinCmds)
local SkinUIModule = require(Client.SkinUI)
local VariablesModule = require(Library.Variables)
local GIFModule = require(Client.GIF)
local WorldCmdsModule = require(Client.WorldCmds)

-- O(1) skin config lookup backed by the in-memory Directory module.
-- The old code ran require(Directory:Skins:WaitForChild(cat):WaitForChild(item)
-- :WaitForChild(id)) once per inventory item, once per FRAME (UpdateSkins runs
-- on Heartbeat). A single missing child blocked the whole render loop for ~5s
-- (WaitForChild default timeout) — that was the heavy click lag vs IBS, which
-- indexes Directory.Pets directly. Index is built lazily once, keys lowercased
-- to mirror SkinUI's case-insensitive matching.
local skinConfigIndex = nil
local function buildSkinConfigIndex()
	local index = {}
	local skins = DirectoryModule and DirectoryModule.Skins
	if skins then
		for catName, catTable in pairs(skins) do
			if type(catTable) == "table" then
				for modName, modTable in pairs(catTable) do
					if type(modTable) == "table" then
						for skinName, skinConfig in pairs(modTable) do
							if type(skinConfig) == "table" then
								index[string.lower(catName) .. "_" .. string.lower(modName) .. "_" .. string.lower(skinName)] = skinConfig
							end
						end
					end
				end
			end
		end
	end
	return index
end

local resolvedSkinInfo = {}
local function resolveSkinInfo(skinEntry)
	local uid = skinEntry.uid or skinEntry.UID
	if uid and resolvedSkinInfo[uid] ~= nil then
		return resolvedSkinInfo[uid]
	end
	if not skinConfigIndex then
		skinConfigIndex = buildSkinConfigIndex()
	end
	local category = skinEntry.Category or skinEntry.category or "Launcher"
	local itemName = skinEntry.ItemName or skinEntry.itemName or "Rocket"
	local skinId = skinEntry.ID or skinEntry.id or "Default"
	local cfg = skinConfigIndex[string.lower(category) .. "_" .. string.lower(itemName) .. "_" .. string.lower(skinId)]
	local isTradeable = true
	if cfg then
		if cfg.tradeble == false or cfg.tradable == false or cfg.tradeable == false or cfg.Tradeable == false or cfg.Tradeble == false then
			isTradeable = false
		end
	end
	local info = {
		name = skinId,
		rarity = (cfg and cfg.rarity) or "Basic",
		tradeable = isTradeable,
	}
	if uid then
		resolvedSkinInfo[uid] = info
	end
	return info
end

-- UI Panels
local PlayerListFrame = MainFrame:WaitForChild("PlayerList")
local TradingHistoryPanel = MainFrame:FindFirstChild("TradingHistory")
local TradeViewPanel = MainFrame:FindFirstChild("TradeView")

local Assets = ReplicatedStorage:WaitForChild("Assets")
local AssetsUI = Assets and Assets:FindFirstChild("UI")
local ReplicatedTradeFolder = AssetsUI and (AssetsUI:FindFirstChild("Trade") or AssetsUI:FindFirstChild("Trading"))

-- Templates
local PlayerTemplate = (ReplicatedTradeFolder and ReplicatedTradeFolder:FindFirstChild("Player"))
	or PlayerListFrame.Players:FindFirstChild("Player")
local EmptyServerTemplate = (ReplicatedTradeFolder and ReplicatedTradeFolder:FindFirstChild("EmptyServer"))
	or PlayerListFrame.Players:FindFirstChild("EmptyServer")

if PlayerTemplate then
	PlayerTemplate.Visible = false
end
if EmptyServerTemplate then
	EmptyServerTemplate.Visible = false
end

PlayerListFrame.Visible = true
TradeFrame.Visible = false
TradeScreenGui.Enabled = false
if TradingHistoryPanel then
	TradingHistoryPanel.Visible = false
end
if TradeViewPanel then
	TradeViewPanel.Visible = false
end

-- State variables
local activeOpenInvites = {}
local isActionDebounce = false
local isFilterFriendsOnly = false
local isTradeActive = false
local activeTradeData = nil
local activeTradeId = nil
local isGridView = false
local currentRandom = Random.new()



local lastClientContracts = nil
local lastPlayerContracts = nil
local lastClientCoins = nil
local lastPlayerCoins = nil
local confirmCountdownStartTick = nil
local activeGifCleanup = nil
local hasWarnedFairTrade = false
local cachedPartnerUserId = nil
local cachedPartnerThumb = nil
local chatPartnerThumbCache = nil

-- Wraps every remote call made inside debounced paths. If InvokeServer throws
-- (server handler errored, network hiccup), the raw throw would unwind past
-- the `isActionDebounce = false` reset and freeze the window permanently.
local function safeInvoke(remoteName, ...)
	local callOk, result1, result2 = pcall(NetworkModule.Invoke, remoteName, ...)
	if not callOk then
		return false, "Network error, please try again."
	end
	return result1, result2
end

local xboxSubtractActive = false
local xboxAddActive = false
local xboxHoldTimer = 0

-- Trade UI search query input
local TradeSearchQueryInput = nil
local function getTradeSearchInput()
	if TradeSearchQueryInput and TradeSearchQueryInput.Parent then
		return TradeSearchQueryInput
	end
	local bottom = TradeBottomFrame or TradeFrame:FindFirstChild("TradeBottom") or TradeFrame:FindFirstChild("Bottom") or MainFrame:FindFirstChild("TradeBottom")
	if bottom then
		local tradeSearch = bottom:FindFirstChild("TradeSearch") or bottom:FindFirstChild("Search")
		if tradeSearch then
			TradeSearchQueryInput = tradeSearch:FindFirstChild("TradeQuery") or tradeSearch:FindFirstChild("Query") or tradeSearch:FindFirstChildWhichIsA("TextBox")
		end
	end
	return TradeSearchQueryInput
end
getTradeSearchInput()

-- Default filter label is "All"
local showToggleLabel = PlayerListFrame.Bottom.Show:FindFirstChild("TextLabel")
if showToggleLabel then
	showToggleLabel.Text = "All"
end

-- Helper: Calculates player's trade reputation rating
function GetTradeRating(targetPlayer)
	local playerSave = SaveModule.Get(targetPlayer)
	if not playerSave then
		return -1, "(Unrated)"
	end
	assert(playerSave)
	local positiveRatings = 0
	local negativeRatings = 0
	if playerSave.TradeHistory2 then
		local evaluatedUsers = {}
		for index = #playerSave.TradeHistory2, 1, -1 do
			local historyEntry = playerSave.TradeHistory2[index]
			if historyEntry.or_ ~= nil and not evaluatedUsers[historyEntry.u] then
				evaluatedUsers[historyEntry.u] = true
				if historyEntry.or_ then
					positiveRatings = positiveRatings + 1
				else
					negativeRatings = negativeRatings + 1
				end
			end
		end
	end
	if positiveRatings + negativeRatings < SharedModule.TradeRatingRequirement then
		return 0, "(Unrated)"
	end
	local calculatedRating = math.round(positiveRatings * 9 / (positiveRatings + negativeRatings) * 10) / 10 + 1
	return calculatedRating, "(" .. string.format("%0.1f", calculatedRating) .. " Rating)"
end

-- Renders the active list of players eligible for trading requests
function RenderPlayerList()
	local emptyPlaceholder = nil
	local filterQuery = FunctionsModule.RegexEscape(string.lower(tostring(PlayerListFrame.Bottom.Search.Query.Text)))
	local isFilterQueryActive = (filterQuery ~= nil and filterQuery ~= "")

	for _, player in ipairs(Players:GetPlayers()) do
		local playerSave = SaveModule.Get(player, true)
		if playerSave and player ~= LocalPlayer then
			local playerSettings = playerSave.Settings or {}
			local isTradingAllowed = (playerSettings.Trading ~= 3)
			local isInvitePending = FunctionsModule.SearchArray(activeOpenInvites, player)
			local playerRow = PlayerListFrame.Players:FindFirstChild(player.Name)

			if not playerRow then
				local playerName = player.Name
				local playerDisplayName = player.DisplayName
				if not PlayerTemplate then
					warn("Player template not found in PlayerList.Players")
					return
				end

				playerRow = PlayerTemplate:Clone()
				if playerRow:FindFirstChild("Username") then
					playerRow.Username.Text = "@" .. playerName
				end
				if playerRow:FindFirstChild("DisplayName") then
					playerRow.DisplayName.Text = playerDisplayName
				end
				local ratingScore, ratingText = GetTradeRating(player)
				if playerRow:FindFirstChild("Rating") then
					playerRow.Rating.Text = ratingText
				end

				task.spawn(function()
					local tradeSuffix = SignalModule.Invoke("Get Trade Suffix", player)
					if tradeSuffix and playerRow:FindFirstChild("DisplayName") then
						playerRow.DisplayName.Text = playerDisplayName .. tradeSuffix
					end
				end)

				playerRow.Name = playerName
				playerRow.Parent = PlayerListFrame.Players
				GUIFXModule.ButtonFX(playerRow)

				local clickTarget = playerRow
				if not playerRow:IsA("GuiButton") then
					clickTarget = playerRow:FindFirstChildOfClass("TextButton")
						or playerRow:FindFirstChildOfClass("ImageButton")
					if not clickTarget then
						clickTarget = Instance.new("TextButton")
						clickTarget.Name = "ClickOverlay"
						clickTarget.BackgroundTransparency = 1
						clickTarget.Text = ""
						clickTarget.Size = UDim2.new(1, 0, 1, 0)
						clickTarget.Parent = playerRow
					end
				end

				clickTarget.Activated:Connect(function()
					if not isActionDebounce then
						isActionDebounce = true
						local tradingAllowed = (playerSettings.Trading ~= 3)
						local invitePending = FunctionsModule.SearchArray(activeOpenInvites, player)
						if tradingAllowed and not invitePending then
							local ok, successResult, failReason = pcall(NetworkModule.Invoke, "Send Trade Invite", player)
							if not ok then
								warn("[Trade] Send Trade Invite error:", successResult)
								MessageModule.New("Failed to send trade request (server error)")
							elseif successResult then
								MessageModule.New("\240\159\147\169 Trade request sent!")
							else
								MessageModule.New(failReason or "Failed to send trade request (unknown)")
							end
						end
						isActionDebounce = false
					end
				end)

				task.spawn(function()
					local thumb = Players:GetUserThumbnailAsync(
						player.UserId,
						Enum.ThumbnailType.HeadShot,
						Enum.ThumbnailSize.Size180x180
					)
					if thumb then
						local avatarIcon = playerRow:FindFirstChild("Player")
						if avatarIcon and (avatarIcon:IsA("ImageLabel") or avatarIcon:IsA("ImageButton")) then
							avatarIcon.Image = thumb
						end
					end
				end)
			end

			local noticeLabel = playerRow:FindFirstChild("Notice")
			local iconElement = playerRow:FindFirstChild("Icon")
			local isNoticeVisible = (not isTradingAllowed) or (isInvitePending == true)
			if noticeLabel then
				noticeLabel.Visible = isNoticeVisible
				if not isTradingAllowed then
					noticeLabel.Text = "(Disabled)"
				elseif isInvitePending then
					noticeLabel.Text = "(Pending)"
				end
			end
			if iconElement then
				iconElement.Visible = not isNoticeVisible
			end

			if isFilterQueryActive then
				local matchesName = string.find(string.lower(player.Name), filterQuery) ~= nil
					or string.find(string.lower(player.DisplayName), filterQuery) ~= nil
				playerRow.Visible = matchesName
			else
				playerRow.Visible = true
			end

			if isFilterFriendsOnly then
				if not LocalPlayer:IsFriendsWith(player.UserId) then
					playerRow.Visible = false
				end
			end

			playerRow.LayoutOrder = isTradingAllowed and FunctionsModule.StringByte(player.Name) or 999999999
		end
	end

	emptyPlaceholder = PlayerListFrame.Players:FindFirstChild("__EMPTY")
	if #Players:GetPlayers() <= 1 then
		if not emptyPlaceholder and EmptyServerTemplate then
			local emptyClone = EmptyServerTemplate:Clone()
			emptyClone.Name = "__EMPTY"
			emptyClone.Visible = true
			emptyClone.Parent = PlayerListFrame.Players
			PlayerListFrame.Players.CanvasSize = UDim2.new(0, 0, 0, 0)
		end
	elseif emptyPlaceholder then
		emptyPlaceholder:Destroy()
	end

	for _, child in ipairs(PlayerListFrame.Players:GetChildren()) do
		if child:IsA("ImageButton") or child:IsA("Frame") then
			if
				child.Name ~= "Player"
				and child.Name ~= "player"
				and child.Name ~= "EmptyServer"
				and child.Name ~= "emptyServer"
				and child.Name ~= "__EMPTY"
			then
				if not Players:FindFirstChild(child.Name) then
					child:Destroy()
				end
			end
		end
	end
	ListScrolling()
end

local lastRenderWarnAt = 0
local rawRenderPlayerList = RenderPlayerList
function RenderPlayerList()
	local ok, err = pcall(rawRenderPlayerList)
	if not ok and os.clock() - lastRenderWarnAt > 5 then
		lastRenderWarnAt = os.clock()
		warn("[Trade] RenderPlayerList error:", err)
	end
end

function ListScrolling()
	local layout = PlayerListFrame.Players:FindFirstChildOfClass("UIListLayout")
	local padding = PlayerListFrame.Players:FindFirstChildOfClass("UIPadding")
	if layout then
		layout:ApplyLayout()
		PlayerListFrame.Players.CanvasSize = UDim2.new(
			0,
			0,
			0,
			layout.AbsoluteContentSize.Y + (padding and (padding.PaddingTop.Offset + padding.PaddingBottom.Offset) or 0)
		)
	end
end

-- Updates client and partner skin offer grids in trade window
function UpdateSkins()
	if not isTradeActive or not activeTradeData then
		return
	end

	local localPlayerSave = SaveModule.Get()
	if not localPlayerSave then
		return
	end
	assert(localPlayerSave)
	assert(activeTradeData)

	local clientOfferData, partnerOfferData, clientPlayer, partnerPlayer, isSender = FigureOutTrade()
	local bothReady = activeTradeData.targetReady and activeTradeData.senderReady

	-- Clean up partner offer cards that were removed
	for _, child in ipairs(TradeFrame.Player.Offer:GetChildren()) do
		if child:IsA("GuiObject") and child.Name ~= "UIGridLayout" and child.Name ~= "UIListLayout" and child.Name ~= "UIPadding" then
			if not FunctionsModule.SearchArray(partnerOfferData.skins, child.Name) then
				child:Destroy()
			end
		end
	end

	local function getSkinTemplate()
		local ui = Assets and Assets:FindFirstChild("UI")
		local uiInventory = ui and ui:FindFirstChild("Inventory")
		if uiInventory then
			return uiInventory:FindFirstChild("SkinsTemplate")
				or uiInventory:FindFirstChild("Offer")
				or uiInventory:FindFirstChild("Skin")
				or uiInventory:FindFirstChild("TypesTemplate")
				or uiInventory:FindFirstChild("TemplateSkins")
		end
		return nil
	end

	-- Render partner offered skins
	for orderIndex, skinUid in ipairs(partnerOfferData.skins) do
		if SkinCmdsModule.Get(skinUid) then
			local offerSlot = TradeFrame.Player.Offer:FindFirstChild(skinUid)
			if not offerSlot then
				local template = getSkinTemplate()
				if template then
					offerSlot = template:Clone()
				else
					offerSlot = Instance.new("ImageButton")
					offerSlot.Size = UDim2.new(0, 80, 0, 80)
					offerSlot.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
					local corner = Instance.new("UICorner", offerSlot)
					corner.CornerRadius = UDim.new(0, 8)
					local stroke = Instance.new("UIStroke", offerSlot)
					stroke.Thickness = 2
					stroke.Color = Color3.fromRGB(65, 65, 80)
					local icon = Instance.new("ImageLabel", offerSlot)
					icon.Name = "SkinIcon"
					icon.Size = UDim2.new(0.75, 0, 0.75, 0)
					icon.Position = UDim2.new(0.5, 0, 0.45, 0)
					icon.AnchorPoint = Vector2.new(0.5, 0.5)
					icon.BackgroundTransparency = 1
					local lvl = Instance.new("TextLabel", offerSlot)
					lvl.Name = "Level"
					lvl.Size = UDim2.new(1, 0, 0.25, 0)
					lvl.Position = UDim2.new(0, 0, 0.75, 0)
					lvl.BackgroundTransparency = 1
					lvl.TextColor3 = Color3.new(1, 1, 1)
					lvl.TextScaled = true
					lvl.Font = Enum.Font.GothamBold
				end
				if offerSlot:IsA("TextButton") then
					offerSlot.Text = ""
				end
				offerSlot.Name = tostring(skinUid)
				SkinUIModule.Create(offerSlot, skinUid, true)
				if not offerSlot:GetAttribute("HasNewAnimated") then
					offerSlot:SetAttribute("HasNewAnimated", true)
					task.spawn(function()
						local animElapsed = 0
						local animConnection = nil
						animConnection = RunService.RenderStepped:Connect(function(dt)
							if not (offerSlot and offerSlot.Parent and TradeScreenGui.Enabled) then
								if animConnection then
									animConnection:Disconnect()
									animConnection = nil
								end
								return
							end
							animElapsed = animElapsed + dt
							if animElapsed >= 4 then
								if animConnection then
									animConnection:Disconnect()
									animConnection = nil
								end
								if offerSlot:FindFirstChild("SkinIcon") then
									offerSlot.SkinIcon.ImageTransparency = 0
								end
							else
								if offerSlot:FindFirstChild("SkinIcon") then
									offerSlot.SkinIcon.ImageTransparency = math.abs(math.sin(animElapsed / 4 * math.pi * 6) / 2)
								end
							end
						end)
					end)
				end
				offerSlot.Parent = TradeFrame.Player.Offer
			end

			local strokeThickness = isGridView and 2 or 4
			local levelLabel = offerSlot:FindFirstChild("Level")
			local levelStroke = levelLabel and levelLabel:FindFirstChildOfClass("UIStroke")
			if levelStroke then
				levelStroke.Thickness = strokeThickness
			end
			local hcLabel = offerSlot:FindFirstChild("HC")
			local hcStroke = hcLabel and hcLabel:FindFirstChildOfClass("UIStroke")
			if hcStroke then
				hcStroke.Thickness = strokeThickness
			end
			offerSlot.LayoutOrder = orderIndex
		end
	end

	local searchInput = getTradeSearchInput()
	local hasSearchQuery = (searchInput and searchInput.Text ~= "")
	local searchQueryPattern = hasSearchQuery and FunctionsModule.RegexEscape(string.lower(tostring(searchInput.Text))) or nil

	-- Render client inventory skins
	for index, skinEntry in ipairs(localPlayerSave.Skins or {}) do
		local skinUid = skinEntry.uid or skinEntry.UID
		local skinInfo = resolveSkinInfo(skinEntry)

		local isTradeable = skinInfo.tradeable
		local isOffered = FunctionsModule.SearchArray(clientOfferData.skins, skinUid)
		local skinButton = TradeFrame.Client.Offer:FindFirstChild(skinUid)

		if not skinButton then
			local template = getSkinTemplate()
			if template then
				skinButton = template:Clone()
			else
				skinButton = Instance.new("ImageButton")
				skinButton.Size = isGridView and UDim2.new(0, 54, 0, 54) or UDim2.new(0, 80, 0, 80)
				skinButton.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
				skinButton.AutoButtonColor = true
				local corner = Instance.new("UICorner", skinButton)
				corner.CornerRadius = UDim.new(0, 8)
				local stroke = Instance.new("UIStroke", skinButton)
				stroke.Thickness = isGridView and 2 or 4
				stroke.Color = Color3.fromRGB(65, 65, 80)
				local icon = Instance.new("ImageLabel", skinButton)
				icon.Name = "SkinIcon"
				icon.Size = UDim2.new(0.75, 0, 0.75, 0)
				icon.Position = UDim2.new(0.5, 0, 0.45, 0)
				icon.AnchorPoint = Vector2.new(0.5, 0.5)
				icon.BackgroundTransparency = 1
				local lvl = Instance.new("TextLabel", skinButton)
				lvl.Name = "Level"
				lvl.Size = UDim2.new(1, 0, 0.25, 0)
				lvl.Position = UDim2.new(0, 0, 0.75, 0)
				lvl.BackgroundTransparency = 1
				lvl.TextColor3 = Color3.new(1, 1, 1)
				lvl.TextScaled = true
				lvl.Font = Enum.Font.GothamBold
				local equipped = Instance.new("ImageLabel", skinButton)
				equipped.Name = "Equipped"
				equipped.Size = UDim2.new(0.3, 0, 0.3, 0)
				equipped.Position = UDim2.new(1, -2, 0, 2)
				equipped.AnchorPoint = Vector2.new(1, 0)
				equipped.BackgroundTransparency = 1
				equipped.Visible = false
			end

			if skinButton:IsA("TextButton") then
				skinButton.Text = ""
			end

			skinButton.Name = tostring(skinUid)
			SkinUIModule.Create(skinButton, skinUid, false)
			if not isTradeable then
				skinButton.BackgroundColor3 = Color3.new(0.5, 0.5, 0.5)
				local sIcon = skinButton:FindFirstChild("SkinIcon") or skinButton:FindFirstChild("Icon")
				if sIcon then
					sIcon.ImageTransparency = 0.5
					sIcon.ImageColor3 = Color3.new(0.5, 0.5, 0.5)
				end
				skinButton.LayoutOrder = 999999999
			end

			if isTradeable then
				skinButton.Activated:Connect(function()
					if not isActionDebounce and not IsChatting() then
						isActionDebounce = true
						if not IsProcessing() then
							if skinEntry.l then
								MessageModule.New("This skin is locked! Unlock it before you can trade it!")
								isActionDebounce = false
								return
							end
							local boothCheckOk, isBoothSkin = pcall(SignalModule.Invoke, "Is Trading Booth Skin", skinUid)
							if boothCheckOk and isBoothSkin then
								MessageModule.New("This skin is currently in your trading booth! Remove it before you can trade it!")
								isActionDebounce = false
								return
							end

							local currentClientOffer = FigureOutTrade()
							local alreadyOffered = FunctionsModule.SearchArray(currentClientOffer.skins, skinUid)
							local isOffered = (alreadyOffered ~= false and alreadyOffered ~= nil)
							print(string.format("[Trade Client] 👆 Skin Clicked: UID=%s (%s) | Currently Offered: %s -> Requesting %s", tostring(skinUid), tostring(skinInfo.name), tostring(isOffered), isOffered and "REMOVE" or "ADD"))

							-- Optimistic feedback (IBS-style 0 ms response): flip the
							-- Equipped badge immediately, revert if the server rejects.
							-- The authoritative state still arrives via "Update Trade".
							local equippedIcon = skinButton:FindFirstChild("Equipped")
							if equippedIcon then
								equippedIcon.Visible = not isOffered
							end

							local ok, err
							if isOffered then
								ok, err = safeInvoke("Remove Trade Skin", activeTradeId, skinUid)
							else
								ok, err = safeInvoke("Add Trade Skin", activeTradeId, skinUid)
							end
							if not ok then
								if equippedIcon then
									equippedIcon.Visible = isOffered
								end
								MessageModule.New(err or "Something went wrong.")
							end
						end
						isActionDebounce = false
					end
				end)
			else
				skinButton.Activated:Connect(function()
					if not isActionDebounce and not IsChatting() then
						isActionDebounce = true
						MessageModule.New("This skin cannot be traded!")
						isActionDebounce = false
					end
				end)
			end
			GUIFXModule.ButtonFX(skinButton)
			skinButton.Parent = TradeFrame.Client.Offer
		end

		local strokeThickness = isGridView and 2 or 4
		local levelLabel = skinButton:FindFirstChild("Level")
		local levelStroke = levelLabel and levelLabel:FindFirstChildOfClass("UIStroke")
		if levelStroke then
			levelStroke.Thickness = strokeThickness
		end
		local hcLabel = skinButton:FindFirstChild("HC")
		local hcStroke = hcLabel and hcLabel:FindFirstChildOfClass("UIStroke")
		if hcStroke then
			hcStroke.Thickness = strokeThickness
		end

		local matchesFilter = false
		if hasSearchQuery and not bothReady then
			assert(searchQueryPattern)
			local nameMatch = skinInfo.name and string.find(string.lower(skinInfo.name), searchQueryPattern, 1, true)
			local idMatch = (skinEntry.ID or skinEntry.id) and string.find(string.lower(skinEntry.ID or skinEntry.id), searchQueryPattern, 1, true)
			local itemMatch = (skinEntry.ItemName or skinEntry.itemName) and string.find(string.lower(skinEntry.ItemName or skinEntry.itemName), searchQueryPattern, 1, true)
			local catMatch = (skinEntry.Category or skinEntry.category) and string.find(string.lower(skinEntry.Category or skinEntry.category), searchQueryPattern, 1, true)
			local rarityMatch = skinInfo.rarity and string.find(string.lower(skinInfo.rarity), searchQueryPattern, 1, true)
			local nkMatch = skinEntry.nk and string.find(string.lower(skinEntry.nk), searchQueryPattern, 1, true)
			if nameMatch or idMatch or itemMatch or catMatch or rarityMatch or nkMatch then
				matchesFilter = true
			end
		end

		skinButton.LayoutOrder = index
		if isTradeable then
			local equippedIcon = skinButton:FindFirstChild("Equipped")
			if equippedIcon then
				equippedIcon.Visible = isOffered
			end
			local deleteIcon = skinButton:FindFirstChild("Delete")
			if deleteIcon then
				deleteIcon.Visible = false
			end
		end

		if bothReady or (activeTradeData and activeTradeData.confirmStage == true) then
			skinButton.Visible = isOffered
		elseif hasSearchQuery then
			-- Offered skins always stay visible: hiding them would let a player
			-- lose sight of (and be unable to un-offer) their own offer items.
			skinButton.Visible = matchesFilter or isOffered
		else
			skinButton.Visible = true
		end
	end
end

function UpdateMessageScroll()
	local holder = TradeFrame.ChatOverlay.Messages.Holder
	local layout = holder:FindFirstChildOfClass("UIListLayout")
	holder.CanvasSize = UDim2.new(0, layout.AbsoluteContentSize.X, 0, layout.AbsoluteContentSize.Y + 30)
end

function UpdateContracts()
	if not isTradeActive or not activeTradeData then
		return
	end

	local clientOffer, partnerOffer = FigureOutTrade()
	local clientContracts = clientOffer.contracts or 0
	local partnerContracts = partnerOffer.contracts or 0

	if lastClientContracts and lastClientContracts ~= clientContracts then
		GUIFXModule.FlashText(TradeFrame.Client.Contracts.Display.Input)
	end
	if lastPlayerContracts and lastPlayerContracts ~= partnerContracts then
		GUIFXModule.FlashText(TradeFrame.Player.Contracts.Amount)
	end

	lastClientContracts = clientContracts
	lastPlayerContracts = partnerContracts
	TradeFrame.Client.Contracts.Display.Input.PlaceholderText = (clientContracts > 0) and FunctionsModule.Commas(clientContracts) or "None"
	TradeFrame.Player.Contracts.Amount.Text = FunctionsModule.Commas(partnerContracts)
end

function UpdateXbox()
	TradeFrame.Client.Contracts.Add.Visible = VariablesModule.Console
	TradeFrame.Client.Contracts.Minus.Visible = VariablesModule.Console

	local cancelKeybind = TradeFrame.Buttons.Cancel:FindFirstChild("ButtonKeybind")
		or (TradeFrame.Buttons.Cancel:FindFirstChild("Frame") and TradeFrame.Buttons.Cancel.Frame:FindFirstChild("ButtonKeybind"))
	if cancelKeybind then
		cancelKeybind.Visible = VariablesModule.Console
	end

	local readyKeybind = TradeFrame.Buttons.Ready:FindFirstChild("ButtonKeybind")
		or (TradeFrame.Buttons.Ready:FindFirstChild("Frame") and TradeFrame.Buttons.Ready.Frame:FindFirstChild("ButtonKeybind"))
	if readyKeybind then
		readyKeybind.Visible = VariablesModule.Console
	end
end

-- Visual colors for Ready & Confirm states
local COLOR_BUTTON_RED = Color3.fromRGB(170, 0, 0)
local COLOR_BUTTON_GREEN = Color3.fromRGB(0, 170, 0)
local COLOR_ACTIVE_INDICATOR = Color3.fromRGB(64, 252, 59)
local COLOR_INACTIVE_INDICATOR = Color3.fromRGB(7, 141, 34)

-- Updates overall trade window state, Ready/Confirm buttons, countdown, and participant labels
function UpdateInterface()
	if not isTradeActive or not activeTradeData then
		return
	end
	assert(activeTradeData)

	local clientOffer, partnerOffer, clientPlayer, targetPlayer, isSender = FigureOutTrade()

	local isLocalReady = if isSender then (activeTradeData.senderReady == true) else (activeTradeData.targetReady == true)
	local isPartnerReady = if isSender then (activeTradeData.targetReady == true) else (activeTradeData.senderReady == true)

	local isLocalConfirmed = if isSender then (activeTradeData.senderConfirmed == true) else (activeTradeData.targetConfirmed == true)
	local isPartnerConfirmed = if isSender then (activeTradeData.targetConfirmed == true) else (activeTradeData.senderConfirmed == true)

	local timeSinceLastCounter = workspace:GetServerTimeNow() - activeTradeData.lastCounter

	local function getReadyButton()
		local buttons = TradeFrame:FindFirstChild("Buttons")
		if buttons then
			return buttons:FindFirstChild("Ready") or buttons:FindFirstChild("Yes") or buttons:FindFirstChild("Confirm")
		end
		return nil
	end

	local function getCancelButton()
		local buttons = TradeFrame:FindFirstChild("Buttons")
		if buttons then
			return buttons:FindFirstChild("Cancel") or buttons:FindFirstChild("No") or buttons:FindFirstChild("Decline")
		end
		return nil
	end

	local readyButton = getReadyButton()
	local readyButtonFrame = readyButton and (readyButton:FindFirstChild("Frame") or readyButton)
	local readyLabel = readyButton and (readyButton:FindFirstChild("TextLabel")
		or (readyButton:FindFirstChild("Frame") and readyButton.Frame:FindFirstChild("TextLabel"))
		or (readyButton:IsA("TextButton") and readyButton))

	local cancelButton = getCancelButton()
	local cancelButtonFrame = cancelButton and (cancelButton:FindFirstChild("Frame") or cancelButton)

	-- Color and text state handling
	if not (activeTradeData.confirmStage == true) then
		if isLocalReady then
			if readyButtonFrame then readyButtonFrame.BackgroundColor3 = COLOR_BUTTON_RED end
			if readyLabel then
				readyLabel.Text = "Unready"
			end
		else
			if readyButtonFrame then readyButtonFrame.BackgroundColor3 = COLOR_BUTTON_GREEN end
			if readyLabel then
				readyLabel.Text = "Ready"
			end
		end
	elseif isLocalConfirmed then
		if readyButtonFrame then readyButtonFrame.BackgroundColor3 = COLOR_BUTTON_RED end
		if readyLabel then
			readyLabel.Text = "Unconfirm"
		end
	else
		if readyButtonFrame then readyButtonFrame.BackgroundColor3 = COLOR_BUTTON_GREEN end
		if readyLabel then
			readyLabel.Text = "Confirm"
		end
	end

	if TradeBottomFrame then
		TradeBottomFrame.Visible = (activeTradeData.confirmStage == false)
	end

	local isClientReadyOrConfirmed = (activeTradeData.confirmStage == false and isLocalReady)
		or (activeTradeData.confirmStage == true and isLocalConfirmed)
	local isPartnerReadyOrConfirmed = (activeTradeData.confirmStage == false and isPartnerReady)
		or (activeTradeData.confirmStage == true and isPartnerConfirmed)

	if TradeFrame.Client:FindFirstChild("Ready") then
		TradeFrame.Client.Ready.Visible = (activeTradeData.confirmStage == false and isLocalReady)
	end
	if TradeFrame.Player:FindFirstChild("Ready") then
		TradeFrame.Player.Ready.Visible = (activeTradeData.confirmStage == false and isPartnerReady)
	end

	if TradeFrame.Client:FindFirstChild("Confirmed") then
		TradeFrame.Client.Confirmed.Visible = (activeTradeData.confirmStage == true and isLocalConfirmed)
	end
	if TradeFrame.Player:FindFirstChild("Confirmed") then
		TradeFrame.Player.Confirmed.Visible = (activeTradeData.confirmStage == true and isPartnerConfirmed)
	end

	if TradeFrame.Client:FindFirstChild("Title") and TradeFrame.Client.Title:IsA("TextLabel") then
		TradeFrame.Client.Title.TextColor3 = isClientReadyOrConfirmed and COLOR_ACTIVE_INDICATOR or COLOR_INACTIVE_INDICATOR
	end
	if TradeFrame.Client:FindFirstChild("Contracts") then
		TradeFrame.Client.Contracts.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	end
	if TradeFrame.Client:FindFirstChild("Arrow") then
		TradeFrame.Client.Arrow.ImageColor3 = isClientReadyOrConfirmed and COLOR_ACTIVE_INDICATOR or COLOR_INACTIVE_INDICATOR
	end
	if TradeFrame.Client:FindFirstChild("Offer") then
		TradeFrame.Client.Offer.ScrollBarImageColor3 = isClientReadyOrConfirmed and COLOR_ACTIVE_INDICATOR or COLOR_INACTIVE_INDICATOR
	end

	if TradeFrame.Player:FindFirstChild("Title") and TradeFrame.Player.Title:FindFirstChild("Title") then
		TradeFrame.Player.Title.Title.TextColor3 = isPartnerReadyOrConfirmed and COLOR_ACTIVE_INDICATOR or COLOR_INACTIVE_INDICATOR
	end
	if TradeFrame.Player:FindFirstChild("Arrow") then
		TradeFrame.Player.Arrow.ImageColor3 = isPartnerReadyOrConfirmed and COLOR_ACTIVE_INDICATOR or COLOR_INACTIVE_INDICATOR
	end
	if TradeFrame.Player:FindFirstChild("Contracts") then
		TradeFrame.Player.Contracts.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	end
	if TradeFrame.Player:FindFirstChild("Offer") then
		TradeFrame.Player.Offer.ScrollBarImageColor3 = isPartnerReadyOrConfirmed and COLOR_ACTIVE_INDICATOR or COLOR_INACTIVE_INDICATOR
	end

	TradeFrame.Player.Title.Title.Text = targetPlayer.DisplayName
	TradeFrame.Player.Title.Subtitle.Text = "@" .. targetPlayer.Name

	local partnerUserId = isSender and activeTradeData.target.UserId or activeTradeData.sender.UserId
	if cachedPartnerUserId ~= partnerUserId or not cachedPartnerThumb then
		cachedPartnerUserId = partnerUserId
		task.spawn(function()
			local tradeSuffix = SignalModule.Invoke("Get Trade Suffix", targetPlayer)
			if tradeSuffix and TradeFrame.Player and TradeFrame.Player:FindFirstChild("Title") and TradeFrame.Player.Title:FindFirstChild("Title") then
				TradeFrame.Player.Title.Title.Text = targetPlayer.DisplayName .. tradeSuffix
			end
			local avatarThumb = nil
			pcall(function()
				avatarThumb = Players:GetUserThumbnailAsync(
					partnerUserId,
					Enum.ThumbnailType.HeadShot,
					Enum.ThumbnailSize.Size180x180
				)
			end)
			cachedPartnerThumb = avatarThumb or "rbxassetid://11453721156"
			if TradeFrame.Player and TradeFrame.Player:FindFirstChild("Title") and TradeFrame.Player.Title:FindFirstChild("ImageLabel") then
				TradeFrame.Player.Title.ImageLabel.Image = cachedPartnerThumb
				TradeFrame.Player.Title.ImageLabel.Visible = true
			end
		end)
	else
		if TradeFrame.Player and TradeFrame.Player:FindFirstChild("Title") and TradeFrame.Player.Title:FindFirstChild("ImageLabel") then
			TradeFrame.Player.Title.ImageLabel.Image = cachedPartnerThumb
			TradeFrame.Player.Title.ImageLabel.Visible = true
		end
	end

	local countdownRemaining = nil
	if activeTradeData.confirmStage == true then
		if isPartnerConfirmed and isLocalConfirmed then
			if activeTradeData.confirmTick and activeTradeData.confirmTick > 0 then
				if not confirmCountdownStartTick then
					confirmCountdownStartTick = activeTradeData.confirmTick
				end
				local elapsed = workspace:GetServerTimeNow() - confirmCountdownStartTick
				countdownRemaining = math.clamp(math.ceil(4 - elapsed), 0, 4)
				if countdownRemaining > 0 then
					TradeFrame.Notice.Text = "⏱ " .. countdownRemaining .. " seconds left..."
				else
					TradeFrame.Notice.Text = "⏱ Trade confirming..."
				end
			else
				confirmCountdownStartTick = nil
				TradeFrame.Notice.Text = "Countdown starts when both players Confirm the trade!"
			end
		else
			confirmCountdownStartTick = nil
			TradeFrame.Notice.Text = "Countdown starts when both players Confirm the trade!"
		end
	else
		confirmCountdownStartTick = nil
		TradeFrame.Notice.Text = "Press Ready when you are satisfied with the trade!"
	end

	local isProcessingTrade = activeTradeData.processing or (countdownRemaining ~= nil and countdownRemaining <= 0)
	if isProcessingTrade then
		TradeFrame.Notice.Text = "⏱ Trade confirming..."
	end
	TradeFrame.Processing.Visible = isProcessingTrade
	TradeFrame.Player.Title.Title.Visible = not isProcessingTrade
	TradeFrame.Client.Title.Visible = not isProcessingTrade
	TradeFrame.Buttons.Visible = not isProcessingTrade
	TradeFrame.Client.Contracts.Display.Input.TextEditable = not isProcessingTrade
	if TradeFrame.Client:FindFirstChild("Coins") and TradeFrame.Client.Coins:FindFirstChild("Display") then
		TradeFrame.Client.Coins.Display.Input.TextEditable = not isProcessingTrade
	end

	local gridIconAsset = isGridView and "rbxassetid://72477333604468" or "rbxassetid://76043634790624"
	if TradeBottomFrame and TradeBottomFrame:FindFirstChild("Grid") then
		TradeBottomFrame.Grid.Image = gridIconAsset
	end

	if activeGifCleanup then
		if not isProcessingTrade then
			activeGifCleanup()
			activeGifCleanup = nil
		end
	elseif isProcessingTrade then
		activeGifCleanup = GIFModule.Create(TradeFrame.Processing.GIF, { 100, 100 }, { 5, 6 }, 28, 0.65, true)
	end

	if TradeBottomFrame then
		TradeBottomFrame.Visible = (not isProcessingTrade) and (activeTradeData.confirmStage == false)
	end

	UpdateXbox()
	UpdateChat()
	UpdateMessageScroll()
end

function ChangeDiamondAmount()
	local contractInput = TradeFrame.Client.Contracts.Display.Input
	if isTradeActive and activeTradeId then
		local clientOffer = FigureOutTrade()
		local localPlayerSave = SaveModule.Get()
		local maxContracts = (localPlayerSave and localPlayerSave.Contracts) or 0
		local parsedAmount = FunctionsModule.ParseNumberSmart(contractInput.Text)
		if parsedAmount then
			local roundedAmount = math.clamp(math.round(parsedAmount), 0, maxContracts)
			local ok, updatedAmount = safeInvoke("Change Trade Contracts", activeTradeId, roundedAmount)
			if ok then
				clientOffer.contracts = updatedAmount or roundedAmount
				contractInput.PlaceholderText = (roundedAmount > 0) and FunctionsModule.Commas(roundedAmount) or "None"
			else
				coroutine.wrap(function()
					MessageModule.New(updatedAmount or "Amount is invalid. Try something else!")
				end)()
			end
		end
	end
	contractInput.Text = ""
end

function UpdateCoins()
	local clientOffer, partnerOffer = FigureOutTrade()
	local clientCoins = clientOffer.coins or clientOffer.Coins or 0
	local partnerCoins = partnerOffer.coins or partnerOffer.Coins or 0

	if lastClientCoins and lastClientCoins ~= clientCoins then
		AudioModule.Play(95137592533310, script, 1, 0.2)
		GUIFXModule.FlashText(TradeFrame.Client.Coins.Display.Input)
	end
	if lastPlayerCoins and lastPlayerCoins ~= partnerCoins then
		AudioModule.Play(95137592533310, script, 1, 0.2)
		GUIFXModule.FlashText(TradeFrame.Player.Coins.Amount)
	end

	lastClientCoins = clientCoins
	lastPlayerCoins = partnerCoins
	TradeFrame.Client.Coins.Display.Input.PlaceholderText = (clientCoins > 0) and FunctionsModule.Commas(clientCoins) or "None"
	TradeFrame.Player.Coins.Amount.Text = FunctionsModule.Commas(partnerCoins)
end

function ChangeCoinsAmount()
	local coinInput = TradeFrame.Client:FindFirstChild("Coins") and TradeFrame.Client.Coins:FindFirstChild("Display") and TradeFrame.Client.Coins.Display.Input
	if not coinInput then return end
	if isTradeActive and activeTradeId then
		local clientOffer = FigureOutTrade()
		local localPlayerSave = SaveModule.Get()
		local maxCoins = (localPlayerSave and (localPlayerSave.Coins or localPlayerSave.Diamonds or (SharedModule.GetCoins and SharedModule.GetCoins(localPlayerSave)))) or 0
		local parsedAmount = FunctionsModule.ParseNumberSmart(coinInput.Text)
		if parsedAmount then
			local roundedAmount = math.clamp(math.round(parsedAmount), 0, maxCoins)
			local ok, updatedAmount = safeInvoke("Change Trade Coins", activeTradeId, roundedAmount)
			if ok then
				clientOffer.coins = updatedAmount or roundedAmount
				coinInput.PlaceholderText = (roundedAmount > 0) and FunctionsModule.Commas(roundedAmount) or "None"
			else
				coroutine.wrap(function()
					MessageModule.New(updatedAmount or "Amount is invalid. Try something else!")
				end)()
			end
		end
	end
	coinInput.Text = ""
end

function UpdateChat()
	if VariablesModule.Console then
		TradeFrame.Chat.Visible = false
		return
	end
	if not activeTradeData then
		return
	end
	assert(activeTradeData)

	local isSender = (activeTradeData.sender == LocalPlayer)
	local chatOverlay = TradeFrame.ChatOverlay
	local messagesHolder = chatOverlay.Messages.Holder
	local playerLineTemplate = messagesHolder.PlayerLine
	local clientLineTemplate = messagesHolder.ClientLine
	local chatNotification = TradeFrame.Chat.Notification

	TradeFrame.Chat.BackgroundColor3 = chatOverlay.Visible and Color3.fromRGB(252, 209, 59) or Color3.fromRGB(39, 233, 55)
	chatOverlay.Footer.Send.ImageColor3 = (chatOverlay.Footer.Message.Input.Text ~= "") and Color3.new(1, 1, 1) or Color3.new(0.5, 0.5, 0.5)

	for msgIndex, msgEntry in ipairs(activeTradeData.messages) do
		if not messagesHolder:FindFirstChild("Message" .. msgIndex) then
			local isLocalMessage = (msgEntry.isSender and isSender) or (not msgEntry.isSender and not isSender)
			local messageRow = isLocalMessage and clientLineTemplate:Clone() or playerLineTemplate:Clone()
			messageRow.Name = "Message" .. msgIndex

			local labelElement = isLocalMessage and messageRow.ClientMessage.Label or messageRow.PlayerMessage.Label
			labelElement.Text = msgEntry.message

			if not isLocalMessage then
				-- Thumbnail is fetched once per trade, asynchronously. Doing it
				-- inline here would yield the render loop for hundreds of ms
				-- on every new partner message.
				if not chatPartnerThumbCache then
					chatPartnerThumbCache = "rbxassetid://11453721156"
					local authorUserId = isSender and activeTradeData.target.UserId or activeTradeData.sender.UserId
					task.spawn(function()
						local thumbOk, thumb = pcall(function()
							return Players:GetUserThumbnailAsync(
								authorUserId,
								Enum.ThumbnailType.HeadShot,
								Enum.ThumbnailSize.Size180x180
							)
						end)
						if thumbOk and thumb then
							chatPartnerThumbCache = thumb
							for _, row in ipairs(messagesHolder:GetChildren()) do
								local rowImage = row:IsA("Frame") and row:FindFirstChild("ImageLabel")
								if rowImage then
									rowImage.Image = thumb
								end
							end
						end
					end)
				end
				messageRow.ImageLabel.Image = chatPartnerThumbCache
			end

			messageRow:SetAttribute("Template", false)
			messageRow.Parent = messagesHolder
			messageRow.LayoutOrder = messageRow.LayoutOrder + msgIndex
			messageRow.Visible = true

			if not chatOverlay.Visible then
				chatNotification.Count.Text = tostring((tonumber(chatNotification.Count.Text) or 0) + 1)
				chatNotification.Visible = true
			end

			local rowHeight = VariablesModule.Mobile and 50 or 100
			messageRow.Size = UDim2.new(1, 0, 0, rowHeight)

			task.defer(function()
				messagesHolder.CanvasPosition = messagesHolder.AbsoluteCanvasSize
			end)
		end
	end
end

function FigureOutTrade()
	assert(activeTradeData)
	local isSender = (activeTradeData.sender == LocalPlayer)
	return isSender and activeTradeData.senderItems or activeTradeData.targetItems,
		isSender and activeTradeData.targetItems or activeTradeData.senderItems,
		LocalPlayer,
		isSender and activeTradeData.target or activeTradeData.sender,
		isSender,
		not isSender,
		not isSender,
		isSender
end

function IsProcessing()
	if not activeTradeData then
		return false
	end
	assert(activeTradeData)
	if confirmCountdownStartTick then
		if math.round(math.clamp(4 - (workspace:GetServerTimeNow() - confirmCountdownStartTick), 0, 4) * 10) / 10 <= 0 then
			return true
		end
	end
	return activeTradeData.processing
end

function IsChatting()
	return TradeFrame.ChatOverlay.Visible
end

function Reset()
	isTradeActive = false
	activeTradeId = nil
	activeTradeData = nil
	confirmCountdownStartTick = nil
	lastClientContracts = nil
	lastPlayerContracts = nil
	cachedPartnerUserId = nil
	cachedPartnerThumb = nil
	chatPartnerThumbCache = nil
	lastClientCoins = nil
	lastPlayerCoins = nil
	isGridView = false
	_G.ActiveTradeSkinsData = nil

	if TradeFrame and TradeFrame:FindFirstChild("Processing") then
		TradeFrame.Processing.Visible = false
	end

	if activeGifCleanup then
		pcall(activeGifCleanup)
		activeGifCleanup = nil
	end

	if TradeBottomFrame then
		local tradeSearch = TradeBottomFrame:FindFirstChild("TradeSearch")
		if tradeSearch then
			local tradeQuery = tradeSearch:FindFirstChild("TradeQuery")
			if tradeQuery then
				tradeQuery.Text = ""
			end
		end
	end

	TradeFrame.Client.Contracts.Display.Input.Text = ""
	local historyPanel = MainFrame:FindFirstChild("TradingHistory")
	if historyPanel then
		historyPanel.Visible = false
	end
	local viewPanel = MainFrame:FindFirstChild("TradeView")
	if viewPanel then
		viewPanel.Visible = false
	end

	TradeScreenGui.Enabled = false
	local chatOverlay = TradeFrame.ChatOverlay
	local chatNotification = TradeFrame.Chat.Notification
	chatOverlay.Visible = false
	chatNotification.Count.Text = 0
	chatNotification.Visible = false

	for _, child in ipairs(chatOverlay.Messages.Holder:GetChildren()) do
		-- Message rows are named "Message1".."MessageN"; leaving them behind
		-- leaks the previous trade's chat and skips rendering of new messages
		-- (UpdateChat only creates rows whose name is missing).
		if string.find(child.Name, "^Message%d+$") then
			child:Destroy()
		end
	end

	if TradeFrame:FindFirstChild("Client") then
		if TradeFrame.Client:FindFirstChild("Ready") then TradeFrame.Client.Ready.Visible = false end
		if TradeFrame.Client:FindFirstChild("Confirmed") then TradeFrame.Client.Confirmed.Visible = false end
	end
	if TradeFrame:FindFirstChild("Player") then
		if TradeFrame.Player:FindFirstChild("Ready") then TradeFrame.Player.Ready.Visible = false end
		if TradeFrame.Player:FindFirstChild("Confirmed") then TradeFrame.Player.Confirmed.Visible = false end
	end

	for _, child in ipairs(TradeFrame.Client.Offer:GetChildren()) do
		if child:IsA("TextButton") or child:IsA("ImageButton") then
			child:Destroy()
		end
	end
	if TradeFrame:FindFirstChild("Player") and TradeFrame.Player:FindFirstChild("Offer") then
		for _, child in ipairs(TradeFrame.Player.Offer:GetChildren()) do
			if child:IsA("TextButton") or child:IsA("ImageButton") then
				child:Destroy()
			end
		end
	end
end

function Close()
	if not isTradeActive then
		Reset()
		return
	end
	local success, err = safeInvoke("Cancel Trade", activeTradeId)
	if not success then
		MessageModule.New(err or "Something went wrong.")
	end
	Reset()
end

function ToggleGrid()
	debug.profilebegin("Trading.ToggleGrid")
	isGridView = not isGridView

	local clientGrid = TradeFrame.Client.Offer:FindFirstChildOfClass("UIGridLayout")
	if clientGrid then
		if isGridView then
			clientGrid.CellSize = UDim2.new(0, 54, 0, 54)
			clientGrid.CellPadding = UDim2.new(0, 6, 0, 6)
		else
			clientGrid.CellSize = UDim2.new(0, 80, 0, 80)
			clientGrid.CellPadding = UDim2.new(0, 10, 0, 10)
		end
	end

	local playerGrid = TradeFrame.Player.Offer:FindFirstChildOfClass("UIGridLayout")
	if playerGrid then
		if isGridView then
			playerGrid.CellSize = UDim2.new(0, 54, 0, 54)
			playerGrid.CellPadding = UDim2.new(0, 6, 0, 6)
		else
			playerGrid.CellSize = UDim2.new(0, 80, 0, 80)
			playerGrid.CellPadding = UDim2.new(0, 10, 0, 10)
		end
	end

	if TradeBottomFrame and TradeBottomFrame:FindFirstChild("Grid") then
		TradeBottomFrame.Grid.Image = isGridView and "rbxassetid://72477333604468" or "rbxassetid://76043634790624"
	end

	UpdateSkins()
	debug.profileend()
end

function readyTrade()
	if not isActionDebounce and isTradeActive and not IsChatting() then
		isActionDebounce = true
		if not activeTradeData then
			isActionDebounce = false
			return
		end

		local clientOffer, partnerOffer, clientPlayer, partnerPlayer, isSender = FigureOutTrade()
		local isLocalReady = if isSender then (activeTradeData.senderReady == true) else (activeTradeData.targetReady == true)
		local isLocalConfirmed = if isSender then (activeTradeData.senderConfirmed == true) else (activeTradeData.targetConfirmed == true)

		if activeTradeData.confirmStage == false then
			if isLocalReady then
				-- Optimistic toggle
				if isSender then activeTradeData.senderReady = false else activeTradeData.targetReady = false end
				UpdateInterface()

				if typeof(activeTradeId) == "string" then
					local ok, err = safeInvoke("Unready Trade", activeTradeId)
					if not ok then
						MessageModule.New(err or "Something went wrong.")
						if isSender then activeTradeData.senderReady = true else activeTradeData.targetReady = true end
						UpdateInterface()
					end
				end
			else
				-- Optimistic toggle
				if isSender then activeTradeData.senderReady = true else activeTradeData.targetReady = true end
				UpdateInterface()

				if typeof(activeTradeId) == "string" then
					local ok, err = safeInvoke("Ready Trade", activeTradeId, activeTradeData.counter)
					if not ok and err then
						MessageModule.New(err or "Something went wrong.")
						if isSender then activeTradeData.senderReady = false else activeTradeData.targetReady = false end
						UpdateInterface()
					end
				end
			end
		elseif isLocalConfirmed then
			-- Optimistic toggle
			if isSender then activeTradeData.senderConfirmed = false else activeTradeData.targetConfirmed = false end
			UpdateInterface()

			if typeof(activeTradeId) == "string" then
				local ok, err = safeInvoke("Unconfirm Trade", activeTradeId)
				if not ok then
					MessageModule.New(err or "Something went wrong.")
					if isSender then activeTradeData.senderConfirmed = true else activeTradeData.targetConfirmed = true end
					UpdateInterface()
				end
			end
		else
			-- Optimistic toggle
			if isSender then activeTradeData.senderConfirmed = true else activeTradeData.targetConfirmed = true end
			UpdateInterface()

			if typeof(activeTradeId) == "string" then
				local ok, err = safeInvoke("Confirm Trade", activeTradeId, activeTradeData.counter)
				if not ok and err ~= "Trade contents changed!" and err then
					MessageModule.New(err or "Something went wrong.")
					if isSender then activeTradeData.senderConfirmed = false else activeTradeData.targetConfirmed = false end
					UpdateInterface()
				end
			end
		end
		isActionDebounce = false
	end
end

function cancelTrade()
	if not isActionDebounce and not IsChatting() then
		isActionDebounce = true
		Close()
		isActionDebounce = false
	end
end

function sendChatMessage()
	local chatInput = TradeFrame.ChatOverlay.Footer.Message.Input
	local messageText = chatInput.Text
	if not activeTradeData or messageText == "" then
		return
	end
	assert(activeTradeData)

	if #messageText > 200 then
		MessageModule.New("Your message is too long! Please keep it under 200 characters!")
		return
	end
	if #activeTradeData.messages >= 50 then
		MessageModule.New("This chat is now full! You can use default chat as a backup.")
		return
	end

	chatInput.Text = ""
	local success, err = safeInvoke("Send Trade Message", activeTradeId, messageText)
	if not success then
		MessageModule.New(err or "Failed to send trade message (unknown)")
	end
end

-- Input Focus Events
TradeFrame.Client.Contracts.Display.Input.FocusLost:Connect(function()
	ChangeDiamondAmount()
end)

if TradeFrame.Client:FindFirstChild("Coins") and TradeFrame.Client.Coins:FindFirstChild("Display") then
	TradeFrame.Client.Coins.Display.Input.FocusLost:Connect(function()
		ChangeCoinsAmount()
	end)
end

local tradeButtons = TradeFrame:FindFirstChild("Buttons")
local readyBtn = tradeButtons and (tradeButtons:FindFirstChild("Ready") or tradeButtons:FindFirstChild("Yes") or tradeButtons:FindFirstChild("Confirm"))
if readyBtn then
	readyBtn.Activated:Connect(readyTrade)
end

local cancelBtn = tradeButtons and (tradeButtons:FindFirstChild("Cancel") or tradeButtons:FindFirstChild("No") or tradeButtons:FindFirstChild("Decline"))
if cancelBtn then
	cancelBtn.Activated:Connect(cancelTrade)
end

TradeFrame.Chat.Activated:Connect(function()
	TradeFrame.ChatOverlay.Visible = not TradeFrame.ChatOverlay.Visible
	TradeFrame.Chat.Notification.Count.Text = 0
	TradeFrame.Chat.Notification.Visible = false
end)

if TradeBottomFrame then
	local gridBtn = TradeBottomFrame:FindFirstChild("Grid")
	if gridBtn then
		gridBtn.Activated:Connect(function()
			if not isActionDebounce then
				isActionDebounce = true
				ToggleGrid()
				isActionDebounce = false
			end
		end)
	end
end

TradeFrame.ChatOverlay.Footer.Send.Activated:Connect(function()
	sendChatMessage()
end)

TradeFrame.ChatOverlay.Footer.Message.Input.FocusLost:Connect(function(enterPressed)
	if enterPressed then
		sendChatMessage()
	end
end)

PlayerListFrame.Close.Activated:Connect(function()
	if not isActionDebounce then
		isActionDebounce = true
		TradeScreenGui.Enabled = false
		-- No WindowManager.Close(): Trade GUI is isolated from the window registry
		isActionDebounce = false
	end
end)

PlayerListFrame.Bottom.Search.Query:GetPropertyChangedSignal("Text"):Connect(function()
	if PlayerListFrame.Bottom.Search.Query.Text ~= "" then
		PlayerListFrame.Players.CanvasPosition = Vector2.new()
	end
	RenderPlayerList()
end)

GUIFXModule.ButtonFX(PlayerListFrame.Bottom.Show)
PlayerListFrame.Bottom.Show.Activated:Connect(function()
	if not isActionDebounce then
		isActionDebounce = true
		local currentText = PlayerListFrame.Bottom.Show.TextLabel.Text
		local nextText = (currentText == "All") and "Friends" or "All"
		PlayerListFrame.Bottom.Show.TextLabel.Text = nextText
		isFilterFriendsOnly = (nextText == "Friends")
		RenderPlayerList()
		isActionDebounce = false
	end
end)

GUIFXModule.ButtonFX(PlayerListFrame.Bottom.History)
PlayerListFrame.Bottom.History.Activated:Connect(function()
	if not isActionDebounce then
		isActionDebounce = true
		SignalModule.Fire("Open Trading History")
		isActionDebounce = false
	end
end)

SignalModule.Fired("Resolution Changed"):Connect(function()
	task.defer(function()
		ListScrolling()
	end)
end)

SignalModule.Fired("Open Trade List"):Connect(function()
	local historyPanel = MainFrame:FindFirstChild("TradingHistory")
	if historyPanel then
		historyPanel.Visible = false
	end
	local viewPanel = MainFrame:FindFirstChild("TradeView")
	if viewPanel then
		viewPanel.Visible = false
	end
	TradeFrame.Visible = false
	PlayerListFrame.Visible = true
	TradeScreenGui.Enabled = true
	RenderPlayerList()
end)

SignalModule.Fired("Xbox Start Subtract"):Connect(function()
	xboxSubtractActive = true
	xboxHoldTimer = 0
end)

SignalModule.Fired("Xbox Stop Subtract"):Connect(function()
	xboxSubtractActive = false
	xboxHoldTimer = 0
	ChangeDiamondAmount()
end)

SignalModule.Fired("Xbox Start Add"):Connect(function()
	xboxAddActive = true
	xboxHoldTimer = 0
end)

SignalModule.Fired("Xbox Stop Add"):Connect(function()
	xboxAddActive = false
	xboxHoldTimer = 0
	ChangeDiamondAmount()
end)

SignalModule.Fired("Attempt Accept Trade"):Connect(readyTrade)
SignalModule.Fired("Attempt Cancel Trade"):Connect(cancelTrade)

RunService.Heartbeat:Connect(function(dt)
	if not VariablesModule.Console then
		return
	end
	if isTradeActive and activeTradeId and (xboxSubtractActive or xboxAddActive) then
		xboxHoldTimer = xboxHoldTimer + dt
		local contractContainer = TradeFrame.Client.Contracts
		local multiplier = math.pow(10, math.floor(xboxHoldTimer / 3))
		local currentAmount = contractContainer.Display.Input:GetAttribute("Amount") or 0

		if xboxSubtractActive then
			currentAmount = math.max(0, currentAmount - 1 * multiplier)
			if currentAmount < 10 then
				currentAmount = 0
			end
		elseif xboxAddActive then
			currentAmount = currentAmount + 1 * multiplier
			if currentAmount < 10 then
				currentAmount = 10
			end
		end

		if currentAmount >= 0 then
			contractContainer.Display.Input.PlaceholderText = (currentAmount > 0) and currentAmount or "None"
			contractContainer.Display.Input.Text = FunctionsModule.Commas(currentAmount)
			contractContainer.Display.Input:SetAttribute("Amount", currentAmount)
		end
	end
end)

-- Network Trade Events
NetworkModule.Fired("Trade Processed"):Connect(function(success, reason)
	if success then
		Reset()
		MessageModule.New("\226\156\133 Trade successfully completed!")
		return
	end
	MessageModule.New(reason or "Trade failed (unknown error)")
end)

NetworkModule.Fired("Init Trade"):Connect(function(tradeId, tradeData)
	activeTradeData = tradeData
	activeTradeId = tradeId
	isTradeActive = true
	UpdateSkins()
	UpdateContracts()
	UpdateInterface()
	TradeScreenGui.Enabled = true
end)

SignalModule.Invoked("Get Trade Suffix").OnInvoke = function(targetPlayer)
	if targetPlayer.UserId < 0 then
		return " (Local:" .. targetPlayer.UserId .. ")"
	end
	if targetPlayer:GetRankInGroup(1105415251) == 5 then
		return " (\240\159\148\165 Partner)"
	end
	if FunctionsModule.SearchDictionary({ 255, 50, 25, 10 }, targetPlayer:GetRankInGroup(1072042)) then
		return " (\240\159\148\165 Staff)"
	end
	return nil
end

function TradeReceived(tradeId, tradeData)
	while true do
		if WorldCmdsModule.CanDoAction() then
			if not VariablesModule.BankOpen then
				break
			end
		end
		RunService.Heartbeat:Wait()
	end

	if not tradeData.sender or not tradeData.sender.Parent then
		return false
	end

	local senderDisplayName = tradeData.sender.DisplayName
	local tradeSuffix = SignalModule.Invoke("Get Trade Suffix", tradeData.sender)
	if tradeSuffix then
		senderDisplayName = senderDisplayName .. tradeSuffix
	end
	return MessageModule.New(senderDisplayName .. " sent you a trade request. Do you accept?", true)
end

NetworkModule.Fired("Trade Recieved"):Connect(function(tradeId, tradeData)
	-- tradeId is the SENDER player (server contract). Guard the prompt so a
	-- client-side error surfaces as a warning instead of silently swallowing
	-- the whole trade request.
	local ok, accepted = pcall(TradeReceived, tradeId, tradeData)
	if not ok then
		warn("[Trade] TradeReceived error:", accepted)
		accepted = false
	end
	if accepted then
		NetworkModule.Fire("Accept Trade Invite", tradeId)
		return
	end
	NetworkModule.Fire("Ignore Trade", tradeId)
end)

local function Reset()
	isTradeActive = false
	activeTradeData = nil
	activeTradeId = nil
	confirmCountdownStartTick = nil
	hasWarnedFairTrade = false
	lastClientContracts = nil
	lastPlayerContracts = nil
	lastClientCoins = nil
	lastPlayerCoins = nil
	if TradeFrame then
		TradeFrame.Visible = false
	end
	if PlayerListFrame then
		PlayerListFrame.Visible = true
	end
	if activeGifCleanup then
		pcall(activeGifCleanup)
		activeGifCleanup = nil
	end
end

local function onTradeStarted(tradeId, initialTradeData)
	Reset()
	activeTradeId = tostring(tradeId)
	activeTradeData = initialTradeData
	if initialTradeData and initialTradeData.skinsData then
		_G.ActiveTradeSkinsData = initialTradeData.skinsData
	end
	isTradeActive = true
	print(string.format("[Trade Client] 🟢 Session Initialized! TradeID: %s", tostring(tradeId)))
	TradeScreenGui.Enabled = true
	if MainFrame then
		MainFrame.Visible = true
	end
	if PlayerListFrame then
		PlayerListFrame.Visible = false
	end
	if TradeFrame then
		TradeFrame.Visible = true
		if TradeFrame:FindFirstChild("Processing") then
			TradeFrame.Processing.Visible = false
		end
	end
	UpdateSkins()
	UpdateContracts()
	if TradeFrame.Client:FindFirstChild("Coins") then
		UpdateCoins()
	end
	UpdateInterface()
end

NetworkModule.Fired("Init Trade"):Connect(onTradeStarted)

NetworkModule.Fired("Trade Processed"):Connect(function(tradeId, status)
	print(string.format("[Trade Client] 🏁 Trade Processed event received! Status: %s", tostring(status)))
	Reset()
	if status == true or status == "/" then
		MessageModule.New("Trade completed successfully! \240\159\142\137")
	elseif status == false then
		MessageModule.New("Trade was cancelled or stopped.")
	end
end)

NetworkModule.Fired("Trade Cancelled"):Connect(function(tradeId, cancellingPlayer)
	print(string.format("[Trade Client] 🛑 Trade Cancelled event received! Cancelled by: %s", tostring(cancellingPlayer and cancellingPlayer.Name)))
	if isTradeActive and (tradeId == activeTradeId or tostring(tradeId) == tostring(activeTradeId)) then
		Reset()
		local cancellingName = (cancellingPlayer and cancellingPlayer.DisplayName) or "Other player"
		MessageModule.New("Your trade with " .. cancellingName .. " was cancelled \240\159\152\148")
	end
end)

NetworkModule.Fired("Trade Ignored"):Connect(function(ignoredPlayer)
	if not isTradeActive then
		local ignoredName = (ignoredPlayer and ignoredPlayer.DisplayName) or "Player"
		MessageModule.New("Your trade request with " .. ignoredName .. " was ignored \240\159\152\148")
	end
end)

NetworkModule.Fired("Trade Errored"):Connect(function(erroredPlayer)
	local erroredName = (erroredPlayer and erroredPlayer.DisplayName) or "Player"
	MessageModule.New("Your trade with " .. erroredName .. " could not be created. Try again!")
end)

NetworkModule.Fired("Update Trade Invites Open"):Connect(function(newInvites)
	activeOpenInvites = newInvites
end)

NetworkModule.Fired("Trade Sent Chat Result"):Connect(function(success, reason)
	if success then
		MessageModule.New("\240\159\147\169 Trade request sent!")
		return
	end
	MessageModule.New(reason or "Failed to send trade request.")
end)

NetworkModule.Fired("Update Trade"):Connect(function(tradeId, updatedTradeData)
	if not isTradeActive then
		activeTradeId = tostring(tradeId)
		isTradeActive = true
		TradeScreenGui.Enabled = true
		if PlayerListFrame then
			PlayerListFrame.Visible = false
		end
		if TradeFrame then
			TradeFrame.Visible = true
			if TradeFrame:FindFirstChild("Processing") then
				TradeFrame.Processing.Visible = false
			end
		end
	elseif activeTradeId ~= tostring(tradeId) then
		return
	end

	activeTradeData = updatedTradeData
	if updatedTradeData and updatedTradeData.skinsData then
		_G.ActiveTradeSkinsData = updatedTradeData.skinsData
	end

	-- Instant render push without waiting
	task.spawn(function()
		if isTradeActive and activeTradeData then
			UpdateSkins()
			UpdateContracts()
			if TradeFrame.Client:FindFirstChild("Coins") then
				UpdateCoins()
			end
			UpdateInterface()
		end
	end)
end)

-- Main GUI update loop
coroutine.wrap(function()
	while true do
		VariablesModule.Trading = isTradeActive
		TradeFrame.Visible = isTradeActive

		local isHistoryOpen = false
		local historyPanel = MainFrame:FindFirstChild("TradingHistory")
		local viewPanel = MainFrame:FindFirstChild("TradeView")
		if (historyPanel and historyPanel.Visible) or (viewPanel and viewPanel.Visible) then
			isHistoryOpen = true
		end

		PlayerListFrame.Visible = (not isTradeActive) and not isHistoryOpen
		if isTradeActive then
			UpdateSkins()
			UpdateContracts()
			if TradeFrame.Client:FindFirstChild("Coins") then
				UpdateCoins()
			end
			UpdateInterface()
		elseif TradeScreenGui.Enabled and PlayerListFrame.Visible then
			RenderPlayerList()
		end
		RunService.Heartbeat:Wait()
	end
end)()

coroutine.wrap(function()
	while true do
		if isTradeActive and activeTradeId then
			-- Safety-net poll only. Version-guarded so a stale snapshot (request
			-- fired before a newer "Update Trade" push landed) can never
			-- overwrite fresher state and cause flicker.
			local callOk, polledTrade = pcall(NetworkModule.Invoke, "Get Trade", activeTradeId)
			if callOk and polledTrade then
				local currentVersion = (activeTradeData and activeTradeData.version) or 0
				if (polledTrade.version or 0) >= currentVersion then
					activeTradeData = polledTrade
					if polledTrade.skinsData then
						_G.ActiveTradeSkinsData = polledTrade.skinsData
					end
				end
			end
		end
		task.wait(2)
	end
end)()

coroutine.wrap(function()
	while true do
		if not isTradeActive then
			activeOpenInvites = NetworkModule.Invoke("Get Invites Open") or activeOpenInvites
		end
		task.wait(4)
	end
end)()

if TradeBottomFrame then
	local gridBtn = TradeBottomFrame:FindFirstChild("Grid")
	if gridBtn then
		GUIFXModule.Tooltip(gridBtn, "Toggle Grid View")
		GUIFXModule.ButtonFX(gridBtn)
	end
end

local playerListSearchInput = PlayerListFrame.Bottom:FindFirstChild("Search") and PlayerListFrame.Bottom.Search:FindFirstChild("Query")
if playerListSearchInput then
	playerListSearchInput:GetPropertyChangedSignal("Text"):Connect(function()
		RenderPlayerList()
	end)
end

local tradeSearchInput = getTradeSearchInput()
if tradeSearchInput then
	tradeSearchInput:GetPropertyChangedSignal("Text"):Connect(function()
		if isTradeActive then
			UpdateSkins()
		end
	end)
end

GUIFXModule.ButtonFX(PlayerListFrame.Close)
GUIFXModule.ButtonFX(TradeFrame.Buttons.Ready)
GUIFXModule.ButtonFX(TradeFrame.Buttons.Cancel)
GUIFXModule.ButtonFX(TradeFrame.Chat)
GUIFXModule.ButtonFX(TradeFrame.ChatOverlay.Footer.Send)

-- Console Controls
local function updateTradeConsoleButtons()
	local isGamepad = UserInputService:GetGamepadConnected(Enum.UserInputType.Gamepad1)
		or (UserInputService:GetLastInputType() == Enum.UserInputType.Gamepad1)

	local clientFrame = TradeFrame:FindFirstChild("Client")
	if clientFrame then
		local currencyFrame = clientFrame:FindFirstChild("Diamonds")
			or clientFrame:FindFirstChild("Coins")
			or clientFrame:FindFirstChild("Currency")
		if currencyFrame then
			local addBtn = currencyFrame:FindFirstChild("Add")
			local minusBtn = currencyFrame:FindFirstChild("Minus")
			if addBtn then
				addBtn.Visible = isGamepad
			end
			if minusBtn then
				minusBtn.Visible = isGamepad
			end
		end
	end

	local buttonsFrame = TradeFrame:FindFirstChild("Buttons")
	if buttonsFrame then
		local cancelKey = buttonsFrame:FindFirstChild("Cancel")
			and (buttonsFrame.Cancel:FindFirstChild("ButtonKeybind") or (buttonsFrame.Cancel:FindFirstChild("Frame") and buttonsFrame.Cancel.Frame:FindFirstChild("ButtonKeybind")))
		local readyKey = buttonsFrame:FindFirstChild("Ready")
			and (buttonsFrame.Ready:FindFirstChild("ButtonKeybind") or (buttonsFrame.Ready:FindFirstChild("Frame") and buttonsFrame.Ready.Frame:FindFirstChild("ButtonKeybind")))
		if cancelKey then
			cancelKey.Visible = isGamepad
		end
		if readyKey then
			readyKey.Visible = isGamepad
		end
	end
end

updateTradeConsoleButtons()
UserInputService.GamepadConnected:Connect(updateTradeConsoleButtons)
UserInputService.GamepadDisconnected:Connect(updateTradeConsoleButtons)
UserInputService.LastInputTypeChanged:Connect(updateTradeConsoleButtons)
