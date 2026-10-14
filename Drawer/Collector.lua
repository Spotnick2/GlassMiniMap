-- Collector.lua: finds the addon buttons around the minimap and takes them
-- into the bar.
--
-- Technique from HidingBar (sfmict, GPLv3), streamlined: a candidate is a
-- NAMED, unprotected, square child of Minimap/MinimapBackdrop between 16 px
-- and half the minimap, with a click or mouse script on itself or a child;
-- LibDBIcon buttons also arrive through its IconCreated callback. Grabbing
-- one replaces its positioning methods on its own table with no-ops, so the
-- owning addon (LibDBIcon repositions on every drag and login) can't pull it
-- back to the minimap; the bar moves it through API.W, the real methods.
-- Show/Hide from the owner are recorded, not applied: the bar decides.
--
-- Nothing here is secure: protected frames are never grabbed, so all of it
-- may run in combat.
--
-- Glass MiniMap Bar's Collector.lua, plus AddOwn/RemoveOwn: the drawer's own
-- buttons for AddOns-compartment entries (Drawer/Compartment.lua) are entries
-- too, so hiding, ordering and "last used" treat every button alike.

GlassMiniMap = GlassMiniMap or {}
local Collector = {}
GlassMiniMap.Collector = Collector
local API = GlassMiniMap.API
local W = API.W

Collector.entries = {}             -- ordered by display name
Collector.byName = {}
local entryOf = setmetatable({}, { __mode = "k" })   -- btn -> entry

-- Set by the core: where grabbed buttons live, and who hears about changes.
Collector.host = nil
Collector.onChange = function() end          -- the set or a button's visibility changed
Collector.onClick = function(entry, mouse) end

-- Blizzard's own minimap children, Retail- and Classic-era names (from
-- HidingBar's per-client lists). Never grabbed.
Collector.IGNORE = {
    GameTimeFrame = true, TimeManagerClockButton = true, HelpOpenWebTicketButton = true,
    MinimapBackdrop = true, ExpansionLandingPageMinimapButton = true, QueueStatusButton = true,
    AddonCompartmentFrame = true, MinimapZoomIn = true, MinimapZoomOut = true,
    MiniMapWorldMapButton = true, MiniMapMailFrame = true, MiniMapTracking = true,
    MiniMapTrackingButton = true, MiniMapBattlefieldFrame = true, LFGMinimapFrame = true,
    MinimapZoneTextButton = true, MiniMapLFGFrame = true, GarrisonLandingPageMinimapButton = true,
}
Collector.IGNORE_PATTERNS = {
    "^GatherMatePin%d+$", "^TTMinimapButton%d+$", "^HandyNotes.*Pin",
    "^LibDBIcon10_GlassMiniMapBar$",   -- the standalone Glass MiniMap Bar's launcher
    "^LibDBIcon10_HidingBar%d+$",      -- HidingBar's, if both are ever enabled
}

-- "LibDBIcon10_DBM" -> "DBM", "AltStableMinimapButton" -> "AltStable".
function Collector.DisplayName(name)
    local n = name:gsub("^LibDBIcon10_", "")
    n = n:gsub("[_%-]?[Mm]ini[Mm]ap[_%-]?[Bb]utton$", ""):gsub("[_%-]?[Mm]ini[Mm]ap[Bb]tn$", "")
    if n == "" then n = name end
    return n
end

-- The script a frame's click runs through: "OnClick", "OnMouseUp" (also for
-- a frame with only OnMouseDown: the hook goes on the up edge), or nil.
local function clickScriptOf(frame)
    if W.HasScript(frame, "OnClick") and W.GetScript(frame, "OnClick") then return "OnClick" end
    for _, s in ipairs({ "OnMouseUp", "OnMouseDown" }) do
        if W.HasScript(frame, s) and W.GetScript(frame, s) then return "OnMouseUp" end
    end
    return nil
end

