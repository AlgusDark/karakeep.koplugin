local UIManager = require('ui/uimanager')
local _ = require('gettext')
local EventListener = require('ui/widget/eventlistener')
local Device = require('device')

local EventManager = require('karakeep/shared/event_manager')

---@class ReaderLink : EventListener
---@field ui {link: table} # ReaderUI
local ReaderLink = EventListener:extend({})

function ReaderLink:init()
    if self.ui.link then
        self.ui.link:addToExternalLinkDialog('50_create_bookmark', function(this, link_url)
            return {
                text = _('Create new bookmark'),
                callback = function()
                    UIManager:close(this.external_link_dialog)
                    EventManager.broadcast(
                        'CreateNewKarakeepBookmark',
                        link_url
                    )
                end,
                show_in_dialog_func = function()
                    if Device:canOpenLink() then
                        return true
                    end
                end,
            }
        end)
    end
end

return ReaderLink
