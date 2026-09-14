--[[
	© DestructionSimulator [2025]
	LeaderboardClient.local.luau
	Hooks up the Leaderboard world-surface buttons and fills the entries.
	Supports dynamic world swapping (Spawn, Magic, Space, etc.) without freezing.
	Ranks 1 to 100 with Podium colors: #1 Gold/Yellow, #2 Silver, #3 Bronze.
	Clean layout: only lists top 100 entries with "#<rank> @<user>".
]]--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local localPlayer = Players.LocalPlayer

local _L = require(ReplicatedStorage:WaitForChild("Library"))
while not _L.Loaded do
	task.wait(0.05)
end
local FormatNumber = _L.Functions.FormatNumber or require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Functions"):WaitForChild("FormatNumber"))

local SELECTED_COLOR = Color3.fromRGB(200, 200, 0)
local UNSELECTED_COLOR = Color3.fromRGB(0, 170, 0)
local MAX_ROWS = 100
local LOCAL_ROW_OFFSET = 61

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------
local selection = "Power" -- "Power" or "RAP"
local currentBoard = nil
local boardFrame = nil
local powerButtons = {}
local rapButtons = {}

local localBoard = nil
local localBoardFrame = nil
local localPlayerLabels = {}
local localValueLabels = {}
local isHooked = false

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
local function getViewerScore()
	if selection == "RAP" then
		return localPlayer:GetAttribute("SkinRAP") or 0
	end
	return localPlayer:GetAttribute("SkinPower")
		or localPlayer:GetAttribute("DestructiblesDestroyed")
		or localPlayer:GetAttribute("Blocks") or 0
end

local function updateViewerPanel()
	local cleanName = string.gsub(localPlayer.Name, "^@+", "")
	local formattedName = "@" .. cleanName
	for _, label in ipairs(localPlayerLabels) do
		if label and label.Parent then
			label.Text = formattedName
		end
	end
	for _, label in ipairs(localValueLabels) do
		if label and label.Parent then
			label.Text = FormatNumber(getViewerScore())
		end
	end
end

----------------------------------------------------------------------
-- Board discovery
----------------------------------------------------------------------
local function findBoardModels()
	local boards = {}
	local roots = { workspace }
	local map = workspace:FindFirstChild("__MAP")
	if map then table.insert(roots, 1, map) end

	for _, root in ipairs(roots) do
		for _, descendant in ipairs(root:GetDescendants()) do
			if (descendant.Name == "Leaderboard" or descendant.Name == "Leadboard" or descendant.Name == "Local Leaderboard")
				and (descendant:IsA("Model") or descendant:IsA("Folder")) then
				if not table.find(boards, descendant) then
					table.insert(boards, descendant)
				end
			end
		end
	end
	return boards
end

local function resolveClickable(holder)
	if not holder then return nil end
	if holder:IsA("GuiButton") then return holder end
	local inner = holder:FindFirstChild(holder.Name)
	if inner and inner:IsA("GuiButton") then return inner end
	return holder:FindFirstChildOfClass("TextButton") or holder:FindFirstChildOfClass("ImageButton")
end

local function applyTint(button, color)
	if not button then return end
	if button:IsA("ImageLabel") or button:IsA("ImageButton") then
		button.ImageColor3 = color
	end
	if button:IsA("GuiObject") then
		button.BackgroundColor3 = color
	end
end

----------------------------------------------------------------------
-- Row rendering
----------------------------------------------------------------------
local function setTextOn(row, names, value)
	for _, name in ipairs(names) do
		local label = row:FindFirstChild(name)
		if label and label:IsA("TextLabel") then
			label.Text = value
			return
		end
	end
	for _, name in ipairs(names) do
		local label = row:FindFirstChild(name, true)
		if label and (label:IsA("TextLabel") or label:IsA("TextButton") or label:IsA("TextBox")) then
			label.Text = value
			return
		end
	end
end

