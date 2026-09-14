--!strict
--[[
	© DestructionSimulator [2025]
	Library/Client/ViewportUtil — Single Source of Truth for 3D model asset lookups and ViewportFrame rendering.
]]--

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Assets = ReplicatedStorage:WaitForChild("Assets")

local ViewportUtil = {}

--- Retrieves the 3D model template for a given item category and name
function ViewportUtil.GetModel(category: string, name: string): Instance?
	local launcherFolder = Assets:FindFirstChild("Launcher")
		or Assets:FindFirstChild("Launchers")
		or Assets:FindFirstChild("Weapons")
		or Assets:FindFirstChild("Tools")
	local bombFolder = Assets:FindFirstChild("Bomb") or Assets:FindFirstChild("Bombs")
	local bpFolder = Assets:FindFirstChild("Backpack")
		or Assets:FindFirstChild("Backpacks")
		or Assets:FindFirstChild("BackPack")

	if category == "Launcher" then
		if launcherFolder and launcherFolder:FindFirstChild(name) then
			return launcherFolder:FindFirstChild(name)
		end
		if Assets:FindFirstChild(name) then
			return Assets:FindFirstChild(name)
		end
	elseif category == "Bomb" then
		if bombFolder and bombFolder:FindFirstChild(name) then
			return bombFolder:FindFirstChild(name)
		end
		if Assets:FindFirstChild(name) then
			return Assets:FindFirstChild(name)
		end
	elseif category == "BackPack" then
		if bpFolder and bpFolder:FindFirstChild(name) then
			return bpFolder:FindFirstChild(name)
		end
		if Assets:FindFirstChild(name) then
			return Assets:FindFirstChild(name)
		end
		local bShop = workspace:FindFirstChild("BackpackShop")
		if bShop and bShop:FindFirstChild(name) then
			return bShop:FindFirstChild(name)
		end
	end

	-- Safe fallback model
	local m = Instance.new("Model")
	m.Name = name
	return m
end

--- Creates a standardized, perfectly framed ViewportFrame with auto-calibrated camera and positioning
--- Returns the cloned model inside the ViewportFrame
function ViewportUtil.Create(model: Instance, parent: Instance, category: string?): Model?
	if not model or not parent then return nil end

	local vpf = Instance.new("ViewportFrame")
	vpf.Size = UDim2.fromScale(1, 1)
	vpf.BackgroundTransparency = 1
	vpf.Parent = parent

	local clone = model:Clone()
	local preview = clone:FindFirstChild("PREVIEW")

	local center, size
	if preview then
		local previewCenter = preview.Position
		local previewMaxDim = math.max(preview.Size.X, preview.Size.Y, preview.Size.Z)
		local maxDist = previewMaxDim * 3

		local minPos = Vector3.new(math.huge, math.huge, math.huge)
		local maxPos = Vector3.new(-math.huge, -math.huge, -math.huge)
		local foundPart = false

		for _, part in ipairs(clone:GetDescendants()) do
			if part:IsA("BasePart") then
				local dist = (part.Position - previewCenter).Magnitude
				if dist <= maxDist then
					foundPart = true
					minPos = Vector3.new(
						math.min(minPos.X, part.Position.X - part.Size.X / 2),
						math.min(minPos.Y, part.Position.Y - part.Size.Y / 2),
						math.min(minPos.Z, part.Position.Z - part.Size.Z / 2)
					)
					maxPos = Vector3.new(
						math.max(maxPos.X, part.Position.X + part.Size.X / 2),
						math.max(maxPos.Y, part.Position.Y + part.Size.Y / 2),
						math.max(maxPos.Z, part.Position.Z + part.Size.Z / 2)
					)
				end
			end
		end

		if foundPart then
			size = maxPos - minPos
			center = (minPos + maxPos) / 2
		else
			size = preview.Size
			center = preview.Position
		end
	else
		local bboxCFrame, bboxSize = clone:GetBoundingBox()
		center = bboxCFrame.Position
		size = bboxSize
	end

	local offset = Vector3.new(0, 10000, 0) - center
	for _, part in ipairs(clone:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CFrame = part.CFrame + offset
		end
	end
	clone.Parent = vpf

	-- Setup camera
	local camAngle = math.rad(225)
	local cosA = math.abs(math.cos(camAngle))
	local sinA = math.abs(math.sin(camAngle))
	local apparentWidth = size.X * cosA + size.Z * sinA
	local apparentHeight = size.Y
	local maxApparent = math.max(apparentWidth, apparentHeight)

	local function setupCamera(aspectRatio)
		local fov = math.rad(70)
		local halfFovTan = math.tan(fov / 2)

		local camDistance
		if aspectRatio >= 1 then
			camDistance = (maxApparent / 2) / halfFovTan
		else
			camDistance = (maxApparent / 2) / (halfFovTan * aspectRatio)
		end

		if category == "Launcher" then
			camDistance = camDistance * 1.55
		elseif category == "BackPack" then
			camDistance = camDistance * 1.8
		else
			camDistance = camDistance * 1.25
		end

		local cam = Instance.new("Camera")
		cam.CameraType = Enum.CameraType.Scriptable
		cam.FieldOfView = 70
		local angleY = math.rad(225)
		if category == "BackPack" then
			angleY = angleY + math.rad(180)
		end
		cam.CFrame = CFrame.new(Vector3.new(0, 10000, 0)) * CFrame.Angles(0, angleY, 0) * CFrame.new(0, 0, camDistance)
		vpf.CurrentCamera = cam
		cam.Parent = vpf
	end

	local absSize = parent.AbsoluteSize
	if absSize.X > 0 and absSize.Y > 0 then
		setupCamera(absSize.X / absSize.Y)
	else
		setupCamera(1.0)
		task.defer(function()
			if not vpf.Parent then
				return
			end
			local newSize = parent.AbsoluteSize
			if newSize.X > 0 and newSize.Y > 0 then
				local oldCam = vpf:FindFirstChildOfClass("Camera")
				if oldCam then
					oldCam:Destroy()
				end
				setupCamera(newSize.X / newSize.Y)
			end
		end)
	end

	return clone
end

return ViewportUtil
