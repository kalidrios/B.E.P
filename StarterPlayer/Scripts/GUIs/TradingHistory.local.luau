--[[
	TradingHistory.local.luau — Client-side Trading History and Rating Controller for Destruction Simulator
	Handles displaying past trade logs, ratings (thumbs up / down), trade review viewer, and trade statistics.
]]--

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Library = require(ReplicatedStorage:WaitForChild("Library"))

local loadStartTime = tick()
while not Library.Loaded do
	RunService.Heartbeat:Wait()
	if tick() - loadStartTime > 30 then
		warn("Library.Loaded never became true after 30s. TradingHistory script continuing anyway.")
		break
	end
end

local LocalPlayer = Players.LocalPlayer
local playerGui = LocalPlayer:WaitForChild("PlayerGui", 30)
if not playerGui then
	warn("PlayerGui not found after 30 seconds. Trading History script will not run.")
	return
end

local TradeScreenGui = playerGui:WaitForChild("Trade", 30) or playerGui:WaitForChild("Trading", 30) or playerGui:WaitForChild("Trade")
local MainFrame = TradeScreenGui:WaitForChild("Frame")

local TradingHistoryPanel = MainFrame:WaitForChild("TradingHistory")
local TradeViewPanel = MainFrame:WaitForChild("TradeView")
local PlayerListPanel = MainFrame:WaitForChild("PlayerList")
local ActiveTradePanel = MainFrame:WaitForChild("Trade")

local SaveModule = Library.Save
local FunctionsModule = Library.Functions
local NetworkModule = Library.Network
local MessageModule = Library.Message
local SignalModule = Library.Signal
local GUIFXModule = Library.GUIFX
local AudioModule = Library.Audio
local SharedModule = Library.Shared
local SkinUIModule = Library.SkinUI
local WindowManager = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Client"):WaitForChild("UIFramework"):WaitForChild("WindowManager"))

local randomGenerator = Random.new()
local isActionDebounce = false
local currentSearchFilter = ""
local cachedUserProfiles = {}

-- Helper: Computes trade rating score and formatted label
function GetTradeRating(targetPlayer)
	local playerSave = SaveModule.Get(targetPlayer, true)
	if not playerSave then
		return -1, "(Unrated)"
	end
	assert(playerSave)

	local positiveCount = 0
	local negativeCount = 0

	if playerSave.TradeHistory2 then
		local evaluatedUsers = {}
		for historyIndex = #playerSave.TradeHistory2, 1, -1 do
			local tradeEntry = playerSave.TradeHistory2[historyIndex]
			if tradeEntry.or_ ~= nil and not evaluatedUsers[tradeEntry.u] then
				evaluatedUsers[tradeEntry.u] = true
				if tradeEntry.or_ then
					positiveCount = positiveCount + 1
				else
					negativeCount = negativeCount + 1
				end
			end
		end
	end

	if positiveCount + negativeCount < SharedModule.TradeRatingRequirement then
		return 0, "(Unrated)"
	end

	local ratingScore = math.round(positiveCount * 9 / (positiveCount + negativeCount) * 10) / 10 + 1
	return ratingScore, string.format("%0.1f", ratingScore) .. "/10 Rating"
end

-- Helper: Formats timestamp difference to human readable time
function GetStringTime(timestamp)
	local timeElapsed = workspace:GetServerTimeNow() - timestamp
	return (timeElapsed <= 120) and "Just now" or (FunctionsModule.TimeString(timeElapsed) .. " ago")
end

-- Helper: Finds a specific trade by timestamp inside history list
function GetTrade(targetTimestamp, historyList)
	if not historyList then return nil end
	local targetStr = tostring(targetTimestamp)
	for _, tradeEntry in ipairs(historyList) do
		if tostring(tradeEntry.ts) == targetStr then
			return tradeEntry
		end
	end
	return nil
end

