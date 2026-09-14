--[[
	© DestructionSimulator [2025]
	UIStrokeScaler — Scales UIStrokes exclusively for 2D ScreenGui elements in PlayerGui (StarterGui).
	Explicitly ignores BillboardGuis and SurfaceGuis to keep 3D interactive billboards exact.
]]--

local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local isTouchMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local MULTIPLIER = isTouchMobile and 1.0 or 1.5

local baseThicknessMap = setmetatable({}, { __mode = "k" })

local function scaleUIStroke(uiStroke)
	if not uiStroke or not uiStroke:IsA("UIStroke") then return end
	
	-- EXPLICITLY IGNORE BillboardGui and SurfaceGui (3D world & interactive billboards)
	if uiStroke:FindFirstAncestorOfClass("BillboardGui") or uiStroke:FindFirstAncestorOfClass("SurfaceGui") then
		return
	end
	
	-- Strictly scale only 2D elements inside ScreenGuis in PlayerGui
	if not uiStroke:IsDescendantOf(PlayerGui) then return end
	if not uiStroke:FindFirstAncestorOfClass("ScreenGui") then return end

	local original = uiStroke:GetAttribute("OriginalThickness") or baseThicknessMap[uiStroke]
	if original == nil then
		original = uiStroke.Thickness
		uiStroke:SetAttribute("OriginalThickness", original)
		baseThicknessMap[uiStroke] = original
	end
	
	local targetThickness = math.max(1, math.round(original * MULTIPLIER))
	if uiStroke.Thickness ~= targetThickness then
		uiStroke.Thickness = targetThickness
	end
end

-- Strictly apply to 2D ScreenGuis inside PlayerGui
for _, desc in ipairs(PlayerGui:GetDescendants()) do
	if desc:IsA("UIStroke") then
		scaleUIStroke(desc)
	end
end

PlayerGui.DescendantAdded:Connect(function(desc)
	if desc:IsA("UIStroke") then
		task.defer(scaleUIStroke, desc)
	end
end)
