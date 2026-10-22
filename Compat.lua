-- Compat.lua: the one place this addon touches client APIs that moved, may be
-- absent, or behave differently on WoW: Forever. Everything else calls through
-- GlassMiniMap.API. Nothing is injected into _G.
--
-- GlassMail's Compat.lua (failures, events, version), plus API.Fade: the
-- alpha-only way this addon hides Blizzard's minimap art.

GlassMiniMap = GlassMiniMap or {}
local GMM = GlassMiniMap
local API = {}
GMM.API = API

-- The build the notes in docs/ were measured on. Bump only after re-measuring
-- in game; tests/test_toc.lua pins the same literal.
GMM.MEASURED_ON_BUILD = "1.60.1.70374"

function API.Print(msg)
    print("|cff7fd4ffGlassMiniMap|r " .. msg)
end

-- True for a Retail secret value: it may be handed back to the client but
-- never compared, concatenated or truth-tested in Lua.
function API.IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

-- v, or nil when it is secret.
function API.Plain(v)
    if API.IsSecret(v) then return nil end
    return v
end

function API.ClientBuild()
    local version, build = GetBuildInfo()
    return tostring(version) .. "." .. tostring(build)
end

-- The one failure recorder: key -> first error, read by /gmm failures.
GMM.failures = GMM.failures or {}
function API.Fail(key, err)
    if GMM.failures[key] ~= nil then return end
    local msg = "(unprintable error)"
    if type(err) == "string" then
        msg = err
    elseif not API.IsSecret(err) then
        local ok, s = pcall(tostring, err)
        if ok and type(s) == "string" then msg = s end
    end
    GMM.failures[key] = msg
end

-- Run fn under pcall; a throw is recorded under `key` and nil is returned.
function API.Try(key, fn, ...)
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
    API.Fail(key, a)
    return nil
end

-- RegisterEvent throws on an unknown name and returns false on a refusal.
-- Both count as failure, and every failure is reported: a silently missing
-- handler is the bug this exists to prevent.
function API.RegisterEvent(frame, name, who)
    local ok, registered = pcall(frame.RegisterEvent, frame, name)
    if ok and registered ~= false then return true end
    local why = ok and "refused" or tostring(registered)
    API.Fail("event:" .. name, (who and (who .. ": ") or "") .. why)
    API.Print("|cffff6060could not register|r " .. name .. " (" .. why .. ")")
    return false
end

function API.RegisterEvents(frame, events, who)
    for _, name in ipairs(events) do API.RegisterEvent(frame, name, who) end
end

-- An addon's TOC Version, or nil (absent API, error, secret, not a string).
function API.AddOnVersion(addon)
    local get = C_AddOns and C_AddOns.GetAddOnMetadata
    if not get then return nil end
    local ok, v = pcall(get, addon, "Version")
    if not ok or API.IsSecret(v) or type(v) ~= "string" then return nil end
    return v
end

function API.IsAddOnLoaded(name)
    local fn = C_AddOns and C_AddOns.IsAddOnLoaded
    if not fn then return false end
    local ok, loaded = pcall(fn, name)
    return ok and API.Plain(loaded) == true
end

-- A Blizzard game rule (Enum.GameRule.<name>) is on. Unknown names, a
-- missing API or an error all read as off: the feature stays available.
function API.GameRule(name)
    local rules = Enum and rawget(Enum, "GameRule")
    local id = type(rules) == "table" and rules[name]
    if id == nil or not (C_GameRules and C_GameRules.IsGameRuleActive) then return false end
    local ok, on = pcall(C_GameRules.IsGameRuleActive, id)
    return ok and API.Plain(on) == true
end

function API.CVarBool(name)
    local ok, on = pcall(GetCVarBool, name)
    return ok and API.Plain(on) == true
end

