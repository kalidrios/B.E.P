local defaultErrorBlacklist = {
    "Failed to load sound rbxassetid://%d+: Unable to download sound data", 
    "Failed to load sound http://www.roblox.com/asset/?id=%d+: Unable to download sound data", 
    "Animation \"rbxassetid://%d+\" failed to load in \".*\": Animation failed to load", 
    "Animation \"http://www.roblox.com/asset/?id=%d+\" failed to load in \".*\": Animation failed to load", 
    "Players%.<Player>%.PlayerScripts%.ChatScript%.ChatMain%.ChatBar:%d+: String contains invalid UTF%-8", 
    "MeshContentProvider failed to process https://assetdelivery.roblox.com/v1/asset%?id=%d+ because 'could not fetch'", 
    "HSRDataContentProvider failed to process .+", 
    "MeshContentProvider failed to process .+", 
    "Coin ID %d+ doesn't exist", 
    "Player:IsInGroup error: Player not in datamodel", 
    "Setting GuiService.SelectedObject to invalid GuiObject", 
    "Failed to get skin data for skinId .+", 
    "Character does not exist for .+", 
    "Entity Get exceeded max yield time %(.+%)", 
    ".+ has been broken in .+", 
    "Failed to grab translator %(.*%)", 
    "Failed to grab price for ID %(%d+%)", 
    "exception while signaling: Unable to cast to Dictionary", 
    "Failed to update .+'s Save", 
    "Failed to load sound rbxassetid://.+: Unable to download sound data", 
    "Invalid entry .+%. Unescaped '}' at end of string, not part of a parameter token%.", 
    "Failed to load sound rbxassetid://.+: error code 46", 
    "Unhandled Promise rejection:\n", 
    "Unhandled promise rejection:\n", 
    "RunService:UnbindFromRenderStep removed different functions with same reference name Hoverboard .+ %d+ times.", 
    "SetCore: ResetButtonCallback has not been registered by the CoreScripts", 
    "IXP %- Accessing user layer that has not been registered : AvatarMarketplace.ShoppingCart", 
    "Humanoid::ApplyDescription%(%) Failed to load Pants, default applied", 
    "Failed to grab .+", 
    "Invalid entry .+%. Incomplete parameter token at end of string%.", 
    "ContentProvider:getContent%(%) in fetch HSR asset data failed for Temp read failed%.", 
    "Intro error #1: Time exceeded for IsLoaded%(%)", 
    "Failed to load sound rbxassetid://.+: Unable to start loading sound in to fmod", 
    "ContentProvider:getContent%(%) in fetch HSR asset data failed for Temp read failed%.", 
    "Mode 6 failed: \"Unable to pick Vulkan device\"", 
    "Mode 6 failed: \"Vulkan is disabled\"", 
    "Unable to get game name for .+", 
    "CoreGui%.RobloxGui.Modules.Stats.StatsViewer:%d+: attempt to call missing method 'OnPerformanceStatsShouldBeVisibleChanged' of table", 
    "Failed to load MaterialService%..+%. PBR textures may not be visible in game%.", 
    "Humanoid::ApplyDescription%(%) Some requested assets were not available", 
    "Mode 6 failed: \"Android version is too old to activate Vulkan\"", 
    "CorePackages%.Packages%..+:%d+: \n", 
    "Cannon is already active", 
    "CoreGui%..+: .+", 
    "GuiService:AddSelectionParent already has selection group with name RBXBackpackSelection, overwriting selection group%.", 
    "https://www%.roblox%.com/client%-status/.+: HttpError: .+", 
    "Unable to retrieve game name for in game menu", 
    "HTTP error code:`nil`", 
    "HTTP error body:`nil`", 
    "HTTP error url:`.+`", 
    "raiseTeleportInitFailedEvent: Teleport failed because .+", 
    "Failed to load sound rbxasset://sounds/.+: Unable to download sound data", 
    "Failed to allocate %d+ kB VRAM for part render data: Failed to allocate buffer", 
    "Failed to allocate %d+ KB of VRAM for TC2 texture: Failed to allocate image memory", 
    "ContentProvider:getContent%(%) in fetch HSR asset data failed for HttpError: Timedout", 
    "Humanoid::ApplyDescription%(%) Failed to load Shirt, default applied", 
    "Skin not loaded yet: id.+", 
    "debug%.profileEnd%(%) %- No active profile annotation%. At: Stack Begin"
};
local isDebugEnvironment = game:GetService("RunService"):IsStudio() or ({
    [126451432817619] = true,
})[game.GameId] == true

local reportRate = 15
if not isDebugEnvironment then
    if game:GetService("RunService"):IsStudio() then
        reportRate = 5
    end
else
    reportRate = nil
end

local activeBlacklist = isDebugEnvironment and {} or defaultErrorBlacklist

local BlunderConfig = {
    ReportRate = reportRate,
    ErrorFilter = {
        AllowedTypes = {
            [Enum.MessageType.MessageOutput] = isDebugEnvironment,
            [Enum.MessageType.MessageInfo] = isDebugEnvironment,
            [Enum.MessageType.MessageWarning] = true,
            [Enum.MessageType.MessageError] = true,
        },
        MessageBlacklist = activeBlacklist,
        MessageWhitelist = nil,
    },
    MessageFilter = {
        AllowedTypes = {
            [Enum.MessageType.MessageOutput] = isDebugEnvironment,
            [Enum.MessageType.MessageInfo] = isDebugEnvironment,
            [Enum.MessageType.MessageWarning] = true,
            [Enum.MessageType.MessageError] = true,
        },
        MessageBlacklist = activeBlacklist,
        MessageWhitelist = nil,
    },
    OtherFilter = {
        AllowedTypes = {
            [Enum.MessageType.MessageOutput] = true,
            [Enum.MessageType.MessageInfo] = true,
            [Enum.MessageType.MessageWarning] = true,
            [Enum.MessageType.MessageError] = true,
        },
        MessageBlacklist = nil,
        MessageWhitelist = nil,
    },
    NetworkFilter = {
        AllowedTypes = {
            [Enum.MessageType.MessageOutput] = true,
            [Enum.MessageType.MessageInfo] = true,
            [Enum.MessageType.MessageWarning] = true,
            [Enum.MessageType.MessageError] = true,
        },
        MessageBlacklist = nil,
        MessageWhitelist = nil,
    },
}

table.freeze(BlunderConfig)
return BlunderConfig