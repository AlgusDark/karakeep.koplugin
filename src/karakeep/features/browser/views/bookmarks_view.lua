local BaseView = require('karakeep/features/browser/views/base_view')
local _ = require('gettext')

---@class BookmarksView : BaseView
local BookmarksView = BaseView:extend({})

---Load view data with API call to get all bookmarks
---@return {title: string, items: Item[]}|nil View data with title and items, or nil on error
function BookmarksView:load()
    ---@type BookmarksListResponse|nil, Error|nil
    local result, error = self:handleApiCall(function()
        return self.api_client:getAllBookmarks({
            query = {
                includeContent = false,
                limit = 50,
                sortOrder = 'desc',
            },
        })
    end, _('Loading bookmarks...'))

    if error then
        return nil
    end

    if not result or not result.bookmarks then
        self:showError(_('Invalid response from server'))
        return nil
    end

    local items = {}
    for _, bookmark in ipairs(result.bookmarks) do
        table.insert(items, self:transformBookmark(bookmark))
    end

    return {
        title = _('Bookmarks'),
        items = items,
    }
end

return BookmarksView
