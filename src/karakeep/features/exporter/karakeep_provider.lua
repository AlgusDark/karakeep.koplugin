local EventListener = require('ui/widget/eventlistener')
local logger = require('logger')
local _ = require('gettext')

local Provider = require('provider')
local Notification = require('karakeep/shared/widgets/notification')
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

---@class KarakeepProvider : EventListener
---@field ui UI Reference to UI for accessing registered modules
local KarakeepProvider = EventListener:extend({})

function KarakeepProvider:init()
    local KarakeepExporter = require('karakeep/features/exporter/modules/karakeep_exporter')
    Provider:register('exporter', 'karakeep', KarakeepExporter)
end

---Create a new bookmark in Karakeep
---@param params {title: string, content: string} The bookmark data
---@return table|nil result The created bookmark data if successful
function KarakeepProvider:createBookmark(params)
    local result, error = self.ui.karakeep_api:createNewBookmark({
        body = {
            type = 'text',
            title = params.title,
            text = params.content,
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
    return result
end

---Update an existing bookmark in Karakeep
---@param params {id: string, content: string} The bookmark update data
---@return table|nil result The updated bookmark data if successful
function KarakeepProvider:updateBookmark(params)
    local result, error = self.ui.karakeep_api:updateBookmark(params.id, {
        body = {
            type = 'text',
            text = params.content,
        },
    })

    if error then
        logger.err('[KarakeepProvider] Failed to update bookmark:', error.message)
        Notification:error(_('Failed to update Karakeep bookmark'))
        return nil
    end

    logger.dbg('[KarakeepProvider] Updated bookmark:', params.id)
    return result
end

---Handle export request from KarakeepExporter
---@param books_with_markdown table[] Array of {book: BookNotes, markdown_content: string}
function KarakeepProvider:onExportToKarakeep(books_with_markdown)
    logger.info('[KarakeepProvider] Starting export of', #books_with_markdown, 'books')

    local success_count = 0
    local error_count = 0

    for _, item in ipairs(books_with_markdown) do
        local book = item.book
        local markdown_content = item.markdown_content
        local bookmark_data = KarakeepMetadata.getBookmark(book.file)

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
end

return KarakeepProvider
