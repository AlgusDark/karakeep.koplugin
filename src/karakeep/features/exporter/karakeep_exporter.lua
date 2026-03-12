local BaseExporter = require('base')
local logger = require('logger')
local _ = require('gettext')

local KarakeepMetadata = require('karakeep/shared/karakeep_metadata')
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

---Get a Bookmark from Karakeep
---@param id string The id of a bookmark to request from Karakeep
---@return table|nil result The requested bookmark from Karakeep
function KarakeepExporter:getBookmark(id)
    local result, error = self.ui.karakeep_api:getBookmark(id)
    
    if error then
        logger.err('[KarakeepExporter] Failed to get bookmark with id: ' .. id, error.message)
        return nil
    end

    if not result or not result.id then
        logger.err('[KarakeepExporter] Failed to get bookmark with id: ' .. id)
        return nil
    end

    logger.dbg('[KarakeepExporter] Got bookmark from Server with ID:', result.id)
    return result
end

---Add tags to a bookmark in Karakeep
---@param bookmark_id string The bookmark ID to attach the tags to
---@param tags table[] A list of tag objects, e.g. {{ tagName: string }}
---@return table|nil result The created bookmark data if successful
function KarakeepExporter:addTagsToBookmark(bookmark_id, tags)
    logger.dbg("[KarakeepExporter] Creating tag")
    local result, error = self.ui.karakeep_api:addTagsToBookmark(bookmark_id, {
        body = {
            tags = tags
        }
    })
    if error then
        logger.err('[KarakeepExporter] Failed to attach tags to book', error.message)
    end

    logger.dbg('[KarakeepExporter] Attached tags to Book')
    return result
end

---Create a new bookmark in Karakeep
---@param params {title: string, content: string} The bookmark data
---@return table|nil result The created bookmark data if successful
function KarakeepExporter:createBookmark(params)
    local result, error = self.ui.karakeep_api:createNewBookmark({
        body = {
            type = 'text',
            title = params.title,
            note = params.title,
            text = params.content,
        },
    })

    if error then
        logger.err('[KarakeepExporter] Failed to create bookmark:', error.message)
        Notification:error(_('Failed to create Karakeep bookmark'))
        return nil
    end

    if not result or not result.id then
        logger.err('[KarakeepExporter] Invalid response: missing bookmark ID')
        Notification:error(_('Failed to create Karakeep bookmark'))
        return nil
    end

    logger.dbg('[KarakeepExporter] Created bookmark with ID:', result.id)
    return result
end

---Update an existing bookmark in Karakeep
---@param params {id: string, content: string, title: string} The bookmark update data
---@return table|nil result The updated bookmark data if successful
function KarakeepExporter:updateBookmark(params)
    local result, error = self.ui.karakeep_api:updateBookmark(params.id, {
        body = {
            type = 'text',
            note = params.title,
            text = params.content,
        },
    })

    if error then
        logger.err('[KarakeepExporter] Failed to update bookmark:', error.message)
        Notification:error(_('Failed to update Karakeep bookmark'))
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
        logger.dbg('[KarakeepExporter] Next Book:')

        if(book.author and book.title) then
            for key, wrapper in pairs(book) do
                if(type(key) == "number" and wrapper[1]) then
                    local highlight = wrapper[1]
                    if(highlight and highlight.text and highlight.page and highlight.time) then
                        local bookmark_data = KarakeepMetadata.getBookmark(highlight.pn_xp, book.file)

                        local markdown_content = book.title .. " by " .. book.author .. " (page: " .. highlight.page .. ")"

                        --- Got all information, creating bookmarks now!

                        if bookmark_data and bookmark_data.id and self:getBookmark(bookmark_data.id) then
                            logger.dbg("[KarakeepExporter] Updating existing highlight")
                            local result = self:updateBookmark({
                                id = bookmark_data.id,
                                title = highlight.text,
                                content = markdown_content,
                            })
                            if result then
                                local tagResult = self:addTagsToBookmark(bookmark_data.id, {
                                    {tagName = "KoReader"},
                                    {tagName = book.author},
                                    {tagName = book.title}
                                })

                                if result.modifiedAt then
                                    bookmark_data.modifiedAt = result.modifiedAt
                                    KarakeepMetadata.saveBookmark(book.file, bookmark_data)
                                end
                                success_count = success_count + 1
                            else
                                error_count = error_count + 1
                            end
                        else
                            logger.dbg("[KarakeepExporter] Creating new highlight...")
                            local result = self:createBookmark({
                                title = highlight.text,
                                content = markdown_content,
                            })
                            if result then
                                if result.id then
                                local tagResult = self:addTagsToBookmark(result.id, {
                                    {tagName = "KoReader"},
                                    {tagName = book.author},
                                    {tagName = book.title}
                                })
                                end

                                KarakeepMetadata.saveBookmark(book.file, {
                                    id = result.id,
                                    createdAt = result.createdAt,
                                    modifiedAt = result.modifiedAt,
                                    pointer = highlight.pn_xp
                                })
                                logger.info("[KarakeepExporter] Created new bookmark with id: " .. result.id)
                                success_count = success_count + 1
                            else
                                error_count = error_count + 1
                            end
                        end
                    end
                end
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
        '[KarakeepExporter] Export completed:',
        success_count,
        'success,',
        error_count,
        'errors'
    )
    return error_count == 0
end

return KarakeepExporter
