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
-- opts.db: saved variables. opts.gmb: a fake Glass MiniMap Bar API (true, or
-- its PUBLIC_API_VERSION), loaded before us as OptionalDeps makes it.
-- opts.suite: a fake Glass UI (WoW.FakeGlassUI's options, or true), loaded
-- before us too, and returned second; opts.glassUI: a GlassUI of your own.
-- opts.before(): runs after the files load and before ADDON_LOADED.
function loadAddon(opts)
    opts = opts or {}
    GlassMiniMap, GlassMiniMapDB, GlassMiniMapBar, LibStub, GlassUI = nil, nil, nil, nil, nil
    WoW.reset()
    if opts.gmb then WoW.FakeGlassMiniMapBar(opts.gmb ~= true and opts.gmb or nil) end
    local fakeUI
    if opts.suite then fakeUI = WoW.FakeGlassUI(opts.suite ~= true and opts.suite or nil) end
    if opts.glassUI ~= nil then GlassUI = opts.glassUI end
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
    if opts.db then GlassMiniMapDB = opts.db end
    if opts.before then opts.before() end
    WoW.fire("ADDON_LOADED", "GlassMiniMap")
    WoW.fire("PLAYER_LOGIN")
    WoW.fire("PLAYER_ENTERING_WORLD", true, false)
    WoW.flushTimers(0)
    return GlassMiniMap, fakeUI
end

function disc() return GlassMiniMap.Drawer.Disc() end

-- ForeverProbe, the host MinimapProbe is a module of, from its checkout:
-- $FOREVERPROBE, else ../ForeverProbe (GlassChat's loader). It's private, so
-- CI sets FOREVERPROBE_OPTIONAL=1 and the probe's tests skip there.
function loadForeverProbe()
    local root = (os.getenv("FOREVERPROBE") or "../ForeverProbe"):gsub("\\", "/"):gsub("/$", "")
    local toc = io.open(root .. "/ForeverProbe.toc", "rb")
    if not toc then
        if os.getenv("FOREVERPROBE_OPTIONAL") == "1" then
            io.write("SKIPPED: ForeverProbe isn't here (private, local only); the probe tests run locally\n")
            os.exit(0)
        end
        error("ForeverProbe checkout not found at " .. root .. ": clone it there or set FOREVERPROBE", 0)
    end
    local files = {}
    for line in toc:read("*a"):gmatch("[^\r\n]+") do
        if line:match("%.lua$") and not line:match("^#") then files[#files + 1] = root .. "/" .. line end
    end
    toc:close()
    for _, file in ipairs(files) do assert(loadfile(file))("ForeverProbe", {}) end
    WoW.fire("ADDON_LOADED", "ForeverProbe")
    return ForeverProbe
end

-- MinimapProbe, as the client loads it after the host: its TOC's files, then
-- its ADDON_LOADED. opts.db: its saved variables.
function loadProbe(opts)
    opts = opts or {}
    local dir = "Tools/MinimapProbe/"
    for line in io.lines(dir .. "MinimapProbe.toc") do
        line = line:gsub("\r", "")
        if line:match("%.lua$") and not line:match("^#") then assert(loadfile(dir .. line))("MinimapProbe", {}) end
    end
    MinimapProbeDB = opts.db
    WoW.fire("ADDON_LOADED", "MinimapProbe")
end
