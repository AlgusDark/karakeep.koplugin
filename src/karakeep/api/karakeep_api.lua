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

---@class BookmarkRequestBase
---@field title? string
---@field archived? boolean
---@field favourited? boolean
---@field note? string
---@field summary? string
---@field createdAt? string
---@field crawlPriority? CrawlPriority

---@class BookmarkRequestLink : BookmarkRequestBase
---@field type 'link'
---@field url string
---@field precrawledArchiveId? number

---@class BookmarkRequestText : BookmarkRequestBase
---@field type 'text'
---@field text string
---@field sourceUrl? string

---@class BookmarkRequestAsset : BookmarkRequestBase
---@field type 'asset'
---@field assetType 'image' | 'pdf'
---@field assetId string
---@field fileName? string
---@field sourceUrl? string

---@class BookmarkContentLink
---@field type 'link'
---@field url string
---@field title string|nil
---@field description string|nil
---@field imageUrl string|nil
---@field imageAssetId string|nil
---@field screenshotAssetId string|nil
---@field fullPageArchiveAssetId string|nil
---@field precrawledArchiveAssetId string|nil
---@field videoAssetId string|nil
---@field favicon string|nil
---@field htmlContent string|nil
---@field contentAssetId string|nil
---@field crawledAt string|nil
---@field author string|nil
---@field publisher string|nil
---@field datePublished string|nil
---@field dateModified string|nil

---@class BookmarkContentText
---@field type 'text'
---@field text string
---@field sourceUrl string|nil

---@class BookmarkContentAsset
---@field type 'asset'
---@field assetType 'image'|'pdf'
---@field assetId string
---@field fileName string|nil
---@field sourceUrl string|nil
---@field size number|nil
---@field content string|nil

---@class BookmarkContentUnknown
---@field type 'unknown'

---@alias BookmarkContent BookmarkContentLink | BookmarkContentText | BookmarkContentAsset | BookmarkContentUnknown

---@class BookmarkResponse
---@field id string
---@field createdAt string
---@field modifiedAt string|nil
---@field title string|nil
---@field archived boolean
---@field favourited boolean
---@field taggingStatus "success"|"failure"|"pending"|nil
---@field summarizationStatus "success"|"failure"|"pending"|nil
---@field note string|nil
---@field summary string|nil
---@field tags table[] Array of tag objects
---@field content BookmarkContent Content object with type-specific fields
---@field assets table[] Array of asset objects

---@class BookmarkQueryParams
---@field archived? boolean Filter bookmarks by archived status
---@field favourited? boolean Filter bookmarks by favorite status
---@field sortOrder? 'asc'|'desc' Sort direction (default: 'desc')
---@field limit? number Maximum number of bookmarks to return
---@field cursor? string Pagination cursor
---@field includeContent? boolean Include bookmark content in response (default: true)

---@class BookmarksListResponse
---@field bookmarks BookmarkResponse[] Array of bookmark objects
---@field nextCursor string|nil Cursor for next page of results

---@alias ListType 'manual'|'smart'

---@class ListResponse
---@field id string
---@field name string
---@field description string|nil
---@field icon string
---@field parentId string|nil
---@field type ListType
---@field query string|nil
---@field public boolean

---@class ListsResponse
---@field lists ListResponse[] Array of list objects

---@class ListBookmarksQueryParams
---@field sortOrder? 'asc'|'desc' Sort direction (default: 'desc')
---@field limit? number Maximum number of bookmarks to return
---@field cursor? string Pagination cursor
---@field includeContent? boolean Include bookmark content in response (default: true)

---@class SingleBookmarkQueryParams
---@field includeContent? boolean Include bookmark content in response (default: true)

---@alias BookmarkRequest BookmarkRequestLink | BookmarkRequestText | BookmarkRequestAsset

-- =============================================================================
-- Bookmarks
-- =============================================================================

---Create a new bookmark
---@param config HttpClientOptions<BookmarkRequest, QueryParam[]>
---@return table|nil result, Error|nil error
function KarakeepAPI:createNewBookmark(config)
    return self.api_client:post('/bookmarks', config)
end

---Update an existing bookmark
---@param bookmark_id string The bookmark ID to update
---@param config HttpClientOptions<BookmarkRequest, QueryParam[]>
---@return table|nil result, Error|nil error
function KarakeepAPI:updateBookmark(bookmark_id, config)
    return self.api_client:patch('/bookmarks/' .. bookmark_id, config)
end

---Get all bookmarks with optional filtering and pagination
---@param config? HttpClientOptions<nil, BookmarkQueryParams>
---@return BookmarksListResponse|nil result, Error|nil error
function KarakeepAPI:getAllBookmarks(config)
    return self.api_client:get('/bookmarks', config)
end

---Get a single bookmark by ID
---@param bookmark_id string The bookmark ID to retrieve
---@param config? HttpClientOptions<nil, SingleBookmarkQueryParams>
---@return BookmarkResponse|nil result, Error|nil error
function KarakeepAPI:getBookmark(bookmark_id, config)
    return self.api_client:get('/bookmarks/' .. bookmark_id, config)
end

-- =============================================================================
-- Lists
-- =============================================================================

---Get all lists
---@return ListsResponse|nil result, Error|nil error
function KarakeepAPI:getAllLists()
    return self.api_client:get('/lists')
end

---Get a single list by ID
---@param list_id string The list ID to retrieve
---@return ListResponse|nil result, Error|nil error
function KarakeepAPI:getList(list_id)
    return self.api_client:get('/lists/' .. list_id)
end

---Get bookmarks in a specific list
---@param list_id string The list ID to get bookmarks from
---@param config? HttpClientOptions<nil, ListBookmarksQueryParams>
---@return BookmarksListResponse|nil result, Error|nil error
function KarakeepAPI:getBookmarksInList(list_id, config)
    return self.api_client:get('/lists/' .. list_id .. '/bookmarks', config)
end

return KarakeepAPI
