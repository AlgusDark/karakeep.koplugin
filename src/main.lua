local WidgetContainer = require('ui/widget/container/widgetcontainer')
local _ = require('gettext')
local logger = require('logger')

local ReaderLink = require('karakeep/features/reader/modules/readerlink')
local Settings = require('karakeep/shared/karakeep_settings')
local getMainMenu = require('karakeep/features/menu/main_menu')
local KarakeepAPI = require('karakeep/api/karakeep_client')
local KarakeepBookmark = require('karakeep/domains/karakeep_bookmark')

---@class Karakeep : WidgetContainer
local Karakeep = WidgetContainer:extend({
    name = 'Karakeep',
    is_doc_only = false,
})

function Karakeep:init()
    self.settings = Settings:new({
        defaults = {
            server_address = 'https://karakeep.com',
            api_token = '',
        },
    })

    self.api = KarakeepAPI:new({
        server_address = self.settings.server_address,
        api_token = self.settings.api_token,
        api_base = '/api/v1',
    })

    self.ui:registerModule(
        'karakeepbookmark',
        KarakeepBookmark:new({
            ui = self.ui,
            api = self.api,
        })
    )

    self.ui:registerModule(
        'karakeeplink',
        ReaderLink:new({
            ui = self.ui,
        })
    )

    self.ui.menu:registerToMainMenu(self)
end

function Karakeep:addToMainMenu(menu_items)
    menu_items.karakeep = getMainMenu(self)
end

---Handle FlushSettings event from UIManager
function Karakeep:onFlushSettings()
    if self.settings.updated then
        logger.dbg('[Karakeep:Main] Writing settings to disk')
        self.settings:save()
        self.settings.updated = false
    end
end

return Karakeep
