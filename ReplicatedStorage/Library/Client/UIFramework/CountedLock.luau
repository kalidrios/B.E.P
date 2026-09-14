local CountedLock = {}
CountedLock.__index = CountedLock

function CountedLock.new()
	local self = setmetatable({}, CountedLock)
	self._obtainedCount = 0
	
	local bindable = Instance.new("BindableEvent")
	self._bindable = bindable
	self.OnLockChanged = bindable.Event
	
	return self
end

function CountedLock:IsUnlocked()
	return self._obtainedCount <= 0
end

function CountedLock:ObtainLock()
	local wasUnlocked = self:IsUnlocked()
	self._obtainedCount += 1
	
	if wasUnlocked and not self:IsUnlocked() then
		self._bindable:Fire(false)
	end
	
	local released = false
	return function()
		if released then return end
		released = true
		
		local wasLocked = not self:IsUnlocked()
		self._obtainedCount -= 1
		
		if wasLocked and self:IsUnlocked() then
			self._bindable:Fire(true)
		end
	end
end

return CountedLock
