--[[
	© DestructionSimulator [2025]
	Library/Client/SkinCmds — Client Skin Lookup Helper

	Looks up skin data across player saves and active trade cache for instant 0ms trade UI rendering.
]]--

local Players = game:GetService("Players")
local Save = require(script.Parent.Save)

local SkinCmds = {}

function SkinCmds.Get(uid)
	if not uid then return nil end
	local targetUid = tostring(uid)

	-- 1. Fast cache check from active trade payload (0 ms instant resolution)
	if _G.ActiveTradeSkinsData and _G.ActiveTradeSkinsData[targetUid] then
		return _G.ActiveTradeSkinsData[targetUid], nil
	end

	-- 2. Player replicated save lookup
	for _, player in ipairs(Players:GetPlayers()) do
		local save = Save.Get(player, true)
		if save and save.Skins then
			for _, skin in ipairs(save.Skins) do
				if tostring(skin.uid) == targetUid or tostring(skin.UID) == targetUid then
					return skin, player
				end
			end
		end
	end

	return nil
end

return SkinCmds
