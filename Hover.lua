-- Hover.lua: is the mouse over the minimap (docs/PLAN-zoom-ping-fader.md §0).
-- The fader (#15), the auto zoom-out (#13) and the ring zoom discs (#42) all
-- ask it. One throttled OnUpdate, never a hook on Blizzard's frames.
--
-- Over: the cursor inside the ring's circle (the host is a square, and its
-- corners are off the map: Codex's review), or over one of our pieces while
-- it is visible (a zoom disc faded to alpha 0 still is: hovering its spot
-- brings it back).
-- Held: nothing may fade or zoom out while our tracking menu is open or Edit
-- Mode is active. Glass MiniMap Bar's drawer has no "is open" in its public
-- API, so an open bar holds nothing.

GlassMiniMap = GlassMiniMap or {}
local GMM = GlassMiniMap
local API = GMM.API
local Hover = {}
GMM.Hover = Hover

Hover.INTERVAL = 0.05

local frame = CreateFrame("Frame")
local listeners = {}
local over, held, idle, since = false, false, 0, 0

-- Our pieces, read each time: some are built late (the drawer's disc waits
-- for Glass MiniMap Bar) and any may be absent.
local function zoomIn() return (GMM.Footer.ZoomButtons()) end
local function zoomOut() return select(2, GMM.Footer.ZoomButtons()) end
local PIECES = {
    GMM.Header.Pill, GMM.Footer.Pill, zoomIn, zoomOut, GMM.Ring.Notch, GMM.Ring.Sun,
    GMM.Drawer.Disc, GMM.Mail.Disc, GMM.Difficulty.Disc, GMM.Queue.Disc,
}

-- fn(dt) after each measure, dt the seconds since the last one.
function Hover.OnTick(fn)
    listeners[#listeners + 1] = fn
end

local function overRing()
    local host = GMM.Ring.Host()
    if not (host and host:IsVisible()) then return false end
    local ok, x, y = pcall(GetCursorPosition)
    x, y = ok and API.Plain(x), ok and API.Plain(y)
    local cx, cy = host:GetCenter()
    local s, w = host:GetEffectiveScale(), host:GetWidth()
    if type(x) ~= "number" or type(y) ~= "number" or type(cx) ~= "number" or type(cy) ~= "number"
        or type(s) ~= "number" or s <= 0 or type(w) ~= "number" then
        return false
    end
    local dx, dy, r = x / s - cx, y / s - cy, w / 2
    return dx * dx + dy * dy <= r * r
end

local function editMode()
    local em = rawget(_G, "EditModeManagerFrame")
    if type(em) ~= "table" or type(em.IsEditModeActive) ~= "function" then return false end
    local ok, on = pcall(em.IsEditModeActive, em)
    return ok and API.Plain(on) == true
end

local function measure()
    if overRing() then return true end
    for _, get in ipairs(PIECES) do
        local f = get()
        if f and f:IsVisible() and f:IsMouseOver() then return true end
    end
    return false
end

local function tick(dt)
    over = measure()
    held = GMM.Tracking.IsOpen() or editMode()
    idle = (over or held) and 0 or idle + dt
    for _, fn in ipairs(listeners) do API.Try("hover", fn, dt) end
end

frame:SetScript("OnUpdate", function(_, elapsed)
    since = since + elapsed
    if since < Hover.INTERVAL then return end
    local dt = since
    since = 0
    tick(dt)
end)

function Hover.Over() return over end
function Hover.Held() return held end
-- Seconds since the mouse left (0 while over or held).
function Hover.Idle() return idle end

Hover._test = { tick = tick, frame = frame }
