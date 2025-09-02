---@meta
---@module 'ui/widget/focusmanager'

--[[--
FocusManager handles focus navigation between widgets using directional movement.
--]]
---@class FocusManager : InputContainer
---@field layout table[][] 2D layout array for focus navigation
---@field selected table Current selection coordinates {x, y}
local FocusManager = {}

---Initialize FocusManager instance
function FocusManager:init() end

---Move focus to specified position
---@param x number X coordinate in layout
---@param y number Y coordinate in layout
---@param focus_type? number Type of focus to apply
function FocusManager:moveFocusTo(x, y, focus_type) end

---Send hold event to focused widget
---@return boolean True if event was handled
function FocusManager:sendHoldEventToFocusedWidget() end

---Create new FocusManager instance
---@param opts table Options table
---@return FocusManager
function FocusManager:new(opts) end

---Extend FocusManager class
---@param o table
---@return FocusManager
function FocusManager:extend(o) end

return FocusManager
