-- The scan API (#56): another addon borrows Minimap for a few frames (NodeRadar's
-- scan mode moves it under the cursor, shrunk, at alpha 0). Nothing of ours is
-- anchored to the map, nothing reads its size after the build, and the
-- contract: version 1, a boolean ScanBegin, an idempotent ScanEnd, the 1 s
-- self-release per owner, the auto zoom-out paused meanwhile.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GMM = loadAddon({ gmb = true, db = { runicMode = true, zoom = "ring", indicators = "ring" } })
local host, container = GMM.Ring.Host(), GMM.Ring.Container()

local function point(frame, name)
    for _, p in ipairs(frame._points) do if p[1] == name then return p end end
end

--------------------------------------------------------------------------------
-- Nothing of ours follows the map
--------------------------------------------------------------------------------
local hp = point(host, "CENTER")
check(hp and hp[2] == container and hp[3] == "CENTER" and hp[4] == 0 and hp[5] == 0,
    "the ring on the container's centre, where Blizzard puts the map")

-- Does an anchor chain reach Minimap? Through relative frames, and a point
-- with no relative frame is on the parent. Minimap's own children and
-- Blizzard's queue eye (anchored to the map by Blizzard; our disc follows the
-- eye on purpose) are not ours to judge.
local function within(f, root)
    while f do
        if f == root then return true end
        f = f._parent
    end
    return false
end
local function reachesMinimap(f, seen)
    if f == Minimap then return true end
    if f == QueueStatusButton or seen[f] then return false end
    seen[f] = true
    for _, p in ipairs(f._points or {}) do
        local rel = p[2]
        if type(rel) ~= "table" then rel = f._parent end
        if rel and reachesMinimap(rel, seen) then return true end
    end
    return false
end
local mine = 0
for _, f in ipairs(WoW.frames) do
    if within(f, container) and not within(f, Minimap) then
        mine = mine + 1
        check(not reachesMinimap(f, {}), "nothing under the container is anchored to the map: "
            .. tostring(f._type) .. " " .. tostring(f._width) .. "x" .. tostring(f._height))
    end
end
check(mine >= 10, "...the ring, the tab, the pills and the discs were all looked at (" .. mine .. ")")
-- The walk has teeth: a frame on the map is caught, one on a frame on the map too.
local probe = CreateFrame("Frame", nil, container)
probe:SetPoint("CENTER", Minimap, "CENTER")
local chained = CreateFrame("Frame", nil, container)
chained:SetPoint("TOP", probe, "BOTTOM")
check(reachesMinimap(probe, {}) and reachesMinimap(chained, {}), "(the walk catches a frame on the map, directly or not)")
probe:ClearAllPoints(); chained:ClearAllPoints()

--------------------------------------------------------------------------------
-- A shrunken map: the radius and every placement from it unchanged
--------------------------------------------------------------------------------
local r = GMM.Ring.Radius()
near(r, GMM.Ring.MAP_SIZE / 2 + GMM.Ring.RING_WIDTH / 2, 1e-9, "the ring's middle, from the host")
local notch = GMM.Ring._test.notch()
WoW.cvars.rotateMinimap = true
WoW.fire("CVAR_UPDATE", "rotateMinimap", "1")
WoW.facing = 0.5
WoW.tick(0.02)
local np = notch._points[1]
local notchR = math.sqrt(np[4] ^ 2 + np[5] ^ 2)
local zoomIn = GMM.Footer.ZoomButtons()
local zp = point(zoomIn, "CENTER")
local zoomR = math.sqrt(zp[4] ^ 2 + zp[5] ^ 2)

