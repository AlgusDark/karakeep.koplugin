---@meta
---@module 'ui/widget/menu'

---@class MenuItem
---@field text string Display text for the menu item
---@field mandatory? string Optional right-aligned text (file size, page count, etc.)
---@field mandatory_func? fun(): string Function that returns mandatory text
---@field mandatory_dim? boolean Whether mandatory text should be dimmed
---@field mandatory_dim_func? fun(): boolean Function that returns whether to dim mandatory text
---@field callback? fun() Function called when item is tapped/selected
---@field hold_callback? fun() Function called when item is held/long-pressed
---@field sub_item_table? MenuItem[] Sub-menu items for hierarchical navigation
---@field is_dir? boolean Whether item represents a directory/folder
---@field is_file? boolean Whether item represents a file
---@field bold? boolean Whether text should be bold
---@field dim? boolean Whether item should be dimmed
---@field select_enabled? boolean Whether item can be selected
---@field select_enabled_func? fun(): boolean Function that returns whether item can be selected
---@field post_text? string Additional text after main text
---@field bidi_wrap_func? fun(text: string): string Function to wrap text for bidirectional text support
---@field idx? number Item index (set automatically when displayed)

---@class MenuOptions
---@field title? string Menu title
---@field subtitle? string Menu subtitle
---@field item_table? MenuItem[] Array of menu items
---@field width? number Menu width
---@field height? number Menu height
---@field is_borderless? boolean Whether menu should have no border
---@field is_popout? boolean Whether menu is a popup
---@field show_parent? table Parent widget for showing
---@field close_callback? fun() Function called when menu is closed
---@field onMenuChoice? fun(self: Menu, item: MenuItem) Function called when item is selected
---@field onMenuHold? fun(self: Menu, item: MenuItem) Function called when item is held

--[[--
Menu widget that displays a list of items with navigation support.
Handles item selection, pagination, and hierarchical navigation.
--]]
---@class Menu : FocusManager
---@field title string Menu title
---@field subtitle? string Menu subtitle
---@field item_table MenuItem[] Array of menu items
---@field item_table_stack MenuItem[][] Stack for hierarchical navigation
---@field page number Current page number
---@field page_num number Total number of pages
---@field perpage number Items per page
---@field close_callback? fun() Function called when menu is closed
---@field paths table[] Navigation path stack
---@field onMenuChoice fun(self: Menu, item: MenuItem) Handle item selection
---@field onMenuHold fun(self: Menu, item: MenuItem) Handle item hold
---@field onReturn? fun() Handle return/back navigation
---@field onMenuSelect fun(self: Menu, item: MenuItem): boolean Handle menu item selection
---@field switchItemTable fun(self: Menu, title: string, item_table: MenuItem[], item_number?: number, item_match?: table, subtitle?: string) Switch to new item table
---@field updateItems fun(self: Menu, select_number?: number, no_recalculate_dimen?: boolean) Update displayed items
---@field onClose fun(self: Menu): boolean Handle menu close
---@field onCloseAllMenus fun(self: Menu): boolean Close all menus
local Menu = {}

---Create new Menu instance
---@param opts MenuOptions
---@return Menu
function Menu:new(opts) end

---Extend Menu class
---@param o table
---@return Menu
function Menu:extend(o) end

return Menu
