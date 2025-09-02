local InfoMessage = require('ui/widget/infomessage')
local UIManager = require('ui/uimanager')
local _ = require('gettext')
local logger = require('logger')

---@class BaseViewOptions
---@field browser Browser Browser instance for navigation
---@field api_client KarakeepAPI API client for data fetching

---@class MenuItem
---@field text string Display text for the menu item
---@field is_file? boolean Whether this is a file item (for bookmarks)
---@field is_dir? boolean Whether this is a directory item (for lists)
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
---@return MenuItem Menu item for the bookmark
function BaseView:transformBookmark(bookmark)
    local title = bookmark.title
    if not title or title == '' then
        if bookmark.content and bookmark.content.type == 'link' then
            title = bookmark.content.title or bookmark.content.url
        elseif bookmark.content and bookmark.content.type == 'text' then
            title = _('Text note')
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
            self:showSuccess(_('You tapped ') .. bookmark.id)
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
---@return MenuItem Menu item for the list
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
