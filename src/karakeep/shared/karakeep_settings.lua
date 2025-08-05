local DataStorage = require('datastorage')
local LuaSettings = require('luasettings')
local logger = require('logger')

---@class Settings
---@field settings table
---@field updated boolean
---@field defaults table
---@field [string] any
local Settings = {}

---Create a new Settings instance
---@param config? {defaults: table}
---@return Settings
function Settings:new(config)
    logger.dbg('Karakeep:Settings:new', config)
    local instance = {
        settings = LuaSettings:open(DataStorage:getSettingsDir() .. '/karakeep.lua'),
        updated = false,
        defaults = (config and config.defaults) or {},
    }

    setmetatable(instance, self)
    return instance
end

---Handle property reading with automatic defaults
---@param key string Property name
---@return any Property value or default
function Settings:__index(key)
    -- Handle method calls first
    if rawget(Settings, key) then
        return rawget(Settings, key)
    end

    -- Handle setting access
    local default = self.defaults[key]
    if default ~= nil then
        return self.settings:readSetting(key, default)
    end

    -- Fallback to nil for unknown keys
    return nil
end

---Handle property writing with auto-save
---@param key string Property name
---@param value any Property value
function Settings:__newindex(key, value)
    -- Handle settings
    if self.defaults[key] ~= nil then
        local old_value = self.settings:readSetting(key, self.defaults[key])
        self.settings:saveSetting(key, value)

        if old_value ~= value then
            self.updated = true
        end

        -- Broadcast settings change event
        local EventManager = require('karakeep/shared/event_manager')
        EventManager.broadcast('SettingsChange', {
            key = key,
            old_value = old_value,
            new_value = value,
        })
    else
        -- For unknown keys, set them directly on the object
        rawset(self, key, value)
    end
end

---Explicitly save settings to disk
---@return nil
function Settings:save()
    self.settings:flush()
end

return Settings
