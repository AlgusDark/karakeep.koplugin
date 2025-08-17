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
    EventManager.broadcast('ExportToKarakeep', book_notes)
    return true
end

return KarakeepExporter
