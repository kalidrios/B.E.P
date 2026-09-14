--[[
	© DestructionSimulator [2025]
	Library/Signal — Simple event system
]]--

local Signal = {}
local signals = {}
local bindables = {}

function Signal.new(name)
	if not signals[name] then
		signals[name] = {
			connections = {}
		}
	end
	return signals[name]
end

function Signal.Fire(name, ...)
	local signal = signals[name]
	if signal then
		for _, callback in ipairs(signal.connections) do
			task.spawn(callback, ...)
		end
	end
end

function Signal.Connect(name, callback)
	local signal = Signal.new(name)
	table.insert(signal.connections, callback)

	return {
		Disconnect = function()
			local idx = table.find(signal.connections, callback)
			if idx then
				table.remove(signal.connections, idx)
			end
		end,
		disconnect = function()
			local idx = table.find(signal.connections, callback)
			if idx then
				table.remove(signal.connections, idx)
			end
		end
	}
end

-- Alias for Connect
Signal.On = Signal.Connect

function Signal.Once(name, callback)
	local connection
	connection = Signal.Connect(name, function(...)
		connection.Disconnect()
		callback(...)
	end)
	return connection
end

-- Extension for Velvet Signal API compatibility
function Signal.Fired(name)
	return {
		Connect = function(self, callback)
			return Signal.Connect(name, callback)
		end,
		connect = function(self, callback)
			return Signal.Connect(name, callback)
		end
	}
end

local invokes = {}

function Signal.Invoke(name, ...)
	local callback = invokes[name]
	if callback then
		return callback(...)
	end
	return nil
end

function Signal.Invoked(name)
	local wrapper = {}
	setmetatable(wrapper, {
		__newindex = function(tbl, key, value)
			if key == "OnInvoke" then
				invokes[name] = value
			else
				rawset(tbl, key, value)
			end
		end,
		__index = function(tbl, key)
			if key == "OnInvoke" then
				return invokes[name]
			end
			return nil
		end
	})
	return wrapper
end

return Signal
