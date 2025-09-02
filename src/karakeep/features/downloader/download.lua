local UIManager = require('ui/uimanager')
local InfoMessage = require('ui/widget/infomessage')
local Trapper = require('ui/trapper')
local util = require('util')
local lfs = require('libs/libkoreader-lfs')
local FFIUtil = require('ffi/util')
local DocSettings = require('docsettings')
local _ = require('gettext')
local T = require('ffi/util').template
local logger = require('logger')

---@class DownloadOptions
---@field bookmark BookmarkResponse The bookmark to download
---@field browser Browser Browser instance for navigation
---@field ui UI UI manager reference for proper file opening
---@field data_dir string Karakeep data directory path

---@class Downloader
local Downloader = {}

-- Workflow message templates for consistency
local WORKFLOW_MESSAGES = {
    DUPLICATE_CHECK = _('Checking for existing download...'),
    DOWNLOAD_PREPARING = _('Downloading:\n%1\n\nPreparing...'),
    DOWNLOAD_IMAGES = _('Downloading:\n%1\n\nDownloading %2/%3 images'),
    DOWNLOAD_PROCESSING = _('Downloading:\n%1\n\nProcessing content...'),
    DOWNLOAD_COMPLETING = _('Downloading:\n%1\n\nFinalizing EPUB...'),
}

---Get effective title from bookmark (bookmark.title or bookmark.content.title)
---@param bookmark BookmarkResponse The bookmark to get title from
---@param default_title? string Default title if neither is available (default: 'Untitled')
---@return string title The effective title
local function getEffectiveTitle(bookmark, default_title)
    default_title = default_title or _('Untitled')
    local title = bookmark.title
    if not title or title == '' then
        if bookmark.content and bookmark.content.title and bookmark.content.title ~= '' then
            title = bookmark.content.title
        else
            title = default_title
        end
    end
    ---@cast title -nil
    return title
end

