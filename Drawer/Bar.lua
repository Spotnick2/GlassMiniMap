-- Bar.lua: the addon drawer and its launcher disc.
--
-- Glass MiniMap Bar's Bar.lua and settings, absorbed. The launcher is no
-- longer a LibDBIcon button dragged around the ring: it is our own glass
-- disc on the ring at the bottom left (Ring.AddDisc), and the drawer (a glass
-- panel, Glass.Apply) grows out of it. The buttons in it are the addon buttons
-- collected off the minimap (Collector.lua) and the AddOns compartment's
-- entries (Compartment.lua), laid out in rows, in the user's order, then
-- alphabetically.
--
-- Opening: hover (default) or click on the launcher. Closing: the mouse has
-- been off the drawer, the launcher and any open menu for `hideDelay`
-- seconds; in click mode, a click anywhere else. Right-click on the launcher
-- repeats the last button used when that option is on, else opens the
-- drawer's options. Nothing is secure, so all of this works in combat.
--
-- When the standalone Glass MiniMap Bar is loaded too, the two would fight
-- over the same buttons: the drawer stays off, Blizzard's AddOns button stays
-- where it is, and that addon's settings are imported once (Drawer.Import).

GlassMiniMap = GlassMiniMap or {}
local GMM = GlassMiniMap
local Bar = {}
local Drawer = Bar
GMM.Drawer = Drawer
local API = GMM.API
local Glass = GMM.Glass
local Theme = GMM.Theme
local Orb = GMM.Orb
local Collector = GMM.Collector
local Compartment = GMM.Compartment
local W = API.W

Bar.GAP = 3                         -- between buttons, and between the drawer and the launcher
Bar.ANGLE = 225                     -- the launcher's place on the ring (degrees clockwise from the top)
Bar.ARROWS = {
    left = "Interface\\Icons\\misc_arrowleft", right = "Interface\\Icons\\misc_arrowright",
    up = "Interface\\Icons\\misc_arrowlup", down = "Interface\\Icons\\misc_arrowdown",
}

--------------------------------------------------------------------------------
-- Settings (GlassMiniMapDB.drawer)
--------------------------------------------------------------------------------

--   hidden     [buttonName] = true for buttons the user hid in the options
--   openOn     "hover" | "click"
--   hideDelay  seconds the mouse may be away before the drawer closes
--   direction  "auto" | "left" | "right" | "up" | "down"
--   perRow     buttons per line before wrapping
--   buttonSize px
--   skin       glass orb skin on the collected buttons
--   animate    the drawer grows out of the launcher and shrinks back
--   lastUsed   the launcher wears the last button used; right-click repeats it
--   last       { name = , mouse = } the last button clicked in the drawer
--   order      button names in the user's order (Up/Down in the options)
--   imported   Glass MiniMap Bar's settings were copied in (once)
Drawer.DEFAULTS = {
    openOn = "hover", hideDelay = 0.75, direction = "auto", perRow = 12, buttonSize = 28,
    skin = true, lastUsed = false, animate = true,
}
Drawer.LIMITS = {
    hideDelay = { 0.25, 3, 0.25 }, perRow = { 1, 30, 1 }, buttonSize = { 20, 40, 2 },
}

local db                             -- GlassMiniMapDB.drawer
local frame, glass, launcher
local hideTimer = 0

local function clamp(key, v)
    local l = Drawer.LIMITS[key]
    if type(v) ~= "number" then return Drawer.DEFAULTS[key] end
    return math.max(l[1], math.min(l[2], v))
end

