---@meta
---@module 'ui/widget/booklist'

---@class CollateFunction
---@field text string Display name for the collation method
---@field menu_order number Order in menu (lower numbers appear first)
---@field can_collate_mixed? boolean Whether this can sort mixed file types
---@field init_sort_func? fun(cache?: table): (fun(a: table, b: table): boolean), table? Initialize sort function
---@field item_func? fun(item: table, ui?: table) Process item before sorting
---@field mandatory_func? fun(item: table): string Generate mandatory text for item

---@class BookInfo
---@field been_opened boolean Whether book has been opened
---@field status? "reading"|"abandoned"|"complete" Book reading status
---@field pages? number Number of pages in book
---@field has_annotations? boolean Whether book has annotations
---@field percent_finished? number Reading progress (0-1)

---@class BookListOptions : MenuOptions
---@field covers_fullscreen? boolean Whether covers should be fullscreen
---@field custom_title_bar? boolean Whether to use custom title bar

--[[--
BookList widget extends Menu to display and manage lists of books.
Provides sorting, filtering, and book information management.
--]]
---@class BookList : Menu
---@field covers_fullscreen boolean Whether covers should be fullscreen
---@field is_borderless boolean Whether list should have no border
---@field is_popout boolean Whether list is a popup
---@field book_info_cache table<string, BookInfo> Cache of book information indexed by file path
---@field collates table<string, CollateFunction> Available sorting methods
local BookList = {}

---Available collation/sorting methods
BookList.collates = {
    strcoll = {
        text = 'name',
        menu_order = 10,
        can_collate_mixed = true,
    },
    natural = {
        text = 'name (natural sorting)',
        menu_order = 20,
        can_collate_mixed = true,
    },
    access = {
        text = 'last read date',
        menu_order = 30,
        can_collate_mixed = true,
    },
    date = {
        text = 'date modified',
        menu_order = 40,
        can_collate_mixed = true,
    },
    size = {
        text = 'size',
        menu_order = 50,
        can_collate_mixed = false,
    },
    type = {
        text = 'type',
        menu_order = 60,
        can_collate_mixed = false,
    },
    percent_unopened_first = {
        text = 'percent - unopened first',
        menu_order = 70,
        can_collate_mixed = false,
    },
    percent_unopened_last = {
        text = 'percent - unopened last',
        menu_order = 80,
        can_collate_mixed = false,
    },
    percent_natural = {
        text = 'percent – unopened – finished last',
        menu_order = 90,
        can_collate_mixed = false,
    },
    title = {
        text = 'Title',
        menu_order = 100,
    },
    authors = {
        text = 'Authors',
        menu_order = 110,
    },
    series = {
        text = 'Series',
        menu_order = 120,
    },
    keywords = {
        text = 'Keywords',
        menu_order = 130,
    },
}

---Set book information in cache
---@param file string File path
---@param doc_settings table Document settings
function BookList.setBookInfoCache(file, doc_settings) end

---Set specific property in book info cache
---@param file string File path
---@param prop_name string Property name
---@param prop_value any Property value
function BookList.setBookInfoCacheProperty(file, prop_name, prop_value) end

---Reset book info cache for file
---@param file string File path
function BookList.resetBookInfoCache(file) end

---Check if book info is cached
---@param file string File path
---@return boolean
function BookList.hasBookInfoCache(file) end

---Get book information (from cache or sidecar file)
---@param file string File path
---@return BookInfo
function BookList.getBookInfo(file) end

---Check if book has been opened
---@param file string File path
---@return boolean
function BookList.hasBookBeenOpened(file) end

---Get document settings
---@param file string File path
---@return table
function BookList.getDocSettings(file) end

---Get book reading status
---@param file string File path
---@return "new"|"reading"|"abandoned"|"complete"
function BookList.getBookStatus(file) end

---Get localized status string
---@param status string Status code
---@param with_prefix? boolean Whether to include "Status:" prefix
---@param singular? boolean Whether to use singular form
---@return string?
function BookList.getBookStatusString(status, with_prefix, singular) end

---Initialize BookList instance
function BookList:init() end

---Create new BookList instance
---@param opts BookListOptions
---@return BookList
function BookList:new(opts) end

---Extend BookList class
---@param o table
---@return BookList
function BookList:extend(o) end

return BookList
