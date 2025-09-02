local BaseView = require('karakeep/features/browser/views/base_view')
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
        },
    }
end

return InitView