-- Helper: Formats textual summary of items and currency exchanged
function GetTradeDescription(tradeEntry, partnerUsername)
	local prefix = "Traded "
	local clientSkinCount = tradeEntry.p and #tradeEntry.p or (tradeEntry.pn or 0)
	local clientContracts = tradeEntry.d or 0
	local clientCash = tradeEntry.tk or 0

	local partnerSkinCount = tradeEntry.op and #tradeEntry.op or (tradeEntry.opn or 0)
	local partnerContracts = tradeEntry.od or 0
	local partnerCash = tradeEntry.otk or 0

	local clientSummary = ""
	local hasClientOffer = false

	if clientSkinCount > 0 then
		clientSummary = FunctionsModule.NumberShorten(clientSkinCount) .. (clientSkinCount == 1 and " Skin" or " Skins")
		hasClientOffer = true
	end
	if clientContracts > 0 then
		if hasClientOffer then
			clientSummary = clientSummary .. " & "
		end
		clientSummary = clientSummary .. FunctionsModule.NumberShorten(clientContracts) .. " Contracts"
		hasClientOffer = true
	end
	if clientCash > 0 then
		if hasClientOffer then
			clientSummary = clientSummary .. " & "
		end
		clientSummary = clientSummary .. FunctionsModule.NumberShorten(clientCash) .. " Cash"
		hasClientOffer = true
	end
	if not hasClientOffer then
		clientSummary = "nothing"
	end

	local partnerSummary = ""
	local hasPartnerOffer = false

	if partnerSkinCount > 0 then
		partnerSummary = FunctionsModule.NumberShorten(partnerSkinCount) .. (partnerSkinCount == 1 and " Skin" or " Skins")
		hasPartnerOffer = true
	end
	if partnerContracts > 0 then
		if hasPartnerOffer then
			partnerSummary = partnerSummary .. " & "
		end
		partnerSummary = partnerSummary .. FunctionsModule.NumberShorten(partnerContracts) .. " Contracts"
		hasPartnerOffer = true
	end
	if partnerCash > 0 then
		if hasPartnerOffer then
			partnerSummary = partnerSummary .. " & "
		end
		partnerSummary = partnerSummary .. FunctionsModule.NumberShorten(partnerCash) .. " Cash"
		hasPartnerOffer = true
	end
	if not hasPartnerOffer then
		partnerSummary = nil
	end

	local fullDescription = prefix .. clientSummary
	if not partnerSummary then
		return fullDescription .. " to " .. partnerUsername
	end
	return fullDescription .. " for " .. partnerUsername .. "'s " .. partnerSummary
end

-- Asynchronously fetches partner name/avatar and populates history row
function UpdateTradeDescription(tradeEntry, descriptionLabel, avatarImageLabel)
	local partnerUserId = tradeEntry.u
	if not cachedUserProfiles[partnerUserId] then
		descriptionLabel.Text = GetTradeDescription(tradeEntry, "Loading...")
		task.spawn(function()
			local success, profileData = pcall(function()
				local username = FunctionsModule.UserIdToUsername(partnerUserId)
				local avatarThumb = Players:GetUserThumbnailAsync(
					partnerUserId,
					Enum.ThumbnailType.HeadShot,
					Enum.ThumbnailSize.Size180x180
				)
				local userProfile = {
					Name = username,
					Avatar = avatarThumb,
				}
				cachedUserProfiles[partnerUserId] = userProfile
				return userProfile
			end)
			if not success or not profileData then
				return
			end
			descriptionLabel.Text = GetTradeDescription(tradeEntry, profileData.Name)
			avatarImageLabel.Image = profileData.Avatar
		end)
		return
	end
	descriptionLabel.Text = GetTradeDescription(tradeEntry, cachedUserProfiles[partnerUserId].Name)
	avatarImageLabel.Image = cachedUserProfiles[partnerUserId].Avatar
end

-- Updates positive/negative rating icons on a history card
function UpdateRating(tradeEntry, historyCard)
	if tradeEntry.r == true then
		historyCard.Positive.Button.Image = "rbxassetid://12047990832"
		historyCard.Negative.Button.HoverImage = ""
		return
	end
	if tradeEntry.r == false then
		historyCard.Negative.Button.Image = "rbxassetid://12065403063"
		historyCard.Positive.Button.HoverImage = ""
	end
end

-- Animates feedback rotation and text fade when user clicks thumbs up/down
function AnimateThumb(thumbContainer)
	local spinTweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0)
	local spinTween = TweenService:Create(thumbContainer.Button, spinTweenInfo, { Rotation = 360 })
	spinTween:Play()

	local textLabel = thumbContainer:FindFirstChild("TextLabel")
	if textLabel then
		local textFadeInInfo = TweenInfo.new(0.15, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0)
		local textFadeIn = TweenService:Create(textLabel, textFadeInInfo, { TextTransparency = 0 })
		textFadeIn:Play()

		local stroke = textLabel:FindFirstChildOfClass("UIStroke")
		if stroke then
			local strokeFadeInInfo = TweenInfo.new(0.15, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0)
			local strokeFadeIn = TweenService:Create(stroke, strokeFadeInInfo, { Transparency = 0 })
			strokeFadeIn:Play()

			strokeFadeIn.Completed:Connect(function()
				local strokeFadeOutInfo = TweenInfo.new(0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, 0)
				local strokeFadeOut = TweenService:Create(stroke, strokeFadeOutInfo, { Transparency = 1 })
				strokeFadeOut:Play()
			end)
		end

		textFadeIn.Completed:Connect(function()
			local textFadeOutInfo = TweenInfo.new(0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, 0)
			local textFadeOut = TweenService:Create(textLabel, textFadeOutInfo, { TextTransparency = 1 })
			textFadeOut:Play()
		end)
	end
