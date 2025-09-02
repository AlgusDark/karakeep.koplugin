local http = require('socket.http')
local ltn12 = require('ltn12')
local socket = require('socket')
local socket_url = require('socket.url')
local socketutil = require('socketutil')
local util = require('util')
local time = require('ui/time')
local _ = require('gettext')
local T = require('ffi/util').template
local logger = require('logger')

-- Third party HTML parser from KOReader base
local htmlparser = require('htmlparser')

---@class ImageInfo
---@field src string Original image URL
---@field src2x string|nil High-resolution image URL from srcset
---@field filename string Local filename for the image
---@field width number|nil Image width from HTML attributes
---@field height number|nil Image height from HTML attributes
---@field data string|nil Downloaded image data
---@field downloaded boolean Whether image was successfully downloaded
---@field error_reason string|nil Error reason if download failed

---@class ImagesModule
local ImagesModule = {}

-- Valid image file extensions for validation
local VALID_EXTENSIONS = {
    jpg = true,
    jpeg = true,
    png = true,
    gif = true,
    webp = true,
    svg = true,
}

-- MIME type mapping for EPUB manifest
local EXT_TO_MIMETYPE = {
    png = 'image/png',
    jpg = 'image/jpeg',
    jpeg = 'image/jpeg',
    gif = 'image/gif',
    webp = 'image/webp',
    svg = 'image/svg+xml',
}