local function findTemplate(frame, which)
	local assetsUI = ReplicatedStorage:FindFirstChild("Assets")
		and ReplicatedStorage.Assets:FindFirstChild("UI")
	local boardsFolder = assetsUI and (assetsUI:FindFirstChild("Leadboards") or assetsUI:FindFirstChild("Leaderboards"))
	
	if which == "Local" or (frame and frame.Parent and frame.Parent.Parent and frame.Parent.Parent.Name == "Local Leaderboard") then
		if boardsFolder and boardsFolder:FindFirstChild("PlayerLocal") then
			return boardsFolder.PlayerLocal
		end
		if frame and frame:FindFirstChild("PlayerLocal") then
			return frame.PlayerLocal
		end
	end

	if boardsFolder and boardsFolder:FindFirstChild("PlayerGlobal") then
		return boardsFolder.PlayerGlobal
	end
	if frame and frame:FindFirstChild("PlayerGlobal") then
		return frame.PlayerGlobal
	end

	local names = { "TemplatePlayerGlobal", "PlayerGlobal", "TemplatePlayerLocal", "PlayerLocal", "Spot" }
	if boardsFolder then
		for _, name in ipairs(names) do
			local t = boardsFolder:FindFirstChild(name)
			if t then return t end
		end
	end
	for _, name in ipairs(names) do
		local t = frame:FindFirstChild(name)
		if t then return t end
	end
	return nil
end

local function clearClonedRows(frame)
	for _, child in ipairs(frame:GetChildren()) do
		if string.match(child.Name, "^PlayerGlobal_%d+$") or string.match(child.Name, "^LB_Row_%d+$") or string.match(child.Name, "^LB_Local_%d+$") then
			child:Destroy()
		end
	end
end

local function fillRow(row, rank, entry)
	local rawUsername = entry.username or (entry.player and entry.player.Name) or entry.name or "?"
	rawUsername = string.gsub(rawUsername, "^@+", "")
	local usernameFormatted = "@" .. rawUsername
	local value = entry.level or entry.value or entry.score or 0

	local rankLabel = row:FindFirstChild("Rank") or row:FindFirstChild("RankLabel") or row:FindFirstChild("Position")
	local playerLabel = row:FindFirstChild("Player") or row:FindFirstChild("Username") or row:FindFirstChild("Name")

	if rankLabel and rankLabel:IsA("TextLabel") then
		rankLabel.Text = "#" .. tostring(rank)
		if playerLabel and (playerLabel:IsA("TextLabel") or playerLabel:IsA("TextButton")) then
			playerLabel.Text = usernameFormatted
		end
	else
		if playerLabel and (playerLabel:IsA("TextLabel") or playerLabel:IsA("TextButton")) then
			playerLabel.Text = "#" .. tostring(rank) .. " " .. usernameFormatted
		end
	end

	if playerLabel and (playerLabel:IsA("TextLabel") or playerLabel:IsA("TextButton")) then
		-- Podium colors
		if rank == 1 then
			playerLabel.TextColor3 = Color3.fromRGB(255, 215, 0) -- Gold / Amarelo
		elseif rank == 2 then
			playerLabel.TextColor3 = Color3.fromRGB(205, 205, 205) -- Silver / Prata
		elseif rank == 3 then
			playerLabel.TextColor3 = Color3.fromRGB(205, 127, 50) -- Bronze / Bronze
		elseif rawUsername == localPlayer.Name then
			playerLabel.TextColor3 = Color3.fromRGB(103, 255, 103) -- Local player highlight
		else
			playerLabel.TextColor3 = Color3.fromRGB(121, 121, 121) -- Standard gray
		end
	end

	local valueLabel = row:FindFirstChild("Value") or row:FindFirstChild("Score") or row:FindFirstChild("Level")
	if valueLabel and (valueLabel:IsA("TextLabel") or valueLabel:IsA("TextButton")) then
		valueLabel.Text = FormatNumber(value)
	end
end