---Execute complete download workflow with progress tracking
---@param options DownloadOptions Configuration containing bookmark, browser, and data directory
function Downloader:execute(options)
    local bookmark = options.bookmark
    local browser = options.browser
    local ui = options.ui
    local data_dir = options.data_dir

    -- Validate inputs
    if not bookmark or not bookmark.id then
        UIManager:show(InfoMessage:new({
            text = _('Invalid bookmark data'),
            timeout = 3,
        }))
        return
    end

    local download_dir = data_dir .. '/karakeep/'

    -- Ensure download directory exists
    if not lfs.attributes(download_dir, 'mode') then
        local success = lfs.mkdir(download_dir)
        if not success then
            UIManager:show(InfoMessage:new({
                text = _('Failed to create download directory'),
                timeout = 3,
            }))
            return
        end
    end

    -- Execute workflow in Trapper for UI progress tracking
    Trapper:wrap(function()
        -- Generate safe filename from title
        local safe_title = util.getSafeFilename(getEffectiveTitle(bookmark, 'untitled'))
        local epub_path = download_dir .. safe_title .. '.epub'
        local epub_path_tmp = epub_path .. '.tmp'

        -- Check for existing download
        if lfs.attributes(epub_path, 'mode') == 'file' then
            local existing_metadata = self:getDownloadMetadata(epub_path)

            if
                existing_metadata
                and existing_metadata.download
                and existing_metadata.download.id == bookmark.id
            then
                -- Same bookmark already downloaded
                local choice = Trapper:confirm(
                    T(
                        _("'%1' already downloaded.\nLast downloaded: %2"),
                        getEffectiveTitle(bookmark),
                        existing_metadata.download.date
                                and os.date('%Y-%m-%d %H:%M', existing_metadata.download.date)
                            or _('Unknown')
                    ),
                    _('Open existing'),
                    _('Re-download')
                )

                if choice then
                    -- Open existing file
                    self:openFile(epub_path, browser, ui)
                    return
                else
                    -- Re-download: clean up existing
                    self:cleanupExistingFile(epub_path)
                end
            else
                -- Different bookmark with same title - find unique filename
                epub_path = self:findUniqueFilename(download_dir, safe_title)
                epub_path_tmp = epub_path .. '.tmp'
            end
        end

        -- Phase 1: Prepare content
        local user_wants_to_continue =
            Trapper:info(T(WORKFLOW_MESSAGES.DOWNLOAD_PREPARING, getEffectiveTitle(bookmark)))

        if not self:handleCancellation(user_wants_to_continue, epub_path_tmp) then
            return
        end

        -- Detect content type and prepare for processing
        local ContentProcessor = require('karakeep/features/downloader/modules/content_processor')
        local content_data, content_error = ContentProcessor.prepareContent(bookmark)

        if content_error then
            UIManager:show(InfoMessage:new({
                text = _('Failed to prepare content: ') .. content_error.message,
                timeout = 5,
            }))
            return
        end

        if not content_data or not content_data.needs_epub then
            UIManager:show(InfoMessage:new({
                text = _('This bookmark type is not supported for EPUB conversion yet'),
                timeout = 3,
            }))
            return
        end

        -- Phase 2: Process HTML content
        user_wants_to_continue =
            Trapper:info(T(WORKFLOW_MESSAGES.DOWNLOAD_PROCESSING, getEffectiveTitle(bookmark)))

        if not self:handleCancellation(user_wants_to_continue, epub_path_tmp) then
            return
        end

        local HtmlModule = require('karakeep/features/downloader/modules/html')
        local cleaned_html = HtmlModule.cleanHtml(content_data and content_data.content or '')
        cleaned_html = HtmlModule.processYouTubeIframes(cleaned_html)
        cleaned_html = HtmlModule.resolveUrls(cleaned_html, content_data and content_data.base_url)

        -- Phase 3: Discover and download images
        local ImagesModule = require('karakeep/features/downloader/modules/images')
        local images =
            ImagesModule.discoverImages(cleaned_html, content_data and content_data.base_url)

        local downloaded_images = {}
        if #images > 0 then
            downloaded_images = ImagesModule.downloadImagesWithProgress({
                images = images,
                title = getEffectiveTitle(bookmark),
                trapper = Trapper,
                on_cancellation = function()
                    return self:handleCancellation(false, epub_path_tmp)
                end,
            })

            -- Update HTML with downloaded images
            cleaned_html = ImagesModule.processHtmlImages(cleaned_html, downloaded_images)
        end

        -- Phase 4: Create final HTML document
        local final_html = HtmlModule.createHtmlDocument(bookmark, cleaned_html)

        -- Phase 5: Generate EPUB
        user_wants_to_continue =
            Trapper:info(T(WORKFLOW_MESSAGES.DOWNLOAD_COMPLETING, getEffectiveTitle(bookmark)))

        if not self:handleCancellation(user_wants_to_continue, epub_path_tmp) then
            return
        end

        local EpubModule = require('karakeep/features/downloader/modules/epub')
        local success, epub_error = EpubModule.createEpub({
            epub_path_tmp = epub_path_tmp,
            html_content = final_html,
            images = downloaded_images,
            bookmark = bookmark,
        })

        if not success then
            UIManager:show(InfoMessage:new({
                text = _('Failed to create EPUB: ') .. (epub_error or _('Unknown error')),
                timeout = 5,
            }))
            self:cleanupTempFile(epub_path_tmp)
            return
        end

        -- Move temp file to final location
        os.rename(epub_path_tmp, epub_path)

        -- Save download metadata
        self:saveDownloadMetadata(epub_path, bookmark)

        -- Clean up memory
        collectgarbage()
        collectgarbage()

        -- Prompt user to open the file
        local should_open =
            Trapper:confirm(_('Download completed. Open the file?'), _('Later'), _('Open now'))

        if should_open then
            self:openFile(epub_path, browser, ui)
        end
    end)
end

