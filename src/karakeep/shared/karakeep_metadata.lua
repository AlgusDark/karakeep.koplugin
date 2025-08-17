local DocSettings = require('docsettings')

---@class KarakeepMetadata
local KarakeepMetadata = {}

---Get Karakeep metadata from book's SDR file
---@param file_path string Path to the book file
---@return table|nil karakeep_data The metadata if it exists
function KarakeepMetadata.getMetadata(file_path)
    if not DocSettings:hasSidecarFile(file_path) then
        return nil
    end

    local doc_settings = DocSettings:open(file_path)
    return doc_settings:readSetting('karakeep')
end

---Get Karakeep bookmark data from book's SDR file
---@param file_path string Path to the book file
---@return table|nil bookmark_data The bookmark data if it exists {id, createdAt, modifiedAt}
function KarakeepMetadata.getBookmark(file_path)
    local karakeep_data = KarakeepMetadata.getMetadata(file_path)
    return karakeep_data and karakeep_data.bookmark
end

---Save Karakeep bookmark data to book's SDR file
---@param file_path string Path to the book file
---@param bookmark_data table The bookmark data to save (must contain id field)
function KarakeepMetadata.saveBookmark(file_path, bookmark_data)
    if not bookmark_data or not bookmark_data.id then
        error('bookmark_data must contain an id field')
    end

    local doc_settings = DocSettings:open(file_path)

    local karakeep_metadata = {
        bookmark = bookmark_data,
        last_updated = os.date('%Y-%m-%d %H:%M:%S', os.time()),
    }

    doc_settings:saveSetting('karakeep', karakeep_metadata)
    doc_settings:flush()
end

return KarakeepMetadata
