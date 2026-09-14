--[[
	© DestructionSimulator [2026]
	Server/AnalyticsManager — Centralized Roblox Analytics Funnel Instrumentation.
	
	Safely handles AnalyticsService calls with pcall guards, server-side validations,
	one-time step deduplication, and structured recurring session logging.
--]]

local AnalyticsService = game:GetService("AnalyticsService")
local HttpService = game:GetService("HttpService")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AnalyticsManager = {}

-- Lazy required reference to Saving module
local Saving = nil
local function getSaving()
	if not Saving then
		local success, lib = pcall(function()
			return require(ServerScriptService:WaitForChild("Library"):WaitForChild("Saving"))
		end)
		if success then Saving = lib end
	end
	return Saving
end

--- Ensures profile has a FunnelHistory table for One-Time event deduplication
local function ensureFunnelHistory(profile)
	if not profile.FunnelHistory then
		profile.FunnelHistory = {}
	end
	return profile.FunnelHistory
end

--- Safely logs a One-Time Onboarding Funnel Step (Deduplicated per player save)
--- @param player Player
--- @param funnelName string
--- @param stepIndex number
--- @param stepName string
--- @param customFields table?
function AnalyticsManager.LogOneTimeStep(player: Player, funnelName: string, stepIndex: number, stepName: string, customFields: { [string]: string }?)
	if not player or not player:IsA("Player") then return end
	
	local savingLib = getSaving()
	if savingLib then
		local profile = savingLib.GetPlayerData(player)
		if profile then
			local history = ensureFunnelHistory(profile)
			local key = funnelName .. "_Step_" .. tostring(stepIndex)
			if history[key] then
				-- Step already recorded for this player profile
				return
			end
			history[key] = os.time()
		end
	end

	-- Only log Onboarding_FTUE steps to Roblox Onboarding Funnel (Player Churn tracking)
	if funnelName ~= "Onboarding_FTUE" then
		return
	end

	-- Skip calling AnalyticsService in Roblox Studio to prevent debugger pauses / warnings
	if RunService:IsStudio() then
		return
	end

	task.spawn(function()
		pcall(function()
			-- Official Roblox AnalyticsService API signature:
			-- LogOnboardingFunnelStepEvent(player, stepNumber, stepName, customFields)
			AnalyticsService:LogOnboardingFunnelStepEvent(
				player,
				stepIndex,
				stepName,
				customFields or {}
			)
		end)
	end)
end

--- Disabled recurring funnels (Case_Unboxing_Flow and Player_Trade_Flow removed per request)
function AnalyticsManager.LogRecurringStep(player: Player, funnelName: string, funnelSessionId: string, stepIndex: number, stepName: string, customFields: { [string]: string }?)
	-- No-op: Only Onboarding / player churn funnel is tracked
	return
end

--- Generates a unique Session ID for recurring funnels
function AnalyticsManager.GenerateSessionId(): string
	return HttpService:GenerateGUID(false)
end

return AnalyticsManager
