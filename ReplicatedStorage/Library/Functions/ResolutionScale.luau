--[[
	© DestructionSimulator [2025]
	Returns the resolution scale based on 1920 viewport width.
]]--

return function()
	local camera = game.Workspace.CurrentCamera
	if camera then
		return camera.ViewportSize.X / 1920
	end
	return 1
end
