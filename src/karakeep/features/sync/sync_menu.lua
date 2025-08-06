local _ = require('gettext')

local SyncMenu = {}

---Get sync pending items menu item
---@param karakeep Karakeep
---@return table|nil Menu item table or nil if no pending items
function SyncMenu.getSyncPendingMenuItem(karakeep)
    return {
        text = _('Sync pending items'),
        callback = function()
            karakeep.ui.karakeep_sync_service:showSyncDialog()
        end,
    }
end

return SyncMenu
