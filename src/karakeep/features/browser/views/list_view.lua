local BaseView = require('karakeep/features/browser/views/base_view')
local _ = require('gettext')
local T = require('ffi/util').template

---@class ListView : BaseView
local ListView = BaseView:extend({})

---Load view data with API call to get bookmarks in a specific list
---@param params table Parameters containing list_id
---@return table|nil View data with title and items, or nil on error
function ListView:load(params)
    local list_id = params.list_id
    if not list_id then
        self:showError(_('List ID is required'))
        return nil
    end

    -- First get the list details to show the proper title
    local list_result, list_error = self:handleApiCall(function()
        return self.api_client:getList(list_id)
    end, _('Loading list details...'))

    if list_error then
        return nil
    end

    if not list_result then
        self:showError(_('List not found'))
        return nil
    end

    -- Then get the bookmarks in the list
    local bookmarks_result, bookmarks_error = self:handleApiCall(function()
        return self.api_client:getBookmarksInList(list_id, {
            query = {
                includeContent = false,
                limit = 50,
                sortOrder = 'desc',
            },
        })
    end, _('Loading bookmarks...'))

    if bookmarks_error then
        return nil
    end

    if not bookmarks_result or not bookmarks_result.bookmarks then
        self:showError(_('Invalid response from server'))
        return nil
    end

    local items = {}
    for _, bookmark in ipairs(bookmarks_result.bookmarks) do
        table.insert(items, self:transformBookmark(bookmark))
    end

    return {
        title = T(_('List: %1'), list_result.name),
        items = items,
    }
end

return ListView
