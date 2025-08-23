local EventListener = require('ui/widget/eventlistener')
local NetworkMgr = require('ui/network/manager')
local logger = require('logger')
local _ = require('gettext')

local Notification = require('karakeep/shared/widgets/notification')

---@class KarakeepBookmark : EventListener
---@field ui UI
local KarakeepBookmark = EventListener:extend({})

---Create a new bookmark directly via API
---@param bookmark_data BookmarkRequest The bookmark data to create
---@return table|nil result, Error|nil error
function KarakeepBookmark:create(bookmark_data)
    return self.ui.karakeep_api:createNewBookmark({
        body = bookmark_data,
    })
end

---Create a new bookmark with connectivity awareness and automatic queueing
---@param bookmark_data BookmarkRequest The bookmark data to create
---@return boolean success Whether the operation completed successfully
function KarakeepBookmark:createOrQueue(bookmark_data)
    if not NetworkMgr:isOnline() then
        self.ui.karakeep_queue_manager:queueCreateBookmark(bookmark_data)
        Notification:info(_('Bookmark will be saved to Karakeep in the next sync.'))
        return true
    end

    local result, error = self:create(bookmark_data)

    logger.dbg('[Karakeep:Bookmark] Creating new bookmark', result, error)

    if not result then
        self.ui.karakeep_queue_manager:queueCreateBookmark(bookmark_data)
        Notification:info(_('Bookmark will be saved to Karakeep in the next sync.'))
        return true
    end

    Notification:success(_('Bookmark saved to Karakeep.'))
    return true
end

return KarakeepBookmark
