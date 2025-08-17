local BaseExporter = require('base')
local EventManager = require('karakeep/shared/event_manager')

---@class KarakeepExporter
local KarakeepExporter = BaseExporter:new({
    name = 'karakeep',
    label = 'karakeep',
    is_remote = true,
})

---Main export method called by KOReader's exporter system
---@param book_notes BookNotes[] Array of book notes to export
---@return boolean success True if export was successful
function KarakeepExporter:export(book_notes)
    -- Generate markdown for each book and prepare export data
    local books_with_markdown = {}

    for _, book in ipairs(book_notes) do
        -- Generate markdown content inline
        local md = require('template/md')
        -- selene: allow(undefined_variable)
        local plugin_settings = G_reader_settings:readSetting('exporter') or {}
        local markdown_settings = plugin_settings.markdown or {}
        local markdown_table = md.prepareBookContent(book, markdown_settings)
        local markdown_content = table.concat(markdown_table, '\n')

        table.insert(books_with_markdown, {
            book = book,
            markdown_content = markdown_content,
        })
    end

    EventManager.broadcast('ExportToKarakeep', books_with_markdown)
    return true
end

return KarakeepExporter