-- The player's class colour (plain numbers), or nil (GlassPanel's).
function API.ClassColor()
    local ok, _, class = pcall(UnitClass, "player")
    class = ok and API.Plain(class) or nil
    if type(class) ~= "string" then return nil end
    local ok2, c = pcall(C_ClassColor.GetClassColor, class)
    if not ok2 or type(c) ~= "table" then return nil end
    local r, g, b = API.Plain(c.r), API.Plain(c.g), API.Plain(c.b)
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return nil end
    return r, g, b
end

-- A texture shows `icon`: an atlas name when the client knows one, else a file.
function API.SetIcon(tex, icon)
    if type(icon) == "string" and C_Texture and C_Texture.GetAtlasInfo then
        local ok, info = pcall(C_Texture.GetAtlasInfo, icon)
        if ok and info then
            tex:SetAtlas(icon)
            return true
        end
    end
    tex:SetTexture(icon)
    return false
end

--------------------------------------------------------------------------------
-- API.Fade: hide a piece of Blizzard's minimap without hiding it
--------------------------------------------------------------------------------

-- The minimap cluster is an Edit Mode system (porting guide, "Edit Mode
-- systems"): its pieces are never Hide()n, reparented or moved here. Fade
-- sets alpha 0 and, on frames, turns the mouse off, so the piece stays where
-- Blizzard put it, does its own work (the tracking button keeps its menu, the
-- coords keep updating) and is simply not seen or clicked. Blizzard shows and
-- fades some of these itself (the zoom buttons on hover, the compass atlas on
-- a rotation change), so Show/SetAlpha/SetShown are hooked to fade again.
-- State lives in our own weak table, never as a field on their frame
-- (writing into a Blizzard frame's table taints it). Unfade gives it back.
local faded = setmetatable({}, { __mode = "k" })   -- region -> { alpha = , mouse = }
local hooked = setmetatable({}, { __mode = "k" })

local function refade(region)
    local s = faded[region]
    if not s or s.busy then return end
    s.busy = true                                    -- our own SetAlpha re-enters the hook
    pcall(region.SetAlpha, region, 0)
    if s.mouse ~= nil and region.EnableMouse then pcall(region.EnableMouse, region, false) end
    s.busy = false
end

function API.Fade(region)
    if type(region) ~= "table" or not region.SetAlpha then return false end
    if faded[region] then refade(region); return true end
    local s = { alpha = region:GetAlpha() }
    if region.IsMouseEnabled then
        local ok, on = pcall(region.IsMouseEnabled, region)
        if ok then s.mouse = API.Plain(on) == true end
    end
    faded[region] = s
    if not hooked[region] then
        hooked[region] = true
        for _, m in ipairs({ "Show", "SetShown", "SetAlpha" }) do
            if type(region[m]) == "function" then
                hooksecurefunc(region, m, function(self) if faded[self] then refade(self) end end)
            end
        end
    end
    refade(region)
    return true
end

function API.Unfade(region)
    local s = faded[region]
    if not s then return end
    faded[region] = nil
    pcall(region.SetAlpha, region, s.alpha or 1)
    if s.mouse ~= nil and region.EnableMouse then pcall(region.EnableMouse, region, s.mouse) end
end

function API.IsFaded(region) return faded[region] ~= nil end

--------------------------------------------------------------------------------
-- Settings (Options > AddOns)
--------------------------------------------------------------------------------

-- The global, read late: Options.lua has a local of the same name.
local function settingsAPI() return rawget(_G, "Settings") end

function API.RegisterSettingsPanel(panel, name)
    local S = settingsAPI()
    if not (S and S.RegisterCanvasLayoutCategory and S.RegisterAddOnCategory) then return nil end
    local category = S.RegisterCanvasLayoutCategory(panel, name)
    S.RegisterAddOnCategory(category)
    return category
end

function API.OpenSettings(category)
    local S = settingsAPI()
    if not (category and S and S.OpenToCategory) then return false end
    return pcall(S.OpenToCategory, category:GetID()) and true or false
end