---Handle cancellation with cleanup
---@param user_wants_to_continue boolean User choice from Trapper:info()
---@param temp_file_path string Path to temp file for cleanup
---@return boolean true to continue, false to cancel
function Downloader:handleCancellation(user_wants_to_continue, temp_file_path)
    if user_wants_to_continue then
        return true
    end

    -- User cancelled - clean up and exit
    logger.info('[Karakeep:Downloader] User cancelled download, cleaning up')
    self:cleanupTempFile(temp_file_path)
    return false
end

---Get download metadata from EPUB file's SDR
---@param epub_path string Path to EPUB file
---@return table|nil metadata Karakeep metadata from SDR
function Downloader:getDownloadMetadata(epub_path)
    if not DocSettings:hasSidecarFile(epub_path) then
        return nil
    end

    local doc_settings = DocSettings:open(epub_path)
    local karakeep_data = doc_settings:readSetting('karakeep')
    doc_settings:close()

    return karakeep_data
end

---Save download metadata to EPUB file's SDR
---@param epub_path string Path to EPUB file
---@param bookmark BookmarkResponse Bookmark data
function Downloader:saveDownloadMetadata(epub_path, bookmark)
    local doc_settings = DocSettings:open(epub_path)

    local karakeep_data = doc_settings:readSetting('karakeep') or {}

    -- Store download info under karakeep.download to avoid collision with karakeep.bookmark
    karakeep_data.download = {
        id = bookmark.id,
        date = os.time(),
        url = bookmark.content and bookmark.content.url,
        type = bookmark.content and bookmark.content.type or 'link',
    }
    karakeep_data.last_updated = os.date('%Y-%m-%d %H:%M:%S', os.time())

    doc_settings:saveSetting('karakeep', karakeep_data)
    doc_settings:flush()
    doc_settings:close()

    logger.info('[Karakeep:Downloader] Saved metadata for bookmark', bookmark.id)
end

---Find unique filename when collision occurs
---@param download_dir string Download directory path
---@param base_title string Base filename without extension
---@return string unique_path Unique file path
function Downloader:findUniqueFilename(download_dir, base_title)
    local counter = 1
    local epub_path

    repeat
        local filename = base_title .. '_' .. counter .. '.epub'
        epub_path = download_dir .. filename
        counter = counter + 1
    until not lfs.attributes(epub_path, 'mode')

    return epub_path
end

---Clean up existing file and its SDR directory
---@param epub_path string Path to EPUB file
function Downloader:cleanupExistingFile(epub_path)
    -- Remove the file
    os.remove(epub_path)

    -- Remove SDR directory
    local sdr_dir = DocSettings:getSidecarDir(epub_path)
    if lfs.attributes(sdr_dir, 'mode') == 'directory' then
        FFIUtil.purgeDir(sdr_dir)
    end
end

---Clean up temporary file
---@param temp_path string Path to temporary file
function Downloader:cleanupTempFile(temp_path)
    if lfs.attributes(temp_path, 'mode') == 'file' then
        os.remove(temp_path)
    end
end

---Open downloaded file in reader and close browser
---@param epub_path string Path to EPUB file
---@param browser Browser|nil Browser instance to close
---@param ui UI UI manager reference for proper file opening
function Downloader:openFile(epub_path, browser, ui)
    -- Close browser first to free resources
    if browser and browser.close_callback then
        browser.close_callback()
    end

    -- Open file using appropriate method
    ---@cast ui +{document: any}
    if ui and ui.document then
        -- Already in reader, switch document
        ---@cast ui +{switchDocument: fun(self, path: string)}
        ui:switchDocument(epub_path)
    elseif ui then
        -- In FileManager, open file
        ---@cast ui +{openFile: fun(self, path: string)}
        ui:openFile(epub_path)
    else
        -- Fallback to direct ReaderUI (shouldn't happen normally)
        local ReaderUI = require('apps/reader/readerui')
        ReaderUI:showReader(epub_path)
    end
end

return Downloader
