-- wow_stubs.lua: a minimal WoW: Forever mock for Lua 5.1 unit tests.
-- dofile("tests/wow_stubs.lua") FIRST in every test; drive it via the WoW table.
-- Glass MiniMap Bar's stubs (themselves GlassUnitFrames' and GlassPanel's,
-- trimmed), plus the Forever minimap cluster as Blizzard_Minimap builds it,
-- C_Minimap's tracking, the calendar, the AddOns compartment and a fake LibDBIcon.
--
-- What it models, on purpose:
-- - STRICT globals: reading any global it does not define is an error. The
--   stub is the allowlist of APIs verified present in the API dump.
-- - EVENT names: RegisterEvent throws on a name the API dump does not declare.
-- - METHOD calls: every widget method called is recorded (WoW.methodsCalled)
--   so test_methods.lua can check each against the dump's widget methods.
-- - The widget METATABLE is a real method table, like the client's, because
--   the drawer calls methods through getmetatable(CreateFrame("Frame")).__index
--   on buttons whose own SetPoint/Show/... it has replaced.

WoW = {}
WoW.DUMP = os.getenv("GLASSMM_API_DUMP") or "C:/Projects/WoW/References/Forever/api/forever-api-1.60.1.70374.md"

--------------------------------------------------------------------------------
-- Known events (from the dump when present)
--------------------------------------------------------------------------------

WoW.KNOWN_EVENTS = {}
do
    local f = io.open(WoW.DUMP, "r")
    if f then
        local inEvents = false
        for line in f:lines() do
            if line:match("^## Documented events") then inEvents = true
            elseif line:match("^## ") then inEvents = false
            elseif inEvents then
                local name = line:match("^([A-Z][A-Z0-9_]+)%s+%(")
                if name then WoW.KNOWN_EVENTS[name] = true end
            end
        end
        f:close()
    end
    if next(WoW.KNOWN_EVENTS) == nil then
        for _, e in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "GLOBAL_MOUSE_DOWN",
                             "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA",
                             "CALENDAR_UPDATE_PENDING_INVITES", "MINIMAP_UPDATE_ZOOM", "MINIMAP_UPDATE_TRACKING",
                             "SPELLS_CHANGED", "CVAR_UPDATE", "DIEL_CYCLE_CHANGED", "EDIT_MODE_LAYOUTS_UPDATED",
                             "PLAYER_REGEN_ENABLED", "UPDATE_PENDING_MAIL",
                             "SCREENSHOT_SUCCEEDED", "SCREENSHOT_FAILED" }) do
            WoW.KNOWN_EVENTS[e] = true
        end
    end
end

--------------------------------------------------------------------------------
-- Widgets
--------------------------------------------------------------------------------

local Methods = {}   -- implementations, by method name
WoW.Methods = Methods

local function record(w, name)
    WoW.methodsCalled[(rawget(w, "_type") or "?") .. ":" .. name] = true
end

-- The shared method table: any Capitalised name is a method (a no-op unless
-- implemented below); anything else reads as nil, like a missing field.
local MethodTable = setmetatable({}, {
    __index = function(_, k)
        if type(k) ~= "string" or not k:match("^%u") then return nil end
        return function(self, ...)
            record(self, k)
            local impl = Methods[k]
            if impl then return impl(self, ...) end
            return nil
        end
    end,
})
local widgetMT = { __index = MethodTable }

local function newWidget(wtype, parent, name)
    local w = setmetatable({ _type = wtype, _parent = parent, _shown = true, _points = {},
                             _scripts = {}, _events = {}, _children = {}, _regions = {},
                             _level = parent and parent._level and (parent._level + 1) or 1,
                             _width = 0, _height = 0, _name = name, _scale = 1, _alpha = 1,
                             _mouse = false }, widgetMT)
    return w
end
WoW.newWidget = newWidget

local function adopt(parent, w)
    if parent and parent._children then table.insert(parent._children, w) end
end

local SCRIPTED = { Frame = true, Button = true, CheckButton = true, StatusBar = true, GameTooltip = true,
                   Minimap = true, EditBox = true }

function CreateFrame(ftype, name, parent, template)
    local w = newWidget(ftype, parent, name)
    w._template = template
    adopt(parent, w)
    table.insert(WoW.frames, w)
    if name then rawset(_G, name, w) end
    if template == "UICheckButtonTemplate" or template == "UIPanelButtonTemplate" then
        w.Text = newWidget("FontString", w)
    end
    if template == "UIRadioButtonTemplate" then w.text = newWidget("FontString", w) end
    return w
