local socket_url = require('socket.url')
local _ = require('gettext')
local logger = require('logger')

---@class ContentData
---@field content string The processed content
---@field needs_epub boolean Whether content should be converted to EPUB
---@field base_url table|nil Parsed base URL for resolving relative links
---@field content_type string Type of content: 'link_html', 'link_plain', 'asset', 'text'

---@class ContentError
---@field message string Error message describing what went wrong

---@class ContentProcessor
local ContentProcessor = {}

---Detect the type of bookmark content
---@param bookmark BookmarkResponse The bookmark to analyze
---@return string content_type One of: 'link_html', 'link_plain', 'asset', 'text'
function ContentProcessor.detectContentType(bookmark)
    if not bookmark.content then
        return 'unknown'
    end

    local content = bookmark.content

    if content.type == 'link' then
        return 'link'
    elseif content.type == 'asset' then
        return 'asset'
    elseif content.type == 'text' then
        return 'text'
    end

    return 'unknown'
end

---Extract HTML content from bookmark
---@param bookmark BookmarkResponse The bookmark to process
---@return string|nil html_content The HTML content, or nil if not available
function ContentProcessor.extractHtmlContent(bookmark)
    if not bookmark.content or bookmark.content.type ~= 'link' then
        return nil
    end

    return bookmark.content.htmlContent
end

---Determine if bookmark content should be converted to EPUB
---@param bookmark BookmarkResponse The bookmark to check
---@return boolean should_convert True if EPUB conversion is appropriate
function ContentProcessor.shouldConvertToEpub(bookmark)
    local content_type = ContentProcessor.detectContentType(bookmark)

    -- Currently only support link bookmarks with HTML content
    if
        content_type == 'link'
        and bookmark.content
        and bookmark.content.htmlContent
        and bookmark.content.htmlContent ~= ''
    then
        return true
    end

    -- Future: Could support text bookmarks, certain asset types, etc.
    return false
end

---Parse base URL from bookmark for resolving relative links
---@param bookmark BookmarkResponse The bookmark to process
---@return table|nil base_url Parsed URL components, or nil if no URL
function ContentProcessor.parseBaseUrl(bookmark)
    if not bookmark.content or not bookmark.content.url then
        return nil
    end

    local url = bookmark.content.url
    local parsed = socket_url.parse(url)

    if not parsed or not parsed.scheme or not parsed.host then
        logger.warn('[ContentProcessor] Invalid URL:', url)
        return nil
    end

    return parsed
end

---Prepare bookmark content for download processing
---@param bookmark BookmarkResponse The bookmark to prepare
---@return ContentData|nil content_data The prepared content data
---@return ContentError|nil error Error if preparation failed
function ContentProcessor.prepareContent(bookmark)
    -- Validate bookmark structure
    if not bookmark then
        return nil, { message = _('No bookmark provided') }
    end

    if not bookmark.id then
        return nil, { message = _('Bookmark missing ID') }
    end

    if not bookmark.content then
        return nil, { message = _('Bookmark has no content') }
    end

    local content_type = ContentProcessor.detectContentType(bookmark)
    logger.info(
        '[ContentProcessor] Detected content type:',
        content_type,
        'for bookmark:',
        bookmark.id
    )

    -- Check if we can process this content type
    if not ContentProcessor.shouldConvertToEpub(bookmark) then
        return {
            content = '',
            needs_epub = false,
            base_url = nil,
            content_type = content_type,
        },
            nil
    end

    -- Extract content based on type
    local content = ''
    if content_type == 'link' then
        local html_content = ContentProcessor.extractHtmlContent(bookmark)
        if not html_content or html_content == '' then
            return nil, { message = _('Link bookmark has no HTML content') }
        end
        content = html_content
    elseif content_type == 'text' then
        -- Future: Handle text bookmarks
        content = bookmark.content.text or ''
    else
        return nil, { message = _('Unsupported content type: ') .. content_type }
    end

    -- Parse base URL for resolving relative links
    local base_url = ContentProcessor.parseBaseUrl(bookmark)

    -- Log content preparation
    logger.info(
        '[ContentProcessor] Prepared content for bookmark:',
        bookmark.id,
        'type:',
        content_type,
        'length:',
        #content,
        'has_base_url:',
        base_url and true or false
    )

    return {
        content = content,
        needs_epub = true,
        base_url = base_url,
        content_type = content_type,
    },
        nil
end

---Get a human-readable description of content type
---@param content_type string The content type string
---@return string description Localized description
function ContentProcessor.getContentTypeDescription(content_type)
    local descriptions = {
        link = _('Web page'),
        asset = _('File or document'),
        text = _('Text note'),
        unknown = _('Unknown content type'),
    }

    return descriptions[content_type] or descriptions.unknown
end

---Validate that content is suitable for EPUB conversion
---@param content string The content to validate
---@return boolean is_valid True if content is suitable
---@return string|nil error_message Error message if not valid
function ContentProcessor.validateContent(content)
    if not content or content == '' then
        return false, _('Content is empty')
    end

    -- Check minimum content length (avoid creating EPUBs for tiny content)
    if #content < 50 then
        return false, _('Content too short for EPUB conversion')
    end

    -- Basic HTML validation - ensure it looks like HTML
    if not content:match('<%w+[^>]*>') then
        -- Doesn't contain HTML tags - might be plain text
        logger.warn('[ContentProcessor] Content does not appear to contain HTML tags')
    end

    return true, nil
end

return ContentProcessor
