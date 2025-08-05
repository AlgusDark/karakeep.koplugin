local EventListener = require('ui/widget/eventlistener')
local NetworkMgr = require('ui/network/manager')
local logger = require('logger')
local _ = require('gettext')

local Notification = require('karakeep/shared/widgets/notification')

---@class KarakeepBookmark : EventListener
---@field api KarakeepAPI
local KarakeepBookmark = EventListener:extend {}

---@param link_url string
function KarakeepBookmark:onCreateNewKarakeepBookmark(link_url)
    if not NetworkMgr:isOnline() then
        -- Add to Offline queue
        Notification:info(_('Link will be bookmarked to Karakeep in the next sync.'))
        return
    end

    local result, error = self.api:createNewBookmark({
        body = {
            type = 'link',
            url = link_url,
        }
    })

    logger.dbg('[Karakeep:Bookmark] Creating new bookmark', result, error)

    if not result then
        return Notification:error(_('Failed to bookmark link to Karakeep.'))
    end

    return Notification:success(_('Link bookmarked to Karakeep.'))
end

return KarakeepBookmark
