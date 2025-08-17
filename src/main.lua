local WidgetContainer = require('ui/widget/container/widgetcontainer')
local _ = require('gettext')
local logger = require('logger')
local lfs = require('libs/libkoreader-lfs')
local DataStorage = require('datastorage')
local Provider = require('provider')

local KarakeepReaderLink = require('karakeep/features/reader/modules/readerlink')
local Settings = require('karakeep/shared/karakeep_settings')
local getMainMenu = require('karakeep/features/menu/main_menu')
local KarakeepAPI = require('karakeep/api/karakeep_api')
local KarakeepBookmark = require('karakeep/domains/karakeep_bookmark')
local QueueManager = require('karakeep/features/queue/queue_manager')
local SyncService = require('karakeep/features/sync/sync_service')
local KarakeepExporter = require('karakeep/features/exporter/karakeep_exporter')

---Augment UI interface with registered Karakeep modules
---@class UI : WidgetContainer
---@field karakeep_api KarakeepAPI
---@field karakeep_bookmark KarakeepBookmark
---@field karakeep_link KarakeepReaderLink
---@field karakeep_queue_manager QueueManager

---@class Karakeep : WidgetContainer
---@field name string Plugin internal name (from _meta.lua)
---@field fullname string Plugin display name (from _meta.lua)
---@field description string Plugin description (from _meta.lua)
---@field version string Plugin version (from _meta.lua)
---@field author string Plugin author (from _meta.lua)
---@field repo_owner string GitHub repository owner (from _meta.lua)
---@field repo_name string GitHub repository name (from _meta.lua)
---@field settings Settings Plugin settings instance
---@field data_dir string Full path to karakeep data directory
local Karakeep = WidgetContainer:extend({
    name = 'Karakeep',
    is_doc_only = false,
    data_dir = ('%s/%s/'):format(DataStorage:getFullDataDir(), 'karakeep'),
})

function Karakeep:init()
    -- Create the karakeep directory if it doesn't exist
    if not lfs.attributes(self.data_dir, 'mode') then
        local success = lfs.mkdir(self.data_dir)
        if not success then
            logger.err('[Karakeep:Main] Failed to create data directory')
            return
        end
    end

    self.settings = Settings:new({
        defaults = {
            server_address = '',
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

    -- Register queue manager as EventListener module (after API)
    self.ui:registerModule(
        'karakeep_queue_manager',
        QueueManager:new({
            data_dir = self.data_dir,
            ui = self.ui,
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

    self.ui:registerModule(
        'karakeep_sync_service',
        SyncService:new({
            ui = self.ui,
        })
    )

    Provider:register('exporter', 'karakeep', KarakeepExporter:new({ ui = self.ui }))

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
