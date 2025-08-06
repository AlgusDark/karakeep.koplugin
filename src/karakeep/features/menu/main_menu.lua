local _ = require('gettext')

local getServerSettings = require('karakeep/features/menu/settings/server_config')
local updateMenuItems = require('karakeep/features/update/menu_items')

---@param karakeep Karakeep
return function(karakeep)
    return {
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
            updateMenuItems.getCheckForUpdatesMenuItem(karakeep),
        },
    }
end
