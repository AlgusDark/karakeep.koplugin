local InfoMessage = require('ui/widget/infomessage')
local UIManager = require('ui/uimanager')
local _ = require('gettext')
local logger = require('logger')

---@class BaseViewOptions
---@field browser Browser Browser instance for navigation
---@field api_client KarakeepAPI API client for data fetching

---@class Item : MenuItem
---@field callback function Action when item is tapped
---@field hold_callback? function Action when item is held

---@class BaseView
---@field browser Browser Browser instance for navigation
---@field api_client KarakeepAPI API client for data fetching
local BaseView = {}

---Extend BaseView to create a subclass
---@param o? table Optional table to extend
---@return table Extended class
function BaseView:extend(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

---Create a new BaseView instance
---@param options BaseViewOptions Configuration options
---@return BaseView
function BaseView:new(options)
    local instance = {
        browser = options.browser,
        api_client = options.api_client,
    }
    setmetatable(instance, self)
    self.__index = self
    return instance
end

---Show loading message to user
---@param message? string Custom loading message (optional)
---@return table loading_notification The notification instance for manual closing
function BaseView:showLoading(message)
    message = message or _('Loading...')
    return UIManager:show(InfoMessage:new({
        text = message,
        timeout = nil, -- Manual close required
    }))
end

---Show error message to user
---@param error_message string Error message to display
---@param timeout? number Timeout in seconds (default: 5)
function BaseView:showError(error_message, timeout)
    timeout = timeout or 5
    UIManager:show(InfoMessage:new({
        text = error_message,
        timeout = timeout,
    }))
end

---Show success message to user
---@param message string Success message to display
---@param timeout? number Timeout in seconds (default: 2)
function BaseView:showSuccess(message, timeout)
    timeout = timeout or 2
    UIManager:show(InfoMessage:new({
        text = message,
        timeout = timeout,
    }))
end

---Load view data - to be implemented by subclasses
---@param params? table Parameters passed to the view
---@return table|nil view_data View data with title and items, or nil on error
-- selene: allow(unused_variable)
function BaseView:load(params)
    error('load() method must be implemented by subclass')
end

---Handle API call with automatic loading/error handling
---@param api_call function Function that makes the API call
---@param loading_message? string Custom loading message
---@return table|nil result, Error|nil error
function BaseView:handleApiCall(api_call, loading_message)
    local loading_notification = self:showLoading(loading_message)

    local result, error = api_call()

    if loading_notification then
        UIManager:close(loading_notification)
    end

    if error then
        logger.warn('[BaseView] API call failed:', error.message)
        self:showError(error.message)
        return nil, error
    end

    return result, nil
end

---Transform bookmark data into menu item format
---@param bookmark BookmarkResponse Bookmark data from API
---@return Item Menu item for the bookmark
function BaseView:transformBookmark(bookmark)
    local title = bookmark.title
    if not title or title == '' then
        if bookmark.content and bookmark.content.type == 'link' then
            title = bookmark.content.title or bookmark.content.url
        elseif bookmark.content and bookmark.content.type == 'text' then
            title = _('Text note: ') .. bookmark.id
        elseif bookmark.content and bookmark.content.type == 'asset' then
            title = bookmark.content.fileName or (_('Asset: ') .. bookmark.content.assetType)
        else
            title = _('Untitled bookmark')
        end
    end

    return {
        text = title,
        is_file = true,
        callback = function()
            -- First check if it's potentially downloadable (link type)
            if bookmark.content and bookmark.content.type == 'link' then
                -- Fetch full bookmark with content to check for htmlContent
                local full_bookmark, error = self:handleApiCall(function()
                    return self.api_client:getBookmark(bookmark.id, {
                        query = {
                            includeContent = true,
                        },
                    })
                end, _('Loading bookmark content...'))

                if error then
                    return -- Error already shown by handleApiCall
                end

                -- Check if the full bookmark has htmlContent for EPUB conversion
                if
                    full_bookmark
                    and full_bookmark.content
                    and full_bookmark.content.htmlContent
                then
                    -- Download and convert to EPUB
                    local Downloader = require('karakeep/features/downloader/download')
                    Downloader:execute({
                        bookmark = full_bookmark,
                        browser = self.browser,
                        ui = self.browser.ui,
                        data_dir = require('datastorage'):getFullDataDir(),
                    })
                else
                    -- Link bookmark but no HTML content
                    self:showSuccess(_('Link bookmark has no HTML content for download'))
                end
            else
                -- Show info for non-link bookmarks
                local content_type = bookmark.content and bookmark.content.type or 'unknown'
                self:showSuccess(_('Bookmark type: ') .. content_type .. ' (not downloadable yet)')
            end
        end,
        hold_callback = function()
            UIManager:show(InfoMessage:new({
                text = _('Bookmark ID: ') .. bookmark.id,
                timeout = 3,
            }))
        end,
    }
end

---Transform list data into menu item format
---@param list ListResponse List data from API
---@return Item Menu item for the list
function BaseView:transformList(list)
    return {
        text = list.name,
        is_dir = true,
        callback = function()
            self.browser:navigate('list', { list_id = list.id })
        end,
        hold_callback = function()
            UIManager:show(InfoMessage:new({
                text = _('List ID: ')
                    .. list.id
                    .. (list.description and ('\n' .. list.description) or ''),
                timeout = 3,
            }))
        end,
    }
end

return BaseView
