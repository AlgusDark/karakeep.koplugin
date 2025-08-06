local EventListener = require('ui/widget/eventlistener')

local HttpClient = require('karakeep/shared/http_client')

---@class KarakeepAPI : EventListener
---@field server_address string Server address for API calls
---@field api_token string API token for authentication
---@field api_base string API base URL
---@field api_client HttpClient Generic HTTP API client
local KarakeepAPI = EventListener:extend({})

---Create a new HttpClient instance
---@param config HttpClientConfig
---@return HttpClient
local function createHttpClient(config)
    return HttpClient:new({
        server_address = config.server_address,
        api_token = config.api_token,
        api_base = config.api_base,
    })
end

---Initialize the API instance with configuration
function KarakeepAPI:init()
    self.api_client = createHttpClient({
        server_address = self.server_address,
        api_token = self.api_token,
        api_base = self.api_base,
    })
end

---Handle server configuration change event
---@param args {api_token: string, server_address: string} New server configuration
function KarakeepAPI:onServerConfigChange(args)
    self.api_token = args.api_token
    self.server_address = args.server_address

    -- Recreate HttpClient with new settings
    self.api_client = createHttpClient({
        server_address = self.server_address,
        api_token = self.api_token,
        api_base = self.api_base,
    })
end

-- =============================================================================
-- Bookmarks
-- =============================================================================

---@alias CrawlPriority 'low' | 'normal'

---@class BookmarkBase
---@field title? string
---@field archived? boolean
---@field favourited? boolean
---@field note? string
---@field summary? string
---@field created_at? string
---@field crawlPriority? CrawlPriority

---@class BookmarkLink : BookmarkBase
---@field type 'link'
---@field url string
---@field precrawledArchiveId? number

---@class BookmarkText : BookmarkBase
---@field type 'text'
---@field text string
---@field sourceUrl? string

---@class BookmarkAsset : BookmarkBase
---@field type 'asset'
---@field assetType 'image' | 'pdf'
---@field assetId string
---@field fileName? string
---@field sourceUrl? string

---@alias Bookmark BookmarkLink | BookmarkText | BookmarkAsset

---Create a new bookmark
---@param config HttpClientOptions<Bookmark, QueryParam[]>
---@return table|nil result, Error|nil error
function KarakeepAPI:createNewBookmark(config)
    return self.api_client:post('/bookmarks', config)
end

return KarakeepAPI