---Discover images in HTML content using DOM parser
---@param html_content string HTML content to scan for images
---@param base_url table|nil Parsed base URL for resolving relative URLs
---@return ImageInfo[] images Array of discovered images
---@return table<string, ImageInfo> seen_images Map of URL to ImageInfo for deduplication
function ImagesModule.discoverImages(html_content, base_url)
    local images = {}
    local seen_images = {}
    local image_count = 0

    if not html_content or html_content == '' then
        return images, seen_images
    end

    logger.dbg('[ImagesModule] Discovering images in HTML content')

    -- Parse HTML content
    local root = htmlparser.parse(html_content, 5000)
    if not root then
        logger.warn('[ImagesModule] Failed to parse HTML for image discovery')
        return images, seen_images
    end

    -- Find all img elements
    local img_elements = root:select('img')

    if img_elements then
        for _, img_element in ipairs(img_elements) do
            local attrs = img_element.attributes or {}
            local src = attrs.src

            -- Skip invalid or data URLs
            if src and src ~= '' and src:sub(1, 5) ~= 'data:' then
                -- Normalize URL to absolute
                local normalized_src = ImagesModule.normalizeImageUrl(src, base_url)

                -- Check for duplicates
                if not seen_images[normalized_src] then
                    image_count = image_count + 1

                    -- Extract file extension
                    local ext = ImagesModule.getImageExtension(normalized_src)

                    -- Generate safe filename
                    local filename = ImagesModule.generateImageFilename(image_count, ext)

                    -- Extract dimensions
                    local width = tonumber(attrs.width)
                    local height = tonumber(attrs.height)

                    -- Extract high-resolution URL from srcset
                    local src2x = ImagesModule.extractHighResUrl(attrs.srcset, base_url)

                    local image_info = {
                        src = normalized_src,
                        src2x = src2x,
                        filename = filename,
                        width = width,
                        height = height,
                        data = nil,
                        downloaded = false,
                    }

                    images[image_count] = image_info
                    seen_images[normalized_src] = image_info
                end
            end
        end
    end

    logger.info('[ImagesModule] Discovered', #images, 'images in HTML content')
    return images, seen_images
end

---Download images with progress tracking
---@param options table Options containing images, title, trapper, on_cancellation
---@return ImageInfo[] downloaded_images Array of images with download results
function ImagesModule.downloadImagesWithProgress(options)
    local images = options.images
    local title = options.title
    local trapper = options.trapper
    local on_cancellation = options.on_cancellation

    if not images or #images == 0 then
        return {}
    end

    logger.info('[ImagesModule] Starting download of', #images, 'images')

    -- Track progress for eink optimization
    local time_prev = time.now()
    local total_images = #images
    local downloaded_count = 0
    local failed_count = 0

    for i, image in ipairs(images) do
        local user_wants_to_continue

        -- Throttled progress updates for eink displays
        if time.to_ms(time.since(time_prev)) > 1000 then
            time_prev = time.now()

            -- Full progress update with cancellation check
            user_wants_to_continue = trapper:info(
                T(_('Downloading:\n%1\n\nDownloading %2/%3 images'), title, i, total_images)
            )

            -- Handle cancellation
            if not user_wants_to_continue then
                if on_cancellation then
                    local should_continue = on_cancellation()
                    if not should_continue then
                        break
                    end
                else
                    break
                end
            end
        else
            -- Fast refresh for better UX
            trapper:info(
                T(_('Downloading:\n%1\n\nDownloading %2/%3 images'), title, i, total_images),
                true,
                true
            )
        end

        -- Download the image
        local success, image_data = ImagesModule.downloadSingleImage(image)

        if success and image_data then
            image.data = image_data
            image.downloaded = true
            downloaded_count = downloaded_count + 1
            logger.dbg('[ImagesModule] Successfully downloaded:', image.filename)
        else
            image.downloaded = false
            image.error_reason = 'network_error'
            failed_count = failed_count + 1
            logger.warn('[ImagesModule] Failed to download:', image.src)
        end
    end

    logger.info(
        '[ImagesModule] Image download complete:',
        downloaded_count,
        'successful,',
        failed_count,
        'failed'
    )
    return images
end

---Download a single image
---@param image ImageInfo Image information with src URL
---@return boolean success Whether download succeeded
---@return string|nil data Image data if successful
function ImagesModule.downloadSingleImage(image)
    local url = image.src2x or image.src
    local timeout = 10

    logger.dbg('[ImagesModule] Downloading image from:', url)

    -- Set socket timeout
    socketutil:set_timeout(timeout, 30)

    local sink = {}
    local request = {
        url = url,
        method = 'GET',
        sink = ltn12.sink.table(sink),
        headers = {
            ['User-Agent'] = 'KOReader Karakeep Plugin',
        },
    }

    local code, _headers, _status = socket.skip(1, http.request(request))
    socketutil:reset_timeout()

    local content = table.concat(sink)

    logger.dbg('[ImagesModule] HTTP response:', code, 'content length:', #content)

    -- Check for successful response
    if code == 200 and content and #content > 0 then
        -- Validate content looks like an image (basic check)
        if ImagesModule.isValidImageData(content) then
            return true, content
        else
            logger.warn('[ImagesModule] Downloaded content does not appear to be valid image data')
        end
    end

    return false, nil
end

---Process HTML images and replace src with local filenames
---@param html_content string HTML content with image tags
---@param downloaded_images ImageInfo[] Array of images with download results
---@return string processed_content HTML with updated image sources
function ImagesModule.processHtmlImages(html_content, downloaded_images)
    if not html_content or not downloaded_images then
        return html_content
    end

    -- Create mapping of original URLs to filenames
    local url_to_filename = {}
    for _, image in ipairs(downloaded_images) do
        if image.downloaded and image.filename then
            url_to_filename[image.src] = image.filename
            -- Also map 2x URL if it exists
            if image.src2x then
                url_to_filename[image.src2x] = image.filename
            end
        end
    end

    -- Replace img src attributes with local filenames
    local processed_content = html_content:gsub(
        '(<img[^>]*)src="([^"]*)"([^>]*>)',
        function(before, src, after)
            local filename = url_to_filename[src]
            if filename then
                return before .. 'src="images/' .. filename .. '"' .. after
            else
                -- Image download failed or not found - remove the img tag
                logger.dbg('[ImagesModule] Removing failed image:', src)
                return ''
            end
        end
    )

    return processed_content
end

---Normalize image URL to absolute form
---@param src string Original image URL
---@param base_url table|nil Parsed base URL
---@return string normalized_url Absolute URL
function ImagesModule.normalizeImageUrl(src, base_url)
    if not src then
        return ''
    end

    -- Handle protocol-relative URLs
    if src:sub(1, 2) == '//' then
        return 'https:' .. src
    end

    -- Handle absolute URLs
    if src:match('^https?://') then
        return src
    end

    -- Handle relative URLs
    if base_url then
        return socket_url.absolute(base_url, src) or src
    end

    return src
end

---Get appropriate file extension for image URL
---@param url string Image URL
---@return string extension File extension (default: 'jpg')
function ImagesModule.getImageExtension(url)
    if not url then
        return 'jpg'
    end

    -- Remove query parameters
    local url_path = url:match('([^%?]+)')
    if not url_path then
        url_path = url
    end

    -- Extract extension
    local ext = url_path:match('.*%.([%w]+)$')
    if ext then
        ext = ext:lower()
        if VALID_EXTENSIONS[ext] then
            return ext
        end
    end

    -- Default to jpg
    return 'jpg'
end

---Generate consistent image filename
---@param image_count number Sequential image number
---@param ext string File extension
---@return string filename Safe filename for the image
function ImagesModule.generateImageFilename(image_count, ext)
    local base_filename = 'image_' .. string.format('%03d', image_count) .. '.' .. ext
    return util.getSafeFilename(base_filename)
end

---Extract high-resolution URL from srcset attribute
---@param srcset string|nil The srcset attribute value
---@param base_url table|nil Base URL for resolving relative URLs
---@return string|nil src2x High-resolution URL or nil
function ImagesModule.extractHighResUrl(srcset, base_url)
    if not srcset then
        return nil
    end

    -- Add spaces for pattern matching
    srcset = ' ' .. srcset .. ', '

    -- Look for 2x variant
    local src2x = srcset:match([[ (%S+) 2x, ]])
    if src2x then
        return ImagesModule.normalizeImageUrl(src2x, base_url)
    end

    return nil
end

---Basic validation that content appears to be image data
---@param content string Downloaded content
---@return boolean is_valid True if content appears to be image data
function ImagesModule.isValidImageData(content)
    if not content or #content < 10 then
        return false
    end

    -- Check for common image file signatures
    local signatures = {
        '\255\216\255', -- JPEG
        '\137PNG\r\n\026\n', -- PNG
        'GIF8', -- GIF
        'RIFF', -- WebP (starts with RIFF)
        '<?xml', -- SVG
    }

    for _, sig in ipairs(signatures) do
        if content:sub(1, #sig) == sig then
            return true
        end
    end

    return false
end

---Get MIME type for image extension
---@param ext string File extension
---@return string mimetype MIME type for EPUB manifest
function ImagesModule.getMimeType(ext)
    return EXT_TO_MIMETYPE[ext:lower()] or 'application/octet-stream'
end

return ImagesModule
