--[[
	© DestructionSimulator [2025]
	CountedLock — Counter-based lock pattern
	Used by Variables.Locks for UI state management
]]--

local CountedLock = {}
CountedLock.__index = CountedLock

function CountedLock.new()
	return setmetatable({
		_count = 0,
	}, CountedLock)
end

function CountedLock:Lock()
	self._count = self._count + 1
end

function CountedLock:Unlock()
	self._count = math.max(0, self._count - 1)
end

function CountedLock:IsLocked()
	return self._count > 0
end

function CountedLock:GetCount()
	return self._count
end

return CountedLock
