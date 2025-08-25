local EventListener = require('ui/widget/eventlistener')
local NetworkMgr = require('ui/network/manager')
local InfoMessage = require('ui/widget/infomessage')
local UIManager = require('ui/uimanager')
local logger = require('logger')
local _ = require('gettext')

---@class KarakeepBookmark : EventListener
---@field ui UI
local KarakeepBookmark = EventListener:extend({})

---Create a new bookmark with connectivity awareness and automatic queueing
---@param bookmark_data BookmarkRequest The bookmark data to create
---@return boolean success Whether the operation completed successfully
function KarakeepBookmark:createOrQueue(bookmark_data)
    if not NetworkMgr:isOnline() then
        self.ui.karakeep_queue_manager:queueCreateBookmark(bookmark_data)
        UIManager:show(InfoMessage:new({
            text = _('Bookmark will be saved to Karakeep in the next sync.'),
            timeout = 1,
        }))
        return true
    end

    local saving_message = InfoMessage:new({
        text = _('Saving...'),
    })
    UIManager:show(saving_message)
    UIManager:forceRePaint()

    local result, error = self.ui.karakeep_api:createNewBookmark({
        body = bookmark_data,
    })

    UIManager:close(saving_message)

    logger.dbg('[Karakeep:Bookmark] Creating new bookmark', result, error)

    if not result then
        self.ui.karakeep_queue_manager:queueCreateBookmark(bookmark_data)
        UIManager:show(InfoMessage:new({
            text = _('Bookmark will be saved to Karakeep in the next sync.'),
            timeout = 1,
        }))
        return true
    end

    UIManager:show(InfoMessage:new({
        text = _('Bookmark saved to Karakeep.'),
        timeout = 1,
    }))
    return true
end

return KarakeepBookmark