-- The frames that actually handle the click: the button itself when it has
-- a click script, else its clickable descendants (3 levels). A named frame
-- whose child Button does the work is a candidate, and its CHILD is what gets
-- hooked and replayed.
local function clickTargets(frame, depth, out)
    out = out or {}
    if clickScriptOf(frame) then
        out[#out + 1] = frame
    elseif depth < 3 then
        for _, child in ipairs({ W.GetChildren(frame) }) do clickTargets(child, depth + 1, out) end
    end
    return out
end

-- Why `frame` (a child of `parent`) is not a candidate, or nil if it is.
function Collector.Reject(frame, parent)
    if entryOf[frame] then return "grabbed" end
    local name = W.GetName(frame)
    if not name then return "no name" end
    if Collector.IGNORE[name] then return "Blizzard" end
    for _, p in ipairs(Collector.IGNORE_PATTERNS) do
        if name:match(p) then return "ignored" end
    end
    if W.IsForbidden(frame) or W.IsProtected(frame) then return "protected" end
    local w, h = W.GetSize(frame)
    if type(w) ~= "number" or type(h) ~= "number" then return "no size" end
    local pw, ph = W.GetSize(parent)
    if math.max(w, h) <= 16 or math.abs(w - h) >= 5 then return "not a button shape" end
    if type(pw) == "number" and (w >= pw * 0.5 or h >= ph * 0.5) then return "too large" end
    if #clickTargets(frame, 0) == 0 then return "not clickable" end
    return nil
end

-- Stop animations that would move or fade the button in the bar (LibDBIcon's
-- showOnMouseover fade); rotations and plain timers are harmless.
local function void() end
local function tameAnimations(btn)
    for _, ag in ipairs({ W.GetAnimationGroups(btn) }) do
        for _, a in ipairs({ ag:GetAnimations() }) do
            local t = a:GetObjectType()
            if a:GetTarget() == btn and t ~= "Animation" and t ~= "Rotation" then
                ag:Stop()
                ag.Play, ag.Restart = void, void
                break
            end
        end
    end
end

local VOIDED = { "SetPoint", "ClearAllPoints", "SetAllPoints", "SetParent", "SetScale", "SetAlpha",
                 "SetFrameStrata", "SetFrameLevel", "SetFixedFrameStrata", "SetFixedFrameLevel",
                 "SetIgnoreParentScale", "StartMoving", "SetSize", "SetWidth", "SetHeight",
                 "SetHitRectInsets", "RegisterForDrag" }

-- The owner's Show/Hide run inside ITS code: never do our work there (a throw
-- would surface in their addon, and re-entrant OnShow scripts would land in
-- the middle of our layout). Record the wish and update once, next frame.
local pending = false
local function flushPending()
    pending = false
    API.Try("change", Collector.onChange)
end
function Collector.Changed()
    if pending then return end
    pending = true
    C_Timer.After(0, flushPending)
end

