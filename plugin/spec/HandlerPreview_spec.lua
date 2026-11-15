local helper = require 'spec_helper'

-- thumbnail(photo, w, h, callback) stands in for Lightroom's renderer: it may
-- call back at once, keep the callback for later, or never call it.
local function previewPhoto(meta, thumbnail)
    local photo = helper.fakePhoto(meta)
    photo.requestJpegThumbnail = function(self, w, h, callback)
        meta.__requested = { w, h }
        thumbnail(self, w, h, callback)
        return { request = true }
    end
    return photo
end

-- SOI, an APP0 segment to skip, then SOF0 for a width x height image
-- (855x570 by default).
local function fakeJpeg(width, height)
    width, height = width or 855, height or 570
    local app0 = string.char(0xFF, 0xE0, 0x00, 0x10) .. string.rep("\0", 14)
    local sof0 = string.char(0xFF, 0xC0, 0x00, 0x11, 0x08,
        math.floor(height / 256), height % 256, math.floor(width / 256), width % 256) .. string.rep("\0", 10)
    return string.char(0xFF, 0xD8) .. app0 .. sof0
end

local function setup(photos, onSleep, options)
    options = options or {}
    local catalog = helper.fakeCatalog({ photos = photos or {} })
    local view = { module = options.module or "develop", switches = {} }
    local active, selected = photos and photos[1], photos or {}
    catalog.getTargetPhoto = function() return active end
    catalog.getTargetPhotos = function() return selected end
    catalog.getActiveSources = function() return { "folder" } end
    catalog.setSelectedPhotos = function(_, photo, selection) active, selected = photo, selection end
    -- now is a fake clock: each sleep advances it, and tests can jump it.
    local sleeps = { count = 0, now = 0 }
    helper.installImport({
        LrApplication = { activeCatalog = function() return catalog end },
        LrDate = { currentTime = function() return sleeps.now end },
        LrLogger = helper.defaultLrLogger(),
        LrApplicationView = {
            getCurrentModuleName = function() return view.module end,
            switchToModule = function(module)
                view.switches[#view.switches + 1] = module
                view.module = module
            end,
        },
        LrDevelopController = {},
        LrSelection = { selectNone = function() active, selected = nil, {} end },
        LrStringUtils = { encodeBase64 = function(s) return "b64(" .. s .. ")" end },
        LrTasks = {
            pcall = pcall,
            sleep = function(seconds)
                sleeps.count = sleeps.count + 1
                sleeps.now = sleeps.now + seconds
                if onSleep then onSleep(sleeps.count) end
            end,
        },
    })
    package.loaded.HandlerPreview = nil
    package.loaded.DevelopSession = nil
    view.selection = function() return active, selected end
    return catalog, require 'HandlerPreview', sleeps, view
end

describe("HandlerPreview.getPhotoPreview", function()
    it("reads duplicate capture seconds raw and opens no write gate", function()
        local photo = previewPhoto({ id = "1", path = "/a.nef", dateTimeOriginal = 12345 },
            function(_, _, _, cb) cb("JPEGDATA") end)
        photo.getFormattedMetadata = function() error("formatted capture time must not be read") end
        local catalog, Handler = setup({ photo })
        catalog.withWriteAccessDo = function() error("duplicate grouping must not write") end
        local first = Handler.findDuplicateGroups({ photo_ids = { "1" } })
        photo.getRawMetadata = function(_, key)
            if key == "dateTimeOriginal" then return 12346 end
            if key == "uuid" then return "uuid-1" end
        end
        local second = Handler.findDuplicateGroups({ photo_ids = { "1" } })
        assert.are.equal(1, second.capture_time - first.capture_time)
        assert.are.equal(64, first.requested_size)
    end)

    it("supplies a statistics preview without changing the catalog", function()
        local photo = previewPhoto({ id = "1", path = "/a.nef" }, function(_, _, _, cb) cb("JPEGDATA") end)
        local _, Handler = setup({ photo })

        local r = Handler.getPhotoStats({ photo_ids = { "1" } })

        assert.are.equal("1", r.photo_id)
        assert.are.equal(512, r.requested_size)
        assert.are.same({ mime_type = "image/jpeg", data = "b64(JPEGDATA)" }, r.image)
    end)

    it("returns the rendered JPEG base64-encoded with its mime type", function()
        local meta = { id = "1", path = "/a.nef" }
        local photo = previewPhoto(meta, function(_, _, _, cb) cb("JPEGDATA") end)
        local _, Handler, sleeps = setup({ photo })

        local r = Handler.getPhotoPreview({ photo_id = "1" })

        assert.are.equal("1", r.photo_id)
        assert.are.equal(8, r.bytes)
        assert.are.same({ mime_type = "image/jpeg", data = "b64(JPEGDATA)" }, r.image)
        assert.are.same({ 512, 512 }, meta.__requested)
        assert.are.equal(0, sleeps.count)
    end)

    it("reports the dimensions Lightroom actually returned", function()
        local jpeg = fakeJpeg()
        local photo = previewPhoto({ id = "1", path = "/a.nef" }, function(_, _, _, cb) cb(jpeg) end)
        local _, Handler = setup({ photo })

        local r = Handler.getPhotoPreview({ photo_id = "1", size = 512 })

        assert.are.equal(512, r.requested_size)
        assert.are.equal(855, r.width)
        assert.are.equal(570, r.height)
    end)

    it("leaves dimensions out when the data has no readable JPEG header", function()
        local photo = previewPhoto({ id = "1", path = "/a.nef" }, function(_, _, _, cb) cb("NOTAJPEG") end)
        local _, Handler = setup({ photo })

        local r = Handler.getPhotoPreview({ photo_id = "1" })

        assert.is_nil(r.width)
        assert.is_nil(r.height)
        assert.are.equal(8, r.bytes)
    end)

    it("waits for a callback that arrives after the request returns", function()
        local pending
        local photo = previewPhoto({ id = "1", path = "/a.nef" }, function(_, _, _, cb) pending = cb end)
        local _, Handler, sleeps = setup({ photo }, function(n)
            if n == 3 then pending("LATE") end
        end)

        local r = Handler.getPhotoPreview({ photo_id = "1" })

        assert.are.equal("b64(LATE)", r.image.data)
        assert.are.equal(3, sleeps.count)
    end)

    it("keeps the first image when Lightroom calls back twice", function()
        local photo = previewPhoto({ id = "1", path = "/a.nef" }, function(_, _, _, cb)
            cb("FIRST")
            cb("SECOND")
        end)
        local _, Handler = setup({ photo })

        assert.are.equal("b64(FIRST)", Handler.getPhotoPreview({ photo_id = "1" }).image.data)
    end)

    it("passes the requested size, rounded down, to Lightroom", function()
        local meta = { id = "1", path = "/a.nef" }
        local photo = previewPhoto(meta, function(_, _, _, cb) cb("J") end)
        local _, Handler = setup({ photo })

        local r = Handler.getPhotoPreview({ photo_id = "1", size = 700.7 })

        assert.are.equal(700, r.requested_size)
        assert.are.same({ 700, 700 }, meta.__requested)
    end)

    it("asks for smaller previews until the image fits the size limit", function()
        local big = string.rep("x", 3.5 * 1024 * 1024 + 1)
        local edges = {}
        local photo = previewPhoto({ id = "1", path = "/a.nef" }, function(_, w, _, cb)
            edges[#edges + 1] = w
            cb(w > 500 and big or "SMALL")
        end)
        local _, Handler = setup({ photo })

        local r = Handler.getPhotoPreview({ photo_id = "1", size = 2048 })

        assert.are.same({ 2048, 1024, 512, 256 }, edges)
        assert.are.equal("b64(SMALL)", r.image.data)
        assert.are.equal(2048, r.requested_size)
    end)

    it("asks for smaller previews while the longest edge is over 2000px", function()
        local edges = {}
        local photo = previewPhoto({ id = "1", path = "/a.nef" }, function(_, w, _, cb)
            edges[#edges + 1] = w
            cb(w > 1500 and fakeJpeg(3420, 2280) or fakeJpeg(1710, 1140))
        end)
        local _, Handler = setup({ photo })

        local r = Handler.getPhotoPreview({ photo_id = "1", size = 2048 })

        assert.are.same({ 2048, 1024 }, edges)
        assert.are.equal(1710, r.width)
        assert.are.equal(1140, r.height)
    end)

    it("returns an image over 2000px when even the smallest preview is that big", function()
        local photo = previewPhoto({ id = "1", path = "/a.nef" }, function(_, _, _, cb)
            cb(fakeJpeg(2400, 1600))
        end)
        local _, Handler = setup({ photo })

        local r = Handler.getPhotoPreview({ photo_id = "1", size = 64 })

        assert.are.equal(2400, r.width)
    end)

    it("gives up when even the smallest preview is over the size limit", function()
        local big = string.rep("x", 3.5 * 1024 * 1024 + 1)
        local edges = {}
        local photo = previewPhoto({ id = "1", path = "/a.nef" }, function(_, w, _, cb)
            edges[#edges + 1] = w
            cb(big)
        end)
        local _, Handler = setup({ photo })

        assert.has_error(function() Handler.getPhotoPreview({ photo_id = "1", size = 300 }) end,
            "Preview is 3670017 bytes, over the 3670016 byte limit even at size 64")
        assert.are.same({ 300, 150, 75, 64 }, edges)
    end)

    it("reports the renderer's error instead of an empty image", function()
        local photo = previewPhoto({ id = "1", path = "/a.nef" }, function(_, _, _, cb)
            cb(nil, "file is offline")
        end)
        local _, Handler = setup({ photo })

        assert.has_error(function() Handler.getPhotoPreview({ photo_id = "1" }) end,
            "Preview failed: file is offline")
    end)

    it("recovers a cold thumbnail through Library and restores Develop and selection", function()
        local view
        local photo = previewPhoto({ id = "1", path = "/a.nef" }, function(_, _, _, cb)
            if view.module == "library" then cb(fakeJpeg()) else cb(nil, "error loading thumb") end
        end)
        local other = previewPhoto({ id = "2" }, function(_, _, _, cb) cb(fakeJpeg()) end)
        local catalog, Handler, sleeps
        catalog, Handler, sleeps, view = setup({ photo, other })
        catalog.withWriteAccessDo = function() error("preview recovery must not write") end

        local result = Handler.getPhotoPreview({ photo_id = "1" })

        assert.are.equal(855, result.width)
        assert.are.same({ "library", "develop" }, view.switches)
        assert.are.equal("develop", view.module)
        local active, selected = view.selection()
        assert.are.equal(photo, active)
        assert.are.same({ photo, other }, selected)
        assert.are.equal(1, sleeps.count)
    end)

    it("does not switch modules when the first thumbnail succeeds", function()
        local photo = previewPhoto({ id = "1" }, function(_, _, _, cb) cb(fakeJpeg()) end)
        local _, Handler, _, view = setup({ photo })
        Handler.getPhotoPreview({ photo_id = "1" })
        assert.are.same({}, view.switches)
    end)

    it("bounds repeated thumbnail-load errors and restores the original module", function()
        local photo = previewPhoto({ id = "1" }, function(_, _, _, cb) cb(nil, "error loading thumb") end)
        local _, Handler, sleeps, view = setup({ photo })
        assert.has_error(function() Handler.getPhotoPreview({ photo_id = "1" }) end,
            "Preview failed: error loading thumb")
        assert.are.same({ "library", "develop" }, view.switches)
        assert.is_true(sleeps.now >= 3 and sleeps.now < 3.1)
    end)

    it("does not retry unrelated renderer errors or touch the UI", function()
        local photo = previewPhoto({ id = "1" }, function(_, _, _, cb) cb(nil, "file is offline") end)
        local _, Handler, sleeps, view = setup({ photo })
        assert.has_error(function() Handler.getPhotoPreview({ photo_id = "1" }) end,
            "Preview failed: file is offline")
        assert.are.same({}, view.switches)
        assert.are.equal(0, sleeps.count)
    end)

    it("refuses to switch Library while another Develop tool owns the UI", function()
        local photo = previewPhoto({ id = "1" }, function(_, _, _, cb) cb(nil, "error loading thumb") end)
        local catalog, Handler, _, view = setup({ photo })
        local Session = require 'DevelopSession'
        Session.run("mask edit", catalog, false, function()
            assert.has_error(function() Handler.getPhotoPreview({ photo_id = "1" }) end,
                "mask edit is already running; wait for it to finish, then call again")
        end)
        assert.are.same({}, view.switches)
    end)

    it("respects the batch deadline when Library recovery still cannot render", function()
        local photo = previewPhoto({ id = "1" }, function(_, _, _, cb) cb(nil, "error loading thumb") end)
        local photos = {}
        for _ = 1, 10 do photos[#photos + 1] = photo end
        local _, Handler, sleeps, view = setup({ photo })
        local ids = {}
        for i = 1, #photos do ids[i] = "1" end
        local result = Handler.getPhotoPreviews({ photo_ids = ids })
        assert.is_false(result.complete)
        assert.is_true(#result.remaining_ids > 0)
        assert.is_true(sleeps.now >= 20 and sleeps.now < 20.1)
        assert.are.equal("develop", view.module)
    end)

    it("gives up when Lightroom never calls back", function()
        local photo = previewPhoto({ id = "1", path = "/a.nef" }, function() end)
        local _, Handler, sleeps = setup({ photo })

        assert.has_error(function() Handler.getPhotoPreview({ photo_id = "1" }) end,
            "Preview not ready after 20s")
        assert.is_true(sleeps.count >= 400)
    end)

    it("counts time outside the sleeps against the deadline", function()
        local sleeps
        local photo = previewPhoto({ id = "1", path = "/a.nef" }, function()
            sleeps.now = sleeps.now + 19.99
        end)
        local _, Handler
        _, Handler, sleeps = setup({ photo })

        assert.has_error(function() Handler.getPhotoPreview({ photo_id = "1" }) end,
            "Preview not ready after 20s")
        assert.is_true(sleeps.count <= 1)
    end)

    it("reports an unknown photo", function()
        local _, Handler = setup({})

        assert.has_error(function() Handler.getPhotoPreview({ photo_id = "missing" }) end,
            "Photo not found: missing")
    end)

    it("rejects a missing id or an out-of-range size before scanning", function()
        local meta = { id = "1", path = "/a.nef" }
        local photo = previewPhoto(meta, function(_, _, _, cb) cb("J") end)
        local catalog, Handler = setup({ photo })

        assert.has_error(function() Handler.getPhotoPreview({}) end, "photo_id is required")
        for _, size in ipairs({ 63, 2049, "big" }) do
            assert.has_error(function() Handler.getPhotoPreview({ photo_id = "1", size = size }) end,
                "size must be a number between 64 and 2048")
        end

        assert.are.equal(0, catalog.getQueryCount())
        assert.is_nil(meta.__requested)
    end)
end)


describe("HandlerPreview batch preview", function()
    it("renders in order and isolates missing photos", function()
        local one = previewPhoto({ id = "1" }, function(_, _, _, cb) cb(fakeJpeg()) end)
        local three = previewPhoto({ id = "3" }, function(_, _, _, cb) cb(fakeJpeg(400, 300)) end)
        local _, Handler = setup({ one, three })
        local result = Handler.getPhotoPreviews({ photo_ids = { "1", "2", "3" } })
        assert.is_true(result.complete)
        assert.are.equal(3, #result.previews)
        assert.are.equal("1", result.previews[1].requested_id)
        assert.matches("Photo not found", result.previews[2].error)
        assert.are.equal("3", result.previews[3].requested_id)
        assert.are.equal(256, result.previews[1].requested_size)
    end)

    it("batch preview timeout returns rendered photos and the in-flight tail", function()
        local one = previewPhoto({ id = "1" }, function(_, _, _, cb) cb(fakeJpeg()) end)
        local two = previewPhoto({ id = "2" }, function() end)
        local _, Handler = setup({ one, two })
        local result = Handler.getPhotoPreviews({ photo_ids = { "1", "2", "3" } })
        assert.is_false(result.complete)
        assert.are.equal(1, #result.previews)
        assert.are.same({ "2", "3" }, result.remaining_ids)
    end)

    it("batch preview limit refuses oversized images even at minimum size", function()
        local photo = previewPhoto({ id = "1" }, function(_, _, _, cb) cb(fakeJpeg(2001, 100)) end)
        local _, Handler = setup({ photo })
        local result = Handler.getPhotoPreviews({ photo_ids = { "1" } })
        assert.is_true(result.complete)
        assert.is_nil(result.previews[1].image)
        assert.matches("2000", result.previews[1].error)
    end)

    it("batch preview limit rejects 21 ids", function()
        local _, Handler = setup()
        local ids = {}
        for i = 1, 21 do ids[i] = tostring(i) end
        assert.has_error(function() Handler.getPhotoPreviews({ photo_ids = ids }) end,
            "photo_ids must contain between 1 and 20 photo IDs")
    end)

    it("batch preview limit preserves the 3.5 MiB per-image cap", function()
        local photo = previewPhoto({ id = "1" }, function(_, edge, _, cb)
            cb(fakeJpeg() .. string.rep("x", edge > 64 and 4 * 1024 * 1024 or 100))
        end)
        local _, Handler = setup({ photo })
        local result = Handler.getPhotoPreviews({ photo_ids = { "1" } })
        assert.is_true(result.complete)
        assert.is_nil(result.previews[1].error)
        assert.is_true(result.previews[1].bytes <= 3.5 * 1024 * 1024)
        assert.are.equal(#fakeJpeg() + 100, result.previews[1].bytes)
    end)

    it("keeps the combined JPEG bytes within 8 MiB", function()
        local photos = {}
        for i = 1, 4 do
            photos[i] = previewPhoto({ id = tostring(i) }, function(_, edge, _, cb)
                cb(fakeJpeg() .. string.rep("x", edge > 64 and 3 * 1024 * 1024 or 100))
            end)
        end
        local _, Handler = setup(photos)
        local result = Handler.getPhotoPreviews({ photo_ids = { "1", "2", "3", "4" } })
        assert.is_true(result.complete)
        assert.are.equal(4, #result.previews)
        assert.is_true(result.bytes <= 8 * 1024 * 1024)
    end)
end)
