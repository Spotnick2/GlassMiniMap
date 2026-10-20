-- Glass UI absent, broken or answering junk (#37): each case builds our own
-- material and tint, records no failure and never touches a saved key. A
-- LibGlass older than Pearl, or a New that throws: Clean, with the reason.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local function savedDB() return { material = "clean", look = { tint = "smoked" }, sun = false } end

local function same(db, msg)
    eq(rawget(db, "material"), "clean", msg .. ": material kept")
    eq(type(rawget(db, "look")) == "table" and db.look.tint, "smoked", msg .. ": tint kept")
    eq(rawget(db, "sun"), false, msg .. ": other settings kept")
end

local function own(glassUI, msg, suite)
    local GMM, ui = loadAddon({ db = savedDB(), glassUI = glassUI, suite = suite })
    check(not GMM.Suite.Following(), msg .. ": not following")
    eq(GMM.GlassPreset, "clean", msg .. ": our own material built")
    eq(GMM.Theme.Name(), "smoked", msg .. ": our own tint")
    eq(next(GMM.failures), nil, msg .. ": nothing failed")
    same(GlassMiniMapDB, msg)
    check(not GMM.Settings.SetTheme("suite"), msg .. ": no Glass UI tint choice")
    return GMM, ui
end

own(nil, "no Glass UI")
own({}, "no Suite")
own({ Suite = 5 }, "Suite not a table")
own({ Suite = { API = 2, Theme = function() return { preset = "pearl" } end, Report = function() end } }, "API 2")
own({ Suite = { API = "1", Theme = function() return { preset = "pearl" } end, Report = function() end } }, "API \"1\"")
own({ Suite = { API = 1, Theme = "pearl", Report = function() end } }, "Theme not a function")
own({ Suite = { API = 1, Theme = function() return { preset = "pearl" } end } }, "no Report")
own(setmetatable({}, { __index = function() error("boom") end }), "GlassUI's lookup throws")
own({ Suite = setmetatable({}, { __index = function() error("boom") end }) }, "Suite's lookup throws")

own(nil, "Theme throws", { answer = function() error("boom") end })
own(nil, "Theme answers a string", { answer = function() return "pearl" end })
own(nil, "Theme answers another preset", { answer = function() return { preset = "clean" } end })
own(nil, "Theme answers a number preset", { answer = function() return { preset = 5 } end })
own(nil, "the answer's lookup throws", { answer = function()
    return setmetatable({}, { __index = function() error("boom") end })
end })
local GMM, ui = own(nil, "not-following", { answer = function() return nil, "not-following" end })
eq(ui.LastReport().built, nil, "not-following: reported, our own look")
eq(ui.LastReport().own.tint, true, "...with our own tint")
GMM, ui = own(nil, "not-ready", { answer = function() return nil, "not-ready" end })
eq(GMM.Suite._test.answer(), "not-ready", "not-ready: recorded")
GMM._test.slash("suite")
check(WoW.chat[#WoW.chat]:find("not-ready", 1, true), "...and /gmm suite says so")

-- A throwing Report is harmless, and junk Look and Body payloads are ignored.
GMM = loadAddon({ glassUI = { Suite = {
    API = 1,
    Theme = function() return { preset = "pearl" } end,
    Report = function() error("boom") end,
    Look = function() return { tint = 7 } end,
    Body = function() return { tint = { "a", "b", "c" }, wash = "lots" } end,
} } })
check(GMM.Suite.Following(), "a throwing Report: still following")
eq(next(GMM.failures), nil, "...nothing failed")
eq(GMM.Theme.Name(), "clear", "a junk Look tint: our default")
eq(GMM.Ring.Glass().tint._color[1], GMM.Ring.Glass().tint.glassColor[1], "a junk Body: our own clear")
check(GMM.Settings.SetTheme("smoked"), "...and a setter still works")

-- A LibGlass older than r11 won LibStub: Pearl can't be built.
-- New refuses a copy whose ready isn't its MINOR: an old copy has both at 10.
local function libraryAt(minor)
    LibStub.minors["LibGlass-1.0"], LibStub("LibGlass-1.0").ready = minor, minor
end
local function oldLibrary() libraryAt(10) end
GMM, ui = loadAddon({ suite = true, before = oldLibrary })
eq(GMM.GlassPreset, "clean", "followed Pearl on an old LibGlass: Clean")
eq(ui.LastReport().built, nil, "...reported as not built")
eq(ui.LastReport().reason, "library-too-old", "...because the library is too old")
eq(ui.LastReport().minor, 10, "...naming its minor")
eq(next(GMM.failures), nil, "...Glass UI's page says so, not our failures")
check(GMM.Suite.MaterialStatus():find("library-too-old", 1, true), "...nor our material line")
libraryAt(11)
check(GMM.BuildGlass("pearl"), "a newer copy arriving later...")
eq(GMM.GlassPreset, "clean", "...never restyles what was built")
GMM = loadAddon({ before = oldLibrary })
eq(GMM.GlassPreset, "clean", "our own Pearl on an old LibGlass: Clean")
check(GMM.failures.material and GMM.failures.material:find("library-too-old", 1, true), "...recorded")
eq(GMM.Suite.MaterialStatus(), "Pearl needs LibGlass r11 or newer: Clean in use", "...and on the page")
eq(rawget(GlassMiniMapDB, "material"), nil, "...the setting untouched")

-- New throwing for Pearl.
local function brokenPearl()
    local lib = LibStub("LibGlass-1.0")
    local new = lib.New
    lib.New = function(self, opts)
        if opts and opts.preset == "pearl" then error("boom") end
        return new(self, opts)
    end
end
GMM, ui = loadAddon({ suite = true, before = brokenPearl })
eq(GMM.GlassPreset, "clean", "Pearl's New throwing: Clean")
eq(ui.LastReport().reason, "build-failed", "...reported as build-failed")

done("test_suite_junk")
