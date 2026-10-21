-- The coords pill and its zoom buttons (#42, the owner's mockup on 70450):
-- the pill hangs as far under the ring as the zone pill sits over it, clear
-- of the ring and over the runic vapor; the zoom buttons at its ends (the
-- default, the text centered under the map) or, with zoom = "ring", two discs
-- on the ring at the bottom right, clear of the mail disc. Live switching,
-- saved values, the options radio.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local DOT = " \194\183 "

local function point(frame, name)
    for _, p in ipairs(frame._points) do if p[1] == name then return p end end
end

-- The angle (degrees clockwise from the top) of a disc anchored on the ring.
local function angleOf(b, host)
    local p = point(b, "CENTER")
    if not (p and p[2] == host) then return nil end
    return (math.deg(math.atan2(p[4], p[5])) + 360) % 360
end

local GMM = loadAddon({ db = { runicMode = true } })
local F, host, pill = GMM.Footer._test, GMM.Ring.Host(), GMM.Footer.Pill()
local zoomIn, zoomOut, coords, hit = F.zoomIn(), F.zoomOut(), F.coords(), F.hit()

--------------------------------------------------------------------------------
-- The pill: clear of the ring, over the vapor
--------------------------------------------------------------------------------
eq(GMM.Settings.Zoom(), "pill", "the zoom buttons in the pill by default")
eq(rawget(GlassMiniMapDB, "zoom"), nil, "...not saved")
local top = point(pill, "TOP")
check(top and top[2] == host and top[3] == "BOTTOM", "the pill hangs from the ring's bottom")
eq(top[5], -GMM.Footer.GAP, "...clear of it by the gap")
local zoneBottom = point(GMM.Header.Pill(), "BOTTOM")
eq(zoneBottom and zoneBottom[5], GMM.Footer.GAP, "...the zone pill's gap over the ring")
local runes, fog, bloom = GMM.Ring._test.runes(), GMM.Ring._test.fog(), GMM.Ring._test.bloom()
check(runes and fog and bloom, "runic mode: the runes, vapor and bloom built")
local over = math.max(runes._level, fog._level, bloom._level)
check(pill._level > over, "the pill over the runes, vapor and bloom")
check(zoomIn._level > over and zoomOut._level > over and hit._level > over, "...its buttons and hit area too")
eq(coords._parent, pill, "the text on the pill")

--------------------------------------------------------------------------------
-- zoom = "pill": - at the left end, + at the right, the text centered
--------------------------------------------------------------------------------
local function inPill(msg)
    eq(zoomOut._parent, pill, msg .. ": - in the pill")
    eq(zoomIn._parent, pill, msg .. ": + in the pill")
    local l, r = point(zoomOut, "LEFT"), point(zoomIn, "RIGHT")
    check(l and l[2] == pill and l[4] == 4, msg .. ": - at the left end")
    check(r and r[2] == pill and r[4] == -4, msg .. ": + at the right end")
    local cl, cr = point(coords, "LEFT"), point(coords, "RIGHT")
    check(cl and cl[2] == zoomOut and cl[3] == "RIGHT", msg .. ": the text from -")
    check(cr and cr[2] == zoomIn and cr[3] == "LEFT", msg .. ": ...to +")
    eq(cl[4], -cr[4], msg .. ": ...centered between them")
    local hl, hr = point(hit, "TOPLEFT"), point(hit, "BOTTOMRIGHT")
    check(hl and hl[2] == zoomOut and hr and hr[2] == zoomIn, msg .. ": the hit area over the text only")
    eq(zoomIn._level, GMM.Glass.ContentLevel(pill), msg .. ": the pill's content level")
    eq(pill._width, GMM.Footer.WIDTH, msg .. ": full width")
end
inPill("default")

WoW.cvars.minimapShowPlayerCoords = false
WoW.fire("CVAR_UPDATE", "minimapShowPlayerCoords")
check(pill._width < GMM.Footer.WIDTH and pill:IsShown(), "coordinates off: a narrow pill with the buttons")
WoW.cvars.minimapShowPlayerCoords = true
WoW.fire("CVAR_UPDATE", "minimapShowPlayerCoords")

--------------------------------------------------------------------------------
-- zoom = "ring": two discs at the bottom right, the text alone in the pill
--------------------------------------------------------------------------------
check(GMM.Settings.SetZoom("ring"), "the ring")
eq(rawget(GlassMiniMapDB, "zoom"), "ring", "...saved")
local function onRing(msg, angles)
    eq(zoomIn._parent, GMM.Ring.Container(), msg .. ": + on the ring")
    eq(zoomOut._parent, GMM.Ring.Container(), msg .. ": - on the ring")
    eq(zoomIn._level, GMM.Ring.AboveMap(6), msg .. ": at the discs' level")
    near(angleOf(zoomIn, host), angles[1], 0.01, msg .. ": + at " .. angles[1])
    near(angleOf(zoomOut, host), angles[2], 0.01, msg .. ": - at " .. angles[2])
    local p = point(zoomIn, "CENTER")
    near(math.sqrt(p[4] ^ 2 + p[5] ^ 2), GMM.Ring.Radius() + GMM.Ring.RING_WIDTH * 0.3, 0.01,
        msg .. ": on the ring, where its discs are")
    local cl, cr = point(coords, "LEFT"), point(coords, "RIGHT")
    check(cl and cl[2] == pill and cr and cr[2] == pill, msg .. ": the text across the pill")
    eq(cl[4], -cr[4], msg .. ": ...centered")
    local hl = point(hit, "TOPLEFT")
    check(hl and hl[2] == pill, msg .. ": the hit area over the text")
    eq(pill._width, GMM.Footer.TEXT_WIDTH, msg .. ": a narrower pill")
end
onRing("ring", GMM.Footer.ZOOM_ANGLES.pills)
local before = Minimap:GetZoom()
zoomIn:Click("LeftButton")
eq(Minimap:GetZoom(), before + 1, "...+ still zooms in")

-- The indicators on the ring too: the zoom discs move clear of the mail disc.
GMM.Settings.SetIndicators("ring")
onRing("with the indicators on the ring", GMM.Footer.ZOOM_ANGLES.ring)
for _, a in ipairs(GMM.Footer.ZOOM_ANGLES.ring) do
    check(math.abs(a - GMM.Mail.ANGLE) >= 15, "...clear of the mail disc (" .. a .. ")")
end
GMM.Settings.SetIndicators("pills")
onRing("indicators back in the pills", GMM.Footer.ZOOM_ANGLES.pills)

-- Nothing for the pill to hold: no pill, the discs stay.
WoW.cvars.minimapShowPlayerCoords = false
WoW.fire("CVAR_UPDATE", "minimapShowPlayerCoords")
eq(pill:IsShown(), false, "coordinates off, zoom on the ring: no pill")
check(zoomIn:IsVisible() and zoomOut:IsVisible(), "...the zoom discs still shown")
WoW.instance = { type = "party", maxPlayers = 5 }
MinimapCluster.InstanceDifficulty:Update()
eq(pill:IsShown(), true, "...a dungeon: the pill back for its size")
eq(coords._text, "Dungeon" .. DOT .. "5", "...with the size")
WoW.instance = { type = "none", maxPlayers = 0 }
MinimapCluster.InstanceDifficulty:Update()
eq(pill:IsShown(), false, "...out again: no pill")
WoW.cvars.minimapShowPlayerCoords = true
WoW.fire("CVAR_UPDATE", "minimapShowPlayerCoords")
eq(pill:IsShown(), true, "coordinates on: the pill back")

check(not GMM.Settings.SetZoom("left"), "an unknown placement is refused")
eq(GMM.Settings.Zoom(), "ring", "...and nothing changes")

--------------------------------------------------------------------------------
-- Back in the pill; the options radio
--------------------------------------------------------------------------------
check(GMM.Settings.SetZoom("pill"), "back in the pill")
eq(rawget(GlassMiniMapDB, "zoom"), nil, "...the default, not saved")
inPill("back")

GMM.Options._test.panel:Show()
local radios = GMM.Options._test.zoomRadios
local function checked()
    local on = {}
    for _, rb in ipairs(radios) do if rb:GetChecked() then on[#on + 1] = rb.value end end
    return table.concat(on, ",")
end
eq(checked(), "pill", "options: the pill checked")
radios[2]:Click()
eq(GMM.Settings.Zoom(), "ring", "the ring radio: the ring")
eq(checked(), "ring", "...only it checked")
radios[1]:Click()
eq(checked(), "pill", "back: only the pill")
inPill("from the options")

--------------------------------------------------------------------------------
-- Saved values
--------------------------------------------------------------------------------
GMM = loadAddon({ db = { zoom = "left" } })
eq(rawget(GlassMiniMapDB, "zoom"), nil, "an unknown saved placement is dropped")
eq(GMM.Settings.Zoom(), "pill", "...the default")
GMM = loadAddon({ db = { zoom = "ring" } })
eq(GMM.Footer._test.zoomIn()._parent, GMM.Ring.Container(), "the ring kept: on the ring at login")
eq(GMM.Footer.Pill()._width, GMM.Footer.TEXT_WIDTH, "...the pill narrow")

eq(next(GMM.failures), nil, "no failures")
done("test_zoom")
