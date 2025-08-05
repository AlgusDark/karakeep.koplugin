local UIManager = require('ui/uimanager')
local Event = require('ui/event')

---@class EventManager
local EventManager = {}

---Broadcast event to all widgets (all widgets receive it)
---@param event_name string # The name of the event
---@param payload? table # The payload data of the event
function EventManager.broadcast(event_name, payload)
    UIManager:broadcastEvent(Event:new(event_name, payload))
end

return EventManager
