local Archiver = require('ffi/archiver')
local Version = require('version')
local logger = require('logger')
local lfs = require('libs/libkoreader-lfs')
local util = require('util')
local _ = require('gettext')

---@class EpubOptions
---@field epub_path_tmp string Path to temporary EPUB file
---@field html_content string Complete HTML content for the EPUB
---@field images ImageInfo[] Array of downloaded images
---@field bookmark BookmarkResponse Bookmark data for metadata

---@class EpubModule
local EpubModule = {}

-- Extension to MIME type mapping for EPUB manifest
local EXT_TO_MIMETYPE = {
    png = 'image/png',
    jpg = 'image/jpeg',
    jpeg = 'image/jpeg',
    gif = 'image/gif',
    webp = 'image/webp',
    svg = 'image/svg+xml',
    html = 'application/xhtml+xml',
    xhtml = 'application/xhtml+xml',
    ncx = 'application/x-dtbncx+xml',
    js = 'text/javascript',
    css = 'text/css',
}

---Create EPUB file from HTML content and images
---Adapted from newsdownloader's epubdownloadbackend.lua
---@param options EpubOptions Configuration for EPUB creation
---@return boolean success Whether EPUB creation succeeded
---@return string|nil error Error message if creation failed
function EpubModule.createEpub(options)
    local epub_path_tmp = options.epub_path_tmp
    local html_content = options.html_content
    local images = options.images or {}
    local bookmark = options.bookmark

    logger.info('[EpubModule] Creating EPUB at:', epub_path_tmp)

    -- Open the ZIP file for EPUB creation
    local epub = Archiver.Writer:new({})
    if not epub:open(epub_path_tmp, 'epub') then
        logger.err('[EpubModule] Failed to create EPUB archive at:', epub_path_tmp)
        return false, _('Failed to create EPUB archive')
    end

    local mtime = os.time()
    local bookmark_title = bookmark.title
    if not bookmark_title or bookmark_title == '' then
        if bookmark.content and bookmark.content.title and bookmark.content.title ~= '' then
            bookmark_title = bookmark.content.title
        else
            bookmark_title = _('Untitled Entry')
        end
    end
    ---@cast bookmark_title -nil

    -- Find best cover image from downloaded images
    local cover_imgid = EpubModule.findCoverImage(images)

    -- Create required EPUB files
    local success, error_msg = pcall(function()
        -- 1. /mimetype (must be first and uncompressed)
        epub:setZipCompression('store')
        epub:addFileFromMemory('mimetype', 'application/epub+zip', mtime)
        epub:setZipCompression('deflate')

        -- 2. /META-INF/container.xml
        EpubModule.addContainerXml(epub, mtime)

        -- 3. OEBPS/content.opf (package document)
        EpubModule.addContentOpf(epub, bookmark, bookmark_title, images, cover_imgid, mtime)

        -- 4. OEBPS/toc.ncx (navigation)
        EpubModule.addTocNcx(epub, bookmark_title, mtime)

        -- 5. OEBPS/content.html (main content)
        epub:addFileFromMemory('OEBPS/content.html', html_content, mtime)
        logger.dbg('[EpubModule] Added main content HTML')

        -- 6. OEBPS/stylesheet.css (basic styling)
        EpubModule.addStylesheet(epub, mtime)

        -- 7. OEBPS/images/* (downloaded images)
        EpubModule.addImages(epub, images, mtime)
    end)

    -- Close the EPUB archive
    epub:close()

    if not success then
        logger.err('[EpubModule] Error creating EPUB:', error_msg)
        -- Clean up failed EPUB file
        if lfs.attributes(epub_path_tmp, 'mode') == 'file' then
            os.remove(epub_path_tmp)
        end
        return false, error_msg
    end

    logger.info('[EpubModule] Successfully created EPUB:', epub_path_tmp)

    -- Force garbage collection like newsdownloader does
    collectgarbage()
    collectgarbage()

    return true, nil
end

---Add container.xml file to EPUB
---@param epub table Archiver instance
---@param mtime number Modification time
function EpubModule.addContainerXml(epub, mtime)
    local container_xml = [[<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>]]

    epub:addFileFromMemory('META-INF/container.xml', container_xml, mtime)
    logger.dbg('[EpubModule] Added META-INF/container.xml')
end

---Add content.opf package document to EPUB
---@param epub table Archiver instance
---@param bookmark BookmarkResponse Bookmark data for metadata
---@param title string Book title
---@param images ImageInfo[] Array of images
---@param cover_imgid string|nil Cover image ID
---@param mtime number Modification time
function EpubModule.addContentOpf(epub, bookmark, title, images, cover_imgid, mtime)
    local escaped_title = util.htmlEscape(title)
    local meta_cover = cover_imgid
            and string.format('<meta name="cover" content="%s"/>', cover_imgid)
        or '<!-- no cover image -->'

    -- Extract author, publisher, and description from bookmark
    local author = 'Karakeep'
    local publisher = string.format('KOReader %s', Version:getShortVersion())
    local description = nil

    if bookmark.content then
        if bookmark.content.author and bookmark.content.author ~= '' then
            author = bookmark.content.author
        end
        if bookmark.content.publisher and bookmark.content.publisher ~= '' then
            publisher = bookmark.content.publisher
        end
        if bookmark.content.description and bookmark.content.description ~= '' then
            description = bookmark.content.description
        end
    end

    -- Build description metadata if available
    local description_meta = description
            and string.format('<dc:description>%s</dc:description>', util.htmlEscape(description))
        or '<!-- no description -->'

    -- Build content.opf parts
    local content_opf_parts = {}

    -- Header with metadata
    table.insert(
        content_opf_parts,
        string.format(
            [[<?xml version='1.0' encoding='utf-8'?>
<package xmlns="http://www.idpf.org/2007/opf"
        xmlns:dc="http://purl.org/dc/elements/1.1/"
        unique-identifier="bookid" version="2.0">
  <metadata>
    <dc:title>%s</dc:title>
    <dc:creator>%s</dc:creator>
    <dc:publisher>%s</dc:publisher>
    <dc:language>en</dc:language>
    <dc:identifier id="bookid">karakeep_%s</dc:identifier>
    %s
    %s
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="content" href="content.html" media-type="application/xhtml+xml"/>
    <item id="css" href="stylesheet.css" media-type="text/css"/>]],
            escaped_title,
            util.htmlEscape(author),
            util.htmlEscape(publisher),
            os.time(),
            meta_cover,
            description_meta
        )
    )

    -- Add image manifest items
    for _, img in ipairs(images) do
        if img.downloaded and img.filename then
            local ext = img.filename:match('.*%.([%w]+)$') or 'jpg'
            local mimetype = EXT_TO_MIMETYPE[ext:lower()] or 'image/jpeg'
            local imgid = img.filename:match('(.-)%.') or img.filename -- Remove extension for ID

            table.insert(
                content_opf_parts,
                string.format(
                    '    <item id="%s" href="images/%s" media-type="%s"/>',
                    imgid,
                    img.filename,
                    mimetype
                )
            )
        end
    end

    -- Footer with spine
    table.insert(
        content_opf_parts,
        [[  </manifest>
  <spine toc="ncx">
    <itemref idref="content"/>
  </spine>
</package>]]
    )

    local content_opf = table.concat(content_opf_parts, '\n')
    epub:addFileFromMemory('OEBPS/content.opf', content_opf, mtime)
    logger.dbg('[EpubModule] Added OEBPS/content.opf')
end

---Add toc.ncx navigation document to EPUB
---@param epub table Archiver instance
---@param title string Book title
---@param mtime number Modification time
function EpubModule.addTocNcx(epub, title, mtime)
    local escaped_title = util.htmlEscape(title)
    local bookid = 'karakeep_' .. os.time()

    local toc_ncx = string.format(
        [[<?xml version='1.0' encoding='utf-8'?>
<!DOCTYPE ncx PUBLIC "-//NISO//DTD ncx 2005-1//EN" "http://www.daisy.org/z3986/2005/ncx-2005-1.dtd">
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <head>
    <meta name="dtb:uid" content="%s"/>
    <meta name="dtb:depth" content="1"/>
    <meta name="dtb:totalPageCount" content="0"/>
    <meta name="dtb:maxPageNumber" content="0"/>
  </head>
  <docTitle>
    <text>%s</text>
  </docTitle>
  <navMap>
    <navPoint id="navpoint-1" playOrder="1">
      <navLabel>
        <text>%s</text>
      </navLabel>
      <content src="content.html"/>
    </navPoint>
  </navMap>
</ncx>]],
        bookid,
        escaped_title,
        escaped_title
    )

    epub:addFileFromMemory('OEBPS/toc.ncx', toc_ncx, mtime)
    logger.dbg('[EpubModule] Added OEBPS/toc.ncx')
end

---Add basic stylesheet to EPUB
---@param epub table Archiver instance
---@param mtime number Modification time
function EpubModule.addStylesheet(epub, mtime)
    local css = [[/* Basic EPUB stylesheet */
body {
    font-family: serif;
    line-height: 1.6;
    margin: 1em;
}

.entry-meta {
    border-bottom: 1px solid #ddd;
    padding-bottom: 1em;
    margin-bottom: 1em;
}

.entry-meta h1 {
    margin-top: 0;
    font-size: 1.5em;
}

.entry-meta p {
    margin: 0.5em 0;
    font-size: 0.9em;
    color: #666;
}

.entry-content {
    max-width: 100%;
}

.entry-content img {
    max-width: 100%;
    height: auto;
}

.youtube-thumbnail {
    text-align: center;
    margin: 1em 0;
}

.youtube-thumbnail figcaption {
    font-size: 0.9em;
    color: #666;
    margin-top: 0.5em;
}

/* Responsive images */
img {
    max-width: 100%;
    height: auto;
}

/* Better spacing for paragraphs */
p {
    margin: 1em 0;
}

/* Code blocks */
pre, code {
    font-family: monospace;
    background-color: #f5f5f5;
    padding: 0.2em 0.4em;
    border-radius: 3px;
}

pre {
    padding: 1em;
    overflow-x: auto;
}]]

    epub:addFileFromMemory('OEBPS/stylesheet.css', css, mtime)
    logger.dbg('[EpubModule] Added OEBPS/stylesheet.css')
