--[[
	© DestructionSimulator [2025]
	ExclusiveShopService — Server-side handling of purchases from the ExclusiveShop.
	Provides remote functions for opening boxes and buying gamepass/upgrade DevProducts.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local Library = require(ReplicatedStorage:WaitForChild("Library"))
while not Library.IsLoaded() do
	task.wait()
end
local Saving = Library.Saving

local ProductsConfig = require(ReplicatedStorage:WaitForChild("Directory"):WaitForChild("Products"):WaitForChild("Products"))
local GamepassesConfig = require(ReplicatedStorage:WaitForChild("Directory"):WaitForChild("Gamepasses"):WaitForChild("Gamepasses"))
local Directory = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Directory"))

-- Hard cap on skins per player profile (inventory limit).
local MAX_SKINS = 100

----------------------------------------------------------------------
-- Remote Functions
----------------------------------------------------------------------
local RemotesFolder = workspace:WaitForChild("__THINGS"):WaitForChild("__REMOTES")

local buyBoxRemote = RemotesFolder:FindFirstChild("buybox") or Instance.new("RemoteFunction")
buyBoxRemote.Name = "buybox"
buyBoxRemote.Parent = RemotesFolder

local ShopConfig = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("ShopConfig"))

-- Helper to grant weapons
local function grantWeapon(profile, name, weaponType)
	local owned = false
	for _, weapon in ipairs(profile.Weapons or {}) do
		if weapon.ID == name then
			owned = true
			break
		end
	end
	if not owned then
		if not profile.Weapons then profile.Weapons = {} end
		table.insert(profile.Weapons, {
			ID = name,
			Type = weaponType,
			Float = math.random()
		})
	end
end

local function grantEliteBuildSkins(profile)
	if not profile.Skins then profile.Skins = {} end
	
	local function hasSkin(category, itemName, skinId)
		for _, skin in ipairs(profile.Skins) do
			if skin.Category == category and skin.ItemName == itemName and skin.ID == skinId then
				return true
			end
		end
		return false
	end
	
	-- Bypass MAX_SKINS check for paid Elite Pack Gamepass buyers: grant ALL missing Elite Build skins
	if ShopConfig.Launcher then
		for _, item in ipairs(ShopConfig.Launcher) do
			if not hasSkin("Launcher", item.Name, "Elite Build") then
				table.insert(profile.Skins, {
					UID = HttpService:GenerateGUID(false),
					ID = "Elite Build",
					Category = "Launcher",
					ItemName = item.Name,
					Float = 0.00
				})
			end
		end
	end
	
	if ShopConfig.Bomb then
		for _, item in ipairs(ShopConfig.Bomb) do
			if not hasSkin("Bomb", item.Name, "Elite Build") then
				table.insert(profile.Skins, {
					UID = HttpService:GenerateGUID(false),
					ID = "Elite Build",
					Category = "Bomb",
					ItemName = item.Name,
					Float = 0.00
				})
			end
		end
	end
end


local BOX_NAMES = {
	"Essential Core", "Essential Vanguard", "Essential Bastion",
	"Forge Core", "Forge Vanguard", "Forge Bastion",
	"Elite Core", "Elite Vanguard", "Elite Bastion"
}

local SKIN_RARITIES_MAP = {
	["Safari"] = "Basic",
	["Boreal Forest"] = "Basic",
	["Sand Dune"] = "IndustrialGrade",
	["Urban DDPTA"] = "MilSpec",
	["Neo Fade"] = "Restricted",
	["Pit Viber"] = "Legendary",
	["Gungnir"] = "Convert",
	["Elite Build"] = "Delux"
}

local BACKPACK_SKIN_NAMES = {
	"Safari", "Boreal Forest", "Sand Dune", "Urban DDPTA", "Neo Fade", "Pit Viber", "Gungnir"
}

local RARITY_COLORS = {
	Basic = Color3.fromRGB(140, 140, 140),
	IndustrialGrade = Color3.fromRGB(90, 150, 240),
	MilSpec = Color3.fromRGB(70, 70, 255),
	Restricted = Color3.fromRGB(180, 50, 255),
	Legendary = Color3.fromRGB(255, 50, 150),
	Convert = Color3.fromRGB(255, 50, 50),
	Delux = Color3.fromRGB(255, 215, 0),
	Special = Color3.fromRGB(255, 215, 0)
}

local BOX_ITEMS = {} -- boxName -> { WeaponSkins = { ... }, SpecialBackpacks = { ... } }

local function buildBoxPyramid(possibleSkins, rng)
	local byRarity = {
		Basic = {}, IndustrialGrade = {}, MilSpec = {},
		Restricted = {}, Legendary = {}, Convert = {}, Delux = {}
	}
	for _, skin in ipairs(possibleSkins) do
		table.insert(byRarity[skin.Rarity], skin)
	end
	
	for rarity, list in pairs(byRarity) do
		for i = #list, 2, -1 do
			local j = rng:NextInteger(1, i)
			list[i], list[j] = list[j], list[i]
		end
	end
	
	local selected = {}
	local function take(rarity, count)
		local list = byRarity[rarity]
		for i = 1, math.min(count, #list) do
			table.insert(selected, table.remove(list, 1))
		end
	end
	
	-- CS:GO Pyramid distribution: 5 Basic, 4 IndustrialGrade, 3 MilSpec, 2 Restricted, 1 Legendary/Convert/Delux
	take("Basic", 5)
	take("IndustrialGrade", 4)
	take("MilSpec", 3)
	take("Restricted", 2)
	
	if #byRarity.Convert > 0 then
		take("Convert", 1)
	elseif #byRarity.Delux > 0 then
		take("Delux", 1)
	else
		take("Legendary", 1)
	end
	
	local remainingRarities = { "Basic", "IndustrialGrade", "MilSpec", "Restricted", "Legendary", "Convert", "Delux" }
	while #selected < 15 do
		local added = false
		for _, rarity in ipairs(remainingRarities) do
			if #byRarity[rarity] > 0 then
				table.insert(selected, table.remove(byRarity[rarity], 1))
				added = true
				break
			end
		end
		if not added then break end
	end
	
	return selected
end

local function initializeBoxes()
	local rng = Random.new(12345)
	
	local allWeapons = {}
	for _, item in ipairs(ShopConfig.Launcher) do
		table.insert(allWeapons, { Category = "Launcher", Name = item.Name })
	end
	for _, item in ipairs(ShopConfig.Bomb) do
		table.insert(allWeapons, { Category = "Bomb", Name = item.Name })
	end
	
	for i = #allWeapons, 2, -1 do
		local j = rng:NextInteger(1, i)
		allWeapons[i], allWeapons[j] = allWeapons[j], allWeapons[i]
	end
	
	local allBackpacks = {}
	for _, bp in ipairs(ShopConfig.BackPack) do
		table.insert(allBackpacks, bp.Name)
	end
	
	for i = #allBackpacks, 2, -1 do
		local j = rng:NextInteger(1, i)
		allBackpacks[i], allBackpacks[j] = allBackpacks[j], allBackpacks[i]
	end
	
	for idx, boxName in ipairs(BOX_NAMES) do
		local weaponsCount = (idx <= 6) and 4 or 6
		local boxWeapons = {}
		for _ = 1, weaponsCount do
			if #allWeapons > 0 then
				table.insert(boxWeapons, table.remove(allWeapons, 1))
			end
		end
		
		local possibleSkins = {}
		for _, w in ipairs(boxWeapons) do
			for skinName, rarity in pairs(SKIN_RARITIES_MAP) do
				table.insert(possibleSkins, {
					ItemName = w.Name,
					Category = w.Category,
					ID = skinName,
					Rarity = rarity
				})
			end
		end
		
		local weaponSkins = buildBoxPyramid(possibleSkins, rng)
		
		local specialBps = {}
		local bp1 = allBackpacks[((idx-1)*2) % #allBackpacks + 1]
		local bp2 = allBackpacks[((idx-1)*2 + 1) % #allBackpacks + 1]
		table.insert(specialBps, bp1)
		table.insert(specialBps, bp2)
		
		BOX_ITEMS[boxName] = {
			WeaponSkins = weaponSkins,
			SpecialBackpacks = specialBps
		}
	end
end

-- Initialize the boxes pool statically on startup
initializeBoxes()

local function getCategoryWeights(boxName)
	local lucky = 1.0
	if string.find(boxName, "Forge") then
		lucky = 1.10
	elseif string.find(boxName, "Elite") then
		lucky = 1.25
	end
	
	return {
		Basic = 60 / (lucky ^ 0.5),
		IndustrialGrade = 20 / (lucky ^ 0.2),
		MilSpec = 12,
		Restricted = 5 * lucky,
		Legendary = 2 * lucky,
		Convert = 0.7 * lucky,
		Special = 0.3 * lucky
	}
end

local function rollRarity(weights)
	if not weights or type(weights) ~= "table" then
		return "Basic"
	end
	local totalWeight = 0
	for rarity, weight in pairs(weights) do
		totalWeight = totalWeight + (weight or 0)
	end
	if totalWeight <= 0 then return "Basic" end
	
	local roll = math.random() * totalWeight
	local current = 0
	for rarity, weight in pairs(weights) do
		current = current + (weight or 0)
		if roll <= current then
			return rarity
		end
	end
	return "Basic"
end

local function createItemSlot(item, container, layoutOrder)
	local newSlot = ReplicatedStorage:WaitForChild("Slot"):Clone()
	if item.Rarity == "Special" or item.ID == "Special Backpack" then
		newSlot.Text = "Special Backpack"
		newSlot.BackgroundColor3 = Color3.fromRGB(255, 215, 0)
	else
		newSlot.Text = item.ID
		newSlot.BackgroundColor3 = RARITY_COLORS[item.Rarity] or Color3.fromRGB(140, 140, 140)
	end
	newSlot.LayoutOrder = layoutOrder
	newSlot.Visible = true
	newSlot.Parent = container
	return newSlot
end

-- Rate limiter for BuyBox (prevents race condition exploit)
local buyBoxCooldowns = {}
local buyBoxProcessing = {}

-- Buy Box invoke handler
buyBoxRemote.OnServerInvoke = function(player, boxName)
	-- P0 FIX: Input type validation
	if type(boxName) ~= "string" then
		return false, "Invalid request."
	end

	-- P0 FIX: Rate limiting to prevent race condition exploit
	local now = os.clock()
	if buyBoxCooldowns[player] and now < buyBoxCooldowns[player] then
		return false, "You are opening boxes too fast!"
	end
	if buyBoxProcessing[player] then
		return false, "A box is already being opened!"
	end
	buyBoxCooldowns[player] = now + 1.0
	buyBoxProcessing[player] = true

	local profile = Saving.GetPlayerData(player)
	if not profile then
		buyBoxProcessing[player] = nil
		return false, "Player data not loaded."
	end

	local boxCfg = Directory.Boxes and Directory.Boxes[boxName]
	if not boxCfg then
		buyBoxProcessing[player] = nil
		return false, "Box configuration not found."
	end
	local cost = boxCfg.price or 9999

	-- Check Contracts
	local currentContracts = profile.Contracts or 0
	if currentContracts < cost then
		buyBoxProcessing[player] = nil
		return false, "Not enough Contracts!"
	end

	local boxContent = BOX_ITEMS[boxName]
	if not boxContent then
		buyBoxProcessing[player] = nil
		return false, "Box rewards not initialized."
	end

	-- Skin inventory limit: reject BEFORE charging so nothing is deducted
	if profile.Skins and #profile.Skins >= MAX_SKINS then
		buyBoxProcessing[player] = nil
		return false, "Your skin inventory is full (" .. MAX_SKINS .. " skins)!"
	end

	-- Deduct Contracts atomically (after all validations pass)
	profile.Contracts = currentContracts - cost
	if not profile.Currency then
		profile.Currency = {}
	end
	profile.Currency.Contracts = profile.Contracts

	-- Roll reward
	local pool = {}
	if boxCfg and boxCfg.skins then
		for skinName, val in pairs(boxCfg.skins) do
			if skinName == "Special Backpack" or skinName == "BackPack" then
				local chance = (type(val) == "number") and val or 1
				table.insert(pool, {
					ItemName = "Special Backpack",
					ID = "Special Backpack",
					Category = "BackPack",
					Chance = chance,
					Rarity = "Special"
				})
			elseif type(val) == "table" then
				for itemName, chance in pairs(val) do
					local category = "Launcher"
					local bombFolder = ReplicatedStorage:FindFirstChild("Directory") and ReplicatedStorage.Directory:FindFirstChild("Bomb")
					if bombFolder and bombFolder:FindFirstChild(itemName) then
						category = "Bomb"
					end

					local skinConfig = nil
					local skinsFolder = ReplicatedStorage:FindFirstChild("Directory") and ReplicatedStorage.Directory:FindFirstChild("Skins")
					local catFolder = skinsFolder and skinsFolder:FindFirstChild(category)
					local itemFolder = catFolder and catFolder:FindFirstChild(itemName)
					local skinFile = itemFolder and itemFolder:FindFirstChild(skinName)
					if skinFile then
						pcall(function() skinConfig = require(skinFile) end)
					end

					table.insert(pool, {
						ItemName = itemName,
						ID = skinName,
						Category = category,
						Chance = (type(chance) == "number") and chance or 1,
						Rarity = skinConfig and skinConfig.rarity or "Basic"
					})
				end
			end
		end
	end

	local wonItem = nil
	if #pool > 0 then
		local totalWeight = 0
		for _, entry in ipairs(pool) do
			totalWeight = totalWeight + (entry.Chance or 1)
		end
		local roll = math.random() * totalWeight
		local accumulated = 0
		local selected = pool[1]
		for _, entry in ipairs(pool) do
			accumulated = accumulated + (entry.Chance or 1)
			if roll <= accumulated then
				selected = entry
				break
			end
		end

		if selected.ItemName == "Special Backpack" or selected.ID == "Special Backpack" then
			local bpName = boxContent.SpecialBackpacks[math.random(1, #boxContent.SpecialBackpacks)]
			local bpSkin = BACKPACK_SKIN_NAMES[math.random(1, #BACKPACK_SKIN_NAMES)]
			wonItem = {
				Category = "BackPack",
				ItemName = bpName,
				ID = bpSkin,
				Rarity = "Special"
			}
		else
			wonItem = selected
		end
	else
		local chances = getCategoryWeights(boxName)
		local wonRarity = rollRarity(chances)
		if wonRarity == "Special" then
			local bpName = boxContent.SpecialBackpacks[math.random(1, #boxContent.SpecialBackpacks)]
			local skinName = BACKPACK_SKIN_NAMES[math.random(1, #BACKPACK_SKIN_NAMES)]
			wonItem = {
				Category = "BackPack",
				ItemName = bpName,
				ID = skinName,
				Rarity = "Special"
			}
		else
			local pool = {}
			for _, wSkin in ipairs(boxContent.WeaponSkins) do
				if wSkin.Rarity == wonRarity then
					table.insert(pool, wSkin)
				end
			end
			if #pool == 0 then pool = boxContent.WeaponSkins end
			wonItem = pool[math.random(1, #pool)]
		end
	end

	local floatVal = math.floor(math.random() * 10000) / 10000

	-- Save skin to player inventory
	local skinUid = HttpService:GenerateGUID(false)
	if not profile.Skins then profile.Skins = {} end
	table.insert(profile.Skins, {
		UID = skinUid,
		ID = wonItem.ID,
		Category = wonItem.Category,
		ItemName = wonItem.ItemName,
		Float = floatVal
	})

	-- Save data & notify stats changed for immediate persistence and 0ms UI sync
	Saving.SaveData(player, false)
	local Signal = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Signal"))
	Signal.Fire("Stat Changed", player, "Skins")
	Signal.Fire("Stat Changed", player, "Contracts")

	-- Build spin slots data (sent to client, client builds the UI with Viewports)
	local chances = getCategoryWeights(boxName)
	local spinSlots = {}
	for i = 1, 30 do
		if i == 25 then
			table.insert(spinSlots, {
				LayoutOrder = i,
				ItemName = wonItem.ItemName,
				Category = wonItem.Category,
				ID = wonItem.ID,
				Rarity = wonItem.Rarity,
				IsSelected = true
			})
		else
			if #pool > 0 then
				local randEntry = pool[math.random(1, #pool)]
				if randEntry.ItemName == "Special Backpack" or randEntry.ID == "Special Backpack" then
					local bpName = (boxContent and boxContent.SpecialBackpacks and #boxContent.SpecialBackpacks > 0) and boxContent.SpecialBackpacks[math.random(1, #boxContent.SpecialBackpacks)] or "SmallBag"
					local bpSkin = BACKPACK_SKIN_NAMES[math.random(1, #BACKPACK_SKIN_NAMES)]
					table.insert(spinSlots, {
						LayoutOrder = i,
						ItemName = bpName,
						Category = "BackPack",
						ID = bpSkin,
						Rarity = "Special",
						IsSelected = false
					})
				else
					table.insert(spinSlots, {
						LayoutOrder = i,
						ItemName = randEntry.ItemName,
						Category = randEntry.Category,
						ID = randEntry.ID,
						Rarity = randEntry.Rarity,
						IsSelected = false
					})
				end
			else
				local rRarity = rollRarity(chances)
				if rRarity == "Special" then
					local bpName = (boxContent and boxContent.SpecialBackpacks and #boxContent.SpecialBackpacks > 0) and boxContent.SpecialBackpacks[math.random(1, #boxContent.SpecialBackpacks)] or "SmallBag"
					local skinName = BACKPACK_SKIN_NAMES[math.random(1, #BACKPACK_SKIN_NAMES)]
					table.insert(spinSlots, {
						LayoutOrder = i,
						ItemName = bpName,
						Category = "BackPack",
						ID = skinName,
						Rarity = "Special",
						IsSelected = false
					})
				else
					local rItem = (boxContent and boxContent.WeaponSkins and #boxContent.WeaponSkins > 0) and boxContent.WeaponSkins[math.random(1, #boxContent.WeaponSkins)] or { ItemName = "Rocket Launcher", Category = "Launcher", ID = "Basic", Rarity = "Basic" }
					table.insert(spinSlots, {
						LayoutOrder = i,
						ItemName = rItem.ItemName,
						Category = rItem.Category,
						ID = rItem.ID,
						Rarity = rItem.Rarity,
						IsSelected = false
					})
				end
			end
		end
	end

	buyBoxProcessing[player] = nil

	return true, {
		UID = skinUid,
		ID = wonItem.ID,
		Category = wonItem.Category,
		ItemName = wonItem.ItemName,
		Rarity = wonItem.Rarity,
		Float = floatVal,
		SpinSlots = spinSlots
	}
end

----------------------------------------------------------------------
-- Marketplace Service: ProcessReceipt
----------------------------------------------------------------------
local function processReceipt(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local profile = Saving.GetPlayerData(player)
	if not profile then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- P0 FIX: Idempotency — prevent duplicate processing of the same receipt
	if not profile.ProcessedReceipts then profile.ProcessedReceipts = {} end
	local receiptKey = tostring(receiptInfo.PurchaseId)
	if profile.ProcessedReceipts[receiptKey] then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local productId = receiptInfo.ProductId
	local productName = nil

	-- Match ProductId from ProductsConfig
	for name, config in pairs(ProductsConfig) do
		if config.ID == productId and productId ~= 0 then
			productName = name
			break
		end
	end

	-- P0 SECURITY FIX: Unknown product must return NotProcessedYet to prevent forged receipts!
	-- ProcessReceipt is ONLY called for Developer Products. Assets and Limited UGCs use PromptPurchaseFinished.
	if not productName then
		warn("[ExclusiveShopService] Unknown or forged productId received: " .. tostring(productId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if not profile.UpgradesOwned then
		profile.UpgradesOwned = {}
	end

	-- 1. RunFaster Upgrades (Tiers 1 to 5)
	if string.find(productName, "RunFaster") then
		local currentLevel = profile.UpgradesOwned.RunFaster or 0
		if currentLevel < 5 then
			profile.UpgradesOwned.RunFaster = currentLevel + 1
			Network.Fire("Upgrade Changed", player, "RunFaster", profile.UpgradesOwned.RunFaster)
			
			-- Update WalkSpeed immediately on character if spawned
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				local boostMult = player:GetAttribute("StarterBoostActive") and 2 or 1
				humanoid.WalkSpeed = (24 + profile.UpgradesOwned.RunFaster * 2) * boostMult
			end
		end

	-- 2. Magnet Upgrades (Tiers 1 to 5)
	elseif string.find(productName, "Magnet") then
		local currentLevel = profile.UpgradesOwned.Magnet or 0
		if currentLevel < 5 then
			profile.UpgradesOwned.Magnet = currentLevel + 1
			Network.Fire("Upgrade Changed", player, "Magnet", profile.UpgradesOwned.Magnet)
		end
	end

	-- P0 FIX: Mark receipt as processed AFTER granting items
	profile.ProcessedReceipts[receiptKey] = os.time()

	-- Persist immediately: a server crash before the next autosave must not
	-- lose a paid purchase (receipt is already marked processed above).
	pcall(function()
		Saving.SaveData(player, false)
	end)

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

local okAssign, errAssign = pcall(function()
	MarketplaceService.ProcessReceipt = processReceipt
end)
if not okAssign then
	-- ProcessReceipt can only be assigned ONCE per server; if another script
	-- took it, purchases here would never be granted. Make that visible.
	warn("[ExclusiveShopService] Could not assign ProcessReceipt: " .. tostring(errAssign))
end

-- GamePass Purchase Handler
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
	if not wasPurchased or not player or not player.Parent then return end

	local elitePass = GamepassesConfig["ElitePack"]
	if elitePass and elitePass.ID == passId then
		local profile = Saving.GetPlayerData(player)
		if profile then
			if not profile.UpgradesOwned then profile.UpgradesOwned = {} end
			profile.UpgradesOwned.ElitePack = true
			grantWeapon(profile, "Spooky Staff", "LancaMisseis")
			grantWeapon(profile, "Sticky Bomb", "Minas")
			grantEliteBuildSkins(profile)
			player:SetAttribute("Elite", true)
			Network.Fire("Upgrade Changed", player, "ElitePack", true)
			Saving.SaveData(player, false)
			print(string.format("[ExclusiveShop] %s purchased and unlocked ElitePack Gamepass!", player.Name))
		end
	end
end)

-- Character Spawning: apply speed upgrade
local function onCharacterAdded(character, player)
	local humanoid = character:WaitForChild("Humanoid", 5)
	if humanoid then
		local profile = nil
		for i = 1, 10 do
			profile = Saving.GetPlayerData(player)
			if profile then break end
			task.wait(0.2)
		end
		local runFasterLevel = profile and profile.UpgradesOwned and profile.UpgradesOwned.RunFaster or 0
		humanoid.WalkSpeed = 24 + runFasterLevel * 2
	end
end

local function onPlayerAdded(player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(character, player)
	end)
	
	-- If they join and own ElitePack (via Gamepass on Roblox or save data), grant perks and set attribute
	task.spawn(function()
		local profile = nil
		for i = 1, 30 do
			profile = Saving.GetPlayerData(player)
			if profile then break end
			task.wait(0.5)
		end

		local elitePass = GamepassesConfig["ElitePack"]
		if elitePass and elitePass.ID and elitePass.ID ~= 0 then
			local ownsPass = false
			local success, result = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, elitePass.ID)
			end)
			if success and result then
				ownsPass = true
			end

			if ownsPass and profile then
				if not profile.UpgradesOwned then profile.UpgradesOwned = {} end
				profile.UpgradesOwned.ElitePack = true
			end
		end
		
		if profile and profile.UpgradesOwned and profile.UpgradesOwned.ElitePack then
			player:SetAttribute("Elite", true)
			grantWeapon(profile, "Spooky Staff", "LancaMisseis")
			grantWeapon(profile, "Sticky Bomb", "Minas")
			Saving.SaveData(player, false)
		end
	end)

	-- Studio commands for easy testing of exclusive shop items
	if RunService:IsStudio() then
		player.Chatted:Connect(function(msg)
			local profile = Saving.GetPlayerData(player)
			if not profile then return end
			if not profile.UpgradesOwned then profile.UpgradesOwned = {} end

			local cleanMsg = string.lower(msg)
			if cleanMsg == "/buy magnet" then
				local currentLevel = profile.UpgradesOwned.Magnet or 0
				if currentLevel < 5 then
					profile.UpgradesOwned.Magnet = currentLevel + 1
					print("[TestCommand] Magnet level increased to " .. tostring(profile.UpgradesOwned.Magnet))
				end
			elseif cleanMsg == "/buy speed" then
				local currentLevel = profile.UpgradesOwned.RunFaster or 0
				if currentLevel < 5 then
					profile.UpgradesOwned.RunFaster = currentLevel + 1
					local character = player.Character
					local humanoid = character and character:FindFirstChildOfClass("Humanoid")
					if humanoid then
						humanoid.WalkSpeed = 24 + profile.UpgradesOwned.RunFaster * 2
					end
					print("[TestCommand] RunFaster level increased to " .. tostring(profile.UpgradesOwned.RunFaster))
				end
			elseif cleanMsg == "/buy elite" then
				profile.UpgradesOwned.ElitePack = true
				grantWeapon(profile, "Spooky Staff", "LancaMisseis")
				grantWeapon(profile, "Sticky Bomb", "Minas")
				grantEliteBuildSkins(profile)
				player:SetAttribute("Elite", true)
				print("[TestCommand] ElitePack granted!")
			elseif string.sub(cleanMsg, 1, 11) == "/contracts " then
				local amountStr = string.sub(cleanMsg, 12)
				local amount = tonumber(amountStr)
				if amount then
					profile.Contracts = (profile.Contracts or 0) + amount
					if not profile.Currency then profile.Currency = {} end
					profile.Currency.Contracts = profile.Contracts
					print("[TestCommand] Added contracts: " .. tostring(amount) .. ", Total: " .. tostring(profile.Contracts))
				end
			end
		end)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end