end

-- Dispatch effective visibility changes, including descendants. Re-evaluate
-- after each callback, since a handler can hide another frame in this tree.
local function visibilityTree(w, list)
    list[#list + 1] = { w, Methods.IsVisible(w) }
    for _, child in ipairs(w._children) do visibilityTree(child, list) end
end
local function setShown(w, shown)
    if w._shown == shown then return end
    local list = {}
    visibilityTree(w, list)
    w._shown = shown
    for _, entry in ipairs(list) do
        local node, was = entry[1], entry[2]
        local visible = Methods.IsVisible(node)
        if was ~= visible then
            local fn = node._scripts[visible and "OnShow" or "OnHide"]
            if fn then fn(node) end
        end
    end
end
function Methods.Show(w) setShown(w, true) end
function Methods.Hide(w) setShown(w, false) end
function Methods.SetShown(w, v) if v then Methods.Show(w) else Methods.Hide(w) end end
function Methods.IsShown(w) return w._shown end
function Methods.IsVisible(w)
    local p = w
    while p do if not p._shown then return false end; p = p._parent end
    return true
end
function Methods.SetPoint(w, ...) table.insert(w._points, { ... }) end
function Methods.ClearAllPoints(w) w._points = {} end
function Methods.GetPoint(w, i)
    local p = w._points[i or 1]
    if p then return p[1], p[2], p[3], p[4], p[5] end
end
function Methods.GetNumPoints(w) return #w._points end
function Methods.SetAllPoints(w, rel) table.insert(w._points, { "ALL", rel }) end
function Methods.SetSize(w, x, y) w._width, w._height = x, y end
function Methods.SetWidth(w, x) w._width = x end
function Methods.SetHeight(w, y) w._height = y end
function Methods.GetWidth(w) return w._width end
function Methods.GetHeight(w) return w._height end
function Methods.GetSize(w) return w._width, w._height end
function Methods.GetCenter(w) return w._cx, w._cy end
function Methods.GetEffectiveScale(w) return w._effScale or 1 end
function Methods.SetScale(w, s) w._scale = s end
function Methods.GetScale(w) return w._scale end
-- A gradient texture ignores SetAlpha on this client (70374, porting guide §3):
-- kept here, or a test of a wash's strength passes against that bug.
function Methods.SetAlpha(w, a) if not w._gradient then w._alpha = a end end
function Methods.GetAlpha(w) return w._alpha end
function Methods.GetFrameLevel(w) return w._level end
function Methods.SetFrameLevel(w, l) w._level = l end
function Methods.SetFrameStrata(w, s) w._strata = s end
function Methods.GetFrameStrata(w) return w._strata or "MEDIUM" end
function Methods.GetName(w) return w._name end
function Methods.GetParent(w) return w._parent end
function Methods.SetParent(w, p)
    if w._parent and w._parent._children then
        for i, c in ipairs(w._parent._children) do
            if c == w then table.remove(w._parent._children, i); break end
        end
    end
    w._parent = p
    adopt(p, w)
end
function Methods.GetChildren(w) return unpack(w._children) end
function Methods.GetRegions(w) return unpack(w._regions) end
function Methods.IsObjectType(w, t)
    if w._type == t then return true end
    return t == "Frame" and (w._type == "Button" or w._type == "CheckButton" or w._type == "Minimap")
end
function Methods.GetObjectType(w) return w._type end
function Methods.IsForbidden(w) return false end
function Methods.IsProtected(w) return w._protected == true end
function Methods.EnableMouse(w, v) w._mouse = v and true or false end
function Methods.IsMouseEnabled(w) return w._mouse == true end
function Methods.RegisterForClicks(w, ...) w._clicks = { ... } end
function Methods.RegisterForDrag(w, ...) w._drag = { ... } end
function Methods.IsMouseOver(w) return WoW.mouseOver[w] == true end
function Methods.GetChecked(w) return w._checked == true end
function Methods.SetEnabled(w, v) w._enabled = v and true or false end
function Methods.IsEnabled(w) return w._enabled ~= false end
function Methods.SetChecked(w, v) w._checked = v and true or false end
function Methods.SetText(w, t) w._text = type(t) == "number" and tostring(t) or t end   -- a FontString keeps a string
function Methods.SetValue(w, value)
    if w._value ~= value then
        w._value = value
        if w._scripts.OnValueChanged then w._scripts.OnValueChanged(w, value) end
    end
end

-- A drag requires a visible mouse-enabled slider; direct SetValue alone does
-- not exercise that interaction requirement.
function WoW.dragSlider(w, value)
    assert(Methods.IsVisible(w) and Methods.IsMouseEnabled(w), "slider cannot be dragged")
    w:SetValue(value)
end
function Methods.GetText(w) return w._text end
function Methods.SetTextColor(w, r, g, b) w._textColor = { r, g, b } end
function Methods.GetAnimationGroups(w) return unpack(w._anims or {}) end
function Methods.UnregisterAllEvents(w) w._events = {} end
function Methods.SetHighlightTexture(w, file, blend)
    w._highlight = newWidget("Texture", w)
    w._highlight._file = file
    return true
end
function Methods.GetHighlightTexture(w) return w._highlight end
function Methods.SetNormalTexture(w, file) w._normal = newWidget("Texture", w); w._normal._file = file end
function Methods.GetNormalTexture(w) return w._normal end
function Methods.SetCheckedTexture(w, file) w._checkedTex = newWidget("Texture", w) end
function Methods.GetCheckedTexture(w) return w._checkedTex end

-- Animations: Play marks a group playing; WoW.finishAnimations() completes
-- every playing group (OnFinished), as the client would after its duration.
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
function Methods.IsPlaying(ag) return ag._playing == true end
function Methods.SetLooping(ag, value) ag._looping = value end
function Methods.SetDegrees(a, value) a._degrees = value end
function Methods.SetBlendMode(t, value) t._blendMode = value end
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
local HANDLERS = { OnClick = true, OnMouseUp = true, OnMouseDown = true, OnEnter = true, OnLeave = true,
                   OnShow = true, OnHide = true, OnUpdate = true, OnEvent = true, OnDragStart = true, OnDragStop = true,
                   OnDoubleClick = true, OnMouseWheel = true }
function Methods.HasScript(w, name) return SCRIPTED[w._type] == true and HANDLERS[name] == true end
function Methods.SetScript(w, name, fn) w._scripts[name] = fn end
function Methods.GetScript(w, name) return w._scripts[name] end
function Methods.HookScript(w, name, fn)
    local old = w._scripts[name]
    w._scripts[name] = function(...) if old then old(...) end; fn(...) end
end
function Methods.Click(w, mouse)
    if w._scripts.OnClick then w._scripts.OnClick(w, mouse or "LeftButton", false) end
end
function Methods.RegisterEvent(w, e)
    if not WoW.KNOWN_EVENTS[e] then error("Attempt to register unknown event \"" .. e .. "\"", 2) end
    w._events[e] = true
    return true
end
function Methods.UnregisterEvent(w, e) w._events[e] = nil end

-- Regions.
local function region(w, wtype, layer)
    local r = newWidget(wtype, w)
    r._layer = layer
    if wtype ~= "MaskTexture" then table.insert(w._regions, r) end
    return r
end
function Methods.CreateTexture(w, _, layer) return region(w, "Texture", layer) end
function Methods.CreateMaskTexture(w) return region(w, "MaskTexture") end
function Methods.CreateFontString(w, _, layer) return region(w, "FontString", layer) end
function Methods.SetTexture(t, file) t._file = file; t._atlas = nil; return true end
function Methods.GetTexture(t) return t._file end
function Methods.SetAtlas(t, atlas) t._atlas = atlas; t._file = nil; return true end
function Methods.GetAtlas(t) return t._atlas end
function Methods.SetTexCoord(t, ...) t._coords = { ... } end
function Methods.GetTexCoord(t)
    local c = t._coords or { 0, 0, 0, 1, 1, 0, 1, 1 }
    return unpack(c)
end
function Methods.SetVertexColor(t, r, g, b, a) t._vertex = { r, g, b, a } end
function Methods.SetRotation(t, r) t._rotation = r end
function Methods.SetColorTexture(t, r, g, b, a) t._color = { r, g, b, a } end
function Methods.AddMaskTexture(t, m) t._masks = t._masks or {}; table.insert(t._masks, m) end
function Methods.RemoveMaskTexture(t, m)
    for i, x in ipairs(t._masks or {}) do if x == m then table.remove(t._masks, i); return end end
end
function Methods.SetGradient(t, orientation, c1, c2)
    assert(type(c1) == "table" and type(c2) == "table", "SetGradient takes color objects on this API")
    t._gradient = { orientation, c1, c2 }
end
function Methods.SetFont(fs, file, size, flags) fs._font = { file, size, flags }; return true end

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
    -- The instance flag (InstanceDifficulty.xml): it and its Guild banner have
    -- OnEnter tooltips, so both take the mouse.
    c.InstanceDifficulty = CreateFrame("Frame", nil, c)
    c.InstanceDifficulty._mouse = true
    c.InstanceDifficulty.Guild = CreateFrame("Frame", nil, c.InstanceDifficulty)
    c.InstanceDifficulty.Guild._mouse = true
    local d = c.InstanceDifficulty
    d.Default = CreateFrame("Frame", nil, d)
    d.Default.Text = d.Default:CreateFontString(nil, "OVERLAY")
    d.Guild.Instance = CreateFrame("Frame", nil, d.Guild)
    d.Guild.Instance.Text = d.Guild.Instance:CreateFontString(nil, "OVERLAY")
    d.Default._shown, d.Guild._shown = false, false
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
    c.IndicatorFrame.MailFrame._shown = false
    -- The LFG eye: UIParent's, its own Edit Mode system, hidden until queued.
    QueueStatusButton = CreateFrame("Button", "QueueStatusButton", UIParent)
    QueueStatusButton._width, QueueStatusButton._height = 45, 45
    QueueStatusButton._shown = false
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
-- Globals
--------------------------------------------------------------------------------

function WoW.reset()
    WoW.frames = {}
    WoW.chat = {}
    WoW.methodsCalled = WoW.methodsCalled or {}
    WoW.timers = {}
    WoW.mouseOver = {}
    WoW.animGroups = {}
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
    WoW.facing = 0
    WoW.combat = false
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
end

function print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    table.insert(WoW.chat, table.concat(parts, " "))
end

SlashCmdList = {}
strmatch = string.match
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
function issecretvalue(v) return false end
function InCombatLockdown() return WoW.combat end
EditModeManagerFrame = nil
-- hooksecurefunc(table, name, fn) or hooksecurefunc(globalName, fn).
function hooksecurefunc(t, name, fn)
    if type(t) == "string" then
        local gname, f = t, name
        local orig = rawget(_G, gname)
        rawset(_G, gname, function(...) local r = orig(...); f(...); return r end)
        return
    end
    local orig = t[name]
    rawset(t, name, function(self, ...) local r = orig(self, ...); fn(self, ...); return r end)
end

-- Timers keep their delay: WoW.flushTimers(upTo) runs those due within upTo.
C_Timer = { After = function(s, fn) table.insert(WoW.timers, { s = s, fn = fn }) end }
function WoW.flushTimers(upTo)
    for _ = 1, 10 do   -- timers may schedule timers (a deferred sync); settle them
        local run, keep = {}, {}
        for _, t in ipairs(WoW.timers) do
            if upTo == nil or t.s <= upTo then run[#run + 1] = t else keep[#keep + 1] = t end
        end
        WoW.timers = keep
        if #run == 0 then return end
        for _, t in ipairs(run) do t.fn() end
    end
end

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

--------------------------------------------------------------------------------
-- Driving
--------------------------------------------------------------------------------

-- Fire an event at every frame registered for it. Errors are NOT caught.
function WoW.fire(event, ...)
    local list = {}
    for _, w in ipairs(WoW.frames) do list[#list + 1] = w end
    for _, w in ipairs(list) do
        local handler = w._scripts.OnEvent
        if handler and w._events[event] then handler(w, event, ...) end
    end
end

-- One rendered frame: OnUpdate on every visible frame.
function WoW.tick(elapsed)
    elapsed = elapsed or 0.02
    local list = {}
    for _, w in ipairs(WoW.frames) do list[#list + 1] = w end
    for _, w in ipairs(list) do
        local fn = w._scripts.OnUpdate
        if fn and Methods.IsVisible(w) then fn(w, elapsed) end
    end
end

WoW.reset()

-- Strict globals.
-- LibStub: the embedded library's own loader reads _G.LibStub before creating it.
local allowNil = { GlassMiniMap = true, GlassMiniMapDB = true, GlassMiniMapBar = true, GlassUI = true,
                   SLASH_GLASSMINIMAP1 = true, SLASH_GLASSMINIMAP2 = true, LibStub = true,
                   ForeverProbe = true, ForeverProbeDB = true, MinimapProbeDB = true }
setmetatable(_G, { __index = function(_, k)
    if allowNil[k] then return nil end
    error("read of undefined global '" .. tostring(k) .. "' (not stubbed: is it in the API dump?)", 2)
end })