end

function UpdateScrolling()
	local historyContainer = TradingHistoryPanel.Main.History
	local layout = historyContainer:FindFirstChildOfClass("UIListLayout")
	local padding = historyContainer:FindFirstChildOfClass("UIPadding")
	if layout then
		historyContainer.CanvasSize = UDim2.new(
			0,
			0,
			0,
			layout.AbsoluteContentSize.Y + (padding and (padding.PaddingTop.Offset + padding.PaddingBottom.Offset) or 0)
		)
	end
end

function UpdateSkinsScaling()
	for offerIndex = 1, 2 do
		local offerGrid = (offerIndex == 1) and TradeViewPanel.Client.Offer or TradeViewPanel.Player.Offer
		local gridLayout = offerGrid:FindFirstChildOfClass("UIGridLayout")
		local padding = offerGrid:FindFirstChildOfClass("UIPadding")
		if gridLayout then
			local resolutionScale = FunctionsModule.ResolutionScale()
			local columns = (resolutionScale <= 0.5) and 2 or ((resolutionScale <= 1.1) and 3 or 4)
			gridLayout.CellPadding = UDim2.new(0, 20, 0, 20)

			local paddingLeft = padding and padding.PaddingLeft.Offset or 0
			local paddingRight = padding and padding.PaddingRight.Offset or 0
			local cellDimension = (offerGrid.AbsoluteSize.X - offerGrid.ScrollBarThickness - paddingLeft - paddingRight) / columns
				- gridLayout.CellPadding.X.Offset
			gridLayout.CellSize = UDim2.new(0, cellDimension, 0, cellDimension)
			gridLayout:ApplyLayout()
			offerGrid.CanvasSize = UDim2.new(0, gridLayout.AbsoluteContentSize.X, 0, gridLayout.AbsoluteContentSize.Y + 30)
		end
	end
end

-- Displays detailed view of a historical trade
function UpdateView(tradeEntry)
	if not tradeEntry.p or not tradeEntry.op then
		return
	end

	for _, child in pairs(TradeViewPanel.Client.Offer:GetChildren()) do
		if child:IsA("GuiObject") and child.Name ~= "UIGridLayout" and child.Name ~= "UIListLayout" and child.Name ~= "UIPadding" then
			child:Destroy()
		end
	end
	for _, child in pairs(TradeViewPanel.Player.Offer:GetChildren()) do
		if child:IsA("GuiObject") and child.Name ~= "UIGridLayout" and child.Name ~= "UIListLayout" and child.Name ~= "UIPadding" then
			child:Destroy()
		end
	end

	local function getOfferTemplate()
		local assets = Library.Assets or (ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets)
		local ui = assets and assets:FindFirstChild("UI")
		local inv = ui and ui:FindFirstChild("Inventory")
		if inv then
			return inv:FindFirstChild("Offer") or inv:FindFirstChild("SkinsTemplate") or inv:FindFirstChild("Skin") or inv:FindFirstChild("TypesTemplate")
		end
		return nil
	end

	local offerTemplate = getOfferTemplate()

	local function createOfferSlot(skinData, isOther)
		local slot
		if offerTemplate then
			slot = offerTemplate:Clone()
		else
			slot = Instance.new("ImageButton")
			slot.Size = UDim2.new(0, 80, 0, 80)
			slot.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
			local corner = Instance.new("UICorner", slot)
			corner.CornerRadius = UDim.new(0, 8)
			local icon = Instance.new("ImageLabel", slot)
			icon.Name = "SkinIcon"
			icon.Size = UDim2.new(0.75, 0, 0.75, 0)
			icon.Position = UDim2.new(0.5, 0, 0.45, 0)
			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.BackgroundTransparency = 1
			local lvl = Instance.new("TextLabel", slot)
			lvl.Name = "Level"
			lvl.Size = UDim2.new(1, 0, 0.25, 0)
			lvl.Position = UDim2.new(0, 0, 0.75, 0)
			lvl.BackgroundTransparency = 1
			lvl.TextColor3 = Color3.new(1, 1, 1)
			lvl.TextScaled = true
			lvl.Font = Enum.Font.GothamBold
		end
		if slot:IsA("TextButton") then
			slot.Text = ""
		end
		slot.Visible = true
		SkinUIModule.Create(slot, skinData, isOther)
		return slot
	end

	for _, skinItem in ipairs(tradeEntry.p or {}) do
		local slot = createOfferSlot(skinItem, false)
		slot.Parent = TradeViewPanel.Client.Offer
	end
	for _, skinItem in ipairs(tradeEntry.op or {}) do
		local slot = createOfferSlot(skinItem, true)
		slot.Parent = TradeViewPanel.Player.Offer
	end

	TradeViewPanel.Client.Contracts.Amount.Text = FunctionsModule.Commas(tradeEntry.d or 0)
	TradeViewPanel.Player.Contracts.Amount.Text = FunctionsModule.Commas(tradeEntry.od or 0)

	if TradeViewPanel.Client:FindFirstChild("Coins") then
		TradeViewPanel.Client.Coins.Amount.Text = FunctionsModule.Commas(tradeEntry.tk or 0)
	end
	if TradeViewPanel.Player:FindFirstChild("Coins") then
		TradeViewPanel.Player.Coins.Amount.Text = FunctionsModule.Commas(tradeEntry.otk or 0)
	end

	local partnerProfile = cachedUserProfiles[tradeEntry.u]
	TradeViewPanel.Player.Title.Text = partnerProfile and (partnerProfile.Name .. "'s Offer") or "Their Offer"
	UpdateSkinsScaling()
