local _ = require('gettext')

local getServerSettings = require('karakeep/features/menu/settings/server_config')

---@alias MenuItemCallback fun(touchmenu_instance?: table): nil
---@alias MenuItemCheckedFunc fun(): boolean
---@alias MenuItemEnabledFunc fun(): boolean
---@alias MenuItemTextFunc fun(): string

---@class MenuItem
---@field text? string
---@field text_func? MenuItemTextFunc
---@field callback? MenuItemCallback
---@field checked_func? MenuItemCheckedFunc
---@field enabled_func? MenuItemEnabledFunc
---@field sub_item_table? MenuItem[]
---@field sub_item_table_func? fun(): MenuItem[]
---@field keep_menu_open? boolean
---@field separator? boolean
---@field help_text? string
---@field icon? string

---@alias MenuItems table<string, MenuItem>

---@param karakeep Karakeep
return function(karakeep)
    return {
        text = _('Karakeep'),
        sub_item_table = {
            getServerSettings(karakeep),
        },
    }
end
