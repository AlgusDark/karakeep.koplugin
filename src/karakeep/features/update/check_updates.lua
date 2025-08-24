local _ = require('gettext')
local logger = require('logger')
local InfoMessage = require('ui/widget/infomessage')
local UIManager = require('ui/uimanager')
local ConfirmBox = require('ui/widget/confirmbox')
local GitHubClient = require('karakeep/shared/github_client')

---Update checker feature for Karakeep plugin
---@class CheckUpdates
---@field current_version string Current plugin version
---@field plugin_name string Plugin name
---@field plugin_fullname string Plugin display name
---@field github_client GitHubClient GitHub API client
---@field logger_prefix string Logger prefix for log messages
local CheckUpdates = {}
CheckUpdates.__index = CheckUpdates

---@class UpdateInfo
---@field current_version string Current plugin version
---@field latest_version string Latest available version
---@field has_update boolean Whether an update is available
---@field release_name string Human-readable release name
---@field release_notes string Release notes/changelog
---@field published_at string Release publication date
---@field html_url string GitHub release page URL

---@class CheckUpdatesConfig
---@field current_version string Current plugin version
---@field plugin_name string Plugin name
---@field plugin_fullname? string Plugin display name (optional)
---@field repo_owner string GitHub repository owner
---@field repo_name string GitHub repository name
---@field logger_prefix? string Logger prefix (optional, defaults to plugin name)

---Create a new CheckUpdates instance
---@param config CheckUpdatesConfig Configuration options
---@return CheckUpdates
function CheckUpdates:new(config)
    local instance = setmetatable({}, self)
    instance.current_version = config.current_version
    instance.plugin_name = config.plugin_name
    instance.plugin_fullname = config.plugin_fullname
    instance.logger_prefix = config.logger_prefix or config.plugin_name or 'CheckUpdates'

    instance.github_client = GitHubClient:new({
        repo_owner = config.repo_owner,
        repo_name = config.repo_name,
        logger_prefix = instance.logger_prefix,
    })

    return instance
end

---Parse semantic version string into comparable numbers
---@param version string Version string like "1.2.3" or "1.2.3-dev"
---@return table {major, minor, patch, is_prerelease}
function CheckUpdates.parseVersion(version)
    -- Remove 'v' prefix if present
    local clean_version = version:gsub('^v', '')

    -- Check for pre-release suffix (e.g., "-dev", "-beta", "-alpha")
    local is_prerelease = clean_version:match('%-') ~= nil

    -- Extract base version (remove suffix)
    local base_version = clean_version:gsub('%-.*$', '')

    local major, minor, patch = base_version:match('(%d+)%.(%d+)%.(%d+)')
    return {
        major = tonumber(major) or 0,
        minor = tonumber(minor) or 0,
        patch = tonumber(patch) or 0,
        is_prerelease = is_prerelease,
    }
end

---Compare two versions
---@param current string Current version
---@param latest string Latest version
---@return boolean True if latest > current
function CheckUpdates.isNewerVersion(current, latest)
    local current_parts = CheckUpdates.parseVersion(current)
    local latest_parts = CheckUpdates.parseVersion(latest)

    -- Compare major.minor.patch first
    if latest_parts.major > current_parts.major then
        return true
    elseif latest_parts.major == current_parts.major then
        if latest_parts.minor > current_parts.minor then
            return true
        elseif latest_parts.minor == current_parts.minor then
            if latest_parts.patch > current_parts.patch then
                return true
            elseif latest_parts.patch == current_parts.patch then
                -- Same base version: stable > pre-release
                if current_parts.is_prerelease and not latest_parts.is_prerelease then
                    return true -- stable version is newer than pre-release
                end
                -- Pre-release to pre-release or stable to stable: no update
                return false
            end
        end
    end

    return false
end

