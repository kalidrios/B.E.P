--[[
	EventConfig.luau — Central configuration for Experience Events and Countdowns
	Destruction Simulator
]]--

local EventConfig = {
	-- Roblox Experience Event ID used for SocialService:PromptRsvpToEventAsync
	EventId = "5882426026797171320",

	-- Target date and time for the event countdown
	-- Scheduled: Tuesday, September 8, 2026 at 8:00 PM (20:00) UTC-3 (23:00 UTC)
	TargetDate = {
		Year = 2026,
		Month = 9,
		Day = 8,
		Hour = 23,
		Minute = 0,
		Second = 0,
	},

	-- Direct Unix timestamp in seconds (overrides TargetDate if set)
	TargetTimestamp = 1788908400,

	-- Text displayed on the Header Billboard when countdown reaches zero
	LiveText = "HAPPENING NOW!",

	-- Text displayed after event has concluded (if applicable)
	EndedText = "EVENT ENDED",

	-- Minimum cooldown (in seconds) between RSVP prompt popups for a player
	PromptCooldown = 5,
}

-- Calculate and return target timestamp in seconds
function EventConfig.GetTargetTimestamp()
	if EventConfig.TargetTimestamp and EventConfig.TargetTimestamp > 0 then
		return EventConfig.TargetTimestamp
	end

	local d = EventConfig.TargetDate
	if d then
		local ok, ts = pcall(function()
			return os.time({
				year = d.Year or 2026,
				month = d.Month or 1,
				day = d.Day or 1,
				hour = d.Hour or 0,
				min = d.Minute or 0,
				sec = d.Second or 0,
			})
		end)
		if ok and ts then
			return ts
		end
	end

	return 0
end

-- Format remaining seconds into a clean, readable countdown string
function EventConfig.FormatRemaining(totalSeconds)
	if totalSeconds <= 0 then
		return EventConfig.LiveText
	end

	local days = math.floor(totalSeconds / 86400)
	local hours = math.floor((totalSeconds % 86400) / 3600)
	local minutes = math.floor((totalSeconds % 3600) / 60)
	local seconds = math.floor(totalSeconds % 60)

	if days > 0 then
		return string.format("%02dd %02dh %02dm %02ds", days, hours, minutes, seconds)
	elseif hours > 0 then
		return string.format("%02dh %02dm %02ds", hours, minutes, seconds)
	else
		return string.format("%02dm %02ds", minutes, seconds)
	end
end

return EventConfig
