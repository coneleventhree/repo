--!strict
-- Small key/value maps shared by every server of the game (MemoryStore), or
-- plain tables in Studio, where one server is all there is. Every call is
-- protected: a failed MemoryStore request returns nil/false and the caller
-- tries again on its next pass.

local MemoryStoreService = game:GetService("MemoryStoreService")

local SharedStore = {}

export type Item = { key: string, value: any }
export type Map = {
	get: (key: string) -> any,
	set: (key: string, value: any, ttl: number) -> boolean,
	-- atomic read-modify-write: `fn` returns the new value, or nil to leave it
	-- alone. Returns the value written (nil if none was).
	update: (key: string, fn: (any) -> any, ttl: number) -> any,
	remove: (key: string) -> boolean,
	-- everything in the map (nil if it could not be read)
	list: () -> { Item }?,
}

local function warnOnce(map: string, err: any)
	warn(string.format("[SharedStore] %s: %s", map, tostring(err)))
end

-- A MemoryStore sorted map (it can be listed; keys are short strings).
function SharedStore.memory(name: string): Map
	local m: MemoryStoreSortedMap? = nil
	local function sm(): MemoryStoreSortedMap?
		if not m then
			local ok, v = pcall(function()
				return MemoryStoreService:GetSortedMap(name)
			end)
			if ok then
				m = v
			else
				warnOnce(name, v)
			end
		end
		return m
	end
	local map: Map = {
		get = function(key)
			local s = sm()
			if not s then
				return nil
			end
			local ok, v = pcall(function()
				return (s :: MemoryStoreSortedMap):GetAsync(key)
			end)
			return if ok then v else nil
		end,
		set = function(key, value, ttl)
			local s = sm()
			if not s then
				return false
			end
			local ok = pcall(function()
				(s :: MemoryStoreSortedMap):SetAsync(key, value, ttl)
			end)
			return ok
		end,
		update = function(key, fn, ttl)
			local s = sm()
			if not s then
				return nil
			end
			local ok, v = pcall(function()
				return (s :: MemoryStoreSortedMap):UpdateAsync(key, function(old)
					return fn(old)
				end, ttl)
			end)
			if not ok then
				warnOnce(name, v)
			end
			return if ok then v else nil
		end,
		remove = function(key)
			local s = sm()
			if not s then
				return false
			end
			local ok = pcall(function()
				(s :: MemoryStoreSortedMap):RemoveAsync(key)
			end)
			return ok
		end,
		list = function()
			local s = sm()
			if not s then
				return nil
			end
			local ok, items = pcall(function()
				return (s :: MemoryStoreSortedMap):GetRangeAsync(Enum.SortDirection.Ascending, 200)
			end)
			if not ok or type(items) ~= "table" then
				return nil
			end
			local out: { Item } = {}
			for _, it in items :: { any } do
				if type(it) == "table" and type(it.key) == "string" then
					table.insert(out, { key = it.key, value = it.value })
				end
			end
			return out
		end,
	}
	return map
end

-- The same in a table, with expiry on `clock`.
function SharedStore.localMap(clock: () -> number): Map
	local data: { [string]: { value: any, expires: number } } = {}
	local function live(key: string): any
		local e = data[key]
		if not e then
			return nil
		end
		if e.expires <= clock() then
			data[key] = nil
			return nil
		end
		return e.value
	end
	local function copy(v: any): any
		return if type(v) == "table" then table.clone(v) else v
	end
	local map: Map = {
		get = function(key)
			return copy(live(key))
		end,
		set = function(key, value, ttl)
			data[key] = { value = copy(value), expires = clock() + ttl }
			return true
		end,
		update = function(key, fn, ttl)
			local v = fn(copy(live(key)))
			if v ~= nil then
				data[key] = { value = copy(v), expires = clock() + ttl }
			end
			return v
		end,
		remove = function(key)
			data[key] = nil
			return true
		end,
		list = function()
			local keys = {}
			for k in data do
				if live(k) ~= nil then
					table.insert(keys, k)
				end
			end
			table.sort(keys)
			local out: { Item } = {}
			for _, k in keys do
				table.insert(out, { key = k, value = copy(data[k].value) })
			end
			return out
		end,
	}
	return map
end

return SharedStore
