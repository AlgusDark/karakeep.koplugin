local EventListener = require('ui/widget/eventlistener')
local _ = require('gettext')
local T = require('ffi/util').template
local logger = require('logger')

local lfs = require('libs/libkoreader-lfs')
local socketutil = require('socketutil')

local Files = require('karakeep/shared/files')
local Notification = require('karakeep/shared/widgets/notification')

---@class BookmarksToFolder : EventListener
---@field ui UI Reference to UI for accessing registered modules
---@field settings Settings Plugin settings instance
local BookmarksToFolder = EventListener:extend({})

local DEFAULT_EXPORT_DIR = '/mnt/us/books/karakeep'

-- KOReader's JSON library decodes null as a function sentinel
local function normalizeNulls(tbl)
    if type(tbl) ~= 'table' then
        return type(tbl) == 'function' and nil or tbl
    end
    for k, v in pairs(tbl) do
        if type(v) == 'function' then
            tbl[k] = nil
        elseif type(v) == 'table' then
            normalizeNulls(v)
        end
    end
    return tbl
end

local function escapeHtml(text)
    if not text then
        return ''
    end
    text = tostring(text)
    text = text:gsub('&', '&amp;')
    text = text:gsub('<', '&lt;')
    text = text:gsub('>', '&gt;')
    text = text:gsub('"', '&quot;')
    return text
end

local imageCounter = 0

local function downloadFile(url, dest_path)
    local http = require('socket.http')
    local socket = require('socket')
    local response_body = {}
    local request = {
        url = url,
        method = 'GET',
        sink = socketutil.table_sink(response_body),
    }
    socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT)
    local code = socket.skip(1, http.request(request))
    socketutil:reset_timeout()
    if code == 200 then
        local f = io.open(dest_path, 'wb')
        if f then
            for _, chunk in ipairs(response_body) do
                f:write(chunk)
            end
            f:close()
            return true
        end
    end
    return false
end

local function stripHtmlWrappers(html)
    if not html then
        return ''
    end
    local body_content = html:match('<body[^>]*>(.-)</body>')
    if body_content then
        return body_content
    end
    local cleaned = html
    cleaned = cleaned:gsub('</?html[^>]*>', '')
    cleaned = cleaned:gsub('</?head[^>]*>', '')
    cleaned = cleaned:gsub('</?body[^>]*>', '')
    cleaned = cleaned:gsub('<script[^>]*>.-</script>', '')
    return cleaned
end

function BookmarksToFolder:downloadAndReplaceImages(html, export_dir)
    local images_dir

    local function getExt(url)
        local ext = url:match('%.([%w]+)[?&#]') or url:match('%.([%w]+)$')
        if ext and #ext <= 5 then
            return ext:lower()
        end
        return 'jpg'
    end

    local function replaceImg(img_tag)
        local src = img_tag:match('src%s*=%s*["\']([^"\']+)["\']')
        if not src then
            return img_tag
        end
        if src:match('^data:') then
            return img_tag
        end
        if not src:match('^https?://') then
            return img_tag
        end

        if not images_dir then
            images_dir = export_dir .. '/images'
            Files.createDirectories(images_dir)
        end

        imageCounter = imageCounter + 1
        local ext = getExt(src)
        local local_name = 'img_' .. string.format('%04d', imageCounter) .. '.' .. ext
        local local_path = images_dir .. '/' .. local_name

        if downloadFile(src, local_path) then
            return img_tag:gsub('(src%s*=%s*["\'])[^"\']+(["\'])', '%1images/' .. local_name .. '%2')
        end

        return img_tag
    end

    return (html:gsub('<img[^>]*>', replaceImg))
end

function BookmarksToFolder:processContentHtml(htmlContent, export_dir)
    local html = stripHtmlWrappers(htmlContent)
    if not export_dir then
        return html
    end
    return self:downloadAndReplaceImages(html, export_dir)
end

function BookmarksToFolder:getExportDir()
    local dir = self.settings and self.settings.export_dir
    if dir and dir ~= '' then
        return dir
    end
    return DEFAULT_EXPORT_DIR