Minimap._width, Minimap._height = 24, 24            -- borrowed (NodeRadar measured 24 px)
near(GMM.Ring.Radius(), r, 1e-9, "the map at 24 px: the radius unchanged")
WoW.facing = 1.5                                     -- the player turns mid-scan
WoW.tick(0.02)
np = notch._points[1]
near(math.sqrt(np[4] ^ 2 + np[5] ^ 2), notchR, 1e-9, "...the north tab still on the ring")
GMM.Footer.Layout()                                  -- a layout mid-scan (a CVar, the instance size)
zp = point(zoomIn, "CENTER")
near(math.sqrt(zp[4] ^ 2 + zp[5] ^ 2), zoomR, 1e-9, "...the ring's zoom discs too")
local late = GMM.Ring.AddDisc(300)                   -- a disc built late (the drawer's can be)
local lp = point(late, "CENTER")
near(math.sqrt(lp[4] ^ 2 + lp[5] ^ 2), r + GMM.Ring.RING_WIDTH * 0.3, 1e-9, "...a late disc on the ring")
Minimap._width, Minimap._height = 198, 198
WoW.cvars.rotateMinimap = false
WoW.fire("CVAR_UPDATE", "rotateMinimap", "0")

--------------------------------------------------------------------------------
-- The contract
--------------------------------------------------------------------------------
eq(GlassMiniMap.PUBLIC_API_VERSION, 1, "public API version 1")
local Begin, End, Scan = GlassMiniMap.ScanBegin, GlassMiniMap.ScanEnd, GMM.Scan
for _, bad in ipairs({ false, "", 5, {} }) do
    eq(Begin(bad), false, "ScanBegin refuses the owner " .. tostring(bad))
end
eq(Begin(), false, "...and none")
eq(Scan.Active(), false, "...nothing held")
for _, bad in ipairs({ false, "", 5, {} }) do End(bad) end
End()
End("nobody")
eq(Scan.Active(), false, "ScanEnd: a bad owner, none, or one never begun, does nothing")

eq(Begin("NodeRadar"), true, "ScanBegin: acquired")
check(Scan.Active(), "...a scan under way")
End("NodeRadar")
eq(Scan.Active(), false, "ScanEnd: released")
End("NodeRadar")
eq(Scan.Active(), false, "...a second ScanEnd does nothing")
eq(Scan._test.count(), 0, "...and counts nothing")

-- In combat or Edit Mode too: no transient refusal (the borrower gates those).
WoW.combat = true
eq(Begin("NodeRadar"), true, "in combat: still acquired")
End("NodeRadar")
WoW.combat = false

-- The self-release: 1 s after the last ScanBegin with no ScanEnd.
WoW.timers = {}
Begin("NodeRadar")
WoW.flushTimers(GMM.Scan.TIMEOUT)
eq(Scan.Active(), false, "no ScanEnd within 1 s: released by itself")
check(GMM.failures["scan:NodeRadar"] ~= nil, "...and recorded (/gmm failures)")
End("NodeRadar")
eq(Scan._test.count(), 0, "...a late ScanEnd does nothing")
GMM.failures["scan:NodeRadar"] = nil

-- A re-Begin restarts the timeout: the first timer is spent on nothing.
WoW.timers = {}
Begin("NodeRadar")
local first = table.remove(WoW.timers, 1)
eq(Begin("NodeRadar"), true, "a second ScanBegin from an active owner: acquired")
eq(Scan._test.count(), 1, "...still one owner")
first.fn()
check(Scan.Active(), "...the first ScanBegin's timeout no longer releases it")
eq(GMM.failures["scan:NodeRadar"], nil, "...nor records anything")
End("NodeRadar")
eq(Scan.Active(), false, "...one ScanEnd clears it")
WoW.flushTimers(GMM.Scan.TIMEOUT)
eq(GMM.failures["scan:NodeRadar"], nil, "an ended scan's timer does nothing")

-- An End then a Begin within the second: the old timer must not end the new one.
WoW.timers = {}
Begin("NodeRadar")
local old = table.remove(WoW.timers, 1)
End("NodeRadar")
Begin("NodeRadar")
old.fn()
check(Scan.Active(), "Begin, End, Begin: the first timer leaves the new scan alone")
End("NodeRadar")

-- Owners are independent.
WoW.timers = {}
Begin("NodeRadar"); Begin("Other")
End("NodeRadar")
check(Scan.Active(), "two owners: one ended, the other still holds")
End("Other")
eq(Scan.Active(), false, "...both ended")
WoW.timers = {}

--------------------------------------------------------------------------------
-- The auto zoom-out pauses during a scan
--------------------------------------------------------------------------------
local function wait(seconds)
    for _ = 1, math.floor(seconds / 0.05 + 0.5) do
        WoW.now = WoW.now + 0.05
        WoW.tick(0.05)
    end
end
WoW.cursor, WoW.mouseOver = { -1000, -1000 }, {}
Minimap:SetZoom(3); WoW.fire("MINIMAP_UPDATE_ZOOM")
wait(4)
local left = GMM.Footer.Countdown()
Begin("NodeRadar")
wait(3)
eq(Minimap:GetZoom(), 3, "a scan under way: no zoom-out, though the delay passed")
near(GMM.Footer.Countdown(), left, 1e-9, "...the countdown paused, not restarted")
End("NodeRadar")
wait(left + 0.1)
eq(Minimap:GetZoom(), 0, "...ended: it zooms out after what was left")

-- An expired lease, then a fresh ScanBegin: a new scan with its own timeout.
WoW.timers = {}
Begin("NodeRadar")
table.remove(WoW.timers, 1).fn()
eq(Scan.Active(), false, "expired")
GMM.failures["scan:NodeRadar"] = nil
eq(Begin("NodeRadar"), true, "...a fresh ScanBegin: acquired")
check(Scan.Active(), "...held")
table.remove(WoW.timers, 1).fn()
eq(Scan.Active(), false, "...and its own timeout releases it")
GMM.failures["scan:NodeRadar"] = nil
WoW.timers = {}

--------------------------------------------------------------------------------
-- The glass behind Blizzard's LFG eye: the one piece that follows the map
-- (Blizzard anchors the eye to it), hidden while a scan is under way
--------------------------------------------------------------------------------
local qdisc = GMM.Queue.Disc()
QueueStatusButton:Show()
eq(qdisc._shown, true, "queued: the eye's glass shows")
Begin("NodeRadar")
eq(qdisc._shown, false, "a scan begins: the eye's glass hides")
End("NodeRadar")
eq(qdisc._shown, true, "...ended: back")
QueueStatusButton:Hide()
WoW.timers = {}
Begin("NodeRadar")
QueueStatusButton:Show()                             -- a queue pop mid-scan
eq(qdisc._shown, false, "the eye shown mid-scan: our glass stays hidden")
table.remove(WoW.timers, 1).fn()                     -- never ended: the timeout
eq(qdisc._shown, true, "...released by the timeout: back with the eye")
GMM.failures["scan:NodeRadar"] = nil
QueueStatusButton:Hide()
eq(qdisc._shown, false, "...hidden with the eye")
WoW.timers = {}

--------------------------------------------------------------------------------
-- Before our build: acquired, and a map borrowed while we build doesn't size
-- the ring (the host keeps its size for the session)
--------------------------------------------------------------------------------
GMM = loadAddon({ before = function()
    eq(GlassMiniMap.ScanBegin("NodeRadar"), true, "before our build: acquired")
    Minimap._width, Minimap._height = 24, 24
end })
Minimap._width, Minimap._height = 198, 198
GlassMiniMap.ScanEnd("NodeRadar")
eq(GMM.Ring.Host()._width, GMM.Ring.MAP_SIZE + 2 * GMM.Ring.RING_WIDTH,
    "built while the map was borrowed: the ring at the map's resting size")
near(GMM.Ring.Radius(), GMM.Ring.MAP_SIZE / 2 + GMM.Ring.RING_WIDTH / 2, 1e-9, "...its radius too")

done("test_scan")
