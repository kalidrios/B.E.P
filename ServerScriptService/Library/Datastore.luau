--[[
	© DestructionSimulator [2025]
	Server/Datastore — DataStore wrapper with retry logic
]]--

local DataStoreService = game:GetService("DataStoreService")

local Datastore = {}

local MAX_RETRIES = 3
local RETRY_DELAY = 1

function Datastore.GetStore(name, scope)
	return DataStoreService:GetDataStore(name, scope)
end

function Datastore.GetAsync(store, key)
	for attempt = 1, MAX_RETRIES do
		local success, result = pcall(function()
			return store:GetAsync(key)
		end)
		
		if success then
			return result
		end
		
		warn(string.format("[Datastore] GetAsync failed (attempt %d/%d): %s", attempt, MAX_RETRIES, tostring(result)))
		
		if attempt < MAX_RETRIES then
			task.wait(RETRY_DELAY * attempt)
		end
	end
	
	error(string.format("[Datastore] GetAsync failed after %d attempts for key: %s", MAX_RETRIES, tostring(key)))
end

function Datastore.SetAsync(store, key, value)
	for attempt = 1, MAX_RETRIES do
		local success, result = pcall(function()
			return store:SetAsync(key, value)
		end)
		
		if success then
			return result
		end
		
		warn(string.format("[Datastore] SetAsync failed (attempt %d/%d): %s", attempt, MAX_RETRIES, tostring(result)))
		
		if attempt < MAX_RETRIES then
			task.wait(RETRY_DELAY * attempt)
		end
	end
	
	error(string.format("[Datastore] SetAsync failed after %d attempts for key: %s", MAX_RETRIES, tostring(key)))
end

function Datastore.UpdateAsync(store, key, callback)
	for attempt = 1, MAX_RETRIES do
		local success, result = pcall(function()
			return store:UpdateAsync(key, callback)
		end)
		
		if success then
			return result
		end
		
		warn(string.format("[Datastore] UpdateAsync failed (attempt %d/%d): %s", attempt, MAX_RETRIES, tostring(result)))
		
		if attempt < MAX_RETRIES then
			task.wait(RETRY_DELAY * attempt)
		end
	end
	
	error(string.format("[Datastore] UpdateAsync failed after %d attempts for key: %s", MAX_RETRIES, tostring(key)))
end

return Datastore