-- LibDBIcon (Refresh, Unlock) sets its drag scripts again through SetScript:
-- refuse those, as HidingBar does, so a drag in the bar can't reach its
-- OnDragStart (which rewrites the owner's saved minimap position).
local DRAG = { ondragstart = true, ondragstop = true }
local function guardedSetScript(self, script, fn, ...)
    if fn ~= nil and type(script) == "string" and DRAG[script:lower()] then return end
    return W.SetScript(self, script, fn, ...)
end
local function guardedHookScript(self, script, ...)
    if type(script) == "string" and DRAG[script:lower()] then return end
    return W.HookScript(self, script, ...)
end

local OVERRIDDEN = { "Show", "Hide", "SetShown", "IsShown", "SetScript", "HookScript" }

local function installOverrides(btn, entry)
    for _, m in ipairs(VOIDED) do btn[m] = void end
    btn.Show = function() if not entry.wanted then entry.wanted = true; Collector.Changed() end end
    btn.Hide = function() if entry.wanted then entry.wanted = false; Collector.Changed() end end
    btn.SetShown = function(self, show) if show then self:Show() else self:Hide() end end
    btn.IsShown = function() return entry.wanted end
    btn.SetScript = guardedSetScript
    btn.HookScript = guardedHookScript
end

local function removeOverrides(btn)
    for _, m in ipairs(VOIDED) do btn[m] = nil end
    for _, m in ipairs(OVERRIDDEN) do btn[m] = nil end
end

-- Hook every click target; each click remembers which one it was, so the
-- replay repeats that target (session only: after a reload, the first).
local function hookClicks(btn, entry)
    entry.targets = clickTargets(btn, 0)
    if #entry.targets == 0 then entry.targets = { btn } end   -- forced grab of a scriptless frame
    for _, target in ipairs(entry.targets) do
        W.HookScript(target, clickScriptOf(target) or "OnMouseUp", function(_, mouse)
            entry.lastTarget = target
            API.Try("click", Collector.onClick, entry, mouse)
        end)
    end
end

-- The user's order, read through the core so the saved list is the only
-- copy. Ordered buttons come first, in that order; the rest alphabetically.
Collector.orderOf = function() return {} end

local function sortEntries()
    local rank = {}
    for i, name in ipairs(Collector.orderOf()) do rank[name] = i end
    table.sort(Collector.entries, function(a, b)
        local ra, rb = rank[a.name], rank[b.name]
        if ra and rb then return ra < rb end
        if ra or rb then return ra ~= nil end
        local x, y = a.display:lower(), b.display:lower()
        if x ~= y then return x < y end
        return a.name < b.name
    end)
end
Collector.Sort = sortEntries

-- Take `btn` into the bar. Returns the entry, or nil when it can't be taken.
function Collector.Grab(btn)
    if entryOf[btn] then return entryOf[btn] end
    local name = W.GetName(btn)
    if not name or not Collector.host then return nil end
    if W.IsForbidden(btn) or W.IsProtected(btn) then return nil end
    local entry = { btn = btn, name = name, display = Collector.DisplayName(name), wanted = W.IsShown(btn) }
    -- What to put back if any step fails, so a half-grabbed button isn't
    -- left hidden inside the bar where no later scan finds it.
    local parent, points = W.GetParent(btn), {}
    for i = 1, W.GetNumPoints(btn) do points[i] = { W.GetPoint(btn, i) } end
    local ok, err = pcall(function()
        W.StopMovingOrSizing(btn)
        W.SetIgnoreParentScale(btn, false)
        W.SetFixedFrameStrata(btn, false)
        W.SetFixedFrameLevel(btn, false)
        W.SetHitRectInsets(btn, 0, 0, 0, 0)
        -- No mouse buttons: no more dragging it around the minimap ring.
        -- A client that refuses the empty call must not cost us the button.
        pcall(W.RegisterForDrag, btn)
        W.SetScript(btn, "OnDragStart", nil)
        W.SetScript(btn, "OnDragStop", nil)
        W.SetAlpha(btn, 1)
        tameAnimations(btn)
        entry.width = W.GetWidth(btn)
        W.SetParent(btn, Collector.host)
        W.ClearAllPoints(btn)
        W.Hide(btn)                      -- the bar's layout shows what it places
        installOverrides(btn, entry)
        hookClicks(btn, entry)
    end)
    if not ok then
        API.Fail("grab:" .. name, err)
        pcall(function()
            removeOverrides(btn)
            W.SetParent(btn, parent)
            W.ClearAllPoints(btn)
            for _, p in ipairs(points) do W.SetPoint(btn, unpack(p)) end
            if entry.wanted then W.Show(btn) end
        end)
        return nil
    end
    entryOf[btn] = entry
    Collector.byName[name] = entry
    table.insert(Collector.entries, entry)
    sortEntries()
    return entry
end

-- One of OUR buttons (Drawer/Compartment.lua makes one per AddOns-compartment
-- entry): an entry like a grabbed one, without the overrides, since nobody
-- else positions it. `name` is its stable key in the hidden/order lists.
function Collector.AddOwn(btn, name, display)
    if Collector.byName[name] or not Collector.host then return nil end
    local entry = { btn = btn, name = name, display = display, wanted = true, own = true,
                    width = W.GetWidth(btn), targets = { btn } }
    W.SetParent(btn, Collector.host)
    W.ClearAllPoints(btn)
    W.Hide(btn)
    entryOf[btn] = entry
    Collector.byName[name] = entry
    table.insert(Collector.entries, entry)
    sortEntries()
    return entry
end

-- Take one of our own entries out again (its compartment entry went away).
function Collector.RemoveOwn(name)
    local e = Collector.byName[name]
    if not (e and e.own) then return false end
    W.Hide(e.btn)
    Collector.byName[name] = nil
    entryOf[e.btn] = nil
    for i, x in ipairs(Collector.entries) do
        if x == e then table.remove(Collector.entries, i); break end
    end
    return true
end

-- Scan the minimap for candidates. Returns the number newly grabbed and, when
-- `report` (for /gmm scan), the rejects: { { name = , reason = }, ... }.
function Collector.Scan(report)
    local added, rejects = 0, {}
    for _, parentName in ipairs({ "Minimap", "MinimapBackdrop" }) do
        local parent = rawget(_G, parentName)
        if parent then
            for _, child in ipairs({ W.GetChildren(parent) }) do
                local why = Collector.Reject(child, parent)
                if why == nil then
                    if Collector.Grab(child) then added = added + 1 end
                elseif report and why ~= "grabbed" then
                    local name = W.GetName(child)
                    if name then
                        table.insert(rejects, { name = name, reason = why })
                    end
                end
            end
        end
    end
    if added > 0 then Collector.onChange() end
    return added, rejects
end

-- LibDBIcon_IconCreated: (event, button, name). Runs inside the other addon's
-- lib:Register call, so the relayout is deferred like an owner's Show/Hide.
function Collector.OnIconCreated(_, btn)
    if not btn then return end
    local parent = W.GetParent(btn) or rawget(_G, "Minimap")
    if Collector.Reject(btn, parent) == nil and Collector.Grab(btn) then Collector.Changed() end
end

-- THE rule for "in the bar": wanted by its addon, not hidden by the user.
function Collector.InBar(e, hidden)
    return e.wanted and not hidden[e.name]
end

-- Entries the bar shows, in order.
function Collector.Visible(hidden)
    local list = {}
    for _, e in ipairs(Collector.entries) do
        if Collector.InBar(e, hidden) then list[#list + 1] = e end
    end
    return list
end

-- The names Up/Down moves `name` among: the buttons in the bar, plus `name`
-- itself even when its addon hid it. Empty when the user hid `name`.
function Collector.Movable(hidden, name)
    local list = {}
    if hidden[name] then return list end
    for _, e in ipairs(Collector.entries) do
        if Collector.InBar(e, hidden) or e.name == name then list[#list + 1] = e.name end
    end
    return list
end

-- Click a grabbed button again, with the mouse button used last time.
function Collector.Replay(name, mouse)
    local e = Collector.byName[name]
    if not e then return false end
    mouse = mouse or "LeftButton"
    local target = e.lastTarget or (e.targets and e.targets[1]) or e.btn
    if clickScriptOf(target) == "OnClick" and target.Click then
        return API.Try("replay:" .. name, function() target:Click(mouse); return true end) == true
    end
    -- Mouse scripts only; true only if one actually ran.
    return API.Try("replay:" .. name, function()
        local down, up = W.GetScript(target, "OnMouseDown"), W.GetScript(target, "OnMouseUp")
        if down then down(target, mouse) end
        if up then up(target, mouse) end
        return (down or up) ~= nil
    end) == true
end

Collector._test = { entryOf = entryOf }
