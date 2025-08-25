local EventListener = require('ui/widget/eventlistener')
local LuaSettings = require('luasettings')
local logger = require('logger')

local BookmarkQueue = require('karakeep/features/queue/types/bookmark_queue')

---@class QueueManager : EventListener
---@field data_dir string Directory path for queue data storage
---@field ui UI
---@field store LuaSettings Static store instance shared across all queue types
---@field updated boolean flag indicating if queue has been modified this session
---@field bookmark_queue BookmarkQueue Bookmark queue instance
---@field queues table<string, any> Registry of all queue instances
local QueueManager = EventListener:extend({
    store = nil,
})

---Initialize QueueManager instance
function QueueManager:init()
    if not QueueManager.store then
        QueueManager.store = LuaSettings:open(self.data_dir .. '/queue.lua')
    end

    -- Initialize queue types with dependency injection
    self.bookmark_queue = BookmarkQueue:new({
        store = QueueManager.store,
        api = self.ui.karakeep_api,
    })

    -- Register all queues for generic operations
    self.queues = {
        bookmark = self.bookmark_queue,
        -- TODO: Add other queue types here as they are implemented
    }
end

---Queue a bookmark for creation with strong typing
---@param payload BookmarkRequest Bookmark payload (currently only BookmarkRequestLink supported)
function QueueManager:queueCreateBookmark(payload)
    logger.dbg('[QueueManager] Queuing bookmark creation', payload.type)

    local key, data

    if payload.type == 'link' then
        ---@cast payload BookmarkRequestLink
        key = payload.url

        -- Always required properties
        data = {
            type = payload.type,
            url = payload.url,
        }

        if payload.precrawledArchiveId and payload.precrawledArchiveId ~= '' then
            data.precrawledArchiveId = payload.precrawledArchiveId
        end

        if payload.title and payload.title ~= '' then
            data.title = payload.title
        end
        if payload.archived then
            data.archived = payload.archived
        end
        if payload.favourited then
            data.favourited = payload.favourited
        end
        if payload.favourited then
            data.favourited = payload.favourited
        end
        if payload.note and payload.note ~= '' then
            data.note = payload.note
        end
        if payload.summary and payload.summary ~= '' then
            data.summary = payload.summary
        end
        if payload.createdAt and payload.createdAt ~= '' then
            data.createdAt = payload.createdAt
        end
        if payload.crawlPriority and payload.crawlPriority ~= '' then
            data.crawlPriority = payload.crawlPriority
        end
    else
        -- TODO: Implement text and asset bookmark types
        logger.err('[QueueManager] Bookmark type not implemented yet:', payload.type)
        return
    end

    self.bookmark_queue:add(key, {
        action = 'create',
        data = data,
    })

    self.updated = true
end

---Check if any queue has pending items
---@return boolean True if any queue has pending items
function QueueManager:hasPendingItems()
    for _queue_name, queue in pairs(self.queues) do
        if queue:hasPendingItems() then
            return true
        end
    end
    return false
end

---Process all pending items across all queues
---@return {success_count: number, error_count: number, total_items: number}
function QueueManager:syncPendingItems()
    local total_success = 0
    local total_error = 0
    local total_items = 0

    for queue_name, queue in pairs(self.queues) do
        logger.dbg('[QueueManager] Processing queue:', queue_name)
        local results = queue:processAll()

        total_success = total_success + results.success_count
        total_error = total_error + results.error_count
        total_items = total_items + results.total_items
    end

    -- Mark as updated if any items were processed
    if total_items > 0 then
        self.updated = true
    end

    return {
        success_count = total_success,
        error_count = total_error,
        total_items = total_items,
    }
end

---Clear all queue data
function QueueManager:clear()
    for _queue_name, queue in pairs(self.queues) do
        queue:clear()
    end
    self.updated = true
    logger.dbg('[QueueManager] Cleared all queue data')
end

function QueueManager:onFlushSettings()
    if self.updated then
        logger.dbg('[QueueManager] Flushing queue to disk')
        QueueManager.store:flush()
        self.updated = false
    end
end

return QueueManager
