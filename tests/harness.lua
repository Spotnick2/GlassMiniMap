-- harness.lua: assertions and the addon loader. dofile it after wow_stubs.lua.

local passed, failed = 0, 0

function check(cond, msg)
    if cond then passed = passed + 1 else
        failed = failed + 1
        io.write("  FAIL: " .. tostring(msg) .. "\n")
    end
end

function eq(actual, expected, msg)
    check(actual == expected, string.format("%s: expected %s, got %s", msg, tostring(expected), tostring(actual)))
end

function near(actual, expected, msg)
    check(type(actual) == "number" and math.abs(actual - expected) < 1e-6,
        string.format("%s: expected %s, got %s", msg, tostring(expected), tostring(actual)))
end

function done(name)
    io.write(string.format("%s: %d passed, %d failed\n", name, passed, failed))
    os.exit(failed == 0 and 0 or 1)
end

-- Every file line of the TOC, in load order, as written.
function tocLines()
    local lines = {}
    for line in io.lines("GlassMiniMap.toc") do
        line = line:gsub("\r", "")
        if line ~= "" and not line:match("^#") then lines[#lines + 1] = line end
    end
    return lines
end

-- Lua files listed in the TOC, in load order.
function tocFiles()
    local files = {}
    for _, line in ipairs(tocLines()) do
        if line:match("%.lua$") then files[#files + 1] = (line:gsub("\\", "/")) end
    end
    return files
end

-- The embedded LibGlass-1.0 comes from a checkout, not from Libs\ (gitignored,
-- filled by the packager): $LIBGLASS, else ../LibGlass. No checkout fails the
-- run loudly; a silently skipped library would test nothing.
LIBGLASS_XML = "Libs\\LibGlass-1.0\\LibGlass-1.0.xml"
function libGlassRoot()
    local root = (os.getenv("LIBGLASS") or "../LibGlass"):gsub("\\", "/"):gsub("/$", "")
    local f = io.open(root .. "/LibGlass-1.0.xml", "rb")
    if not f then
        error("LibGlass checkout not found at " .. root .. " (no LibGlass-1.0.xml): clone "
              .. "github.com/Spotnick2/LibGlass there or set LIBGLASS", 0)
    end
    f:close()
    return root
end

-- The Lua files the library's XML loads, as paths, in order.
function libGlassScripts()
    local root = libGlassRoot()
    local f = assert(io.open(root .. "/LibGlass-1.0.xml", "rb"))
    local xml = f:read("*a"):gsub("<!%-%-.-%-%->", "")   -- listed in a comment is not loaded
    f:close()
    local files = {}
    for file in xml:gmatch('<Script%s+file="([^"]+)"') do
        local path = root .. "/" .. file:gsub("\\", "/")
        local src = io.open(path, "rb")
        if not src then error("LibGlass checkout at " .. root .. " is missing " .. file, 0) end
        src:close()
        files[#files + 1] = path
    end
    if #files == 0 then error("LibGlass-1.0.xml at " .. root .. " lists no Script files", 0) end
    return files
end

-- Load the addon the way the client does, in a fresh session: every TOC line
-- with (name, ns), the library's XML expanded in place, then ADDON_LOADED,
-- PLAYER_LOGIN and PLAYER_ENTERING_WORLD (the compartment's bulk
-- registration runs there, as Blizzard's does).
-- opts.db: saved variables. opts.barDB: Glass MiniMap Bar's (with
-- opts.barLoaded). opts.before(): runs after the files load and before
-- ADDON_LOADED (buttons and compartment entries that exist "before us").
-- opts.tocAddons: TOC compartment entries registered at PLAYER_ENTERING_WORLD.
function loadAddon(opts)
    opts = opts or {}
    GlassMiniMap, GlassMiniMapDB, GlassMiniMapBarDB, LibStub = nil, nil, nil, nil
    WoW.reset()
    if opts.barLoaded then WoW.loaded.GlassMiniMapBar = true end
    local ns = {}
    for _, line in ipairs(tocLines()) do
        local files
        if line == LIBGLASS_XML then
            files = libGlassScripts()
        elseif line:match("%.lua$") then
            files = { (line:gsub("\\", "/")) }
        else
            error("the harness can't load TOC line " .. line, 0)
        end
        for _, file in ipairs(files) do
            local chunk = assert(loadfile(file))
            chunk("GlassMiniMap", ns)
        end
    end
    WoW.installFakeLibs()
    if opts.db then GlassMiniMapDB = opts.db end
    if opts.barDB then GlassMiniMapBarDB = opts.barDB end
    if opts.before then opts.before() end
    WoW.fire("ADDON_LOADED", "GlassMiniMap")
    WoW.fire("PLAYER_LOGIN")
    if opts.tocAddons then WoW.RegisterTocAddons(opts.tocAddons) end
    WoW.fire("PLAYER_ENTERING_WORLD", true, false)
    WoW.flushTimers(0)
    return GlassMiniMap
end

function launcher() return GlassMiniMap.Drawer.Launcher() end
function bar() return GlassMiniMap.Drawer.Frame() end
function entry(name) return GlassMiniMap.Collector.byName[name] end
function names()
    local t = {}
    for _, e in ipairs(GlassMiniMap.Collector.entries) do t[#t + 1] = e.name end
    return table.concat(t, ",")
end
