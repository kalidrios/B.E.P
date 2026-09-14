--[[
	AdminHelpController.local.luau — Client-side Admin Console & Notification Toast Controller
	Handles:
	1. Toast notifications on top of the screen whenever an admin command succeeds or fails.
	2. F4 keybind and '/e help' or '/help' popup window listing all admin commands with live search,
	   descriptions, arguments, and quick-execute command runner.
]]--

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local TextChatService = game:GetService("TextChatService")

local LocalPlayer = Players.LocalPlayer
local playerGui = LocalPlayer:WaitForChild("PlayerGui")

local RemotesFolder = workspace:WaitForChild("__THINGS"):WaitForChild("__REMOTES")
local NotificationEvent = RemotesFolder:WaitForChild("NotificationEvent")
local OpenAdminHelpEvent = RemotesFolder:WaitForChild("OpenAdminHelp")
local AdminCommandInvokeRemote = RemotesFolder:WaitForChild("AdminCommandInvoke")
local GetAdminCommandsRemote = RemotesFolder:WaitForChild("GetAdminCommands")
local IsAdminRemote = RemotesFolder:WaitForChild("IsAdmin")

-- Create Toast ScreenGui
local ToastScreenGui = Instance.new("ScreenGui")
ToastScreenGui.Name = "AdminToastGui"
ToastScreenGui.ResetOnSpawn = false
ToastScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ToastScreenGui.DisplayOrder = 1000
ToastScreenGui.Parent = playerGui

local toastContainer = Instance.new("Frame")
toastContainer.Name = "ToastContainer"
toastContainer.BackgroundTransparency = 1
toastContainer.Size = UDim2.new(1, 0, 0, 300)
toastContainer.Position = UDim2.new(0, 0, 0, 20)
toastContainer.Parent = ToastScreenGui

local UIListLayout = Instance.new("UIListLayout")
UIListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
UIListLayout.VerticalAlignment = Enum.VerticalAlignment.Top
UIListLayout.Padding = UDim.new(0, 8)
UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
UIListLayout.Parent = toastContainer

-- Toast Notification Display Function
local function showToast(message, isSuccess)
	if isSuccess == nil then
		isSuccess = not string.find(string.lower(message), "fail") and not string.find(string.lower(message), "cannot")
	end

	local toast = Instance.new("Frame")
	toast.Name = "Toast"
	toast.Size = UDim2.new(0, 420, 0, 0)
	toast.BackgroundColor3 = isSuccess and Color3.fromRGB(16, 32, 24) or Color3.fromRGB(38, 16, 20)
	toast.BorderSizePixel = 0
	toast.ClipsDescendants = true

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = toast

	local stroke = Instance.new("UIStroke")
	stroke.Color = isSuccess and Color3.fromRGB(46, 204, 113) or Color3.fromRGB(231, 76, 60)
	stroke.Thickness = 1.5
	stroke.Parent = toast

	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.new(0, 30, 1, 0)
	icon.Position = UDim2.new(0, 10, 0, 0)
	icon.Font = Enum.Font.GothamBold
	icon.TextSize = 18
	icon.Text = isSuccess and "✅" or "⚠️"
	icon.TextColor3 = Color3.fromRGB(255, 255, 255)
	icon.Parent = toast

	local label = Instance.new("TextLabel")
	label.Name = "Message"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -55, 1, 0)
	label.Position = UDim2.new(0, 45, 0, 0)
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 14
	label.Text = tostring(message)
	label.TextColor3 = isSuccess and Color3.fromRGB(220, 255, 230) or Color3.fromRGB(255, 220, 225)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextWrapped = true
	label.Parent = toast

	toast.Parent = toastContainer

	-- Animate Open
	local targetHeight = 46
	local tweenIn = TweenService:Create(toast, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, 420, 0, targetHeight)
	})
	tweenIn:Play()

	-- Auto Dismiss
	task.delay(3.5, function()
		if toast and toast.Parent then
			local tweenOut = TweenService:Create(toast, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Size = UDim2.new(0, 420, 0, 0),
				BackgroundTransparency = 1
			})
			tweenOut:Play()
			tweenOut.Completed:Connect(function()
				toast:Destroy()
			end)
		end
	end)
end

NotificationEvent.OnClientEvent:Connect(showToast)

