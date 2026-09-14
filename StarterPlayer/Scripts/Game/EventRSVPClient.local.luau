local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local RemotesFolder = workspace:WaitForChild("__THINGS"):WaitForChild("__REMOTES")
local remoteEvent = RemotesFolder:WaitForChild("PromptEventRSVP")

remoteEvent.OnClientEvent:Connect(function(eventId)
	local success, result = pcall(function()
		return SocialService:PromptRsvpToEventAsync(eventId)
	end)
	if not success then
		warn("[EventRSVP] Failed to prompt RSVP:", result)
	end
end)