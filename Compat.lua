-- Compat.lua: the one place this addon touches client APIs that moved, may be
-- absent, or behave differently on WoW: Forever. Everything else calls through
-- GlassMiniMap.API. Nothing is injected into _G.
--
-- GlassMail's Compat.lua (failures, events, version), GlassPanel's
-- SystemHider (Edit Mode-safe hiding) and Glass MiniMap Bar's widget-method
-- table and menu check, plus API.Fade: the alpha-only way this addon hides
-- Blizzard's minimap art.

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

-- The widget methods themselves, from a Frame's metatable. A grabbed drawer
-- button has SetPoint, SetParent, Show... replaced on its own table so its
-- addon can't pull it back onto the minimap; the drawer moves it through these.
API.W = getmetatable(CreateFrame("Frame")).__index

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

-- Menus a drawer button may open (right-click menus): the drawer stays open
-- while the mouse is over one. Globals looked up late: most are created on demand.
local MENU_FRAMES = { "DropDownList1", "DropDownList2", "L_DropDownList1", "L_DropDownList2",
                      "LibDropDownMenu_List1", "LibDropDownMenu_List2" }
function API.MouseOverMenu()
    for _, name in ipairs(MENU_FRAMES) do
        local f = rawget(_G, name)
        if f and f:IsShown() and f:IsMouseOver() then return true end
    end
    local M = rawget(_G, "Menu")
    if M and M.GetManager then
        local ok, over = pcall(function()
            local menu = M.GetManager():GetOpenMenu()
            return menu and menu:IsMouseOver()
        end)
        if ok and over then return true end
    end
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
-- API.SystemHider: GlassPanel's, for the one frame that must go entirely
--------------------------------------------------------------------------------

-- Hide a Blizzard frame that Blizzard manages (and may show again itself)
-- while one of ours replaces it, and give it back. The references' way
-- (ElvUI, EllesmereUI): reparent to a hidden frame, never Hide(). Every change
-- is deferred to a timer (never inside Blizzard's call), and waits for combat
-- to end if the frame is protected. While Edit Mode is open the frame is
-- given back, and hidden again once Edit Mode closes. Blizzard reparenting it
-- is noticed through hooksecurefunc and undone the same deferred way; a layout
-- change (EDIT_MODE_LAYOUTS_UPDATED) re-checks. Giving it back restores the
-- parent Blizzard last gave it. Used for AddonCompartmentFrame only, whose
-- mixin never calls through its own parent (checked in Blizzard_Minimap).
--   local h = API.SystemHider("AddonCompartmentFrame")
--   h.Set(true)   -- hide, when safe;   h.Set(false)   -- give it back
local systemParent
function API.SystemHider(globalName)
    local h = { want = false }
    local frame, home, hookedParent, scheduled
    local waiter = CreateFrame("Frame")
    local sync

    local function editModeOpen()
        local em = rawget(_G, "EditModeManagerFrame")
        return type(em) == "table" and em.IsShown ~= nil and API.Plain(em:IsShown()) == true
    end

    local function later(seconds)
        if scheduled then return end
        scheduled = true
        C_Timer.After(seconds, function() scheduled = false; sync() end)
    end
    function h.request() later(0) end

    waiter:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_REGEN_ENABLED" then self:UnregisterEvent(event) end
        if h.want or (frame and systemParent and frame:GetParent() == systemParent) then h.request() end
    end)
    API.RegisterEvent(waiter, "EDIT_MODE_LAYOUTS_UPDATED", "hide " .. globalName)

    local emHooked = false
    local function watchEditMode()
        if emHooked then return end
        local em = rawget(_G, "EditModeManagerFrame")
        if type(em) == "table" and em.HookScript then
            emHooked = true
            em:HookScript("OnShow", function() h.request() end)
            em:HookScript("OnHide", function() h.request() end)
        end
    end

    sync = function()
        frame = frame or rawget(_G, globalName)
        if type(frame) ~= "table" or not frame.SetParent then
            if h.want then API.Fail("hide " .. globalName, "no such frame on this client") end
            return
        end
        watchEditMode()
        local hide = h.want and not editModeOpen()
        if API.Plain(InCombatLockdown()) ~= false and API.Plain((frame:IsProtected())) ~= false then
            API.RegisterEvent(waiter, "PLAYER_REGEN_ENABLED", "hide " .. globalName)
            return
        end
        if not systemParent then
            systemParent = CreateFrame("Frame", nil, UIParent)
            systemParent:Hide()
        end
        local parent = frame:GetParent()
        if hide then
            if not hookedParent then
                hookedParent = true
                hooksecurefunc(frame, "SetParent", function(_, p)
                    if h.want and p ~= systemParent then h.request() end
                end)
            end
            if parent ~= systemParent then
                home = parent   -- where Blizzard last put it
                frame:SetParent(systemParent)
            end
        elseif parent == systemParent and home then
            frame:SetParent(home)
        end
    end

    function h.Set(want)
        want = want and true or false
        if want == h.want then return end
        h.want = want
        h.request()
    end
    function h.IsHidden()
        return frame ~= nil and systemParent ~= nil and frame:GetParent() == systemParent
    end
    return h
end

--------------------------------------------------------------------------------
-- Settings (Options > AddOns)
--------------------------------------------------------------------------------

-- The global, read late: Options.lua has a local of the same name.
local function settingsAPI() return rawget(_G, "Settings") end

function API.RegisterSettingsPanel(panel, name, parentCategory)
    local S = settingsAPI()
    if not (S and S.RegisterCanvasLayoutCategory and S.RegisterAddOnCategory) then return nil end
    if parentCategory and S.RegisterCanvasLayoutSubcategory then
        return S.RegisterCanvasLayoutSubcategory(parentCategory, panel, name)
    end
    local category = S.RegisterCanvasLayoutCategory(panel, name)
    S.RegisterAddOnCategory(category)
    return category
end

function API.OpenSettings(category)
    local S = settingsAPI()
    if not (category and S and S.OpenToCategory) then return false end
    return pcall(S.OpenToCategory, category:GetID()) and true or false
end
