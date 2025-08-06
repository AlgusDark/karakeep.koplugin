local _ = require('gettext')
local CheckUpdates = require('karakeep/features/update/check_updates')

---Get the "Check for updates" menu item
---@param karakeep Karakeep
---@return table MenuItem
local function getCheckForUpdatesMenuItem(karakeep)
    return {
        text = _('Check for updates'),
        callback = function()
            -- Create update checker instance with data from karakeep
            local update_checker = CheckUpdates:new({
                current_version = karakeep.version,
                plugin_name = karakeep.name,
                plugin_fullname = karakeep.fullname,
                repo_owner = karakeep.repo_owner,
                repo_name = karakeep.repo_name,
                logger_prefix = 'Karakeep',
            })

            -- Check for updates with current settings
            local include_beta = karakeep.settings and karakeep.settings.include_beta_releases
                or false
            update_checker:checkAndNotify(include_beta)
        end,
        help_text = _('Check for plugin updates on GitHub'),
    }
end

---Get the "Update Settings" menu item
---@param karakeep Karakeep
---@return table MenuItem
local function getUpdateSettingsMenuItem(karakeep)
    return {
        text = _('Update Settings'),
        sub_item_table = {
            {
                text = _('Include beta releases'),
                checked_func = function()
                    return karakeep.settings and karakeep.settings.include_beta_releases
                end,
                callback = function()
                    if karakeep.settings then
                        karakeep.settings.include_beta_releases =
                            not karakeep.settings.include_beta_releases
                    end
                end,
                help_text = _('Include pre-release/beta versions when checking for updates'),
            },
        },
    }
end

return {
    getCheckForUpdatesMenuItem = getCheckForUpdatesMenuItem,
    getUpdateSettingsMenuItem = getUpdateSettingsMenuItem,
}
