--[[
	© DestructionSimulator [2025]
	Library/Client/GIF — SpriteSheet GIF Animator (IBS Parity)

	Plays animated sprite sheets on ImageLabels using ImageRectOffset and ImageRectSize.
	Supports frame dimensions, column/row grid, frame counts, loop speed, and cleanup cancellation.
]]--

local RunService = game:GetService("RunService")

local GIF = {}

function GIF.Create(imageLabel, frameDimensions, gridDimensions, totalFrames, duration, isLooping)
	if not imageLabel or not imageLabel:IsA("ImageLabel") then
		return function() end
	end

	local frameWidth = (frameDimensions and frameDimensions[1]) or 100
	local frameHeight = (frameDimensions and frameDimensions[2]) or 100
	local columns = (gridDimensions and gridDimensions[1]) or 5
	local rows = (gridDimensions and gridDimensions[2]) or 6
	totalFrames = totalFrames or (columns * rows)
	duration = duration or 0.65
	if isLooping == nil then
		isLooping = true
	end

	imageLabel.ImageRectSize = Vector2.new(frameWidth, frameHeight)
	imageLabel.ImageRectOffset = Vector2.new(0, 0)

	local isRunning = true
	local startTime = os.clock()
	local connection = nil

	connection = RunService.RenderStepped:Connect(function()
		if not isRunning or not imageLabel or not imageLabel.Parent then
			if connection then
				connection:Disconnect()
				connection = nil
			end
			return
		end

		local elapsed = os.clock() - startTime
		if not isLooping and elapsed >= duration then
			if connection then
				connection:Disconnect()
				connection = nil
			end
			return
		end

		local progress = (elapsed % duration) / duration
		local frameIndex = math.clamp(math.floor(progress * totalFrames), 0, totalFrames - 1)

		local col = frameIndex % columns
		local row = math.floor(frameIndex / columns)

		imageLabel.ImageRectOffset = Vector2.new(col * frameWidth, row * frameHeight)
	end)

	return function()
		isRunning = false
		if connection then
			connection:Disconnect()
			connection = nil
		end
	end
end

return GIF
