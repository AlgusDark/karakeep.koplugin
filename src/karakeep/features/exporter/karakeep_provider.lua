local EventListener = require('ui/widget/eventlistener')
local DocSettings = require('docsettings')
local logger = require('logger')
local _ = require('gettext')

local Provider = require('provider')
local Notification = require('karakeep/shared/widgets/notification')

---@class BookNotes
---@field title string
---@field author string
---@field file string
---@field number_of_pages number
---@field exported? boolean
---@field [integer] Chapter[] -- Array of chapters

---@class Chapter
---@field [integer] Clipping[] -- Array of clippings

---@class Clipping
---@field text string
---@field note? string
---@field page number
---@field time number
---@field chapter string

---@class KarakeepProvider : EventListener
---@field ui UI Reference to UI for accessing registered modules
local KarakeepProvider = EventListener:extend({})

function KarakeepProvider:init()
    local KarakeepExporter = require('karakeep/features/exporter/modules/karakeep_exporter')
    Provider:register('exporter', 'karakeep', KarakeepExporter)
end

---Get Karakeep bookmark ID from book's SDR file
---@param file_path string Path to the book file
---@return string|nil karakeep_id The bookmark ID if it exists
function KarakeepProvider:getKarakeepId(file_path)
    if not DocSettings:hasSidecarFile(file_path) then
        return nil
    end

    local doc_settings = DocSettings:open(file_path)
    local karakeep_data = doc_settings:readSetting('karakeep')

    return karakeep_data and karakeep_data.id
end

---Save Karakeep bookmark ID to book's SDR file
---@param file_path string Path to the book file
---@param bookmark_id string The bookmark ID to save
function KarakeepProvider:saveKarakeepId(file_path, bookmark_id)
    local doc_settings = DocSettings:open(file_path)
    doc_settings:saveSetting('karakeep', { id = bookmark_id })
    doc_settings:flush()
end

---Generate markdown content from BookNotes using KOReader's template
---@param book BookNotes The book notes to convert to markdown
---@return string[] markdown_content The generated markdown
function KarakeepProvider:generateMarkdown(book)
    local md = require('template/md')
    -- selene: allow(undefined_variable)
    local plugin_settings = G_reader_settings:readSetting('exporter') or {}
    local markdown_settings = plugin_settings.markdown or {}

    return md.prepareBookContent(book, markdown_settings)
end

---Create a new bookmark in Karakeep
---@param title string The bookmark title
---@param content string The markdown content
---@return string|nil bookmark_id The created bookmark ID if successful
function KarakeepProvider:createBookmark(title, content)
    local result, error = self.ui.karakeep_api:createNewBookmark({
        body = {
            type = 'text',
            title = title,
            text = content,
        },
    })

    if error then
        logger.err('[KarakeepProvider] Failed to create bookmark:', error.message)
        Notification:error(_('Failed to create Karakeep bookmark'))
        return nil
    end

    if not result or not result.id then
        logger.err('[KarakeepProvider] Invalid response: missing bookmark ID')
        Notification:error(_('Failed to create Karakeep bookmark'))
        return nil
    end

    logger.dbg('[KarakeepProvider] Created bookmark with ID:', result.id)
    return result.id
end

---Update an existing bookmark in Karakeep
---@param bookmark_id string The bookmark ID to update
---@param content string The new markdown content
---@return boolean success True if update was successful
function KarakeepProvider:updateBookmark(bookmark_id, content)
    local _result, error = self.ui.karakeep_api:updateBookmark(bookmark_id, {
        body = {
            type = 'text',
            text = content,
        },
    })

    if error then
        logger.err('[KarakeepProvider] Failed to update bookmark:', error.message)
        Notification:error(_('Failed to update Karakeep bookmark'))
        return false
    end

    logger.dbg('[KarakeepProvider] Updated bookmark:', bookmark_id)
    return true
end

---Handle export request from KarakeepExporter
---@param book_notes BookNotes[] Array of book notes to export
---@return boolean success True if export was successful
function KarakeepProvider:onExportToKarakeep(book_notes)
    logger.info('[KarakeepProvider] Starting export of', #book_notes, 'books')

    local success_count = 0
    local error_count = 0

    for _, book in ipairs(book_notes) do
        local karakeep_id = self:getKarakeepId(book.file)
        local markdown_table = self:generateMarkdown(book)
        local markdown_content = table.concat(markdown_table, '\n')

        if karakeep_id then
            if self:updateBookmark(karakeep_id, markdown_content) then
                success_count = success_count + 1
            else
                error_count = error_count + 1
            end
        else
            local new_id = self:createBookmark(book.title, markdown_content)
            if new_id then
                self:saveKarakeepId(book.file, new_id)
                success_count = success_count + 1
            else
                error_count = error_count + 1
            end
        end
    end

    if success_count > 0 then
        Notification:success(_('Exported to Karakeep: ') .. success_count .. _(' books'))
    end

    if error_count > 0 then
        Notification:warn(_('Failed to export ') .. error_count .. _(' books'))
    end

    logger.info(
        '[KarakeepProvider] Export completed:',
        success_count,
        'success,',
        error_count,
        'errors'
    )
    return error_count == 0
end

return KarakeepProvider
