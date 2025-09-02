local BookList = require('ui/widget/booklist')
local InfoMessage = require('ui/widget/infomessage')
local TitleBar = require('ui/widget/titlebar')
local UIManager = require('ui/uimanager')
local _ = require('gettext')


---@class BrowserOptions : BookListOptions
---@field ui table UI manager reference
---@field title string Browser title
---@field close_callback? fun() Callback when browser is closed

---@class Browser : BookList
---@field ui UI UI manager reference
---@field close_callback? fun() Callback when browser is closed
---@field new fun(self: Browser, opts: BrowserOptions): Browser Override new to return Browser
---@field extend fun(self: Browser, o: table): Browser Override extend to return Browser
local Browser = BookList:extend({
    title = _('Karakeep Browser'),
    is_borderless = true,
    is_popout = false,
    title_bar_fm_style = true,
    title_shrink_font_to_fit = true,
    title_bar_left_icon = 'appbar.menu',
})

---Initialize Browser instance
function Browser:init()
    self.api_client = self.ui.karakeep_api

    -- Initialize navigation state
    self.current_view_name = nil
    self.current_view_params = {}

    -- Store external close callback
    local external_close_callback = self.close_callback

    self.custom_title_bar = TitleBar:new({
        fullscreen = true,
        title = self.title or _('Karakeep Browser'),
        left_icon = 'appbar.menu',
        left_icon_size_ratio = 1,
        right_icon = 'close',
        right_icon_size_ratio = 1,
        right_icon_tap_callback = function()
            if external_close_callback then
                external_close_callback()
            end
            UIManager:close(self)
        end,
        show_parent = self,
    })

    BookList.init(self)

    -- Initialize with the initial view
    self:navigate('init')
end

---Navigate to a view by name
---@param view_name string View name to navigate to
---@param params? table Parameters to pass to the view
---@param is_back_navigation? boolean True if this is a back navigation (don't push to stack)
function Browser:navigate(view_name, params, is_back_navigation)
    params = params or {}
    is_back_navigation = is_back_navigation or false

    local view_instance = self:getView(view_name)
    if not view_instance then
        UIManager:show(InfoMessage:new({
            text = _('Unknown view: ') .. tostring(view_name),
            timeout = 3,
        }))
        return
    end

    -- Store current state in paths before navigating (unless going back or it's init)
    if not is_back_navigation and self.title and view_name ~= 'init' and #self.paths >= 0 then
        table.insert(self.paths, {
            view_name = self.current_view_name or 'init',
            params = self.current_view_params or {},
        })
    end

    local view_data = view_instance:load(params)
    if view_data then
        -- Store current navigation state
        self.current_view_name = view_name
        self.current_view_params = params

        self:switchItemTable(view_data.title, view_data.items)
    else
        -- Show error message if view failed to load
        UIManager:show(InfoMessage:new({
            text = _('Failed to load view data'),
            timeout = 3,
        }))
    end
end

---Get view instance by name
---@param view_name string View name
---@return table|nil View instance
function Browser:getView(view_name)
    local view_modules = {
        init = require('karakeep/features/browser/views/init_view'),
        bookmarks = require('karakeep/features/browser/views/bookmarks_view'),
        all_lists = require('karakeep/features/browser/views/all_lists_view'),
        list = require('karakeep/features/browser/views/list_view'),
    }

    local view_module = view_modules[view_name]
    if not view_module then
        return nil
    end

    -- Instantiate view with browser and API client
    return view_module:new({
        browser = self,
        api_client = self.api_client,
    })
end

---Handle back navigation (return arrow tap)
function Browser:onReturn()
    local path_entry = table.remove(self.paths)
    if path_entry then
        -- Navigate back to the previous view
        self:navigate(path_entry.view_name, path_entry.params, true)
    else
        -- No history, go to init view
        self:navigate('init', {}, true)
    end
    return true
end

---Handle back navigation hold (return to root)
function Browser:onHoldReturn()
    -- Clear navigation stack and return to init
    self.paths = {}
    self:navigate('init', {}, true)
    return true
end

---Handle menu choice (item selection)
---@param item MenuItem
function Browser:onMenuChoice(item)
    if item.callback then
        item.callback()
    end
end

---Handle menu hold (long press)
---@param item MenuItem
function Browser:onMenuHold(item)
    if item.hold_callback then
        item.hold_callback()
    end
end

---Handle menu select (item tap)
---Override Menu:onMenuSelect to properly handle items with callbacks
---@param item MenuItem
function Browser:onMenuSelect(item)
    if item.callback then
        -- Handle items with callbacks (our navigation system)
        item.callback()
        return true
    else
        -- Fall back to parent behavior for items with sub_item_table
        return BookList.onMenuSelect(self, item)
    end
end

return Browser
