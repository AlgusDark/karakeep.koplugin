local http = require('socket.http')
local ltn12 = require('ltn12')
local json = require('json')
local _ = require('gettext')
local logger = require('logger')
local NetworkMgr = require('ui/network/manager')

-- GitHub API configuration
local GITHUB_API_BASE = 'https://api.github.com'
local USER_AGENT = 'KOReader-Plugin/1.0'

---Generic GitHub API client for making requests to GitHub repositories
---@class GitHubClient
---@field repo_owner string GitHub repository owner
---@field repo_name string GitHub repository name
---@field logger_prefix string Logger prefix for log messages
local GitHubClient = {}
GitHubClient.__index = GitHubClient

---@class GitHubClientConfig
---@field repo_owner string GitHub repository owner
---@field repo_name string GitHub repository name
---@field logger_prefix? string Logger prefix (optional, defaults to empty)

---Create a new GitHubClient instance
---@param config GitHubClientConfig Configuration options
---@return GitHubClient
function GitHubClient:new(config)
    local instance = setmetatable({}, self)
    instance.repo_owner = config.repo_owner
    instance.repo_name = config.repo_name
    instance.logger_prefix = config.logger_prefix or ''
    return instance
end

---Make HTTP request to GitHub API
---@param endpoint string API endpoint (e.g., '/releases', '/releases/latest')
---@return table|nil response, string|nil error
function GitHubClient:makeRequest(endpoint)
    local log_prefix = '[' .. self.logger_prefix .. 'GitHubClient]'
    local url = GITHUB_API_BASE .. '/repos/' .. self.repo_owner .. '/' .. self.repo_name .. endpoint

    logger.info(log_prefix, 'Making GitHub API request to:', url)
    logger.info(log_prefix, 'Using User-Agent:', USER_AGENT)
    logger.info(log_prefix, 'Repository:', self.repo_owner .. '/' .. self.repo_name)

    if not NetworkMgr:isOnline() then
        logger.warn(log_prefix, 'Network not available')
        return nil, _('Network not available')
    end

    logger.info(log_prefix, 'Network connection confirmed')

    local response_body = {}
    local request_config = {
        url = url,
        method = 'GET',
        headers = {
            ['User-Agent'] = USER_AGENT,
            ['Accept'] = 'application/vnd.github.v3+json',
        },
        sink = ltn12.sink.table(response_body),
    }

    logger.info(log_prefix, 'Sending HTTP request...')
    local result, status_code, headers = http.request(request_config)

    logger.info(log_prefix, 'HTTP request completed')
    logger.info(log_prefix, 'Result:', tostring(result))
    logger.info(log_prefix, 'Status code:', tostring(status_code))

    if headers then
        logger.info(log_prefix, 'Response headers received')
        if headers['x-ratelimit-remaining'] then
            logger.info(
                log_prefix,
                'GitHub rate limit remaining:',
                headers['x-ratelimit-remaining']
            )
        end
    end

    if not result or status_code ~= 200 then
        logger.warn(log_prefix, 'GitHub API request failed with status:', tostring(status_code))
        local status_str = tostring(status_code or 'unknown')
        if status_code == 404 then
            logger.warn(log_prefix, '404 - Repository not found or private (no access)')
        elseif status_code == 403 then
            logger.warn(log_prefix, '403 - Rate limited or authentication required')
        elseif status_code == 401 then
            logger.warn(log_prefix, '401 - Authentication required for private repository')
        end
        return nil, _('Failed to make GitHub request: HTTP ') .. status_str
    end

    local response_text = table.concat(response_body)
    logger.info(log_prefix, 'Response body length:', #response_text)

    logger.info(log_prefix, 'Parsing JSON response...')
    local success, parsed_json = pcall(json.decode, response_text)

    if not success then
        logger.warn(log_prefix, 'Failed to parse JSON response:', parsed_json)
        return nil, _('Failed to parse GitHub response')
    end

    logger.info(log_prefix, 'JSON parsing successful')
    return parsed_json, nil
end

---Get all releases for the repository
---@return table|nil releases, string|nil error
function GitHubClient:getReleases()
    return self:makeRequest('/releases')
end

---Get the latest release for the repository
---@return table|nil release, string|nil error
function GitHubClient:getLatestRelease()
    return self:makeRequest('/releases/latest')
end

---Get repository information
---@return table|nil repo_info, string|nil error
function GitHubClient:getRepository()
    return self:makeRequest('')
end

return GitHubClient
