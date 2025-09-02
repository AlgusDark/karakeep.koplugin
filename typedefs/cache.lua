---@meta
---@module 'cache'

---@class CacheOptions
---@field slots? number Maximum number of cache slots
---@field ttl? number Time to live in seconds

--[[--
Cache implementation for storing key-value pairs with automatic cleanup.
--]]
---@class Cache
---@field slots number Maximum number of cache slots
---@field ttl? number Time to live in seconds
local Cache = {}

---Create new Cache instance
---@param opts CacheOptions
---@return Cache
function Cache:new(opts) end

---Get value from cache
---@param key string Cache key
---@return any Value or nil if not found
function Cache:get(key) end

---Set value in cache
---@param key string Cache key
---@param value any Value to store
function Cache:set(key, value) end

---Clear all cached values
function Cache:clear() end

return Cache