end

---Add downloaded images to EPUB
---@param epub table Archiver instance
---@param images ImageInfo[] Array of downloaded images
---@param mtime number Modification time
function EpubModule.addImages(epub, images, mtime)
    local added_count = 0
    local skipped_count = 0

    for _, img in ipairs(images) do
        if img.downloaded and img.data and img.filename then
            -- Images don't need compression (except SVG)
            local no_compression = true
            local ext = img.filename:match('.*%.([%w]+)$')
            if ext and ext:lower() == 'svg' then
                no_compression = false -- SVG is text, can benefit from compression
            end

            local path = 'OEBPS/images/' .. img.filename
            epub:addFileFromMemory(path, img.data, no_compression, mtime)
            added_count = added_count + 1
            logger.dbg('[EpubModule] Added image:', img.filename)
        else
            skipped_count = skipped_count + 1
            logger.dbg('[EpubModule] Skipped image (not downloaded):', img.src)
        end
    end

    logger.info('[EpubModule] Added', added_count, 'images to EPUB,', skipped_count, 'skipped')
end

---Find the best image to use as cover
---@param images ImageInfo[] Array of downloaded images
---@return string|nil cover_imgid Image ID for cover, or nil if none suitable
function EpubModule.findCoverImage(images)
    local best_candidate = nil
    local best_score = 0

    for _, img in ipairs(images) do
        if img.downloaded and img.width and img.height then
            local score = 0

            -- Prefer portrait orientation
            if img.height > img.width then
                score = score + 10
            end

            -- Prefer reasonable size (not icons, not too large)
            if img.width > 100 and img.width < 800 and img.height > 100 and img.height < 1200 then
                score = score + 5
            end

            -- Prefer images closer to typical cover proportions (3:4 ratio)
            if img.width > 0 and img.height > 0 then
                local ratio = img.height / img.width
                if ratio >= 1.2 and ratio <= 1.6 then
                    score = score + 5
                end
            end

            -- Prefer PNG and JPG over other formats
            local ext = img.filename:match('.*%.([%w]+)$')
            if ext and (ext:lower() == 'png' or ext:lower() == 'jpg' or ext:lower() == 'jpeg') then
                score = score + 2
            end

            if score > best_score then
                best_score = score
                best_candidate = img
            end
        end
    end

    if best_candidate then
        local imgid = best_candidate.filename:match('(.-)%.') or best_candidate.filename
        logger.info(
            '[EpubModule] Selected cover image:',
            best_candidate.filename,
            'score:',
            best_score
        )
        return imgid
    end

    return nil
end

return EpubModule
