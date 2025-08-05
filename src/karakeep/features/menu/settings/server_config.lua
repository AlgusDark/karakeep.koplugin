local _ = require('gettext')
local MultiInputDialog = require('ui/widget/multiinputdialog')
local UIManager = require('ui/uimanager')

local Notification = require('karakeep/shared/widgets/notification')
local EventManager = require('karakeep/shared/event_manager')

---@param settings Settings
local function showDialog(settings)
    local server_address = settings.server_address
    local api_token = settings.api_token

    local settings_dialog
    settings_dialog = MultiInputDialog:new({
        title = _('Karakeep server settings'),
        fields = {
            {
                text = server_address,
                input_type = 'string',
                hint = _('Server address (e.g., https://karakeep.example.com)'),
            },
            {
                text = api_token,
                input_type = 'string',
                hint = _('API Token'),
                text_type = 'password',
            },
        },
        buttons = {
            {
                {
                    text = _('Cancel'),
                    callback = function()
                        UIManager:close(settings_dialog)
                    end,
                },
                {
                    text = _('Save'),
                    callback = function()
                        local fields = settings_dialog:getFields()
                        if fields[1] and fields[1] ~= '' then
                            settings.server_address = fields[1]
                        end
                        if fields[2] and fields[2] ~= '' then
                            settings.api_token = fields[2]
                        end

                        -- Broadcast server config change event
                        EventManager.broadcast('SettingsChange', {
                            api_token = settings.api_token,
                            server_address = settings.server_address,
                        })

                        Notification:success(_('Settings saved'))
                        UIManager:close(settings_dialog)
                    end,
                },
            },
        },
    })
    UIManager:show(settings_dialog)
    settings_dialog:onShowKeyboard()
end

---@param karakeep Karakeep
return function(karakeep)
    return {
        text = _('Server Settings'),
        keep_menu_open = true,
        callback = function()
            showDialog(karakeep.settings)
        end,
    }
end
