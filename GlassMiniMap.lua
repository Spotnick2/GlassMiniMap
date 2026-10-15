-- GlassMiniMap.lua: bootstrap, saved settings, the settings helpers and the
-- /gmm command. Loads last: every module is defined by now.

local ADDON = ...
GlassMiniMap = GlassMiniMap or {}
local GMM = GlassMiniMap
local API = GMM.API
local say = API.Print

-- GlassMiniMapDB, account-wide. Only what the player SET is saved: the rest
-- falls through to DEFAULTS, so a changed default reaches everyone (GlassMail's
-- rule). The drawer's settings are Glass MiniMap Bar's own.
local DEFAULTS = {
    theme = "clear",          -- "clear" | "smoked" | "class"
    sun = true,               -- the day/night disc
    glassTracking = true,     -- the magnifier opens the glass menu (off: Blizzard's)
    runicMode = false,
    runeStyle = "glowing",
    runeMotion = "sway",
    runeFog = true,
    runeIntensity = 100,      -- percent of the current glow strength
    runeSpeed = 100,          -- orbit speed percent (30 seconds at 100)
}
GMM.DEFAULTS = DEFAULTS
local BOOLEANS = { sun = true, glassTracking = true, runicMode = true, runeFog = true }
local RUNE_CHOICES = { runeStyle = { etched = true, glowing = true }, runeMotion = { sway = true, orbit = true } }
local RUNE_RANGES = { runeIntensity = { 0, 100 }, runeSpeed = { 25, 200 } }
local function validRuneNumber(key, value)
    local range = RUNE_RANGES[key]
    return range and type(value) == "number" and value == value
        and value >= range[1] and value <= range[2]
end

local function steppedRuneNumber(key, value)
    local lo = RUNE_RANGES[key][1]
    return lo + math.floor((value - lo) / 5 + 0.5) * 5
end

local function ensureDefaults()
    if type(GlassMiniMapDB) ~= "table" then GlassMiniMapDB = {} end
    local db = setmetatable(GlassMiniMapDB, nil)
    for k, v in pairs(DEFAULTS) do
        if db[k] == v then db[k] = nil end
    end
    if db.theme ~= nil and not GMM.Theme.IsValid(db.theme) then db.theme = nil end
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

-- False for a name that isn't a theme; the setting is left as it was.
function Settings.SetTheme(name)
    if not GMM.Theme.IsValid(name) then return false end
    store("theme", name)
    GMM.Theme.Refresh()
    GMM.Options.RefreshRunicControls()
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
        "/gmm theme clear/smoked/class - the glass (" .. GMM.db.theme .. ")",
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
        else say("/gmm theme " .. table.concat(GMM.Theme.NAMES, "/")) end
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
        if arg1 == ADDON then GMM.db = ensureDefaults() end
    elseif event == "PLAYER_LOGIN" then
        -- SavedVariables are read here at the latest (porting guide: not at file scope).
        if not GMM.db then GMM.db = ensureDefaults() end
        start("options", GMM.Options.Register)
        start("blizzard", GMM.Blizzard.Start)
        if start("ring", GMM.Ring.Build) and GMM.Ring.Host() then
            start("zone pill", GMM.Header.Build)
            start("coords pill", GMM.Footer.Build)
            start("lfg eye", GMM.Queue.Build)
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
