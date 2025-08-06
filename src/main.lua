local WidgetContainer = require('ui/widget/container/widgetcontainer')
local _ = require('gettext')
local logger = require('logger')

local KarakeepReaderLink = require('karakeep/features/reader/modules/readerlink')
local Settings = require('karakeep/shared/karakeep_settings')
local getMainMenu = require('karakeep/features/menu/main_menu')
local KarakeepAPI = require('src.karakeep.api.karakeep_api')
local KarakeepBookmark = require('karakeep/domains/karakeep_bookmark')

---Augment UI interface with registered Karakeep modules
---@class UI : WidgetContainer
---@field karakeep_api KarakeepAPI
---@field karakeep_bookmark KarakeepBookmark
---@field karakeep_link KarakeepReaderLink

---@class Karakeep : WidgetContainer
---@field name string Plugin internal name (from _meta.lua)
---@field fullname string Plugin display name (from _meta.lua)
---@field description string Plugin description (from _meta.lua)
---@field version string Plugin version (from _meta.lua)
---@field author string Plugin author (from _meta.lua)
---@field repo_owner string GitHub repository owner (from _meta.lua)
---@field repo_name string GitHub repository name (from _meta.lua)
---@field settings Settings Plugin settings instance
local Karakeep = WidgetContainer:extend({
    name = 'Karakeep',
    is_doc_only = false,
})

function Karakeep:init()
    self.settings = Settings:new({
        defaults = {
            server_address = 'https://karakeep.com',
            api_token = '',
            include_beta_releases = false,
        },
    })

    self.ui:registerModule(
        'karakeep_api',
        KarakeepAPI:new({
            server_address = self.settings.server_address,
            api_token = self.settings.api_token,
            api_base = '/api/v1',
        })
    )

    self.ui:registerModule(
        'karakeep_bookmark',
        KarakeepBookmark:new({
            ui = self.ui,
        })
    )

    self.ui:registerModule(
        'karakeep_link',
        KarakeepReaderLink:new({
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