-- Fill in what is missing; fix what is malformed. Never wipes the user's data.
function Drawer.LoadDB(saved)
    local d = type(saved) == "table" and saved or {}
    if type(d.hidden) ~= "table" then d.hidden = {} end
    for k, v in pairs(Drawer.DEFAULTS) do
        if d[k] == nil or type(d[k]) ~= type(v) then d[k] = v end
    end
    if d.openOn ~= "hover" and d.openOn ~= "click" then d.openOn = "hover" end
    if not Bar.ARROWS[d.direction] and d.direction ~= "auto" then d.direction = "auto" end
    for k in pairs(Drawer.LIMITS) do d[k] = clamp(k, d[k]) end
    if type(d.last) ~= "table" or type(d.last.name) ~= "string" then d.last = nil end
    local order = {}
    if type(d.order) == "table" then
        for _, name in ipairs(d.order) do
            if type(name) == "string" then order[#order + 1] = name end
        end
    end
    d.order = order
    if d.imported ~= true then d.imported = nil end
    db = d
    return d
end

-- Glass MiniMap Bar's settings (GlassMiniMapBarDB), copied once into ours.
-- Only while that addon is loaded can its saved variables be read, so the
-- import happens in the session that has both enabled. Returns true if it ran.
Drawer.IMPORTED_KEYS = { "openOn", "hideDelay", "direction", "perRow", "buttonSize", "skin",
                         "lastUsed", "animate", "last", "order", "hidden" }
function Drawer.Import(old)
    if db.imported or type(old) ~= "table" then return false end
    for _, k in ipairs(Drawer.IMPORTED_KEYS) do
        local v = old[k]
        if type(v) == "table" then
            local copy = {}
            for kk, vv in pairs(v) do copy[kk] = vv end
            db[k] = copy
        elseif v ~= nil then
            db[k] = v
        end
    end
    Drawer.LoadDB(db)                -- repair whatever came over
    db.imported = true
    return true
end

-- Apply a setting from the options page (or a slash command).
function Drawer.Set(key, value)
    if Drawer.LIMITS[key] then value = clamp(key, value) end
    db[key] = value
    if not frame then return end
    if key == "skin" then Bar.ApplySkin()
    elseif key == "lastUsed" then Bar.UpdateLauncherIcon()
    elseif key == "animate" or key == "openOn" or key == "hideDelay" then return
    else Bar.Layout(); Bar.UpdateLauncherIcon() end
end

function Drawer.SetHidden(name, hidden)
    db.hidden[name] = hidden and true or nil
    if not frame then return end
    Bar.Layout()
    Bar.UpdateLauncherIcon()
end

-- Move a button `delta` places (-1 up, +1 down) among the buttons in the
-- drawer (Collector.Movable): buttons hidden by the user or by their addon
-- are stepped over, so every move changes the drawer. Returns true if it moved.
function Drawer.MoveButton(name, delta)
    local movable = Collector.Movable(db.hidden, name)
    local i
    for k, n in ipairs(movable) do if n == name then i = k end end
    local other = i and movable[i + delta]
    if not other then return false end
    -- The full order: the saved list as it is (names not collected this
    -- session keep their slot), then collected names never ordered.
    local full, at, seen = {}, {}, {}
    for _, n in ipairs(db.order) do full[#full + 1] = n; seen[n] = true end
    for _, e in ipairs(Collector.entries) do
        if not seen[e.name] then full[#full + 1] = e.name; seen[e.name] = true end
    end
    for k, n in ipairs(full) do at[n] = k end
    full[at[name]], full[at[other]] = other, name
    db.order = full
    Collector.Sort()
    if frame then Bar.Layout() end
    return true
end

function Drawer.DB() return db end
function Drawer.IsActive() return frame ~= nil end

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

-- Which halves of the screen the launcher sits in: onRight, onTop. Compared
-- in UIParent units: the launcher lives in the minimap's scale.
local function launcherSide()
    if not launcher then return true, true end
    local x, y = launcher:GetCenter()
    if type(x) ~= "number" or type(y) ~= "number" then return true, true end
    local s = launcher:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return x * s >= UIParent:GetWidth() / 2, y * s >= UIParent:GetHeight() / 2
end

-- "left" | "right" | "up" | "down", resolving "auto" from which half of the
-- screen the launcher sits in: the drawer opens toward the middle.
function Bar.Direction()
    local d = db.direction
    if d ~= "auto" then return d end
    return launcherSide() and "left" or "right"
end

-- Place the visible buttons and size the drawer. Returns the number placed.
-- Extra lines stack toward the screen centre, and the first line always sits
-- level with the launcher.
function Bar.Layout()
    if not frame then return 0 end
    local visible = Collector.Visible(db.hidden)
    for _, e in ipairs(Collector.entries) do W.Hide(e.btn) end

    local dir = Bar.Direction()
    local onRight, onTop = launcherSide()
    local vertical = dir == "up" or dir == "down"
    local size, gap = db.buttonSize, Bar.GAP
    local pad = Glass.Inset("large")
    local n = #visible
    local perLine = math.max(1, math.min(db.perRow, math.max(n, 1)))
    local lines = math.max(1, math.ceil(n / perLine))
    local long = pad * 2 + perLine * size + (perLine - 1) * gap
    local short = pad * 2 + lines * size + (lines - 1) * gap
    if vertical then frame:SetSize(short, long) else frame:SetSize(long, short) end

    local level = Glass.ContentLevel(frame)
    for i, e in ipairs(visible) do
        local k = i - 1
        local a = pad + (k % perLine) * (size + gap) + size / 2              -- along the line
        local c = pad + math.floor(k / perLine) * (size + gap) + size / 2    -- which line
        local x, y
        if vertical then
            x, y = onRight and (short - c) or c, -a
        else
            x, y = a, onTop and -c or -(short - c)
        end
        local btn = e.btn
        local scale = size / ((type(e.width) == "number" and e.width > 0) and e.width or size)
        W.SetScale(btn, scale)
        W.SetFrameStrata(btn, frame:GetFrameStrata())
        W.SetFrameLevel(btn, level)
        W.ClearAllPoints(btn)
        W.SetPoint(btn, "CENTER", frame, "TOPLEFT", x / scale, y / scale)
        W.Show(btn)
    end

    -- Beside the launcher, first line level with it. The drawer lives on
    -- UIParent; the launcher in the minimap's scale: anchoring across scales
    -- is fine, offsets are in the drawer's own units.
    frame:ClearAllPoints()
    if launcher then
        local half = pad + size / 2
        if dir == "left" then
            frame:SetPoint(onTop and "TOPRIGHT" or "BOTTOMRIGHT", launcher, "LEFT", -gap, onTop and half or -half)
        elseif dir == "right" then
            frame:SetPoint(onTop and "TOPLEFT" or "BOTTOMLEFT", launcher, "RIGHT", gap, onTop and half or -half)
        elseif dir == "down" then
            frame:SetPoint(onRight and "TOPRIGHT" or "TOPLEFT", launcher, "BOTTOM", onRight and half or -half, -gap)
        else
            frame:SetPoint(onRight and "BOTTOMRIGHT" or "BOTTOMLEFT", launcher, "TOP", onRight and half or -half, gap)
        end
    else
        frame:SetPoint("CENTER", UIParent, "CENTER")
    end
    return n
end

--------------------------------------------------------------------------------
-- Opening and closing
--------------------------------------------------------------------------------

-- The drawer grows out of the launcher (scaled from its launcher-side edge
-- while fading in) and shrinks back into it. Scale animations scale the
-- children too, so the buttons grow with the glass.
Bar.GROW = { duration = 0.18, from = 0.05 }
Bar.SHRINK = { duration = 0.12 }
local ORIGIN = { left = "RIGHT", right = "LEFT", up = "BOTTOM", down = "TOP" }
local grow, shrink, closing = nil, nil, false
-- Set when a click on the launcher closed the drawer: the cursor is still on
-- the launcher, which must not count as "hovering back" until it leaves.
local clickClosed = false

-- Hide GameTooltip only when it's ours.
local function hideOurTooltip()
    local owner = GameTooltip:GetOwner()
    if not owner then return end
    local ok, parent = pcall(W.GetParent, owner)
    if owner == launcher or owner == frame or (ok and parent == frame) then GameTooltip:Hide() end
end

local function makeAnim(fromScale, toScale, fromAlpha, toAlpha, duration, smoothing)
    local ag = frame:CreateAnimationGroup()
    local sc = ag:CreateAnimation("Scale")
    sc:SetDuration(duration)
    sc:SetSmoothing(smoothing)
    local al = ag:CreateAnimation("Alpha")
    al:SetFromAlpha(fromAlpha)
    al:SetToAlpha(toAlpha)
    al:SetDuration(duration)
    ag.scale, ag.fromScale, ag.toScale = sc, fromScale, toScale
    return ag
end

local function aim(ag)
    local dir = Bar.Direction()
    local lo, hi = ag.fromScale, ag.toScale
    ag.scale:SetOrigin(ORIGIN[dir], 0, 0)
    if dir == "up" or dir == "down" then
        ag.scale:SetScaleFrom(1, lo)
        ag.scale:SetScaleTo(1, hi)
    else
        ag.scale:SetScaleFrom(lo, 1)
        ag.scale:SetScaleTo(hi, 1)
    end
end

function Bar.IsOpen() return frame ~= nil and frame:IsShown() and not closing end

function Bar.Open()
    if not frame then return end
    -- Late creators: a scan or compartment change that finds one lays out
    -- through onChange already.
    local added = Collector.Scan()
    local changed = API.Try("compartment:sync", Compartment.Sync)
    if added == 0 and not changed then Bar.Layout() end
    Bar.UpdateLauncherIcon()
    hideTimer = db.hideDelay
    local wasShown, wasClosing = frame:IsShown(), closing
    if closing then shrink:Stop() end
    closing = false
    frame:Show()
    frame:Raise()
    if db.animate and (wasClosing or not wasShown) then
        aim(grow)
        grow:Play()
    end
end

function Bar.Close()
    hideOurTooltip()
    if not (frame and frame:IsShown()) or closing then return end
    if db.animate then
        closing = true
        grow:Stop()
        aim(shrink)
        shrink:Play()                   -- OnFinished hides the frame
    else
        frame:Hide()
    end
end

function Bar.Toggle()
    if Bar.IsOpen() then Bar.Close() else Bar.Open() end
end

local function mouseIsHome()
    return (frame and frame:IsMouseOver(4, -4, -4, 4))
        or (launcher and launcher:IsMouseOver())
        or API.MouseOverMenu()
end

local function onUpdate(_, elapsed)
    if closing then
        if db.openOn == "hover" and not clickClosed and launcher and launcher:IsMouseOver() then Bar.Open() end
        return
    end
    if mouseIsHome() then
        hideTimer = db.hideDelay
    else
        hideTimer = hideTimer - elapsed
        if hideTimer <= 0 then Bar.Close() end
    end
end

local function onEvent(_, event)
    if event == "GLOBAL_MOUSE_DOWN" and db.openOn == "click" and not mouseIsHome() then
        Bar.Close()
    end
end

--------------------------------------------------------------------------------
-- The launcher
--------------------------------------------------------------------------------

local function lastEntry()
    local e = db.lastUsed and db.last and Collector.byName[db.last.name]
    if e and e.wanted and not db.hidden[e.name] then return e end
    return nil
end

-- The launcher's face: the last-used button's icon, or the arrow toward the drawer.
function Bar.UpdateLauncherIcon()
    if not launcher then return end
    local icon, coords, atlas
    local last = lastEntry()
    if last then
        local obj = rawget(last.btn, "dataObject")       -- a LibDBIcon button: ask its broker
        if type(obj) == "table" and obj.icon then
            icon, coords = obj.icon, obj.iconCoords
        else
            local info = Orb.IconOf(last.btn)
            if info and info.atlas then
                atlas = info.atlas
            elseif info and info.file then
                local c = info.coords
                icon = info.file
                if #c >= 8 then coords = { c[1], c[5], c[2], c[4] } end   -- UL, UR, LL -> l, r, t, b
            end
        end
    end
    local tex = launcher.icon
    if atlas then
        tex:SetAtlas(atlas)
        tex:SetTexCoord(0, 1, 0, 1)
        return
    end
    if not icon then icon, coords = Bar.ARROWS[Bar.Direction()], nil end
    tex:SetTexture(icon)
    if type(coords) == "table" and #coords >= 4 then
        tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    else
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    launcher.face = icon
end

local function showTip(owner)
    local last = lastEntry()
    local empty = #Collector.Visible(db.hidden) == 0
    GameTooltip:SetOwner(owner, "ANCHOR_NONE")
    GameTooltip:ClearLines()
    GameTooltip:SetPoint("TOPRIGHT", owner, "BOTTOMLEFT", 0, -4)
    GameTooltip:AddLine("Addon drawer")
    if empty then GameTooltip:AddLine("No addon buttons collected yet.", 1, 1, 1) end
    if last then GameTooltip:AddLine("Right-click: " .. last.display, 1, 1, 1)
    else GameTooltip:AddLine("Right-click: options", 0.6, 0.6, 0.6) end
    GameTooltip:Show()
end

function Bar.OnLauncherClick(_, mouse)
    GameTooltip:Hide()
    if mouse == "RightButton" and not IsShiftKeyDown() then
        local last = lastEntry()
        if last and Collector.Replay(last.name, db.last.mouse) then return end
        GMM.Options.Open("drawer")
    elseif mouse == "RightButton" or mouse == "MiddleButton" then
        GMM.Options.Open("drawer")
    elseif Bar.IsOpen() then
        Bar.Close()
        clickClosed = true
    else
        Bar.Open()
    end
end

function Bar.OnLauncherEnter(owner)
    clickClosed = false
    if db.openOn == "hover" and not Bar.IsOpen() then Bar.Open() end
    showTip(owner)
end

function Bar.OnLauncherLeave()
    clickClosed = false
    GameTooltip:Hide()
end

function Bar.ApplySkin()
    for _, e in ipairs(Collector.entries) do
        API.Try("skin:" .. e.name, db.skin and Orb.Skin or Orb.Unskin, e.btn)
    end
end

function Bar.Launcher() return launcher end
function Bar.Frame() return frame end

--------------------------------------------------------------------------------
-- Start
--------------------------------------------------------------------------------

local function onChange()
    Bar.ApplySkin()
    Bar.Layout()
    Bar.UpdateLauncherIcon()
    Compartment.Request()               -- a minimap button arriving or going may (un)duplicate an entry
    if GMM.Options and GMM.Options.RefreshDrawer then GMM.Options.RefreshDrawer() end
end

local function onClick(entry, mouse)
    db.last = { name = entry.name, mouse = mouse }
    Bar.UpdateLauncherIcon()
end

-- Build once, at login: the drawer, the launcher disc, the sources.
function Bar.Build()
    frame = CreateFrame("Frame", nil, UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(50)
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)             -- the gaps between buttons keep the drawer, not the world
    frame:Hide()
    glass = Glass.Apply(frame, "large")
    Theme.Register(glass)
    frame:SetScript("OnUpdate", onUpdate)
    frame:SetScript("OnEvent", onEvent)
    frame:SetScript("OnShow", function(self) API.RegisterEvent(self, "GLOBAL_MOUSE_DOWN", "drawer") end)
    frame:SetScript("OnHide", function(self)
        self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
        closing = false
    end)
    grow = makeAnim(Bar.GROW.from, 1, 0, 1, Bar.GROW.duration, "OUT")
    shrink = makeAnim(1, Bar.GROW.from, 1, 0, Bar.SHRINK.duration, "IN")
    shrink:SetScript("OnFinished", function() frame:Hide() end)
    Collector.host = frame
    Collector.orderOf = function() return db.order end
    Collector.onChange = onChange
    Collector.onClick = onClick

    launcher = GMM.Ring.AddDisc(Bar.ANGLE, { icon = Bar.ARROWS.left, iconCrop = true })
    launcher:SetScript("OnClick", Bar.OnLauncherClick)
    launcher:SetScript("OnEnter", Bar.OnLauncherEnter)
    launcher:SetScript("OnLeave", Bar.OnLauncherLeave)

    -- LibDBIcon (embedded by the addons whose buttons we collect): its new
    -- buttons arrive through the callback; ones made before us, from objects.
    local lib = LibStub("LibDBIcon-1.0", true)
    if lib and lib.RegisterCallback then
        lib.RegisterCallback(Bar, "LibDBIcon_IconCreated", Collector.OnIconCreated)
        for _, btn in pairs(lib.objects or {}) do Collector.OnIconCreated(nil, btn) end
    end
    Compartment.Start()
    Collector.Scan()
    onChange()
    -- Addons that make their button late. Opening the drawer rescans as well.
    for _, delay in ipairs({ 0, 2, 10 }) do C_Timer.After(delay, Collector.Scan) end
    return frame
end

Bar._test = { glass = function() return glass end, tick = onUpdate, event = onEvent }
