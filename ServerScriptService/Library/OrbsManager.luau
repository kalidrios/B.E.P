--[[
	© DestructionSimulator [2025]
	Server/OrbsManager — Secure orb creation and collection.
	
	Based on the kalidriosFrmaeworkUI Orbs module pattern:
	- Server creates orb data entries with unique IDs
	- Sends creation events to the owning player via RemoteEvent
	- Player client renders the visual orb and magnet attraction
	- Player client sends claim request with UIDs
	- Server validates and grants blocks to Storage
]]--

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ServerLibrary = ServerScriptService:WaitForChild("Library")
local Saving = require(ServerLibrary:WaitForChild("Saving"))
local RewardsManager = require(ServerLibrary:WaitForChild("RewardsManager"))

local OrbsManager = {}

-- Server-side orb registry
local ActiveOrbs = setmetatable({}, { __mode = "v" })
local PlayerOrbs = {} -- Strong references: { [userId] = { [uid] = orbData } }

-- Remote events (lazily created)
local RemotesFolder = workspace:WaitForChild("__THINGS"):WaitForChild("__REMOTES")

local orbsCreateEvent = RemotesFolder:FindFirstChild("OrbsCreate") or Instance.new("RemoteEvent")
orbsCreateEvent.Name = "OrbsCreate"
orbsCreateEvent.Parent = RemotesFolder

local orbsClaimEvent = RemotesFolder:FindFirstChild("OrbsClaim") or Instance.new("RemoteEvent")
orbsClaimEvent.Name = "OrbsClaim"
orbsClaimEvent.Parent = RemotesFolder

local orbsClearEvent = RemotesFolder:FindFirstChild("OrbsClear") or Instance.new("RemoteEvent")
orbsClearEvent.Name = "OrbsClear"
orbsClearEvent.Parent = RemotesFolder

-- Config
local ORB_LIFETIME = 60 -- seconds before server-side cleanup
local MAX_CLAIM_BATCH = 50 -- max UIDs per claim request (anti-spam)
local CLAIM_RATE_LIMIT = 0.05 -- minimum seconds between claim batches
local MAX_ORBS_PER_PLAYER = 200

local claimTimestamps = {}

-- Sweep periódico de memória (a cada 30s)
task.spawn(function()
	while true do
		task.wait(30)
		local now = os.clock()
		for userId, orbs in pairs(PlayerOrbs) do
			for uid, orbData in pairs(orbs) do
				if now - orbData.createdAt > ORB_LIFETIME then
					orbs[uid] = nil
				end
			end
		end
	end
end)

--- Generate a unique ID for an orb
local function GenerateUID(): string
	return HttpService:GenerateGUID(false)
end

--- Create orbs for a player at a given position
--- @param player Player - the player who caused the destruction
--- @param position Vector3 - where the blocks were destroyed
--- @param totalBlocks number - total blocks destroyed
function OrbsManager.CreateOrbs(player: Player, position: Vector3, totalBlocks: number)
	if totalBlocks <= 0 then return end
	if not player or not player.Parent then return end
	
	-- Cap orb count for performance (like ProfileService batches them)
	local numOrbs = math.min(totalBlocks, 8)
	local blocksPerOrb = math.max(1, math.floor(totalBlocks / numOrbs))
	-- Handle remainder
	local remainder = totalBlocks - (blocksPerOrb * numOrbs)
	
	local orbDataList = {}
	
	-- Initialize strong reference table if needed
	if not PlayerOrbs[player.UserId] then
		PlayerOrbs[player.UserId] = {}
	end
	
	-- Check max orbs limit
	local currentOrbs = 0
	for _ in pairs(PlayerOrbs[player.UserId]) do currentOrbs = currentOrbs + 1 end
	if currentOrbs >= MAX_ORBS_PER_PLAYER then
		return -- Limite atingido
	end
	
	for i = 1, numOrbs do
		local uid = GenerateUID()
		local orbValue = blocksPerOrb
		if i == 1 then
			orbValue = orbValue + remainder -- first orb gets the remainder
		end
		
		local orbEntry = {
			uid = uid,
			ownerUserId = player.UserId,
			blocksValue = orbValue,
			position = position,
			createdAt = os.clock(),
		}
		
		PlayerOrbs[player.UserId][uid] = orbEntry
		ActiveOrbs[uid] = orbEntry
		
		-- Data sent to client for visual creation
		table.insert(orbDataList, {
			uid = uid,
			position = position,
			blocksValue = orbValue,
		})
		
		-- Nota: task.delay removido para evitar leaks nas closures; o sweep periódico cuida disso agora.
	end
	
	-- Fire to the owning player only
	orbsCreateEvent:FireClient(player, orbDataList)
end

--- Claim orbs (called when client says they collected)
--- @param player Player
--- @param uidList table - array of arrays of UIDs (batched like ProfileService)
local function OnOrbsClaim(player: Player, uidList)
	if not player or not player.Parent then return end
	if typeof(uidList) ~= "table" then return end
	
	-- Rate limiting
	local now = os.clock()
	local lastClaim = claimTimestamps[player.UserId]
	if lastClaim and (now - lastClaim) < CLAIM_RATE_LIMIT then return end
	claimTimestamps[player.UserId] = now
	
	local playerProfile = Saving.GetPlayerData(player)
	if not playerProfile then return end
	
	-- Ensure storage exists
	if not playerProfile.Storage then
		playerProfile.Storage = { Amount = 0, Max = 100 }
	end
	
	local totalCollected = 0
	local claimedCount = 0
	
	-- uidList is an array of arrays (batched UIDs from ProfileService pattern)
	for _, batch in ipairs(uidList) do
		if typeof(batch) ~= "table" then continue end
		
		for _, uid in ipairs(batch) do
			if claimedCount >= MAX_CLAIM_BATCH then break end
			if typeof(uid) ~= "string" then continue end
			
			local orbData = ActiveOrbs[uid]
			if not orbData then continue end
			
			-- Security: only the player who created the orb can collect it
			if orbData.ownerUserId ~= player.UserId then continue end
			
			-- Distance validation check (max 150 studs to accommodate upgraded magnet range)
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp and orbData.position then
				if (hrp.Position - orbData.position).Magnitude > 150.0 then
					continue
				end
			end
			
			-- Grant blocks via RewardsManager
			local result = RewardsManager.GrantBlocks(playerProfile, orbData.blocksValue)
			totalCollected = totalCollected + (result and result.added or 0)
			
			-- Remove from registry
			ActiveOrbs[uid] = nil
			if PlayerOrbs[player.UserId] then
				PlayerOrbs[player.UserId][uid] = nil
			end
			claimedCount = claimedCount + 1
		end
	end
end

orbsClaimEvent.OnServerEvent:Connect(OnOrbsClaim)

-- Cleanup when player leaves
Players.PlayerRemoving:Connect(function(player)
	claimTimestamps[player.UserId] = nil
	
	-- Remove strong references; weak table cuidará do resto
	PlayerOrbs[player.UserId] = nil
end)

return OrbsManager
