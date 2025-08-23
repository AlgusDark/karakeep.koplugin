local UIManager = require('ui/uimanager')
local _ = require('gettext')
local EventListener = require('ui/widget/eventlistener')

---@class KarakeepReaderLink : EventListener
---@field ui UI # ReaderUI
local KarakeepReaderLink = EventListener:extend({})

function KarakeepReaderLink:init()
    if self.ui.link then
        self.ui.link:addToExternalLinkDialog('50_save_to_karakeep', function(this, link_url)
            return {
                text = _('Save to Karakeep'),
                callback = function()
                    UIManager:close(this.external_link_dialog)
                    self.ui.karakeep_bookmark:createOrQueue({
                        type = 'link',
                        url = link_url,
                    })
                end,
            }
        end)
    end
end

return KarakeepReaderLink
