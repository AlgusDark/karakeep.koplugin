local DocSettings = require('docsettings')
local logger = require('logger')

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
function KarakeepMetadata.getBookmark(pointer,file_path)
    local karakeep_data = KarakeepMetadata.getMetadata(file_path)
    if karakeep_data and karakeep_data.bookmarks then
        if karakeep_data.bookmarks[pointer] then
            return karakeep_data.bookmarks[pointer]
        end
    end
    return nil
end

function KarakeepMetadata.getTag(id, file_path)
    local karakeep_data = KarakeepMetadata.getMetadata(file_path)
    if karakeep_data and karakeep_data.tags then
        if karakeep_data.tags[id] then
            return karakeep_data.tags[id]
        end
    end
    return nil
end

function KarakeepMetadata.saveTag(file_path, tag_data)
    local doc_settings = DocSettings:open(file_path)
    local karakeep_metadata = doc_settings:readSetting('karakeep') or {}
    if not karakeep_metadata.tags then
        karakeep_metadata.tags = {}
    end

    karakeep_metadata.tags[tag_data.id] = tag_data
    karakeep_metadata.last_updated = os.date('%Y-%m-%d %H:%M:%S', os.time())

    doc_settings:saveSetting('karakeep', karakeep_metadata)
    doc_settings:flush()
end

---Save Karakeep bookmark data to book's SDR file
---@param file_path string Path to the book file
---@param bookmark_data table The bookmark data to save (must contain id field)
function KarakeepMetadata.saveBookmark(file_path, bookmark_data)
    if not bookmark_data or not bookmark_data.pointer then
        error('bookmark_data must contain an pointer field')
    end

    local doc_settings = DocSettings:open(file_path)

    local karakeep_metadata = doc_settings:readSetting('karakeep') or {}
    if not karakeep_metadata.bookmarks then
        karakeep_metadata.bookmarks = {}
    end

    karakeep_metadata.bookmarks[bookmark_data.pointer] = bookmark_data
    karakeep_metadata.last_updated = os.date('%Y-%m-%d %H:%M:%S', os.time())

    doc_settings:saveSetting('karakeep', karakeep_metadata)
    doc_settings:flush()
end

return KarakeepMetadata
