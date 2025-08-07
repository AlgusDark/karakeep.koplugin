local UIManager = require('ui/uimanager')
local _ = require('gettext')
local EventListener = require('ui/widget/eventlistener')
local Device = require('device')

local EventManager = require('karakeep/shared/event_manager')

---@class KarakeepReaderLink : EventListener
---@field ui {link: table} # ReaderUI
local KarakeepReaderLink = EventListener:extend({})

function KarakeepReaderLink:init()
    if self.ui.link then
        self.ui.link:addToExternalLinkDialog('50_save_to_karakeep', function(this, link_url)
            return {
                text = _('Save to Karakeep'),
                callback = function()
                    UIManager:close(this.external_link_dialog)
                    EventManager.broadcast('CreateNewKarakeepBookmark', link_url)
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

return KarakeepReaderLink
