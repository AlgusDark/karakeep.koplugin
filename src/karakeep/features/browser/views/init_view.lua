local BaseView = require('karakeep/features/browser/views/base_view')
local InputDialog = require('ui/widget/inputdialog')
local UIManager = require('ui/uimanager')
local _ = require('gettext')

---@class InitView : BaseView
local InitView = BaseView:extend({})

---Load view data with navigation callbacks
---@return table|nil View data with title and items, or nil on error
function InitView:load()
    local browser = self.browser
    return {
        title = _('Karakeep'),
        items = {
            {
                text = _('Home'),
                callback = function()
                    browser:navigate('bookmarks')
                end,
            },
            {
                text = _('All lists'),
                callback = function()
                    browser:navigate('all_lists')
                end,
            },
            {
                text = _('Search'),
                callback = function()
                    local search_dialog
                    search_dialog = InputDialog:new({
                        title = _('Search bookmarks'),
                        input = '',
                        input_hint = _('Title, content, description or note'),
                        buttons = {
                            {
                                {
                                    text = _('Cancel'),
                                    id = 'close',
                                    callback = function()
                                        UIManager:close(search_dialog)
                                    end,
                                },
                                {
                                    text = _('Search'),
                                    is_enter_default = true,
                                    callback = function()
                                        local query = search_dialog:getInputText()
                                        UIManager:close(search_dialog)
                                        if query and query ~= '' then
                                            browser:navigate('search', { q = query })
                                        end
                                    end,
                                },
                            },
                        },
                    })
                    UIManager:show(search_dialog)
                    search_dialog:onShowKeyboard()
                end,
            },
        },
    }
end

return InitView