end

function ShowView()
	TradingHistoryPanel.Visible = false
	TradeViewPanel.Visible = true
end

-- Renders the list of trade logs
function UpdateHistory()
	local localPlayerSave = SaveModule.Get(nil, true)
	if not localPlayerSave then
		return
	end

	local searchPattern = FunctionsModule.RegexEscape(
		string.lower(tostring(TradingHistoryPanel.Bottom.Search.Query.Text))
	)
	local isSearchActive = (searchPattern ~= nil and searchPattern ~= "")

	local historyContainer = TradingHistoryPanel.Main.History
	local historyList = localPlayerSave.TradeHistory2 or {}

	local assets = Library.Assets or (ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets)
	local assetsUI = assets and assets:FindFirstChild("UI")
	local replicatedHistoryFolder = assetsUI
		and (
			assetsUI:FindFirstChild("TradingHIstory")
			or assetsUI:FindFirstChild("TradingHistory")
			or assetsUI:FindFirstChild("Trading")
		)

	local historyLogTemplate = (replicatedHistoryFolder and replicatedHistoryFolder:FindFirstChild("HistoryLog"))
		or historyContainer:FindFirstChild("HistoryLog")
	local noHistoryPlaceholder = (replicatedHistoryFolder and replicatedHistoryFolder:FindFirstChild("NoHistory"))
		or historyContainer:FindFirstChild("NoHistory")

	-- Clean obsolete rows
	for _, child in pairs(historyContainer:GetChildren()) do
		if child:GetAttribute("Template") then
			child.Visible = false
			continue
		end
		if not child:IsA("Frame") or GetTrade(child.Name, historyList) then
			continue
		end
		child:Destroy()
	end

	if #historyList == 0 then
		if noHistoryPlaceholder then
			noHistoryPlaceholder.Visible = true
		end
		historyContainer.Visible = true
		local _, ratingText = GetTradeRating(LocalPlayer)
		TradingHistoryPanel.Rating.Text = ratingText
		UpdateScrolling()
		return
	end

	if noHistoryPlaceholder then
		noHistoryPlaceholder.Visible = false
	end

	for orderIndex, tradeEntry in ipairs(historyList) do
		local cardName = tostring(tradeEntry.ts)
		local existingCard = historyContainer:FindFirstChild(cardName)
		if existingCard then
			UpdateRating(tradeEntry, existingCard)
			existingCard.LayoutOrder = 99999 - orderIndex
			if isSearchActive then
				local partnerProfile = cachedUserProfiles[tradeEntry.u]
				existingCard.Visible = partnerProfile and (string.find(string.lower(partnerProfile.Name), searchPattern) ~= nil)
			else
				existingCard.Visible = true
			end
			continue
		end

		if not historyLogTemplate then
			continue
		end

		local logCard = historyLogTemplate:Clone()
		logCard.Name = cardName
		logCard.Visible = true
		logCard.LogMessage.Log.Player.Image = ""
		UpdateTradeDescription(tradeEntry, logCard.LogMessage.Log.Description.Description, logCard.LogMessage.Log.Player)
		logCard.LogMessage.Log.Timestamp.Text = GetStringTime(tradeEntry.ts)
		logCard.LogMessage.Log.Description.Description.Text = ""
		UpdateRating(tradeEntry, logCard)

		GUIFXModule.ButtonFX(logCard.Positive.Button)
		GUIFXModule.ButtonFX(logCard.Negative.Button)

		if tradeEntry.r == nil then
			logCard.Positive.Button.Activated:Connect(function()
				if not isActionDebounce then
					isActionDebounce = true
					local callOk, invokeResult, invokeErr = pcall(NetworkModule.Invoke, "Rate Trade", tradeEntry.u, tradeEntry.ts, tradeEntry.t, true)
					local success, err = invokeResult, invokeErr
					if not callOk then
						success, err = false, "Network error, please try again."
					end
					if not success then
						MessageModule.New(err or "Something went wrong.")
					else
						tradeEntry.r = true
						UpdateRating(tradeEntry, logCard)
						AnimateThumb(logCard.Positive)
					end
					isActionDebounce = false
				end
			end)

			logCard.Negative.Button.Activated:Connect(function()
				if not isActionDebounce then
					isActionDebounce = true
					local callOk, invokeResult, invokeErr = pcall(NetworkModule.Invoke, "Rate Trade", tradeEntry.u, tradeEntry.ts, tradeEntry.t, false)
					local success, err = invokeResult, invokeErr
					if not callOk then
						success, err = false, "Network error, please try again."
					end
					if not success then
						MessageModule.New(err or "Something went wrong.")
					else
						tradeEntry.r = false
						UpdateRating(tradeEntry, logCard)
						AnimateThumb(logCard.Negative)
					end
					isActionDebounce = false
				end
			end)
		end

		GUIFXModule.ButtonFX(logCard.LogMessage.Log)
		logCard.LogMessage.Log.Activated:Connect(function()
			local fullTrade = GetTrade(tradeEntry.ts, historyList)
			if not fullTrade or not fullTrade.p or not fullTrade.op then
				MessageModule.New("You can no longer view this trade!")
				return
			end
			UpdateView(fullTrade)
			ShowView()
		end)

		logCard:SetAttribute("Template", false)
		logCard.LayoutOrder = 99999 - orderIndex
		logCard.Parent = historyContainer

		if isSearchActive then
			local partnerProfile = cachedUserProfiles[tradeEntry.u]
			logCard.Visible = partnerProfile and (string.find(string.lower(partnerProfile.Name), searchPattern) ~= nil)
		else
			logCard.Visible = true
		end
	end

	local _, ratingSummary = GetTradeRating(LocalPlayer)
	TradingHistoryPanel.Rating.Text = ratingSummary
	UpdateScrolling()
