local BaseView = require('karakeep/features/browser/views/base_view')
local _ = require('gettext')
local T = require('ffi/util').template

---@class SearchView : BaseView
local SearchView = BaseView:extend({})

---Load search results for a query
---@param params? {q: string} Search parameters
---@return {title: string, items: Item[]}|nil View data with title and items, or nil on error
function SearchView:load(params)
    params = params or {}
    local query = params.q

    if not query or query == '' then
        self:showError(_('No search query provided'))
        return nil
    end

    ---@type BookmarksListResponse|nil, Error|nil
    local result, error = self:handleApiCall(function()
        return self.api_client:searchBookmarks({
            query = {
                q = query,
                includeContent = false,
                limit = 50,
            },
        })
    end, T(_('Searching for "%1"...'), query))

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

    if #items == 0 then
        table.insert(items, {
            text = T(_('No results for "%1"'), query),
            dim = true,
            callback = function() end,
        })
    end

    return {
        title = T(_('Search: %1'), query),
        items = items,
    }
end

return SearchView
