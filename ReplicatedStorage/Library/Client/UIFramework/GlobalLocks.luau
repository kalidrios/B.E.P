local CountedLock = require(script.Parent.CountedLock)

local GlobalLocks = {
	HideHUD = CountedLock.new(),
}

return GlobalLocks
--script sync test