-- GlassMiniMap.lua: bootstrap, saved settings, the settings helpers and the
-- /gmm command. Loads last: every module is defined by now.

local ADDON = ...
GlassMiniMap = GlassMiniMap or {}
local GMM = GlassMiniMap
local API = GMM.API
local say = API.Print

-- GlassMiniMapDB, account-wide. Only what the player SET is saved: the rest
-- falls through to DEFAULTS, so a changed default reaches everyone (GlassMail's
-- rule). The drawer's settings are Glass MiniMap Bar's own. The tint is not
-- here: it's GlassMiniMapDB.look.tint, never pruned (Theme.lua, #37).
local DEFAULTS = {
    material = "pearl",       -- "pearl" | "clean", built at load (Glass UI's while following)
    sun = true,               -- the day/night disc
    glassTracking = true,     -- the magnifier opens the glass menu (off: Blizzard's)
    runicMode = false,
    runeStyle = "glowing",
    runeMotion = "sway",
    runeFog = true,
    runeIntensity = 100,      -- percent of the current glow strength
    runeSpeed = 100,          -- orbit speed percent (30 seconds at 100)
    indicators = "pills",     -- mail and instance size: "pills" (zone and coords pills) | "ring" (discs)
}
GMM.DEFAULTS = DEFAULTS
local BOOLEANS = { sun = true, glassTracking = true, runicMode = true, runeFog = true }
local RUNE_CHOICES = { runeStyle = { etched = true, glowing = true }, runeMotion = { sway = true, orbit = true } }
local RUNE_RANGES = { runeIntensity = { 0, 100 }, runeSpeed = { 25, 200 } }
local INDICATORS = { pills = true, ring = true }
local function validRuneNumber(key, value)
    local range = RUNE_RANGES[key]
    return range and type(value) == "number" and value == value
        and value >= range[1] and value <= range[2]
end

local function steppedRuneNumber(key, value)
    local lo = RUNE_RANGES[key][1]
    return lo + math.floor((value - lo) / 5 + 0.5) * 5
end

-- The player's own tint, kept apart (#37): look.tint, an override while
-- following Glass UI. A saved `theme` from before moves in once, unless a
-- look.tint is already there; the old prune never saved "clear", so no
-- default turns into an override. Junk is dropped.
local function migrateLook(db)
    local look = db.look
    local tint = type(look) == "table" and look.tint or nil
    if not GMM.Theme.IsValid(tint) then tint = nil end
    if tint == nil and GMM.Theme.IsValid(db.theme) then tint = db.theme end
    db.theme = nil
    db.look = tint and { tint = tint } or nil
end

local function ensureDefaults()
    if type(GlassMiniMapDB) ~= "table" then GlassMiniMapDB = {} end
    local db = setmetatable(GlassMiniMapDB, nil)
    migrateLook(db)
    for k, v in pairs(DEFAULTS) do
        if db[k] == v then db[k] = nil end
    end
    if db.material ~= nil and not GMM.MATERIALS[db.material] then db.material = nil end
    for k in pairs(BOOLEANS) do
        if db[k] ~= nil and type(db[k]) ~= "boolean" then db[k] = nil end
    end
    for key in pairs(RUNE_RANGES) do
        if db[key] ~= nil then
            db[key] = validRuneNumber(key, db[key]) and steppedRuneNumber(key, db[key]) or nil
            if db[key] == DEFAULTS[key] then db[key] = nil end
        end
    end
    for key, choices in pairs(RUNE_CHOICES) do
        if db[key] ~= nil and not choices[db[key]] then db[key] = nil end
    end
    if db.indicators ~= nil and not INDICATORS[db.indicators] then db.indicators = nil end
    db.drawer = nil   -- the absorbed drawer of a pre-release build; Glass MiniMap Bar keeps its own
    -- Pre-release coordinate settings: Blizzard's own CVars now (Footer.lua).
    db.coords, db.coordsTenths = nil, nil
    setmetatable(db, { __index = DEFAULTS })
    return db
end

-- Every setting goes through here: /gmm and the options pages.
local Settings = {}
GMM.Settings = Settings

local function store(key, value)
    if value == DEFAULTS[key] then GMM.db[key] = nil else GMM.db[key] = value end
end

function Settings.SetRunicMode(on)
    store("runicMode", on == true)
    local rendered = GMM.Ring.UpdateRunes("runicMode")
    GMM.Options.RefreshRunicControls()
    if not rendered then API.Print("Runic settings saved, but effects are unavailable. See /gmm failures.") end
    return rendered
end

function Settings.SetRuneOption(kind, value)
    local key
    if kind == "style" and RUNE_CHOICES.runeStyle[value] then key = "runeStyle"
    elseif kind == "motion" and RUNE_CHOICES.runeMotion[value] then key = "runeMotion"
    elseif kind == "fog" and (value == "on" or value == "off") then key, value = "runeFog", value == "on"
    else return false end
    if GMM.db[key] ~= value then
        store(key, value)
        GMM.Ring.UpdateRunes(key)
    end
    GMM.Options.RefreshRunicControls()
    return true
end

function Settings.SetRuneTuning(key, value)
    if not validRuneNumber(key, value) then return false end
    value = steppedRuneNumber(key, value)
    if GMM.db[key] ~= value then
        store(key, value)
        GMM.Ring.UpdateRunes(key)
    end
    GMM.Options.RefreshRunicControls()
    return true
end

local function tintChanged()
    GMM.Theme.Refresh()
    GMM.Options.RefreshRunicControls()
    GMM.Suite.Report()
end

-- The player's own tint (an override while following Glass UI's look), or
-- "suite": follow Glass UI's again (only while following it). False for
-- anything else; the setting is left as it was.
function Settings.SetTheme(name)
    if name == "suite" then
        if not GMM.Suite.LookFollowing() then return false end
        return Settings.ClearTheme()
    end
    if not GMM.Theme.IsValid(name) then return false end
    GMM.db.look = { tint = name }
    tintChanged()
    return true
end

-- No tint of the player's own: the suite's while following, else clear (the
-- probe's restore puts back "none" this way).
function Settings.ClearTheme()
    GMM.db.look = nil
    tintChanged()
    return true
end

-- Our own material, built at load: Glass UI's replaces it while following.
function Settings.Material()
    local m = GMM.db and GMM.db.material
    return GMM.MATERIALS[m] and m or DEFAULTS.material
end

-- Saved for the next /reload. Refused while following Glass UI (it stays as
-- saved, unused): false, "set in Glass UI". False for an unknown material.
function Settings.SetMaterial(name)
    if GMM.Suite.Following() then return false, "set in Glass UI" end
    if not GMM.MATERIALS[name] then return false end
    store("material", name)
    GMM.Options.Refresh()
    return true
end

-- Where new mail and the instance's size show: "pills" (the zone pill's
-- envelope, the coords pill's text) or "ring" (the two discs) (#27).
function Settings.Indicators()
    return GMM.db and INDICATORS[GMM.db.indicators] and GMM.db.indicators or DEFAULTS.indicators
end

-- False for anything else; the setting is left as it was. Applied live.
function Settings.SetIndicators(where)
    if not INDICATORS[where] then return false end
    store("indicators", where)
    GMM.Mail.Update()
    GMM.Difficulty.Sync()
    GMM.Footer.Layout()
    GMM.Options.Refresh()
    return true
end

function Settings.Set(key, on)
    if key == "runicMode" then return Settings.SetRunicMode(on) end
    if key == "runeFog" then return Settings.SetRuneOption("fog", on and "on" or "off") end
    if not BOOLEANS[key] then return false end
    store(key, on == true)
    if key == "sun" then
        GMM.Ring.ShowSun(on == true)
    elseif key == "glassTracking" then
        GMM.Tracking.Close()
    end
    return true
end

-- A dev build, by its version: "dev" from the deploy script, or the
-- packager's token left unreplaced (matched as a pattern, never written whole:
-- the packager would replace it here too). Unreadable is NOT dev.
function GMM.IsDev()
    local v = API.AddOnVersion(ADDON or "GlassMiniMap")
    return v ~= nil and (v == "dev" or v:find("@project%-version@") ~= nil)
end

function GMM.VersionText()
    local v = API.AddOnVersion(ADDON or "GlassMiniMap")
    if v == nil or v == "" or GMM.IsDev() then return "dev" end
    return v
end

local function failures()
    local any = false
    for key, err in pairs(GMM.failures) do
        any = true
        say(key .. ": " .. err)
    end
    if not any then say("no failures recorded") end
end

local function onoff(v) return v and "on" or "off" end

-- The command list: /gmm help prints it.
local function helpLines()
    local lines = {
        "/gmm theme clear/smoked/class" .. (GMM.Suite.LookFollowing() and "/suite" or "")
            .. " - the glass's tint (" .. GMM.Theme.Name() .. ")",
        "/gmm material pearl/clean - the glass, after /reload (" .. tostring(GMM.GlassPreset) .. ")",
        "/gmm suite - following Glass UI's look, or not",
        "/gmm sun on/off - the day and night disc (" .. onoff(GMM.db.sun) .. ")",
        "/gmm options - open the options page",
        "/gmm failures - what failed to build or register",
        "/gmm version - client build vs the measured one",
        "/gmm runes on/off/status - runic mode",
        "/gmm runes - open runic settings",
        "/gmm runes style etched/glowing",
        "/gmm runes motion sway/orbit",
        "/gmm runes fog on/off",
        "/gmm runes intensity 0-100 / speed 25-200 (percent)",
    }
    return lines
end
GMM.HelpLines = helpLines

local ONOFF = { on = true, off = false }

local function slash(msg)
    local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if cmd == "theme" or cmd == "glass" then
        if Settings.SetTheme(arg) then say("theme " .. arg)
        else say("/gmm theme " .. table.concat(GMM.Theme.NAMES, "/") .. (GMM.Suite.LookFollowing() and "/suite" or "")) end
    elseif cmd == "material" then
        local ok, why = Settings.SetMaterial(arg)
        if ok then say("material " .. arg .. ": applies after /reload")
        elseif why then say("material: " .. why)
        else say("/gmm material pearl/clean") end
        local status = GMM.Suite.MaterialStatus()
        if status then say(status) end
    elseif cmd == "suite" then
        say(GMM.Suite.Status())
    elseif cmd == "sun" then
        if ONOFF[arg] == nil then return say("/gmm " .. cmd .. " on/off") end
        Settings.Set(cmd, ONOFF[arg])
        say(cmd .. " " .. arg)
    elseif cmd == "runes" then
        if arg == "" then return GMM.Options.Open() end
        if arg == "status" then return say(GMM.Ring.RuneStatus()) end
        local kind, value = arg:match("^(%S+)%s+(%S+)$")
        if kind == "intensity" or kind == "speed" then
            local key = kind == "intensity" and "runeIntensity" or "runeSpeed"
            if Settings.SetRuneTuning(key, tonumber(value)) then return say("runes " .. kind .. " " .. GMM.db[key] .. "%") end
            return say(kind == "intensity" and "/gmm runes intensity 0-100" or "/gmm runes speed 25-200")
        end
        if kind == "style" or kind == "motion" or kind == "fog" then
            if Settings.SetRuneOption(kind, value) then return say("runes " .. kind .. " " .. value) end
            if kind == "fog" then return say("/gmm runes fog on/off") end
            return say(kind == "style" and "/gmm runes style etched/glowing" or "/gmm runes motion sway/orbit")
        end
        if ONOFF[arg] == nil then return say("/gmm runes on/off/status") end
        if Settings.SetRunicMode(ONOFF[arg]) then say("runes " .. arg) end
    elseif cmd == "options" or cmd == "" then
        GMM.Options.Open()
    elseif cmd == "failures" then
        failures()
    elseif cmd == "version" then
        say("version " .. GMM.VersionText() .. ", client " .. API.ClientBuild()
            .. ", measured on " .. GMM.MEASURED_ON_BUILD)
    else
        for _, line in ipairs(helpLines()) do say(line) end
    end
end

SLASH_GLASSMINIMAP1 = "/gmm"
SLASH_GLASSMINIMAP2 = "/glassminimap"
SlashCmdList.GLASSMINIMAP = slash

local function start(key, fn)
    local ok, err = pcall(fn)
    if not ok then API.Fail(key, err) end
    return ok
end

local boot = CreateFrame("Frame")
boot:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON then
            GMM.db = ensureDefaults()
            -- Before any glass: Glass UI's answer picks the material (#37).
            start("suite", GMM.Suite.Start)
        end
    elseif event == "PLAYER_LOGIN" then
        -- SavedVariables are read here at the latest (porting guide: not at file scope).
        if not GMM.db then GMM.db = ensureDefaults() end
        if not GMM.Glass then start("suite", GMM.Suite.Start) end
        start("options", GMM.Options.Register)
        start("blizzard", GMM.Blizzard.Start)
        if start("ring", GMM.Ring.Build) and GMM.Ring.Host() then
            start("zone pill", GMM.Header.Build)
            start("coords pill", GMM.Footer.Build)
            start("lfg eye", GMM.Queue.Build)
            start("mail disc", GMM.Mail.Build)
            start("instance disc", GMM.Difficulty.Build)
            start("tracking", GMM.Tracking.Build)
            start("drawer", GMM.Drawer.Start)
        end
        start("theme", GMM.Theme.Refresh)
    elseif event == "PLAYER_ENTERING_WORLD" then
        GMM.Theme.Retry()
        -- arg1 = isInitialLogin. The build warning asks the developer to re-measure.
        if arg1 and GMM.IsDev() and API.ClientBuild() ~= GMM.MEASURED_ON_BUILD then
            say("client build " .. API.ClientBuild() .. " differs from the one this addon was measured on ("
                .. GMM.MEASURED_ON_BUILD .. "). Things may misbehave until it is re-checked.")
        end
    end
end)
API.RegisterEvents(boot, { "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD" }, "boot")

GMM._test = { ensureDefaults = ensureDefaults, DEFAULTS = DEFAULTS, slash = slash }