----------------------------------------------------------------------
-- Request & Render Logic
----------------------------------------------------------------------
local function refreshLocalBoard()
	if not localBoardFrame or not localBoardFrame:IsDescendantOf(workspace) then
		return
	end
	local template = findTemplate(localBoardFrame, "Local")
	if not template then return end

	local ok, list = pcall(function()
		return _L.Network.Invoke("Get Local Leaderboard", selection)
	end)
	if not ok or type(list) ~= "table" then return end

	clearClonedRows(localBoardFrame)
	local tPos = template.Position
	for i, entry in ipairs(list) do
		if i > MAX_ROWS then break end
		local clone = template:Clone()
		clone.Name = "LB_Local_" .. i
		clone.Visible = true
		clone.Position = UDim2.new(
			tPos.X.Scale,
			tPos.X.Offset,
			tPos.Y.Scale,
			tPos.Y.Offset + (LOCAL_ROW_OFFSET * (i - 1))
		)
		clone.Parent = localBoardFrame
		fillRow(clone, i, entry)
	end
end

local function requestList(which)
	if not boardFrame or not boardFrame:IsDescendantOf(workspace) then
		return
	end
	
	local ok, list = pcall(function()
		return _L.Network.Invoke("Get Global Leaderboard", which)
	end)
	if not ok or type(list) ~= "table" then
		return
	end

	local spotRows = {}
	local maxSpot = 0
	for _, child in ipairs(boardFrame:GetChildren()) do
		local n = string.match(child.Name, "^Spot(%d+)$")
		if n then
			local index = tonumber(n)
			spotRows[index] = child
			maxSpot = math.max(maxSpot, index)
		end
	end

	if maxSpot > 0 then
		for i = 1, maxSpot do
			local entry = list[i]
			local row = spotRows[i]
			if row then
				row.Visible = entry ~= nil
				if entry then
					fillRow(row, i, entry)
				end
			end
		end
		clearClonedRows(boardFrame)
		return
	end

	local template = findTemplate(boardFrame, "Global")
	if not template then return end
	clearClonedRows(boardFrame)
	local templatePosition = template.Position
	for i, entry in ipairs(list) do
		if i > MAX_ROWS then break end
		local clone = template:Clone()
		clone.Name = "LB_Row_" .. i
		clone.Visible = true
		clone.Position = UDim2.new(
			templatePosition.X.Scale,
			templatePosition.X.Offset,
			templatePosition.Y.Scale,
			templatePosition.Y.Offset + (LOCAL_ROW_OFFSET * (i - 1))
		)
		clone.LayoutOrder = i
		clone.Parent = boardFrame
		fillRow(clone, i, entry)
	end
end

local function setSelected(which)
	selection = which
	for _, btn in ipairs(powerButtons) do
		applyTint(btn, which == "Power" and SELECTED_COLOR or UNSELECTED_COLOR)
	end
	for _, btn in ipairs(rapButtons) do
		applyTint(btn, which == "RAP" and SELECTED_COLOR or UNSELECTED_COLOR)
	end

	-- Update PowerTitle and RAPTitle visibility on all leaderboard models
	local allModels = findBoardModels()
	for _, board in ipairs(allModels) do
		for _, descendant in ipairs(board:GetDescendants()) do
			if descendant.Name == "PowerTitle" then
				descendant.Visible = (which == "Power")
			elseif descendant.Name == "RAPTitle" then
				descendant.Visible = (which == "RAP")
			end
		end
	end

	updateViewerPanel()
	requestList(which)
	refreshLocalBoard()
end

----------------------------------------------------------------------
-- Hooking Boards
----------------------------------------------------------------------
local function resetHookState()
	isHooked = false
	boardFrame = nil
	currentBoard = nil
	localBoard = nil
	localBoardFrame = nil
	powerButtons = {}
	rapButtons = {}
	localPlayerLabels = {}
	localValueLabels = {}
end