---Check for updates from GitHub releases
---@param include_beta boolean Whether to include beta/pre-release versions
---@return UpdateInfo|nil update_info, string|nil error
function CheckUpdates:checkForUpdates(include_beta)
    local log_prefix = '[' .. self.logger_prefix .. ':CheckUpdates]'
    local current_version = self.current_version

    logger.info(log_prefix, 'Starting update check process')
    logger.info(log_prefix, 'Current version:', current_version)
    logger.info(log_prefix, 'Include beta releases:', include_beta)

    local releases_data, error = self.github_client:getReleases()
    if error then
        logger.warn(log_prefix, 'Failed to get releases:', error)
        return nil, error
    end

    if not releases_data or type(releases_data) ~= 'table' or #releases_data == 0 then
        logger.warn(log_prefix, 'Invalid releases data from GitHub')
        return nil, _('No releases found on GitHub')
    end

    logger.info(log_prefix, 'Found', #releases_data, 'total releases')

    -- Filter releases based on beta setting
    local filtered_releases = {}
    if include_beta then
        logger.info(log_prefix, 'Including beta releases in filter')
        filtered_releases = releases_data -- Include all releases
    else
        logger.info(log_prefix, 'Excluding beta releases from filter')
        for _, release in ipairs(releases_data) do
            if not release.prerelease then
                table.insert(filtered_releases, release)
            end
        end
    end

    if #filtered_releases == 0 then
        local msg = include_beta and _('No releases found') or _('No stable releases found')
        logger.warn(log_prefix, msg)
        return nil, msg
    end

    logger.info(log_prefix, 'Found', #filtered_releases, 'suitable releases after filtering')

    -- Get the latest suitable release (first in filtered list, GitHub returns newest first)
    local latest_release = filtered_releases[1]
    local latest_version = latest_release.tag_name

    local has_update = CheckUpdates.isNewerVersion(current_version, latest_version)
    logger.info(
        log_prefix,
        'Version check:',
        current_version,
        '->',
        latest_version,
        '(update available:',
        has_update,
        ')'
    )

    local update_info = {
        current_version = current_version,
        latest_version = latest_version,
        has_update = has_update,
        release_name = latest_release.name or latest_version,
        release_notes = latest_release.body or _('No release notes available'),
        published_at = latest_release.published_at,
        html_url = latest_release.html_url,
    }

    logger.info(log_prefix, 'Release info:')
    logger.info(log_prefix, '  Release name:', update_info.release_name)
    logger.info(log_prefix, '  Published at:', update_info.published_at)
    logger.info(log_prefix, '  Release URL:', update_info.html_url)

    return update_info, nil
end

---Show update notification dialog
---@param update_info UpdateInfo Update information to display
function CheckUpdates:showUpdateNotification(update_info)
    local plugin_name = self.plugin_fullname or self.plugin_name or 'Plugin'
    local release_notes = update_info.release_notes or _('No release notes available')

    -- Ensure we have valid strings for all components
    local current_version = update_info.current_version or 'unknown'
    local latest_version = update_info.latest_version or 'unknown'
    local release_name = update_info.release_name or latest_version
    local html_url = update_info.html_url or ''

    -- Truncate very long release notes
    if #release_notes > 300 then
        release_notes = release_notes:sub(1, 300) .. '...'
    end

    local message = string.format(
        _(
            '%s update available: %s\n\nCurrent: %s\nLatest: %s\n\n%s\n\nVisit GitHub to download the update?'
        ),
        plugin_name,
        release_name,
        current_version,
        latest_version,
        release_notes
    )

    UIManager:show(ConfirmBox:new({
        text = message,
        ok_text = _('Open GitHub'),
        cancel_text = _('Later'),
        ok_callback = function()
            local Device = require('device')
            if html_url ~= '' and Device:canExternalDictLookup() then
                Device:doExternalDictLookup(html_url, html_url)
            else
                local url_msg = html_url ~= '' and html_url or _('GitHub page not available')
                UIManager:show(InfoMessage:new({
                    text = string.format(_('Visit: %s'), url_msg),
                }))
            end
        end,
    }))
end

---Check for updates and show notification if available
---@param include_beta boolean Whether to include beta/pre-release versions
function CheckUpdates:checkAndNotify(include_beta)
    local update_info, error = self:checkForUpdates(include_beta or false)

    if error then
        local error_msg = error or _('Unknown error')
        UIManager:show(InfoMessage:new({
            text = _('Failed to check for updates: ') .. error_msg,
            timeout = 5,
        }))
        return
    end

    if not update_info then
        UIManager:show(InfoMessage:new({
            text = _('Failed to check for updates: No response'),
            timeout = 5,
        }))
        return
    end

    if update_info.has_update then
        self:showUpdateNotification(update_info)
    else
        UIManager:show(InfoMessage:new({
            text = _('You have the latest version!'),
        }))
    end
end

return CheckUpdates
