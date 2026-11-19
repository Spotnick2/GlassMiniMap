-- wow_stubs.lua: Glass MiniMap's WoW: Forever mock for Lua 5.1 unit tests.
-- dofile("tests/wow_stubs.lua") FIRST in every test; drive it via the WoW table.
--
-- The mechanics are WowTestKit's core (tests/kit.lua loads the commit and the
-- build tests/kit.pin names; its README is the reference): strict globals,
-- secrets, event names checked against the build, widgets that record every
-- method called (and answer only the methods their type has on that build),
-- print with the stray-"|" check done() fails on, timers, hooksecurefunc,
-- fire / fireAllRegistered / tick, check / eq / done. This file adds what a
-- minimap reskin touches beyond those: the Forever minimap cluster as
-- Blizzard_Minimap builds it, C_Minimap's tracking, the calendar, the zone and
-- map APIs, the AddOns compartment, fakes of Glass MiniMap Bar's public API
-- and of Glass UI's suite. Methods are looked up at call time, so an entry
-- here replaces the core's.

dofile("tests/kit.lua")
local Methods = WoW.Methods
local newWidget = WoW.newWidget

--------------------------------------------------------------------------------
-- Templates (CreateFrame's fourth argument)
--------------------------------------------------------------------------------

-- Each template's label, with the font Blizzard's XML gives it (so the core's
-- "Font not set" check holds): UICheckButtonTemplate's Text and
-- UIRadioButtonTemplate's text (Blizzard_SharedXML/Shared/Button/
-- CheckButtonTemplates.xml, GameFontNormalSmall), UIPanelButtonTemplate's Text
-- (Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml, its NormalFont
-- GameFontNormalOutline). Not in the button's regions, as in the old stub.
local function label(w, font)
    local fs = newWidget("FontString", w)
    fs._fontTemplate = font
    return fs
end
WoW.templates.UICheckButtonTemplate = function(w) w.Text = label(w, "GameFontNormalSmall") end
WoW.templates.UIPanelButtonTemplate = function(w) w.Text = label(w, "GameFontNormalOutline") end
WoW.templates.UIRadioButtonTemplate = function(w) w.text = label(w, "GameFontNormalSmall") end

--------------------------------------------------------------------------------
-- Widgets: the methods the core doesn't have, or has differently (each a real
-- method of that widget type on this build: test_methods checks every call)
--------------------------------------------------------------------------------

