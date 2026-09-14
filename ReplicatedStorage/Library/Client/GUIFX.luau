local TweenService = game:GetService("TweenService")

local GUIFX = {}
local connected = setmetatable({}, { __mode = "k" })

--[[
	DISABLED FUNCTION REASON:
	Dual sound feedback (Press down + Release up) was disabled to eliminate 
	audio clutter and repetitive noise across the user interface. 
	Only the single press-down sound trigger is kept active.

	-- Disabled dual-sound code:
	-- function GUIFX.PlayDualButtonSound(button)
	--     button.MouseButton1Down:Connect(function()
	--         Audio.Play("rbxassetid://9114223179", button, 1.0, 0.4)
	--     end)
	--     button.MouseButton1Up:Connect(function()
	--         Audio.Play("rbxassetid://9114223179", button, 0.85, 0.3)
	--     end)
	-- end
]]

function GUIFX.ButtonFX(button)
	if not button or connected[button] then
		return
	end

	connected[button] = true
	local originalSize = button.Size

	if button:IsA("GuiButton") then
		button.MouseEnter:Connect(function()
			TweenService:Create(button, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = UDim2.new(originalSize.X.Scale * 1.03, originalSize.X.Offset, originalSize.Y.Scale * 1.03, originalSize.Y.Offset),
			}):Play()
		end)

		button.MouseLeave:Connect(function()
			TweenService:Create(button, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = originalSize,
			}):Play()
		end)

		button.Activated:Connect(function()
			-- Single Touch Sound (Excludes Skip/Jump buttons)
			local btnName = string.lower(button.Name)
			if not string.find(btnName, "skip") and not string.find(btnName, "jump") then
				local success, Library = pcall(function() return require(game.ReplicatedStorage:WaitForChild("Library")) end)
				if success and Library and Library.Audio and Library.Audio.Play then
					Library.Audio.Play("rbxassetid://87485609714706", button, 1.0, 0.35)
				end
			end

			TweenService:Create(button, TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = UDim2.new(originalSize.X.Scale * 0.98, originalSize.X.Offset, originalSize.Y.Scale * 0.98, originalSize.Y.Offset),
			}):Play()
			task.delay(0.06, function()
				if button.Parent then
					TweenService:Create(button, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
						Size = originalSize,
					}):Play()
				end
			end)
		end)
	end
end

function GUIFX.FlashText(label)
	if not label or not label:IsA("TextLabel") and not label:IsA("TextBox") and not label:IsA("TextButton") then
		return
	end

	local originalColor = label.TextColor3
	label.TextColor3 = Color3.new(1, 1, 1)
	TweenService:Create(label, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TextColor3 = originalColor,
	}):Play()
end

function GUIFX.Tooltip(instance, text)
	if instance then
		instance:SetAttribute("Tooltip", text)
	end
end

return GUIFX