end

-- Event Listeners
TradingHistoryPanel.Bottom.Search.Query:GetPropertyChangedSignal("Text"):Connect(function()
	UpdateHistory()
end)

TradingHistoryPanel.Close.Activated:Connect(function()
	if not isActionDebounce then
		isActionDebounce = true
		TradingHistoryPanel.Visible = false
		TradeViewPanel.Visible = false
		TradeScreenGui.Enabled = false
		WindowManager.Close()
		isActionDebounce = false
	end
end)

TradingHistoryPanel.Bottom.Back.Activated:Connect(function()
	if not isActionDebounce then
		isActionDebounce = true
		SignalModule.Fire("Open Trade List")
		isActionDebounce = false
	end
end)

TradeViewPanel.Button.Back.Activated:Connect(function()
	if not isActionDebounce then
		isActionDebounce = true
		SignalModule.Fire("Open Trading History")
		isActionDebounce = false
	end
end)

SignalModule.Fired("Stat Changed"):Connect(function(statName)
	if statName == "TradeHistory2" or statName == "TradingHistory2" then
		UpdateHistory()
	end
end)

SignalModule.Fired("Open Trading History"):Connect(function()
	TradingHistoryPanel.Bottom.Search.Query.Text = ""
	UpdateHistory()
	PlayerListPanel.Visible = false
	ActiveTradePanel.Visible = false
	TradingHistoryPanel.Visible = true
	TradeViewPanel.Visible = false
	TradeScreenGui.Enabled = true
end)

GUIFXModule.ButtonFX(TradingHistoryPanel.Close)
GUIFXModule.ButtonFX(TradingHistoryPanel.Bottom.Back)
GUIFXModule.ButtonFX(TradeViewPanel.Button.Back)
GUIFXModule.Tooltip(
	TradingHistoryPanel.Rating,
	"Requires " .. SharedModule.TradeRatingRequirement .. " ratings to be rated"
)
