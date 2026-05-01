local _ = require('gettext')

local getServerSettings = require('karakeep/features/menu/settings/server_config')
local getExportDirConfig = require('karakeep/features/menu/settings/export_dir_config')
local updateMenuItems = require('karakeep/features/update/menu_items')
local SyncMenu = require('karakeep/features/sync/sync_menu')

---@param karakeep Karakeep
return function(karakeep)
    local menu_items = {
        text = _('Karakeep'),
        sorting_hint = 'tools',
        sub_item_table = {
            {
                text = _('Settings'),
                separator = true,
                sub_item_table = {
                    getServerSettings(karakeep),
                    getExportDirConfig(karakeep),
                    updateMenuItems.getUpdateSettingsMenuItem(karakeep),
                },
            },
            SyncMenu.getSyncPendingMenuItem(karakeep),
            {
                text = _('Export bookmarks to folder...'),
                callback = function()
                    karakeep.ui.karakeep_bookmarks_to_folder:exportBookmarksToFolder()
                end,
            },
            updateMenuItems.getCheckForUpdatesMenuItem(karakeep),
        },
    }

    return menu_items
end