function Methods.GetNumPoints(w) return #w._points end
-- WowTestKit #78: the core has no GetSize.
function Methods.GetSize(w) return w._width, w._height end
function Methods.SetScale(w, s) w._scale = s end
function Methods.GetScale(w) return w._scale or 1 end
function Methods.SetClampedToScreen(w, v) w._clamped = v and true or false end
function Methods.IsClampedToScreen(w) return w._clamped == true end
-- The pointer: WoW.mouseOver[w] = true puts it over w, and WoW.mouseOver = {}
-- takes it off everything at once (the tests' away()). The core reads a field
-- on each widget instead (w._mouseOver).
function Methods.IsMouseOver(w) return WoW.mouseOver[w] == true end
-- The client keeps a number as a string (its SetText reads a string, so Lua's
-- C API converts it), and Blizzard's own InstanceDifficulty:Update passes the
-- group size as a number (Blizzard_FrameXML/InstanceDifficulty.lua). The core
-- stores what it's given; this converts, then runs the core's (its font check).
local coreSetText = Methods.SetText
function Methods.SetText(w, t)
    if type(t) == "number" then t = tostring(t) end
    return coreSetText(w, t)
end

-- A drag requires a visible mouse-enabled slider; direct SetValue alone does
-- not exercise that interaction requirement.
function WoW.dragSlider(w, value)
    assert(Methods.IsVisible(w) and Methods.IsMouseEnabled(w), "slider cannot be dragged")
    w:SetValue(value)
end

-- Animations: Play marks a group playing; WoW.finishAnimations() completes
-- every playing group (OnFinished), as the client would after its duration.
-- The core doesn't track groups, so these replace its two makers.
function Methods.GetAnimationGroups(w) return unpack(w._anims or {}) end
function Methods.CreateAnimationGroup(w)
    local ag = newWidget("AnimationGroup", w)
    ag._animations = {}
    w._anims = w._anims or {}
    table.insert(w._anims, ag)
    table.insert(WoW.animGroups, ag)
    return ag
end
function Methods.CreateAnimation(ag, atype)
    local a = newWidget(atype or "Animation", ag)
    table.insert(ag._animations, a)
    return a
end
function Methods.GetAnimations(ag) return unpack(ag._animations) end
function Methods.GetTarget(a) return a._parent and a._parent._parent end
function Methods.Play(ag) ag._playing = true; ag._plays = (ag._plays or 0) + 1 end
function Methods.Stop(ag) ag._playing = false; ag._stops = (ag._stops or 0) + 1 end
function Methods.SetLooping(ag, value) ag._looping = value end
function Methods.SetDegrees(a, value) a._degrees = value end
function Methods.SetOrder(a, value) a._order = value end
function Methods.GetProgress(a) return a._progress or 0 end
function Methods.SetDuration(a, value) a._duration = value end
function Methods.SetAnimationSpeedMultiplier(ag, value) ag._speedMultiplier = value end
function Methods.GetAnimationSpeedMultiplier(ag) return ag._speedMultiplier or 1 end
function Methods.SetSmoothing(a, value) a._smoothing = value end
function Methods.SetOrigin(a, point) a._origin = point end
function Methods.SetScaleFrom(a, x, y) a._from = { x, y } end
function Methods.SetScaleTo(a, x, y) a._to = { x, y } end
function WoW.finishAnimations()
    for _, ag in ipairs(WoW.animGroups) do
        if ag._playing and (not ag._looping or ag._looping == "NONE") then
            ag._playing = false
            if ag._scripts.OnFinished then ag._scripts.OnFinished(ag) end
        end
    end
end

-- Scripts. HasScript: every scripted widget type knows these handlers.
local SCRIPTED = { Frame = true, Button = true, CheckButton = true, StatusBar = true, GameTooltip = true,
                   Minimap = true, EditBox = true }
local HANDLERS = { OnClick = true, OnMouseUp = true, OnMouseDown = true, OnEnter = true, OnLeave = true,
                   OnShow = true, OnHide = true, OnUpdate = true, OnEvent = true, OnDragStart = true, OnDragStop = true,
                   OnDoubleClick = true, OnMouseWheel = true }
function Methods.HasScript(w, name) return SCRIPTED[w._type] == true and HANDLERS[name] == true end

-- Callback events (CallbackEvent = true in Blizzard's API documentation, a
-- flag the dump drops): RegisterEvent refuses them as the client does (70450,
-- MINIMAP_PING), and RegisterEventCallback is protected for addons (#14). The
-- core's checks the name against the build's list.
WoW.CALLBACK_EVENTS = { MINIMAP_PING = true }
local coreRegisterEvent = Methods.RegisterEvent
function Methods.RegisterEvent(w, e)
    if WoW.CALLBACK_EVENTS[e] then error("Attempt to register unknown event \"" .. e .. "\"", 2) end
    return coreRegisterEvent(w, e)
end

-- Textures: what the core doesn't read back.
function Methods.GetTexture(t) return t._file end
function Methods.GetAtlas(t) return t._atlas end
function Methods.SetTexCoord(t, ...) t._coords = { ... } end
function Methods.GetTexCoord(t)
    local c = t._coords or { 0, 0, 0, 1, 1, 0, 1, 1 }
    return unpack(c)
end
function Methods.SetRotation(t, r) t._rotation = r end

-- GameTooltip: records its lines.
function Methods.SetOwner(tt, owner) tt._owner = owner; tt._lines = {} end
function Methods.GetOwner(tt) return tt._owner end
function Methods.IsOwned(tt, owner) return tt._owner == owner end
function Methods.NumLines(tt) return #(tt._lines or {}) end
function Methods.ClearLines(tt) tt._lines = {} end
function Methods.AddLine(tt, text, r, g, b)
    table.insert(tt._lines, text)
    tt._colors = tt._colors or {}
    tt._colors[#tt._lines] = { r, g, b }
end
function Methods.AddDoubleLine(tt, l, r) table.insert(tt._lines, tostring(l) .. "|" .. tostring(r)) end

-- Minimap: zoom.
function Methods.GetZoom(m) return m._zoom or 0 end
function Methods.SetZoom(m, z) m._zoom = z end
function Methods.GetZoomLevels(m) return m._zoomLevels or 6 end

--------------------------------------------------------------------------------
-- The Forever minimap cluster (Blizzard_Minimap\Mainline\Minimap.xml + Camelot)
--------------------------------------------------------------------------------

local function buildCluster()
    MinimapCluster = CreateFrame("Frame", "MinimapCluster", UIParent)
    MinimapCluster._strata = "LOW"
    local c = MinimapCluster
    c.BorderTop = CreateFrame("Frame", nil, c)
    c.ZoneTextButton = CreateFrame("Button", nil, c)
    c.ZoneTextButton._mouse = true
    c.Tracking = CreateFrame("Frame", nil, c)
    c.Tracking.Button = CreateFrame("Button", nil, c.Tracking)
    c.Tracking.Button._mouse = true
    c.Tracking.Button.OpenMenu = function(self) WoW.blizzardMenuOpened = (WoW.blizzardMenuOpened or 0) + 1 end
    c.Tracking.Button.SetMenuAnchor = function(self, anchor) self._menuAnchor = anchor end
    c.MinimapContainer = CreateFrame("Frame", nil, c)
    c.MinimapContainer._width, c.MinimapContainer._height = 215, 226
    Minimap = CreateFrame("Minimap", "Minimap", c.MinimapContainer)
    Minimap._width, Minimap._height = 198, 198
    c.MinimapContainer.Minimap = Minimap
    Minimap.ZoomIn = CreateFrame("Button", nil, Minimap)
    Minimap.ZoomOut = CreateFrame("Button", nil, Minimap)
    Minimap.ZoomHitArea = CreateFrame("Frame", nil, Minimap)
    Minimap.ZoomHitArea._mouse = true
    MinimapBackdrop = CreateFrame("Frame", "MinimapBackdrop", Minimap)
    MinimapBackdrop._width, MinimapBackdrop._height = 215, 226
    MinimapBackdrop.StaticOverlayTexture = MinimapBackdrop:CreateTexture(nil, "OVERLAY")
    MinimapCompassTexture = MinimapBackdrop:CreateTexture(nil, "OVERLAY")
    MinimapCompassTextureUnderlay = MinimapBackdrop:CreateTexture(nil, "OVERLAY")
    c.MinimapContainer.PlayerCoords = CreateFrame("Frame", nil, c.MinimapContainer)
    c.DielFrame = CreateFrame("Frame", nil, c)
    -- The instance flag (InstanceDifficulty.xml; its two Texts inherit
    -- GameFontNormalSmall there): it and its Guild banner have
    -- OnEnter tooltips, so both take the mouse.
    c.InstanceDifficulty = CreateFrame("Frame", nil, c)
    c.InstanceDifficulty._mouse = true
    c.InstanceDifficulty.Guild = CreateFrame("Frame", nil, c.InstanceDifficulty)
    c.InstanceDifficulty.Guild._mouse = true
    local d = c.InstanceDifficulty
    d.Default = CreateFrame("Frame", nil, d)
    d.Default.Text = d.Default:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    d.Guild.Instance = CreateFrame("Frame", nil, d.Guild)
    d.Guild.Instance.Text = d.Guild.Instance:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    WoW.setShown(d.Default, false); WoW.setShown(d.Guild, false)
    -- Forever's Update (InstanceDifficulty.lua:106 + the Camelot override):
    -- the size goes into the chosen frame FIRST, then the modes switch, so a
    -- hidden frame keeps its stale text. WoW.instance = { type, maxPlayers, guild }.
    function d:Update()
        local i = WoW.instance
        local content
        if i.guild then content = self.Guild elseif i.type ~= "none" then content = self.Default end
        local textFrame = content == self.Guild and self.Guild.Instance or content
        if textFrame then textFrame.Text:SetText(i.maxPlayers == 0 and "" or i.maxPlayers) end
        self.Default:SetShown(content == self.Default)
        self.Guild:SetShown(content == self.Guild)
    end
    function d:GetDifficultyTooltip(maxPlayers, groupSize, name, isLFR, lfgID, difficulty)
        if maxPlayers == 5 then
            GameTooltip:AddLine("Dungeon"); GameTooltip:AddLine("5 Player")
        elseif maxPlayers == 10 or maxPlayers == 20 or maxPlayers == 40 then
            GameTooltip:AddLine("Raid"); GameTooltip:AddLine(maxPlayers .. " Player")
        end
    end
    -- The mail icon: a mouse-enabled frame in IndicatorFrame, shown by
    -- Blizzard on UPDATE_PENDING_MAIL while there's mail.
    c.IndicatorFrame = CreateFrame("Frame", nil, c)
    c.IndicatorFrame.MailFrame = CreateFrame("Frame", nil, c.IndicatorFrame)
    c.IndicatorFrame.MailFrame._mouse = true
    WoW.setShown(c.IndicatorFrame.MailFrame, false)
    -- The LFG eye: UIParent's, its own Edit Mode system, hidden until queued.
    QueueStatusButton = CreateFrame("Button", "QueueStatusButton", UIParent)
    QueueStatusButton._width, QueueStatusButton._height = 45, 45
    WoW.setShown(QueueStatusButton, false)
    QueueStatusButton._level = 20
    QueueStatusButton:SetPoint("CENTER", Minimap, "CENTER", -68, -68)
    -- Edit Mode's system methods (EditModeSystemTemplates.lua): the base
    -- methods skip its anchor pass; the overrides would run it.
    local q = QueueStatusButton
    q.inDefault = true
    q.SetPointBase = function(self, ...) WoW.Methods.SetPoint(self, ...); self._baseMoves = (self._baseMoves or 0) + 1 end
    q.ClearAllPointsBase = function(self) WoW.Methods.ClearAllPoints(self) end
    q.IsInDefaultPosition = function(self) return self.inDefault end
    -- Camelot's UpdateDefaultAnchor: back to Minimap CENTER (-68, -68).
    q.UpdateDefaultAnchor = function(self)
        WoW.Methods.ClearAllPoints(self)
        WoW.Methods.SetPoint(self, "CENTER", Minimap, "CENTER", -68, -68)
    end
    -- Its art, one level under the button (QueueStatusFrame.lua:165).
    q.Eye = CreateFrame("Frame", nil, q)
    q.Eye._level = q._level - 1
    -- OnLoad registers the ORIGINAL function with EventRegistry (line 12): a
    -- later hooksecurefunc on the frame doesn't wrap this copy.
    EventRegistry = { callbacks = {} }
    function EventRegistry:RegisterCallback(event, fn, owner)
        self.callbacks[event] = self.callbacks[event] or {}
        table.insert(self.callbacks[event], { fn = fn, owner = owner })
    end
    function EventRegistry:TriggerEvent(event, ...)
        for _, c in ipairs(self.callbacks[event] or {}) do c.fn(c.owner, ...) end
    end
    EventRegistry:RegisterCallback("Minimap.OnScaleUpdated", q.UpdateDefaultAnchor, q)
    -- Blizzard's one-time tip on the eye, shown from its OnShow until
    -- acknowledged (QueueStatusFrame.lua:143, CheckTutorials): above the eye,
    -- never flipped. HelpTip keeps its frames in a pool (HelpTip.lua:151);
    -- a tip closes when it hides, and with acknowledgeOnHide that's for good.
    HelpTip = { framePool = { activeObjects = {} } }
    function HelpTip.framePool:EnumerateActive() return pairs(self.activeObjects) end
    function HelpTip:IsShowing(parent)
        for f in pairs(self.framePool.activeObjects) do if f._parent == parent then return true end end
        return false
    end
    function HelpTip:Show(parent, info)
        if self:IsShowing(parent) then return true end
        local f = CreateFrame("Frame", nil, parent)
        f._strata, f.info = "DIALOG", info
        f:SetPoint("BOTTOM", parent, "TOP", 0, 20)
        f:SetScript("OnHide", function(self)
            HelpTip.framePool.activeObjects[self] = nil
            if self.info.acknowledgeOnHide then WoW.tutorialSeen = true end
        end)
        self.framePool.activeObjects[f] = true
        return true
    end
    function q:CheckTutorials()
        if not self:IsShown() or WoW.tutorialSeen then return end
        HelpTip:Show(self, { text = "queue changes", targetPoint = 1, acknowledgeOnHide = true }, self)
    end
    q:SetScript("OnShow", function(self) self:CheckTutorials() end)
    GameTimeFrame = CreateFrame("Button", "GameTimeFrame", c)
    GameTimeFrame._mouse = true

    -- The AddOns compartment (AddonCompartment.lua): RegisterAddon and the
    -- bulk RegisterAddons both end in UpdateDisplay.
    AddonCompartmentFrame = CreateFrame("Button", "AddonCompartmentFrame", c)
    local a = AddonCompartmentFrame
    a.registeredAddons = {}
    function a:RegisterAddon(data)
        table.insert(self.registeredAddons, data)
        self:UpdateDisplay()
    end
    function a:UpdateDisplay()
        self._displayed = #self.registeredAddons
    end
end

--------------------------------------------------------------------------------
-- State WoW.reset() clears besides the core's (WoW.onReset): the client's
-- data, and the frames Blizzard makes, built again
--------------------------------------------------------------------------------

local function resetMinimap()
    WoW.mouseOver = {}
    WoW.animGroups = {}
    WoW.now = 0
    WoW.shift = false
    WoW.settingsOpened = nil
    WoW.blizzardMenuOpened = nil
    WoW.cvars = { rotateMinimap = false, minimapTrackingShowAll = false, minimapShowPlayerCoords = true,
                  coordsByTenths = true }
    WoW.zone, WoW.pvp = "Thendal Village", "sanctuary"
    WoW.position = { 0.432, 0.248 }
    WoW.isDay = true
    WoW.monthDay, WoW.invites = 13, 0
    WoW.class = "MAGE"
    WoW.cursor = { -1000, -1000 }
    WoW.facing = 0
    WoW.mail, WoW.senders = false, {}
    WoW.instance = { type = "none", maxPlayers = 0, guild = false }
    WoW.loaded = {}
    WoW.tracking = {
        { name = "Auctioneer", texture = 1, active = false, type = "other", subType = 2, filterID = 8 },
        { name = "Innkeeper", texture = 2, active = true, type = "other", subType = 2, filterID = 2 },
        { name = "Find Herbs", texture = 3, active = true, type = "spell", subType = -1, spellID = 2383 },
        { name = "Quest POIs", texture = 4, active = true, type = "other", subType = -1, filterID = 20 },
        { name = "Target", texture = 5, active = true, type = "other", subType = -1, filterID = 21 },
        { name = "Hidden thing", texture = 6, active = false, type = "other", subType = -1, filterID = 99 },
    }
    WoW.trackingCalls = {}
    UIParent = newWidget("Frame", nil, "UIParent")
    UIParent._level = 0
    UIParent._width, UIParent._height = 1024, 768
    GameTooltip = newWidget("GameTooltip", UIParent, "GameTooltip")
    UISpecialFrames = {}
    buildCluster()
    -- The stub's own calls while building Blizzard's frames are not the
    -- addon's: test_methods checks only what the addon calls (Kit.strict
    -- forgets them for the first build the same way).
    WoW.methodsCalled = {}
end
table.insert(WoW.onReset, resetMinimap)
resetMinimap()

--------------------------------------------------------------------------------
-- Client APIs (each in the dump)
--------------------------------------------------------------------------------

SlashCmdList = {}
function wipe(t) for k in pairs(t) do t[k] = nil end; return t end
Enum = { UITextureSliceMode = { Stretched = 0, Tiled = 1 },
         MinimapTrackingFilter = { Auctioneer = 8, Innkeeper = 2, QuestPOIs = 20, Target = 21 } }
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end
WoW.build, WoW.version = "70374", "v0.1.0"
function GetBuildInfo() return "1.60.1", WoW.build, "Oct 13 2026", 16001 end
C_AddOns = {
    GetAddOnMetadata = function(name, variable)
        if name == "GlassMiniMap" and variable == "Version" then return WoW.version end
        return nil
    end,
    IsAddOnLoaded = function(name) return WoW.loaded[name] == true end,
}
function IsShiftKeyDown() return WoW.shift end
EditModeManagerFrame = nil

-- Settings (Options > AddOns): the canvas category API.
Settings = {
    RegisterCanvasLayoutCategory = function(panel, name)
        return { panel = panel, name = name, GetID = function() return name end }
    end,
    RegisterCanvasLayoutSubcategory = function(parent, panel, name)
        return { panel = panel, name = name, parent = parent, GetID = function() return name end }
    end,
    RegisterAddOnCategory = function(cat) WoW.settingsCategory = cat end,
    OpenToCategory = function(id) WoW.settingsOpened = id end,
}

function GetCVarBool(name) return WoW.cvars[name] == true end
function GetPlayerFacing() return WoW.facing end
function UnitClass() return "Mage", WoW.class, 8 end
-- The cursor, in screen pixels: WoW.cursor = { x, y } (the core's reads
-- WoW.cursorX / cursorY; the tests set both at once).
function GetCursorPosition() return WoW.cursor[1], WoW.cursor[2] end
function IsIndoors() return WoW.indoors == true end
C_ClassColor = { GetClassColor = function(class)
    if class == "MAGE" then return { r = 0.25, g = 0.78, b = 0.92 } end
    return { r = 1, g = 1, b = 1 }
end }
C_Texture = { GetAtlasInfo = function(name)
    if type(name) == "string" and (name:match("^ui%-hud%-calendar") or name:match("^professions_")) then
        return { width = 20, height = 20 }
    end
    return nil
end }
C_GameRules = { IsGameRuleActive = function() return false end }
C_Map = {
    GetBestMapForUnit = function() return WoW.position and 1429 or nil end,
    GetPlayerMapPosition = function()
        if not WoW.position then return nil end
        return { GetXY = function() return WoW.position[1], WoW.position[2] end }
    end,
}
C_PvP = { GetZonePVPInfo = function() return WoW.pvp, false, nil end }
function GetMinimapZoneText() return WoW.zone end
C_DateAndTime = {
    IsDayTime = function() return WoW.isDay end,
    GetCurrentCalendarTime = function() return { monthDay = WoW.monthDay, month = 10, year = 2026 } end,
}
C_Calendar = { GetNumPendingInvites = function() return WoW.invites end }
function ToggleWorldMap() WoW.worldMapToggled = (WoW.worldMapToggled or 0) + 1 end
function ToggleCalendar() WoW.calendarToggled = (WoW.calendarToggled or 0) + 1 end
function GameTimeFrame_OnClick(self) WoW.calendarClicked = self end
function GameTimeFrame_SetDate() end
function ToggleTimeManager() WoW.timeManager = (WoW.timeManager or 0) + 1 end
function GameTime_GetGameTime() return "21:57" end
function GameTime_GetLocalTime() return "22:57" end
-- Blizzard's, with its owner check (Minimap.lua:179-181): it writes nothing
-- unless MinimapCluster.ZoneTextButton owns the tooltip.
function Minimap_SetTooltip(pvpType)
    if GameTooltip._owner ~= MinimapCluster.ZoneTextButton then return end
    GameTooltip:AddLine("pvp:" .. tostring(pvpType))
end
function GetZoneText() return WoW.zoneName or WoW.zone end
function HasNewMail() return WoW.mail end
-- name, instanceType, difficultyID, difficultyName, maxPlayers, dynamicDifficulty, isDynamic,
-- instanceID, instanceGroupSize, lfgDungeonID (the 70374 dump).
function GetInstanceInfo()
    local i = WoW.instance
    return "Somewhere", i.type, i.type == "none" and 0 or 1, "", i.maxPlayers, 0, false, 33, i.maxPlayers, nil
end
function GetLatestThreeSenders() return unpack(WoW.senders) end
-- Blizzard's (FormattingUtil.lua:181): the header, then one sender per line.
function FormatUnreadMailTooltip(tooltip, headerText, senders)
    for _, sender in ipairs(senders) do headerText = headerText .. "\n" .. sender end
    tooltip:SetText(headerText)
end
function GetSubZoneText() return WoW.subzone or "" end

-- C_Minimap tracking over WoW.tracking.
C_Minimap = {
    GetNumTrackingTypes = function() return #WoW.tracking end,
    GetTrackingInfo = function(i)
        local t = WoW.tracking[i]
        if not t then return nil end
        return { name = t.name, texture = t.texture, active = t.active, type = t.type, subType = t.subType,
                 spellID = t.spellID }
    end,
    GetTrackingFilter = function(i)
        local t = WoW.tracking[i]
        if not t then return nil end
        return { filterID = t.filterID, spellID = t.spellID }
    end,
    SetTracking = function(i, on)
        table.insert(WoW.trackingCalls, { i, on })
        WoW.tracking[i].active = on
    end,
    ClearAllTracking = function()
        table.insert(WoW.trackingCalls, { "clear" })
        for _, t in ipairs(WoW.tracking) do t.active = false end
    end,
}
MinimapConstants = {
    ALWAYS_ON_FILTERS = { [20] = true },
    CONDITIONAL_FILTERS = { [21] = true },
    OPTIONAL_FILTERS = { [8] = true, [2] = true, [20] = false },
}
MinimapUtil = { SetTrackingFilterByFilterIndex = function(i, on)
    table.insert(WoW.trackingCalls, { "util", i, on })
    C_Minimap.SetTracking(i, on)
end }
--------------------------------------------------------------------------------
-- A fake Glass MiniMap Bar public API (its docs/PUBLIC-API.md, version 1)
--------------------------------------------------------------------------------

function WoW.FakeGlassMiniMapBar(version)
    local g = { PUBLIC_API_VERSION = version or 1, calls = {} }
    function g.UseLauncher(frame, opts)
        if type(frame) ~= "table" then return false, "UseLauncher takes a frame" end
        g.launcher, g.opts = frame, opts
        if opts and opts.setIcon then opts.setIcon("Interface\\Icons\\misc_arrowleft", nil) end
        return true
    end
    function g.ReleaseLauncher() g.launcher = nil end
    function g.LauncherClick(f, mouse) table.insert(g.calls, { "click", f, mouse }) end
    function g.LauncherEnter(f) table.insert(g.calls, { "enter", f }) end
    function g.LauncherLeave(f) table.insert(g.calls, { "leave", f }) end
    function g.SetGlassTint(...) g.tint = { n = select("#", ...), ... }; return true end
    function g.OpenOptions() g.optionsOpened = (g.optionsOpened or 0) + 1 end
    GlassMiniMapBar = g
    return g
end

--------------------------------------------------------------------------------
-- A fake Glass UI suite (its docs/SUITE.md and docs/SUITE-LOOK.md, API 1; the
-- numbers are its Suite.BODY, GlassUI 75013df). opts.answer: what Theme
-- returns (default: following, Pearl); opts.tint: the suite look's tint;
-- opts.noLook / noBody / noOpen leave those functions out (an older API 1).
-- Every call is recorded; Report keeps each state it was given.
--------------------------------------------------------------------------------

function WoW.FakeGlassUI(opts)
    opts = opts or {}
    local fake = { reports = {}, asked = {}, bodies = {}, tint = opts.tint or "clear" }
    local BODY = {
        clear  = { tint = { 0.13, 0.16, 0.22, 0.24 }, wash = 1, backing = 0.35 },
        smoked = { tint = { 0.05, 0.06, 0.08, 0.62 }, wash = 0.14 / 0.18, backing = 0.92 },
        class  = { classShade = 0.6, wash = 1, backing = 0.35 },
    }
    fake.BODY = BODY
    local S = { API = 1 }
    function S.Theme(addon)
        fake.asked[#fake.asked + 1] = addon
        if opts.answer then return opts.answer() end
        return { name = "pearl", preset = "pearl" }
    end
    function S.Report(addon, state) fake.reports[#fake.reports + 1] = { addon = addon, state = state } end
    if not opts.noLook then
        function S.Look() return { tint = fake.tint, hover = "glow", press = "flash", emptySlots = "frosted", accent = "gold" } end
    end
    if not opts.noBody then
        function S.Body(tint)
            fake.bodies[#fake.bodies + 1] = tint
            local b = BODY[tint or fake.tint]
            if not b then return nil end
            return { tint = b.tint and { b.tint[1], b.tint[2], b.tint[3], b.tint[4] }, classShade = b.classShade,
                     wash = b.wash, backing = { 0.04, 0.05, 0.07, b.backing } }
        end
    end
    if not opts.noOpen then
        function S.Open() fake.opened = (fake.opened or 0) + 1; return true end
    end
    fake.Suite = S
    GlassUI = { Suite = S }
    -- The suite look changes: Glass UI fires its event with a fresh table.
    function fake.SetTint(tint)
        fake.tint = tint
        EventRegistry:TriggerEvent("GlassUI.Suite.LookChanged",
            { tint = tint, hover = "glow", press = "flash", emptySlots = "frosted", accent = "gold" })
    end
    function fake.LastReport() local r = fake.reports[#fake.reports]; return r and r.state end
    return fake
end

-- Strict globals, last: what may read as nil.
-- LibStub: the embedded library's own loader reads _G.LibStub before creating it.
Kit.strict({ GlassMiniMap = true, GlassMiniMapDB = true, GlassMiniMapBar = true, GlassUI = true,
             SLASH_GLASSMINIMAP1 = true, SLASH_GLASSMINIMAP2 = true, LibStub = true,
             ForeverProbe = true, ForeverProbeDB = true, MinimapProbeDB = true })
