local logger = require('logger')

---@class BookmarkQueue
---@field store LuaSettings Shared store instance from QueueManager
---@field api KarakeepAPI API instance for processing bookmarks
local BookmarkQueue = {}

---@param config {store: LuaSettings, api: KarakeepAPI}
---@return BookmarkQueue
function BookmarkQueue:new(config)
    local instance = {
        store = config.store,
        api = config.api,
    }
    setmetatable(instance, { __index = self })
    return instance
end

---@class BookmarkQueueItem
---@field action 'create'|'update'|'delete' Action type
---@field data Bookmark The bookmark data

---Add a bookmark action to the queue
---@param key string Unique identifier (URL for create, ID for update/delete)
---@param payload BookmarkQueueItem Action and data
function BookmarkQueue:add(key, payload)
    logger.dbg('[BookmarkQueue] Queuing', payload.action, 'for', key)

    local bookmark_queue = self.store:readSetting('bookmark_queue') or { _length = 0 }
    local current_length = bookmark_queue._length or 0

    -- Only increment if this is a new key
    if not bookmark_queue[key] then
        current_length = current_length + 1
    end

    bookmark_queue[key] = {
        action = payload.action,
        data = payload.data,
    }
    bookmark_queue._length = current_length

    self.store:saveSetting('bookmark_queue', bookmark_queue)
end

---Remove a bookmark action from the queue
---@param key string Unique identifier to remove
function BookmarkQueue:remove(key)
    local bookmark_queue = self.store:readSetting('bookmark_queue') or { _length = 0 }

    if bookmark_queue[key] then
        bookmark_queue[key] = nil
        local current_length = bookmark_queue._length or 0
        bookmark_queue._length = math.max(0, current_length - 1)

        self.store:saveSetting('bookmark_queue', bookmark_queue)
        logger.dbg('[BookmarkQueue] Removed item from queue', key)
    end
end

---Get all pending bookmark actions
---@return table # Queue data with _length field
function BookmarkQueue:getAll()
    return self.store:readSetting('bookmark_queue') or { _length = 0 }
end

---Get count of pending items
---@return number
function BookmarkQueue:getCount()
    local queue_data = self:getAll()
    return queue_data._length or 0
end

---Check if there are pending items
---@return boolean
function BookmarkQueue:hasPendingItems()
    return self:getCount() > 0
end

---Check if a specific item is queued
---@param key string
---@return boolean
function BookmarkQueue:has(key)
    local queue_data = self:getAll()
    return queue_data[key] ~= nil
end

---Clear all bookmark queue items
function BookmarkQueue:clear()
    self.store:saveSetting('bookmark_queue', { _length = 0 })
    logger.dbg('[BookmarkQueue] Cleared all items')
end

---Process all bookmark actions in the queue
---@return {success_count: number, error_count: number, total_items: number}
function BookmarkQueue:processAll()
    logger.dbg('[BookmarkQueue] Processing all items')

    local bookmark_queue = self:getAll()
    local success_count = 0
    local error_count = 0
    local total_items = 0

    for key, item in pairs(bookmark_queue) do
        -- Skip the _length field
        if key ~= '_length' then
            total_items = total_items + 1
            local success = false

            if item.action == 'create' then
                ---@type BookmarkQueuePayload
                local payload = { data = item.data }
                success = self:processCreateAction(key, payload)
            else
                logger.warn('[BookmarkQueue] Unknown action:', item.action)
            end

            if success then
                self:remove(key)
                success_count = success_count + 1
            else
                error_count = error_count + 1
            end
        end
    end

    return {
        success_count = success_count,
        error_count = error_count,
        total_items = total_items,
    }
end

---@class BookmarkQueuePayload
---@field data Bookmark

---Process create bookmark action by calling API directly
---@param key string URL key
---@param payload BookmarkQueuePayload Bookmark queue payload
---@return boolean
function BookmarkQueue:processCreateAction(key, payload)
    logger.dbg('[BookmarkQueue] Processing create action for', key)

    -- Call API directly with injected dependency
    local _result, error = self.api:createNewBookmark({
        body = payload.data,
    })

    if error then
        logger.warn('[BookmarkQueue] Failed to process create action for', key, error)
        return false
    else
        logger.dbg('[BookmarkQueue] Successfully processed create action for', key)
        return true
    end
end

return BookmarkQueue
