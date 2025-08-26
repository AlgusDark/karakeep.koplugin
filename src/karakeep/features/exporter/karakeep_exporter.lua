local BaseExporter = require('base')
local InfoMessage = require('ui/widget/infomessage')
local UIManager = require('ui/uimanager')
local logger = require('logger')
local _ = require('gettext')

local KarakeepMetadata = require('karakeep/shared/karakeep_metadata')

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

---@class KarakeepExporter
---@field ui UI Reference to UI for accessing registered modules
local KarakeepExporter = {}

KarakeepExporter.__index = KarakeepExporter
setmetatable(KarakeepExporter, { __index = BaseExporter }) -- inherit from BaseExporter

---Create a new exporter instance with UI dependency injection
---@param config {ui: UI} Configuration with UI reference
---@return table exporter_instance The configured exporter instance
function KarakeepExporter:new(config)
    local instance = BaseExporter.new(self, {
        name = 'karakeep',
        label = 'karakeep',
        is_remote = true,
    })

    instance.ui = config.ui
    return instance
end

---Create a new bookmark in Karakeep
---@param params {title: string, content: string} The bookmark data
---@return table|nil result The created bookmark data if successful
function KarakeepExporter:createBookmark(params)
    local result, error = self.ui.karakeep_api:createNewBookmark({
        body = {
            type = 'text',
            title = params.title,
            text = params.content,
        },
    })

    if error then
        logger.err('[KarakeepExporter] Failed to create bookmark:', error.message)
        UIManager:show(InfoMessage:new({
            text = _('Failed to create Karakeep bookmark'),
            timeout = 5,
        }))
        return nil
    end

    if not result or not result.id then
        logger.err('[KarakeepExporter] Invalid response: missing bookmark ID')
        UIManager:show(InfoMessage:new({
            text = _('Failed to create Karakeep bookmark'),
            timeout = 5,
        }))
        return nil
    end

    logger.dbg('[KarakeepExporter] Created bookmark with ID:', result.id)
    return result
end

---Update an existing bookmark in Karakeep
---@param params {id: string, content: string} The bookmark update data
---@return table|nil result The updated bookmark data if successful
function KarakeepExporter:updateBookmark(params)
    local result, error = self.ui.karakeep_api:updateBookmark(params.id, {
        body = {
            type = 'text',
            text = params.content,
        },
    })

    if error then
        logger.err('[KarakeepExporter] Failed to update bookmark:', error.message)
        UIManager:show(InfoMessage:new({
            text = _('Failed to update Karakeep bookmark'),
            timeout = 5,
        }))
        return nil
    end

    logger.dbg('[KarakeepExporter] Updated bookmark:', params.id)
    return result
end

---Main export method called by KOReader's exporter system
---@param book_notes BookNotes[] Array of book notes to export
---@return boolean success True if export was successful
function KarakeepExporter:export(book_notes)
    logger.info('[KarakeepExporter] Starting export of', #book_notes, 'books')

    local success_count = 0
    local error_count = 0

    for _, book in ipairs(book_notes) do
        local bookmark_data = KarakeepMetadata.getBookmark(book.file)

        -- Generate markdown content inline
        local md = require('template/md')
        -- selene: allow(undefined_variable)
        local plugin_settings = G_reader_settings:readSetting('exporter') or {}
        local markdown_settings = plugin_settings.markdown or {}
        local markdown_table = md.prepareBookContent(book, markdown_settings)
        local markdown_content = table.concat(markdown_table, '\n')

        if bookmark_data and bookmark_data.id then
            local result = self:updateBookmark({
                id = bookmark_data.id,
                content = markdown_content,
            })
            if result then
                if result.modifiedAt then
                    bookmark_data.modifiedAt = result.modifiedAt
                    KarakeepMetadata.saveBookmark(book.file, bookmark_data)
                end
                success_count = success_count + 1
            else
                error_count = error_count + 1
            end
        else
            local result = self:createBookmark({
                title = book.title,
                content = markdown_content,
            })
            if result then
                KarakeepMetadata.saveBookmark(book.file, {
                    id = result.id,
                    createdAt = result.createdAt,
                    modifiedAt = result.modifiedAt,
                })
                success_count = success_count + 1
            else
                error_count = error_count + 1
            end
        end
    end

    if success_count > 0 then
        UIManager:show(InfoMessage:new({
            text = _('Exported to Karakeep: ') .. success_count .. _(' books'),
            timeout = 2,
        }))
    end

    if error_count > 0 then
        UIManager:show(InfoMessage:new({
            text = _('Failed to export ') .. error_count .. _(' books'),
            timeout = 3,
        }))
    end

    logger.info(
        '[KarakeepExporter] Export completed:',
        success_count,
        'success,',
        error_count,
        'errors'
    )
    return error_count == 0
end

return KarakeepExporter
