-- Suite.lua: Glass UI's suite (#37; Glass UI's docs/SUITE.md and
-- docs/SUITE-LOOK.md, API 1; our docs/PLAN-suite.md).
--
-- Glass UI is optional. The player follows it with its "Use Glass UI
-- appearance" switch, which we read once per session, at our ADDON_LOADED
-- (OptionalDeps: GlassUI loads it first; its S.2 measured that on 70450),
-- before any glass is built. While following:
--   - the material is Glass UI's Pearl; our own `material` stays saved and
--     unused ("set in Glass UI");
--   - the tint is the player's own (GlassMiniMapDB.look.tint, an override) if
--     they set one, else the suite's, live through EventRegistry
--     "GlassUI.Suite.LookChanged"; Suite.Body gives its numbers (tint and
--     wash; its opaque backing is never ours: a ring over terrain).
-- Not following, no Glass UI, or one without Suite: our own material and tint.
--
-- Everything read from Glass UI goes through rawget, every call through
-- pcall: a junk or throwing Suite means our own look, never an error. We
-- never read GlassUIDB.

local ADDON = ...
GlassMiniMap = GlassMiniMap or {}
local GMM = GlassMiniMap
local API = GMM.API
local Suite = {}
GMM.Suite = Suite

Suite.ADDON = ADDON or "GlassMiniMap"
Suite.EVENT = "GlassUI.Suite.LookChanged"

local S                -- GlassUI.Suite when it speaks API 1
local decided, following, lookFollowing = false, false, false
local answer           -- what Theme said: "pearl", or its reason
local suiteTint        -- the suite's tint, copied (its payload is read-only)
local failure          -- why a followed Pearl wasn't built
local localFailure     -- why our own material wasn't built

local function read(t, k)
    if type(t) == "table" then return rawget(t, k) end
end

local function num(v)
    if type(v) == "number" and v == v then return v end
end

-- Glass UI's Suite table, or nil: anything but API 1 exactly counts as absent
-- (the released Glass UI has no Suite at all).
local function suiteAPI()
    local G = rawget(_G, "GlassUI")
    local s = read(G, "Suite")
    if type(s) ~= "table" or rawget(s, "API") ~= 1 then return nil end
    if type(rawget(s, "Theme")) ~= "function" or type(rawget(s, "Report")) ~= "function" then return nil end
    return s
end

-- The suite's tint from a Look payload; an unknown or missing one leaves us
-- on our own default (SUITE-LOOK.md: a follower ignores what it doesn't know).
local function copyTint(look)
    local v = read(look, "tint")
    suiteTint = GMM.Theme.IsValid(v) and v or nil
end

local function onLookChanged(_, look)
    copyTint(look)
    API.Try("suite:look", GMM.Theme.Refresh)
    GMM.Options.Refresh()
    Suite.Report()
end

-- Ask Glass UI, once per session. Returns whether we follow it.
function Suite.Decide()
    if decided then return following end
    decided = true
    S = suiteAPI()
    if not S then return false end
    local ok, a, why = pcall(rawget(S, "Theme"), Suite.ADDON)
    if ok and read(a, "preset") == "pearl" then
        following, answer = true, "pearl"
    else
        answer = not ok and "error" or (type(why) == "string" and why) or "no answer"
    end
    local look = rawget(S, "Look")
    if following and type(look) == "function" then
        lookFollowing = true
        -- Register first, then pull: nothing is replayed to a late follower.
        if EventRegistry and EventRegistry.RegisterCallback then
            EventRegistry:RegisterCallback(Suite.EVENT, onLookChanged, Suite)
        end
        local okLook, payload = pcall(look)
        if okLook then copyTint(payload) end
    end
    return following
end

-- At ADDON_LOADED (PLAYER_LOGIN if that failed): decide, build the glass,
-- report what was built.
function Suite.Start()
    Suite.Decide()
    local preset = following and "pearl" or GMM.Settings.Material()
    local ok, why = GMM.BuildGlass(preset)
    if not ok then
        if following then
            failure = why
        else
            localFailure = why
            API.Fail("material", "the " .. preset .. " glass couldn't be built (" .. why .. "): Clean instead")
        end
    end
    Suite.Report()
end

function Suite.Following() return following end
function Suite.LookFollowing() return lookFollowing end
function Suite.Failure() return failure end

-- The suite's tint while we follow its look, else nil.
function Suite.Tint()
    if lookFollowing then return suiteTint end
end

-- The suite's numbers for a tint while we follow, as plain values we may keep:
-- { tint = { r, g, b, a } | nil, classShade = n | nil, wash = factor | nil },
-- or nil (not following, no Body, an unknown name, junk). The backing is
-- left out: our ring and pills sit over the map, unbacked.
function Suite.Body(name)
    if not following then return nil end
    local fn = rawget(S, "Body")
    if type(fn) ~= "function" then return nil end
    local ok, b = pcall(fn, name)
    if not ok or type(b) ~= "table" then return nil end
    local body = { classShade = num(rawget(b, "classShade")), wash = num(rawget(b, "wash")) }
    local t = rawget(b, "tint")
    if type(t) == "table" then
        local r, g, bl = num(rawget(t, 1)), num(rawget(t, 2)), num(rawget(t, 3))
        if r and g and bl then body.tint = { r, g, bl, num(rawget(t, 4)) } end
    end
    if not body.tint and not body.classShade then return nil end
    return body
end

-- What we built and show, for Glass UI's page: fresh plain tables each time
-- (it keeps a copy). Re-sent whenever the tint in effect changes.
function Suite.Report()
    if not S then return end
    local state = {
        api = 1,
        built = following and failure == nil and GMM.GlassPreset or nil,
        reason = following and failure or nil,
        minor = GMM.GlassMinor,
        options = function() GMM.Options.Open() end,
        look = { tint = GMM.Theme.Name() },
        own = { tint = GMM.Theme.Own() ~= nil or nil, backing = true },
    }
    pcall(rawget(S, "Report"), Suite.ADDON, state)
end

-- Glass UI's settings page, when its Suite has Open (added within API 1).
function Suite.CanOpen()
    return S ~= nil and type(rawget(S, "Open")) == "function"
end

function Suite.Open()
    if not Suite.CanOpen() then return false end
    local ok, opened = pcall(rawget(S, "Open"))
    return ok and opened == true
end

-- The material line for the options page and /gmm material.
function Suite.MaterialStatus()
    if following and not failure then return "Following Glass UI (Pearl): set in Glass UI" end
    if failure then return "Own look: " .. failure .. " (Clean in use)" end
    if localFailure then return "Pearl needs LibGlass r11 or newer: Clean in use" end
    return nil
end

-- /gmm suite: this session's answer and what we built.
function Suite.Status()
    local tint = GMM.Theme.Name()
    local source = GMM.Theme.Own() and "yours" or (Suite.Tint() and "Glass UI's" or "the default")
    local glass = "glass " .. tostring(GMM.GlassPreset) .. ", tint " .. tint .. " (" .. source .. ")"
    if not S then return "Glass UI: not loaded, or without the suite API; " .. glass end
    if following then
        return "following Glass UI" .. (failure and (", Pearl failed: " .. failure) or "") .. "; " .. glass
    end
    return "Glass UI: own look (" .. tostring(answer) .. "); " .. glass
end

Suite._test = { suiteAPI = suiteAPI, answer = function() return answer end }