-- =========================================================================
-- Admin Help Window GUI (F4 / /e help)
-- =========================================================================

local AdminHelpScreenGui = Instance.new("ScreenGui")
AdminHelpScreenGui.Name = "AdminHelpGui"
AdminHelpScreenGui.ResetOnSpawn = false
AdminHelpScreenGui.DisplayOrder = 900
AdminHelpScreenGui.Enabled = false
AdminHelpScreenGui.Parent = playerGui

local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 680, 0, 520)
MainFrame.Position = UDim2.new(0.5, -340, 0.5, -260)
MainFrame.BackgroundColor3 = Color3.fromRGB(22, 25, 33)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = AdminHelpScreenGui

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 12)
mainCorner.Parent = MainFrame

local mainStroke = Instance.new("UIStroke")
mainStroke.Color = Color3.fromRGB(52, 152, 219)
mainStroke.Thickness = 2
mainStroke.Parent = MainFrame

-- Top Title Bar
local TopBar = Instance.new("Frame")
TopBar.Name = "TopBar"
TopBar.Size = UDim2.new(1, 0, 0, 45)
TopBar.BackgroundColor3 = Color3.fromRGB(30, 34, 45)
TopBar.BorderSizePixel = 0
TopBar.Parent = MainFrame

local topCorner = Instance.new("UICorner")
topCorner.CornerRadius = UDim.new(0, 12)
topCorner.Parent = TopBar

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Name = "Title"
TitleLabel.BackgroundTransparency = 1
TitleLabel.Size = UDim2.new(1, -60, 1, 0)
TitleLabel.Position = UDim2.new(0, 16, 0, 0)
TitleLabel.Font = Enum.Font.GothamBold
TitleLabel.TextSize = 16
TitleLabel.Text = "🛠️ ADMIN COMMANDS CONSOLE (F4)"
TitleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.Parent = TopBar

local CloseBtn = Instance.new("TextButton")
CloseBtn.Name = "CloseButton"
CloseBtn.Size = UDim2.new(0, 32, 0, 32)
CloseBtn.Position = UDim2.new(1, -40, 0, 6)
CloseBtn.BackgroundColor3 = Color3.fromRGB(231, 76, 60)
CloseBtn.Text = "✕"
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 16
CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseBtn.BorderSizePixel = 0
CloseBtn.Parent = TopBar

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 8)
closeCorner.Parent = CloseBtn

CloseBtn.Activated:Connect(function()
	AdminHelpScreenGui.Enabled = false
end)

-- Search Bar
local SearchBar = Instance.new("TextBox")
SearchBar.Name = "SearchBar"
SearchBar.Size = UDim2.new(1, -32, 0, 38)
SearchBar.Position = UDim2.new(0, 16, 0, 55)
SearchBar.BackgroundColor3 = Color3.fromRGB(30, 34, 45)
SearchBar.TextColor3 = Color3.fromRGB(255, 255, 255)
SearchBar.PlaceholderText = "🔍 Search commands (e.g. cash, speed, level, skin)..."
SearchBar.PlaceholderColor3 = Color3.fromRGB(140, 150, 170)
SearchBar.Font = Enum.Font.Gotham
SearchBar.TextSize = 14
SearchBar.ClearTextOnFocus = false
SearchBar.BorderSizePixel = 0
SearchBar.Parent = MainFrame

local searchCorner = Instance.new("UICorner")
searchCorner.CornerRadius = UDim.new(0, 8)
searchCorner.Parent = SearchBar

local searchPadding = Instance.new("UIPadding")
searchPadding.PaddingLeft = UDim.new(0, 12)
searchPadding.PaddingRight = UDim.new(0, 12)
searchPadding.Parent = SearchBar

-- Commands Scrolling Frame
local ScrollFrame = Instance.new("ScrollingFrame")
ScrollFrame.Name = "CommandList"
ScrollFrame.Size = UDim2.new(1, -32, 0, 340)
ScrollFrame.Position = UDim2.new(0, 16, 0, 102)
ScrollFrame.BackgroundColor3 = Color3.fromRGB(26, 29, 39)
ScrollFrame.BorderSizePixel = 0
ScrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
ScrollFrame.ScrollBarThickness = 6
ScrollFrame.ScrollBarImageColor3 = Color3.fromRGB(52, 152, 219)
ScrollFrame.Parent = MainFrame

