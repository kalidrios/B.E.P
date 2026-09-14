local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SkinUI = {}

local Save = nil
local SkinMath = nil
local Directory = nil

local Assets = ReplicatedStorage:WaitForChild("Assets")
local skinConfigCache = {}

local function getSkinConfig(category, modelName, skinID)
	local cacheKey = string.lower(category or "") .. "_" .. string.lower(modelName or "") .. "_" .. string.lower(skinID or "")
	if skinConfigCache[cacheKey] ~= nil then
		return skinConfigCache[cacheKey] or nil
	end

	if not Directory then
		pcall(function()
			Directory = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Directory"))
		end)
	end
	if Directory and Directory.Skins then
		for catName, catTable in pairs(Directory.Skins) do
			if string.lower(catName) == string.lower(category or "") then
				for modName, modTable in pairs(catTable) do
					if string.lower(modName) == string.lower(modelName or "") then
						if modTable[skinID] then
							skinConfigCache[cacheKey] = modTable[skinID]
							return modTable[skinID]
						end
						for sName, sConfig in pairs(modTable) do
							if string.lower(sName) == string.lower(skinID or "") then
								skinConfigCache[cacheKey] = sConfig
								return sConfig
							end
						end
					end
				end
			end
		end
	end
	skinConfigCache[cacheKey] = false
	return nil
end

local ViewportUtil = nil

local function getModel(category, name)
	if not ViewportUtil then
		ViewportUtil = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Client"):WaitForChild("ViewportUtil"))
	end
	return ViewportUtil.GetModel(category, name)
end

local function createViewport(model, parent, category)
	if not ViewportUtil then
		ViewportUtil = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Client"):WaitForChild("ViewportUtil"))
	end
	return ViewportUtil.Create(model, parent, category)
end

function SkinUI.Create(template, skinUid, isOther)
	if not Save then
		Save = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Client"):WaitForChild("Save"))
	end
	if not SkinMath then
		SkinMath = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Modules"):WaitForChild("SkinMath"))
	end

	if template:IsA("TextButton") then
		template.Text = ""
	end

	local deleteOverlay = template:FindFirstChild("Delete")
	if deleteOverlay then
		deleteOverlay.Visible = false
	end

	local skinData = nil
	if type(skinUid) == "table" then
		skinData = skinUid
	else
		local targetUid = tostring(skinUid)
		if _G.ActiveTradeSkinsData and _G.ActiveTradeSkinsData[targetUid] then
			skinData = _G.ActiveTradeSkinsData[targetUid]
		end

		if not skinData then
			for _, player in ipairs(game.Players:GetPlayers()) do
				local playerProfile = Save.Get(player)
				if playerProfile and playerProfile.Skins then
					for _, skin in ipairs(playerProfile.Skins) do
						if tostring(skin.uid) == targetUid or tostring(skin.UID) == targetUid then
							skinData = skin
							break
						end
					end
				end
				if skinData then break end
			end
		end
	end
	
	if not skinData then return end
	
	local label = template:FindFirstChild("Level") or template:FindFirstChild("Name") or template:FindFirstChild("Condition")
	if label then
		local floatVal = skinData.Float or skinData.fl or 0.5
		local skinID = skinData.ID or skinData.id or "Skin"
		label.Text = SkinMath.GetConditionShort(floatVal) .. " " .. skinID
	end

	local category = skinData.Category or skinData.category or "Launcher"
	local modelName = skinData.ItemName or skinData.itemName or "Rocket"
	local skinID = skinData.ID or skinData.id or "Default"

	-- Look for ViewportContainer / GearIcon / SkinIcon / Icon
	local iconContainer = template:FindFirstChild("GearIcon")
		or template:FindFirstChild("ViewportContainer")
		or template:FindFirstChild("SkinIcon")
		or template:FindFirstChild("Icon")
		or template:FindFirstChild("PetIcon")

	if iconContainer then
		for _, child in ipairs(iconContainer:GetChildren()) do
			child:Destroy()
		end

		local baseModel = getModel(category, modelName)
		local previewModel = baseModel:Clone()

		local skinConfig = getSkinConfig(category, modelName, skinID)
		if skinConfig and skinConfig.textureId then
			for _, part in ipairs(previewModel:GetDescendants()) do
				if part:IsA("MeshPart") then
					part.TextureID = "rbxassetid://" .. skinConfig.textureId
				elseif part:IsA("SpecialMesh") then
					part.TextureId = "rbxassetid://" .. skinConfig.textureId
				elseif part:IsA("Texture") or part:IsA("Decal") then
					part.Texture = "rbxassetid://" .. skinConfig.textureId
				end
			end
		end

		createViewport(previewModel, iconContainer, category)
		previewModel:Destroy()
	end
	
	local lockedIcon = template:FindFirstChild("Locked")
	if lockedIcon then
		lockedIcon.Visible = (skinData.Locked == true or skinData.l == true)
	end
	
	local hcLabel = template:FindFirstChild("HC")
	if hcLabel then hcLabel.Visible = false end

	-- Apply Rarity UIGradient
	local rarityName = "Basic"
	local skinCfg = getSkinConfig(category, modelName, skinID)
	if skinCfg and skinCfg.rarity then
		rarityName = skinCfg.rarity
	end

	local rarityGradContainer = template:FindFirstChild("RarityGradient") or template:FindFirstChild("Rarity") or template
	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	local uiFolder = assetsFolder and assetsFolder:FindFirstChild("UI")
	local gradientFolder = uiFolder and uiFolder:FindFirstChild("Gradient")
	local raritysFolder = (gradientFolder and gradientFolder:FindFirstChild("Raritys"))
		or (uiFolder and uiFolder:FindFirstChild("Raritys"))
		or (assetsFolder and assetsFolder:FindFirstChild("Raritys"))

	if raritysFolder and rarityGradContainer then
		local grad = raritysFolder:FindFirstChild(rarityName)
			or (rarityName == "Covert" and raritysFolder:FindFirstChild("Convert"))
			or (rarityName == "Convert" and raritysFolder:FindFirstChild("Covert"))
		if grad and grad:IsA("UIGradient") then
			for _, child in ipairs(rarityGradContainer:GetChildren()) do
				if child:IsA("UIGradient") then
					child:Destroy()
				end
			end
			local gradClone = grad:Clone()
			gradClone.Parent = rarityGradContainer
		end
	end
end

return SkinUI
