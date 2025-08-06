local EventListener = require('ui/widget/eventlistener')
local NetworkMgr = require('ui/network/manager')
local logger = require('logger')
local _ = require('gettext')

local Notification = require('karakeep/shared/widgets/notification')
local EventManager = require('karakeep/shared/event_manager')
---@class KarakeepBookmark : EventListener
---@field ui UI
local KarakeepBookmark = EventListener:extend({})

---@param link_url string
function KarakeepBookmark:onCreateNewKarakeepBookmark(link_url)
    if not NetworkMgr:isOnline() then
        EventManager.broadcast('QueueBookmarkLink', { url = link_url })
        Notification:info(_('Link will be bookmarked to Karakeep in the next sync.'))
        return
    end

    local result, error = self.ui.karakeep_api:createNewBookmark({
        body = {
            type = 'link',
            url = link_url,
        },
    })

    logger.dbg('[Karakeep:Bookmark] Creating new bookmark', result, error)

    if not result then
        -- API failed - queue for later sync
        EventManager.broadcast('QueueBookmarkLink', { url = link_url })
        return Notification:info(_('Link will be bookmarked to Karakeep in the next sync.'))
    end

    return Notification:success(_('Link bookmarked to Karakeep.'))
end

return KarakeepBookmark