local scrollCorner = Instance.new("UICorner")
scrollCorner.CornerRadius = UDim.new(0, 8)
scrollCorner.Parent = ScrollFrame

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 6)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = ScrollFrame

local listPadding = Instance.new("UIPadding")
listPadding.PaddingTop = UDim.new(0, 8)
listPadding.PaddingBottom = UDim.new(0, 8)
listPadding.PaddingLeft = UDim.new(0, 8)
listPadding.PaddingRight = UDim.new(0, 8)
listPadding.Parent = ScrollFrame

-- Bottom Command Runner Bar
local RunnerBar = Instance.new("Frame")
RunnerBar.Name = "RunnerBar"
RunnerBar.Size = UDim2.new(1, -32, 0, 48)
RunnerBar.Position = UDim2.new(0, 16, 1, -58)
RunnerBar.BackgroundColor3 = Color3.fromRGB(30, 34, 45)
RunnerBar.BorderSizePixel = 0
RunnerBar.Parent = MainFrame

local runnerCorner = Instance.new("UICorner")
runnerCorner.CornerRadius = UDim.new(0, 8)
runnerCorner.Parent = RunnerBar

local CommandInput = Instance.new("TextBox")
CommandInput.Name = "CommandInput"
CommandInput.Size = UDim2.new(1, -110, 1, 0)
CommandInput.Position = UDim2.new(0, 0, 0, 0)
CommandInput.BackgroundTransparency = 1
CommandInput.TextColor3 = Color3.fromRGB(255, 255, 255)
CommandInput.PlaceholderText = "Type command here (e.g. /e cash me 100000 or /e speed me 50)..."
CommandInput.PlaceholderColor3 = Color3.fromRGB(140, 150, 170)
CommandInput.Font = Enum.Font.Gotham
CommandInput.TextSize = 14
CommandInput.ClearTextOnFocus = false
CommandInput.Parent = RunnerBar

local inputPadding = Instance.new("UIPadding")
inputPadding.PaddingLeft = UDim.new(0, 12)
inputPadding.Parent = CommandInput

local RunButton = Instance.new("TextButton")
RunButton.Name = "RunButton"
RunButton.Size = UDim2.new(0, 95, 0, 34)
RunButton.Position = UDim2.new(1, -100, 0, 7)
RunButton.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
RunButton.Text = "▶ RUN"
RunButton.Font = Enum.Font.GothamBold
RunButton.TextSize = 14
RunButton.TextColor3 = Color3.fromRGB(255, 255, 255)
RunButton.BorderSizePixel = 0
RunButton.Parent = RunnerBar

local runCorner = Instance.new("UICorner")
runCorner.CornerRadius = UDim.new(0, 6)
runCorner.Parent = RunButton

local function executeEnteredCommand()
	local text = CommandInput.Text
	if text and text ~= "" then
		local success, result = AdminCommandInvokeRemote:InvokeServer(text)
		if not success and result then
			showToast(tostring(result), false)
		end
		CommandInput.Text = ""
	end
end

RunButton.Activated:Connect(executeEnteredCommand)
CommandInput.FocusLost:Connect(function(enterPressed)
	if enterPressed then
		executeEnteredCommand()
	end
end)

-- Populate Commands List
local cachedCommands = {}

