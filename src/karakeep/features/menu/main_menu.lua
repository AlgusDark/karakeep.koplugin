local _ = require('gettext')

local getServerSettings = require('karakeep/features/menu/settings/server_config')
local updateMenuItems = require('karakeep/features/update/menu_items')
local SyncMenu = require('karakeep/features/sync/sync_menu')

---@param karakeep Karakeep
return function(karakeep)
    local menu_items = {
        text = _('Karakeep'),
        sub_item_table = {
            {
                text = _('Settings'),
                separator = true,
                sub_item_table = {
                    getServerSettings(karakeep),
                    updateMenuItems.getUpdateSettingsMenuItem(karakeep),
                },
            },
            SyncMenu.getSyncPendingMenuItem(karakeep),
            updateMenuItems.getCheckForUpdatesMenuItem(karakeep),
        },
    }

    return menu_items
end
