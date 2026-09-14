local Message = {}

function Message.New(text, isConfirm)
	if _G.Message and _G.Message.New then
		return _G.Message.New(text, isConfirm)
	end

	-- Fail-closed: with the modal controller missing, NEVER auto-accept a
	-- confirm prompt (old fallback returned true and silently accepted
	-- trades/purchases). Treat every prompt as declined.
	warn("[Message] _G.Message not installed; prompt suppressed: " .. tostring(text))
	return nil
end

return Message