local function renderCommandList(filter)
	filter = filter and string.lower(filter) or ""
	for _, child in ipairs(ScrollFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local count = 0
	for _, cmd in ipairs(cachedCommands) do
		local matches = (filter == "")
			or string.find(string.lower(cmd.cmd), filter)
			or string.find(string.lower(cmd.desc or ""), filter)

		if not matches and cmd.aliases then
			for _, alias in ipairs(cmd.aliases) do
				if string.find(string.lower(alias), filter) then
					matches = true
					break
				end
			end
		end

		if matches then
			count = count + 1
			local card = Instance.new("Frame")
			card.Name = "Cmd_" .. cmd.cmd
			card.Size = UDim2.new(1, 0, 0, 62)
			card.BackgroundColor3 = Color3.fromRGB(35, 40, 52)
			card.BorderSizePixel = 0
			card.Parent = ScrollFrame

			local cardCorner = Instance.new("UICorner")
			cardCorner.CornerRadius = UDim.new(0, 6)
			cardCorner.Parent = card

			local cmdBadge = Instance.new("TextLabel")
			cmdBadge.Name = "CmdBadge"
			cmdBadge.BackgroundTransparency = 1
			cmdBadge.Size = UDim2.new(1, -120, 0, 24)
			cmdBadge.Position = UDim2.new(0, 10, 0, 6)
			cmdBadge.Font = Enum.Font.GothamBold
			cmdBadge.TextSize = 14
			cmdBadge.TextColor3 = Color3.fromRGB(52, 152, 219)
			cmdBadge.TextXAlignment = Enum.TextXAlignment.Left

			local argsStr = ""
			if cmd.args and #cmd.args > 0 then
				for _, arg in ipairs(cmd.args) do
					argsStr = argsStr .. " <" .. tostring(arg) .. ">"
				end
			end
			cmdBadge.Text = "/e " .. cmd.cmd .. argsStr
			cmdBadge.Parent = card

			local descLabel = Instance.new("TextLabel")
			descLabel.Name = "Desc"
			descLabel.BackgroundTransparency = 1
			descLabel.Size = UDim2.new(1, -120, 0, 24)
			descLabel.Position = UDim2.new(0, 10, 0, 30)
			descLabel.Font = Enum.Font.Gotham
			descLabel.TextSize = 12
			descLabel.TextColor3 = Color3.fromRGB(180, 190, 205)
			descLabel.TextXAlignment = Enum.TextXAlignment.Left
			descLabel.Text = cmd.desc or ""
			descLabel.Parent = card

			local fillBtn = Instance.new("TextButton")
			fillBtn.Name = "FillBtn"
			fillBtn.Size = UDim2.new(0, 90, 0, 34)
			fillBtn.Position = UDim2.new(1, -100, 0, 14)
			fillBtn.BackgroundColor3 = Color3.fromRGB(41, 128, 185)
			fillBtn.Text = "Use / Fill"
			fillBtn.Font = Enum.Font.GothamBold
			fillBtn.TextSize = 12
			fillBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
			fillBtn.BorderSizePixel = 0
			fillBtn.Parent = card

			local fillCorner = Instance.new("UICorner")
			fillCorner.CornerRadius = UDim.new(0, 6)
			fillCorner.Parent = fillBtn

			fillBtn.Activated:Connect(function()
				local defaultSample = "/e " .. cmd.cmd .. " me"
				if cmd.cmd == "cash" then defaultSample = "/e cash me 100000"
				elseif cmd.cmd == "contracts" then defaultSample = "/e contracts me 10000"
				elseif cmd.cmd == "levelup" or cmd.cmd == "level" then defaultSample = "/e levelup me 5"
				elseif cmd.cmd == "speed" then defaultSample = "/e speed me 50"
				elseif cmd.cmd == "jump" then defaultSample = "/e jump me 70"
				elseif cmd.cmd == "rebirth" then defaultSample = "/e rebirth me 1"
				elseif cmd.cmd == "world" then defaultSample = "/e world me Magic"
				elseif cmd.cmd == "blocks" then defaultSample = "/e blocks me 50"
				elseif cmd.cmd == "maxblocks" then defaultSample = "/e maxblocks me 500"
				elseif cmd.cmd == "help" then defaultSample = "/e help"
				end
				CommandInput.Text = defaultSample
				CommandInput:CaptureFocus()
			end)
		end
	end

	ScrollFrame.CanvasSize = UDim2.new(0, 0, 0, count * 68 + 16)
end

SearchBar:GetPropertyChangedSignal("Text"):Connect(function()
	renderCommandList(SearchBar.Text)
end)

local function toggleAdminHelp()
	local isAdmin = IsAdminRemote:InvokeServer()
	if not isAdmin then
		showToast("⚠️ You do not have admin permissions.", false)
		return
	end

	AdminHelpScreenGui.Enabled = not AdminHelpScreenGui.Enabled
	if AdminHelpScreenGui.Enabled then
		if #cachedCommands == 0 then
			cachedCommands = GetAdminCommandsRemote:InvokeServer() or {}
		end
		renderCommandList(SearchBar.Text)
	end
end

OpenAdminHelpEvent.OnClientEvent:Connect(function()
	toggleAdminHelp()
end)

-- Keybind F4 toggle
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.F4 then
		toggleAdminHelp()
	end
end)