end

function BookmarksToFolder:exportBookmarksToFolder()
    local NetworkMgr = require('ui/network/manager')
    if not NetworkMgr:isOnline() then
        Notification:error(_('Network is not available'))
        return
    end

    local export_dir = self:getExportDir()

    local ok, err = Files.createDirectories(export_dir)
    if not ok then
        Notification:error(_('Failed to create export directory'))
        return
    end

    local all_bookmarks = {}
    local cursor = nil

    local loading = Notification:info(_('Fetching bookmarks...'))

    while true do
        local query = {
            includeContent = true,
            archived = false,
        }
        if cursor ~= nil then
            logger.dbg('[BookmarksToFolder] cursor type:', type(cursor), 'value:', cursor)
            query.cursor = cursor
        end

        local success, result, err = pcall(function()
            return self.ui.karakeep_api:listBookmarks({
                query = query,
            })
        end)

        if not success then
            loading:close()
            logger.err('[BookmarksToFolder] Lua error:', result)
            Notification:error(_('Failed to fetch bookmarks'))
            return
        end

        if not result then
            loading:close()
            local error_msg = err and err.message or _('Unknown error')
            if type(error_msg) ~= 'string' then
                error_msg = tostring(error_msg)
            end
            logger.err('[BookmarksToFolder] API error:', error_msg)
            Notification:error(error_msg)
            return
        end

        local bookmarks = result.bookmarks or {}
        for _, bm in ipairs(bookmarks) do
            table.insert(all_bookmarks, normalizeNulls(bm))
        end

        cursor = type(result.nextCursor) == "string" and result.nextCursor or nil
        logger.dbg('[BookmarksToFolder] nextCursor type:', type(cursor), 'value:', cursor)
        if not cursor then
            break
        end
    end

    loading:close()

    if #all_bookmarks == 0 then
        Notification:info(_('No non-archived bookmarks to export'))
        return
    end

    local saved = 0
    local skipped = 0
    local errors = 0

    local saving = Notification:info(T(_('Saving %1 bookmarks...'), #all_bookmarks))

    for _, bm in ipairs(all_bookmarks) do
        local content, ext = self:formatBookmark(bm, export_dir)
        local filename = self:sanitizeFileName(self:getBookmarkTitle(bm)) .. '.' .. ext
        local filepath = export_dir .. '/' .. filename

        if lfs.attributes(filepath, 'mode') then
            skipped = skipped + 1
        else
            local write_ok, write_err = Files.writeFile(filepath, content)
            if write_ok then
                saved = saved + 1
            else
                errors = errors + 1
                logger.err('[BookmarksToFolder] Failed to write', filepath, write_err and write_err.message)
            end
        end
    end

    saving:close()

    if saved > 0 then
        local msg = T(_('Saved %1 bookmarks to %2'), saved, export_dir)
        if skipped > 0 then
            msg = msg .. ' ' .. T(_('(%1 already existed)'), skipped)
        end
        Notification:success(msg)
    elseif skipped > 0 then
        Notification:info(T(_('All %1 bookmarks already exist in %2'), skipped, export_dir))
    end
    if errors > 0 then
        Notification:warn(T(_('Failed to save %1 bookmarks'), errors))
    end
end

function BookmarksToFolder:getBookmarkTitle(bm)
    if bm.title and bm.title ~= '' then
        return bm.title
    end
    local content = bm.content or {}
    local ctype = content.type
    if ctype == 'link' then
        return content.title or content.url or bm.id
    elseif ctype == 'text' then
        local text = content.text or ''
        return #text > 0 and text:gsub('%s+', ' '):match('^%s*(.-)%s*$'):sub(1, 50) or bm.id
    elseif ctype == 'asset' then
        return content.fileName or bm.id
    end
    return bm.id
end

function BookmarksToFolder:sanitizeFileName(name)
    if not name or name == '' or type(name) ~= 'string' then
        return 'untitled'
    end
    local safe = name:gsub('[<>:"/\\|?*]', '_')
    safe = safe:gsub('%s+', ' ')
    safe = safe:match('^%s*(.-)%s*$') or safe
    if #safe == 0 then
        return 'untitled'
    end
    if #safe > 100 then
        safe = safe:sub(1, 100)
    end
    return safe
end

function BookmarksToFolder:formatBookmark(bm, export_dir)
    local content = bm.content or {}
    local ctype = content.type

    if ctype == 'link' then
        return self:buildBookmarkHtml(bm, export_dir), 'html'
    elseif ctype == 'text' then
        return self:buildBookmarkText(bm), 'txt'
    else
        return self:buildBookmarkText(bm), 'txt'
    end
end

function BookmarksToFolder:buildBookmarkHtml(bm, export_dir)
    local parts = {}
    local content = bm.content or {}

    table.insert(parts, '<?xml version="1.0" encoding="utf-8"?>')
    table.insert(parts, '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">')
    table.insert(parts, '<html xmlns="http://www.w3.org/1999/xhtml">')
    table.insert(parts, '<head>')
    table.insert(parts, '<title>' .. escapeHtml(bm.title or bm.id) .. '</title>')
    table.insert(parts, '<style>')
    table.insert(parts, [[
@page { margin: 0.3em 0; }
html, body { margin: 0; padding: 0; font-size: 1em; }
body { font-family: serif; line-height: 1.6; }
img { max-width: 100%; height: auto; }
h1 { border-bottom: 1px solid #ccc; padding-bottom: 0.3em; margin-top: 0; }
.source { margin: 0.5em 0; }
.content { border-top: 1px solid #ccc; padding-top: 0.5em; }
.content img { max-width: 100%; height: auto; }
pre { overflow-x: auto; white-space: pre-wrap; }
]])
    table.insert(parts, '</style>')
    table.insert(parts, '</head>')
    table.insert(parts, '<body>')

    table.insert(parts, '<h1>' .. escapeHtml(bm.title or bm.id) .. '</h1>')

    if content.url then
        table.insert(parts, '<p class="source"><a href="' .. escapeHtml(content.url) .. '">' .. _('Source') .. '</a></p>')
    end

    if bm.note and bm.note ~= '' then
        table.insert(parts, '<p><strong>Note:</strong><br/>' .. escapeHtml(bm.note) .. '</p>')
    end
    if bm.summary and bm.summary ~= '' then
        table.insert(parts, '<p><strong>Summary:</strong><br/>' .. escapeHtml(bm.summary) .. '</p>')
    end

    if content.htmlContent then
        table.insert(parts, '<div class="content">')
        table.insert(parts, self:processContentHtml(content.htmlContent, export_dir))
        table.insert(parts, '</div>')
    elseif content.description then
        table.insert(parts, '<div class="content">')
        table.insert(parts, '<p>' .. escapeHtml(content.description) .. '</p>')
        table.insert(parts, '</div>')
    end

    table.insert(parts, '</body>')
    table.insert(parts, '</html>')

    return table.concat(parts, '\n')
end

function BookmarksToFolder:buildBookmarkText(bm)
    local lines = {}

    table.insert(lines, 'Title: ' .. (bm.title or '(untitled)'))

    local content = bm.content or {}
    if content.type == 'link' then
        if content.url then
            table.insert(lines, 'URL: ' .. content.url)
        end
        if content.htmlContent then
            table.insert(lines, '')
            table.insert(lines, '---')
            table.insert(lines, content.htmlContent)
            table.insert(lines, '---')
        end
    elseif content.type == 'text' and content.text then
        table.insert(lines, '')
        table.insert(lines, '---')
        table.insert(lines, content.text)
        table.insert(lines, '---')
    end

    if bm.note and bm.note ~= '' then
        table.insert(lines, '')
        table.insert(lines, 'Note:')
        table.insert(lines, bm.note)
    end

    if bm.summary and bm.summary ~= '' then
        table.insert(lines, '')
        table.insert(lines, 'Summary:')
        table.insert(lines, bm.summary)
    end

    return table.concat(lines, '\n')
end

return BookmarksToFolder
