local util = require('util')
local socket_url = require('socket.url')
local _ = require('gettext')
local logger = require('logger')

-- Third party HTML parser from KOReader base
local htmlparser = require('htmlparser')

---@class HtmlModule
local HtmlModule = {}

-- Unwanted HTML elements that won't work offline or cause issues
local UNWANTED_SELECTORS = {
    'script', -- JavaScript won't work offline
    'iframe', -- Iframes won't work offline (except YouTube which we process separately)
    'video', -- Videos won't work offline
    'object', -- Objects and embeds won't work offline
    'embed', -- Flash/multimedia embeds
    'form', -- Forms won't work offline
    'style', -- Style blocks can cause display issues
    'noscript', -- Not needed since we remove scripts
}

---Clean HTML content for offline viewing
---@param content string Raw HTML content
---@return string cleaned_html Cleaned HTML content
function HtmlModule.cleanHtml(content)
    if not content or content == '' then
        return ''
    end

    logger.dbg('[HtmlModule] Cleaning HTML content, original length:', #content)

    -- Parse HTML content
    local root = htmlparser.parse(content, 5000)
    if not root then
        logger.warn('[HtmlModule] Failed to parse HTML, returning original content')
        return content
    end

    -- Track removal statistics for debugging
    local removal_stats = {}

    -- Remove each type of unwanted element
    for _, selector in ipairs(UNWANTED_SELECTORS) do
        local elements = root:select(selector)
        if elements then
            removal_stats[selector] = #elements
            for _, element in ipairs(elements) do
                -- Remove the element from its parent
                if element.parent then
                    for i, child in ipairs(element.parent.nodes) do
                        if child == element then
                            table.remove(element.parent.nodes, i)
                            break
                        end
                    end
                end
            end
        else
            removal_stats[selector] = 0
        end
    end

    -- Convert back to string using htmlparser's gettext method
    local cleaned_content = root:gettext()

    -- Log cleaning results
    logger.dbg('[HtmlModule] HTML cleaning complete. Removed elements:', removal_stats)
    logger.dbg('[HtmlModule] Content length: before =', #content, 'after =', #cleaned_content)

    return cleaned_content
end

---Process YouTube iframes and replace with thumbnails
---@param content string HTML content containing iframes
---@return string processed_content Content with YouTube iframes replaced
function HtmlModule.processYouTubeIframes(content)
    if not content or content == '' then
        return content
    end

    logger.dbg('[HtmlModule] Processing YouTube iframes')

    -- Pattern to match YouTube iframe elements
    local youtube_iframe_pattern = '<iframe[^>]*src="[^"]*youtu[^"]*"[^>]*>.-</iframe>'

    local replacement_count = 0

    -- Replace YouTube iframes with thumbnails
    local processed_content = content:gsub(youtube_iframe_pattern, function(iframe_html)
        local replacement = HtmlModule.replaceYouTubeIframe(iframe_html)
        if replacement ~= iframe_html then
            replacement_count = replacement_count + 1
        end
        return replacement
    end)

    if replacement_count > 0 then
        logger.info('[HtmlModule] Replaced', replacement_count, 'YouTube iframes with thumbnails')
    end

    return processed_content
end

---Replace a single YouTube iframe with thumbnail
---@param iframe_html string The iframe HTML element
---@return string replacement The replacement figure/img tag or original iframe
function HtmlModule.replaceYouTubeIframe(iframe_html)
    -- Extract src URL from iframe
    local src_url = iframe_html:match('src="([^"]+)"')
    if not src_url then
        return iframe_html -- Keep original if no src found
    end

    -- Extract YouTube video ID using various patterns
    local video_id = HtmlModule.extractYouTubeVideoId(src_url)
    if not video_id then
        return iframe_html -- Keep original if no video ID found
    end

    -- Generate thumbnail URL and replacement HTML
    local thumbnail_url = string.format('https://i.ytimg.com/vi/%s/hqdefault.jpg', video_id)
    local youtube_url = string.format('https://www.youtube.com/watch?v=%s', video_id)
    local alt_text = util.htmlEscape(_('YouTube Video Thumbnail'))

    -- Create clickable thumbnail that opens YouTube video
    return string.format(
        [[<figure class="youtube-thumbnail"><a href="%s" target="_blank" rel="noopener noreferrer"><img src="%s" alt="%s" style="max-width: 100%%; height: auto;"></a><figcaption>%s</figcaption></figure>]],
        youtube_url,
        thumbnail_url,
        alt_text,
        _('Click to view on YouTube')
    )
end

---Extract YouTube video ID from various URL formats
---@param url string The YouTube URL to process
---@return string|nil video_id The extracted video ID, or nil if not found
function HtmlModule.extractYouTubeVideoId(url)
    if not url or type(url) ~= 'string' then
        return nil
    end

    -- Common YouTube URL patterns
    local patterns = {
        'youtube%.com/watch%?v=([%w%-_]+)', -- youtube.com/watch?v=ID
        'youtu%.be/([%w%-_]+)', -- youtu.be/ID
        'youtube%.com/embed/([%w%-_]+)', -- youtube.com/embed/ID
        'youtube%-nocookie%.com/embed/([%w%-_]+)', -- youtube-nocookie.com/embed/ID
        'youtube%.com/v/([%w%-_]+)', -- youtube.com/v/ID
        'youtube%.com/watch%?.*v=([%w%-_]+)', -- youtube.com/watch?feature=player_embedded&v=ID
    }

    for _, pattern in ipairs(patterns) do
        local video_id = url:match(pattern)
        if video_id then
            return video_id
        end
    end

    return nil
end

---Resolve relative URLs to absolute URLs
---@param content string HTML content with potentially relative URLs
---@param base_url table|nil Parsed base URL from socket_url.parse()
---@return string processed_content Content with resolved URLs
function HtmlModule.resolveUrls(content, base_url)
    if not content or content == '' or not base_url then
        return content
    end

    logger.dbg(
        '[HtmlModule] Resolving relative URLs with base:',
        base_url.scheme .. '://' .. base_url.host
    )

    -- Process href attributes in links
    content = content:gsub('href="([^"]*)"', function(url)
        local resolved_url = HtmlModule.resolveUrl(url, base_url)
        return 'href="' .. resolved_url .. '"'
    end)

    -- Process src attributes in images (will be handled by images module later)
    content = content:gsub('src="([^"]*)"', function(url)
        local resolved_url = HtmlModule.resolveUrl(url, base_url)
        return 'src="' .. resolved_url .. '"'
    end)

    return content
end

---Resolve a single URL to absolute form
---@param url string The URL to resolve
---@param base_url table Parsed base URL
---@return string resolved_url The resolved absolute URL
function HtmlModule.resolveUrl(url, base_url)
    if not url or url == '' then
        return url
    end

    -- Skip data URLs
    if url:sub(1, 5) == 'data:' then
        return url
    end

    -- Skip URLs that are already absolute
    if url:match('^https?://') then
        return url
    end

    -- Handle protocol-relative URLs
    if url:sub(1, 2) == '//' then
        return (base_url.scheme or 'https') .. ':' .. url
    end

    -- Use socket_url to resolve relative URLs
    local resolved = socket_url.absolute(base_url, url)
    return resolved or url
end

---Create a complete HTML document with metadata
---@param bookmark BookmarkResponse The bookmark data
---@param content string The processed HTML content
---@return string html_document Complete HTML document
function HtmlModule.createHtmlDocument(bookmark, content)
    local title = bookmark.title
    if not title or title == '' then
        if bookmark.content and bookmark.content.title and bookmark.content.title ~= '' then
            title = bookmark.content.title
        else
            title = _('Untitled Entry')
        end
    end
    title = util.htmlEscape(title)

    -- Build metadata sections
    local metadata_sections = {}

    -- Author information if available
    if bookmark.content and bookmark.content.author and bookmark.content.author ~= '' then
        table.insert(
            metadata_sections,
            string.format(
                '<p><strong>%s:</strong> %s</p>',
                _('Author'),
                util.htmlEscape(bookmark.content.author)
            )
        )
    end

    -- Publisher information if available
    if bookmark.content and bookmark.content.publisher and bookmark.content.publisher ~= '' then
        table.insert(
            metadata_sections,
            string.format(
                '<p><strong>%s:</strong> %s</p>',
                _('Publisher'),
                util.htmlEscape(bookmark.content.publisher)
            )
        )
    end

    -- Feed/source information if available
    if bookmark.content and bookmark.content.url then
        local source_url = bookmark.content.url
        local base_url = source_url:match('^(https?://[^/]+)') or source_url
        table.insert(
            metadata_sections,
            string.format(
                '<p><strong>%s:</strong> <a href="%s">%s</a></p>',
                _('Source'),
                source_url,
                util.htmlEscape(base_url)
            )
        )
    end

    -- Creation date
    if bookmark.createdAt then
        table.insert(
            metadata_sections,
            string.format('<p><strong>%s:</strong> %s</p>', _('Saved'), bookmark.createdAt)
        )
    end

    -- Karakeep bookmark info
    table.insert(
        metadata_sections,
        string.format('<p><strong>%s:</strong> %s</p>', _('Bookmark ID'), bookmark.id)
    )

    local metadata_html = table.concat(metadata_sections, '\n        ')

    -- Build description section if available
    local description_html = ''
    if bookmark.content and bookmark.content.description and bookmark.content.description ~= '' then
        description_html = string.format(
            [[
    <div class="entry-description">
        <h2>%s</h2>
        <p>%s</p>
    </div>]],
            _('Description'),
            util.htmlEscape(bookmark.content.description)
        )
    end

    -- Create complete HTML document
    local html_template = [[<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>%s</title>
    <style>
        body { font-family: serif; line-height: 1.6; margin: 2em; }
        .entry-meta { border-bottom: 1px solid #ddd; padding-bottom: 1em; margin-bottom: 1em; }
        .entry-meta h1 { margin-top: 0; }
        .entry-meta p { margin: 0.5em 0; font-size: 0.9em; color: #666; }
        .entry-description { margin-bottom: 1em; }
        .entry-description h2 { font-size: 1.2em; color: #333; margin-bottom: 0.5em; }
        .entry-description p { font-style: italic; color: #555; }
        .entry-content { max-width: 100%%; }
        .entry-content img { max-width: 100%%; height: auto; }
        .youtube-thumbnail { text-align: center; margin: 1em 0; }
        .youtube-thumbnail figcaption { font-size: 0.9em; color: #666; }
    </style>
</head>
<body>
    <div class="entry-meta">
        <h1>%s</h1>
        %s
    </div>
    %s
    <div class="entry-content">
        %s
    </div>
</body>
</html>]]

    return string.format(html_template, title, title, metadata_html, description_html, content)
end

return HtmlModule
