local _ = require('gettext')
local InputDialog = require('ui/widget/inputdialog')
local UIManager = require('ui/uimanager')

local Notification = require('karakeep/shared/widgets/notification')

local DEFAULT_EXPORT_DIR = '/mnt/us/books/karakeep'

---@param karakeep Karakeep
return function(karakeep)
    return {
        text = _('Export folder'),
        keep_menu_open = true,
        callback = function()
            local current = karakeep.settings.export_dir
            if current == '' then
                current = DEFAULT_EXPORT_DIR
            end

            local dialog
            dialog = InputDialog:new({
                title = _('Export folder'),
                description = _('Folder path to save exported bookmarks'),
                input = current,
                buttons = {
                    {
                        {
                            text = _('Cancel'),
                            callback = function()
                                UIManager:close(dialog)
                            end,
                        },
                        {
                            text = _('Reset to default'),
                            callback = function()
                                karakeep.settings.export_dir = ''
                                Notification:success(_('Reset to default export folder'))
                                UIManager:close(dialog)
                            end,
                        },
                        {
                            text = _('Save'),
                            callback = function()
                                local value = dialog:getInputText()
                                if value and value ~= '' then
                                    karakeep.settings.export_dir = value
                                else
                                    karakeep.settings.export_dir = ''
                                end
                                Notification:success(_('Export folder saved'))
                                UIManager:close(dialog)
                            end,
                        },
                    },
                },
            })
            UIManager:show(dialog)
            dialog:onShowKeyboard()
        end,
    }
end
