local BaseView = require('karakeep/features/browser/views/base_view')
local _ = require('gettext')

---@class AllListsView : BaseView
local AllListsView = BaseView:extend({})

---Load view data with API call to get all lists
---@return table|nil View data with title and items, or nil on error
function AllListsView:load()
    local result, error = self:handleApiCall(function()
        return self.api_client:getAllLists()
    end, _('Loading lists...'))

    if error then
        return nil
    end

    if not result then
        self:showError(_('Invalid response from server'))
        return nil
    end

    local items = {}
    for _, list in ipairs(result.lists or {}) do
        table.insert(items, self:transformList(list))
    end

    if #items == 0 then
        table.insert(items, {
            text = _('No lists yet'),
            dim = true,
            callback = function() end,
        })
    end

    return {
        title = _('All lists'),
        items = items,
    }
end

return AllListsView
