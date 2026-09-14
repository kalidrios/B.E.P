local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WindowManager = require(
	ReplicatedStorage:WaitForChild("Library")
		:WaitForChild("Client")
		:WaitForChild("UIFramework")
		:WaitForChild("WindowManager")
)
local Audio = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Audio"))

local messageGui = playerGui:WaitForChild("Message", 15) or playerGui:WaitForChild("Message")
local frame = messageGui:WaitForChild("Frame")
local titleLabel = frame:WaitForChild("Title")
local descLabel = frame:WaitForChild("Desc")
local closeBtn = frame:WaitForChild("Close")

local okBtn = frame:WaitForChild("Ok")
local cancelBtn = frame:WaitForChild("Cancel")
local yesBtn = frame:WaitForChild("Yes")
local noBtn = frame:WaitForChild("No")

-- Hide message by default
messageGui.Enabled = false

_G.MessageSoundId = 134369274766781

local function playMessageSound()
	if Audio and Audio.Play then
		Audio.Play(_G.MessageSoundId, playerGui, 1, 1.0)
	end
end

local activeConnections = {}

local Message = {}
_G.Message = Message

local savedImportantWindow = nil

local function closeMessage()
	for _, conn in ipairs(activeConnections) do
		conn:Disconnect()
	end
	activeConnections = {}
	messageGui.Enabled = false

	if WindowManager._savedWindow then
		local saved = WindowManager._savedWindow
		WindowManager._savedWindow = nil
		WindowManager.ActiveWindow = saved
		saved.Enabled = true
		_G.ImportantWindow = saved
		savedImportantWindow = nil
	elseif savedImportantWindow then
		-- Guard against destroyed GUIs (e.g. after respawn/world transition)
		if savedImportantWindow.Parent then
			_G.ImportantWindow = savedImportantWindow
			if savedImportantWindow:IsA("ScreenGui") then
				savedImportantWindow.Enabled = true
			elseif savedImportantWindow:IsA("GuiObject") then
				savedImportantWindow.Visible = true
			end
		end
		savedImportantWindow = nil
	end
end

function Message.New(text, isConfirm, title)
	-- Save active window in WindowManager
	if WindowManager.ActiveWindow and WindowManager.ActiveWindow ~= messageGui then
		WindowManager._savedWindow = WindowManager.ActiveWindow
		WindowManager.ActiveWindow.Enabled = false
		WindowManager.ActiveWindow = nil
	end

	-- Save active window in _G.ImportantWindow. Only save it if it is ACTUALLY
	-- visible right now: _G.ImportantWindow goes stale (it keeps pointing at
	-- e.g. the Inventory after the player closed it manually), and blindly
	-- saving/restoring it makes windows reopen "by themselves" every time a
	-- message is answered.
	if _G.ImportantWindow and _G.ImportantWindow ~= messageGui then
		local important = _G.ImportantWindow
		local isOpen = (important:IsA("ScreenGui") and important.Enabled)
			or (important:IsA("GuiObject") and important.Visible)
		if isOpen then
			savedImportantWindow = important
			if important:IsA("ScreenGui") then
				important.Enabled = false
			else
				important.Visible = false
			end
		else
			_G.ImportantWindow = nil -- stale reference, drop it
		end
	end
	_G.ImportantWindow = messageGui

	-- Reset the message GUI state from any previous message. This must NOT be
	-- closeMessage(): that also restores the saved window, which here is the
	-- very window (e.g. Inventory) we just hid above — the modal would show
	-- with the Inventory still enabled behind it. Restoring only happens when
	-- the player answers this message (makeChoice -> closeMessage).
	for _, conn in ipairs(activeConnections) do
		conn:Disconnect()
	end
	activeConnections = {}
	messageGui.Enabled = false

	titleLabel.Text = title or "Notice"
	descLabel.Text = text
	for _, child in ipairs(descLabel:GetChildren()) do
		if child:IsA("TextLabel") then
			child.Text = text
		end
	end

	if isConfirm then
		yesBtn.Visible = true
		noBtn.Visible = true
		okBtn.Visible = false
		cancelBtn.Visible = false
	else
		yesBtn.Visible = false
		noBtn.Visible = false
		okBtn.Visible = true
		cancelBtn.Visible = false
	end

	playMessageSound()
	messageGui.Enabled = true

	local choice = nil
	local event = Instance.new("BindableEvent")

	local function makeChoice(value)
		choice = value
		closeMessage()
		event:Fire(value)
	end

	table.insert(
		activeConnections,
		yesBtn.Activated:Connect(function()
			makeChoice(true)
		end)
	)
	table.insert(
		activeConnections,
		okBtn.Activated:Connect(function()
			makeChoice(true)
		end)
	)
	table.insert(
		activeConnections,
		noBtn.Activated:Connect(function()
			makeChoice(false)
		end)
	)
	table.insert(
		activeConnections,
		cancelBtn.Activated:Connect(function()
			makeChoice(false)
		end)
	)
	table.insert(
		activeConnections,
		closeBtn.Activated:Connect(function()
			makeChoice(false)
		end)
	)

	local result = event.Event:Wait()
	event:Destroy()
	return result
end

-- ============================================================
-- Bag-full notification — big modal via Message.New.
-- Intentionally loud: when the bag hits capacity the player gets the
-- full Message dialog with the option to teleport straight to the sell
-- area (_G.TeleportToSell, defined in UIConnect). Spawned in its own
-- thread because Message.New yields until the player answers, and the
-- isBagFull latch re-arms only after the bag drops below capacity.
-- ============================================================
local isBagFull = false

local function checkBagFull()
	local blocks = player:GetAttribute("Blocks") or 0
	local DefaultStats = require(
		game:GetService("ReplicatedStorage")
			:WaitForChild("Library")
			:WaitForChild("Modules")
			:WaitForChild("DefaultStats")
	)
	local maxBlocks = player:GetAttribute("MaxBlocks")
		or ((DefaultStats and DefaultStats.Storage and DefaultStats.Storage.Max) or 100)

	if blocks >= maxBlocks then
		if not isBagFull then
			isBagFull = true
			task.spawn(function()
				if not _G.Message then
					return
				end
				local answer = _G.Message.New("Your bag is full! Teleport to the sell area?", true, "Inventory Full")
				if answer and _G.TeleportToSell then
					_G.TeleportToSell()
				end
			end)
		end
	else
		isBagFull = false
	end
end

player.AttributeChanged:Connect(function(attr)
	if attr == "Blocks" or attr == "MaxBlocks" then
		checkBagFull()
	end
end)

-- Initial check
task.wait(1)
checkBagFull()