local function hookAllBoards(force)
	if isHooked and not force then
		if boardFrame and boardFrame:IsDescendantOf(workspace) then
			return
		end
	end

	local allModels = findBoardModels()
	if #allModels == 0 then
		return
	end

	localPlayerLabels = {}
	localValueLabels = {}
	powerButtons = {}
	rapButtons = {}
	boardFrame = nil
	localBoardFrame = nil

	for _, board in ipairs(allModels) do
		-- 1. Spectator Panel (PlayerPart)
		for _, descendant in ipairs(board:GetDescendants()) do
			if descendant.Name == "PlayerPart" then
				for _, d in ipairs(descendant:GetDescendants()) do
					if d:IsA("TextLabel") or d:IsA("TextButton") then
						if d.Name == "Player" or d.Name == "Username" or d.Name == "Name" then
							table.insert(localPlayerLabels, d)
						elseif d.Name == "Value" or d.Name == "Score" then
							table.insert(localValueLabels, d)
						end
					end
				end
			end
		end

		-- 2. Main Interactive Leaderboard (with Power / RAP buttons)
		if board.Name == "Leaderboard" or board.Name == "Leadboard" then
			local guiPart = board:FindFirstChild("GuiPart")
			local sg = guiPart and guiPart:FindFirstChildOfClass("SurfaceGui")
			local frame = sg and sg:FindFirstChild("Frame")
			if frame then
				boardFrame = frame
				currentBoard = board
			end

			for _, descendant in ipairs(board:GetDescendants()) do
				if descendant.Name == "Power" then
					local btn = resolveClickable(descendant)
					if btn and not table.find(powerButtons, btn) then
						table.insert(powerButtons, btn)
						btn.Activated:Connect(function()
							setSelected("Power")
						end)
					end
				elseif descendant.Name == "RAP" then
					local btn = resolveClickable(descendant)
					if btn and not table.find(rapButtons, btn) then
						table.insert(rapButtons, btn)
						btn.Activated:Connect(function()
							setSelected("RAP")
						end)
					end
				end
			end
		end

		-- 3. Standalone Local Leaderboard (Server board GuiPart)
		if board.Name == "Local Leaderboard" or board.Name == "Leadboards" then
			local guiPart = board:FindFirstChild("GuiPart")
			local sg = guiPart and guiPart:FindFirstChildOfClass("SurfaceGui")
			local frame = sg and sg:FindFirstChild("Frame")
			if frame then
				localBoard = board
				localBoardFrame = frame
			end
		end
	end

	if #localPlayerLabels > 0 or #powerButtons > 0 or boardFrame ~= nil or localBoardFrame ~= nil then
		isHooked = true
	end

	updateViewerPanel()
	if boardFrame then
		requestList(selection)
	end
	if localBoardFrame then
		refreshLocalBoard()
	end
end

-- Initialize setup loop
task.spawn(function()
	while not isHooked do
		hookAllBoards()
		task.wait(1)
	end
end)

-- Periodically refresh data and ensure active boards stay hooked across world swaps
task.spawn(function()
	while true do
		task.wait(5)
		if not boardFrame or not boardFrame:IsDescendantOf(workspace) then
			hookAllBoards(true)
		end
		if boardFrame then
			requestList(selection)
		end
		if localBoardFrame then
			refreshLocalBoard()
		end
		updateViewerPanel()
	end
end)

-- World Switch listeners: seamlessly re-hook leaderboards when traveling between worlds
localPlayer:GetAttributeChangedSignal("World"):Connect(function()
	task.wait(1)
	resetHookState()
	hookAllBoards(true)
end)

local remotesFolder = workspace:FindFirstChild("__THINGS") and workspace.__THINGS:FindFirstChild("__REMOTES")
local worldSwitchedRemote = remotesFolder and remotesFolder:FindFirstChild("WorldSwitched")

if worldSwitchedRemote then
	worldSwitchedRemote.OnClientEvent:Connect(function()
		task.wait(1)
		resetHookState()
		hookAllBoards(true)
	end)
end

workspace.ChildAdded:Connect(function(child)
	if child.Name == "__MAP" then
		task.wait(1)
		resetHookState()
		hookAllBoards(true)
	end
end)
