-- The pieces around the map: the theme, the zone pill, the coords pill and
-- zoom, the day/night disc, the north tab.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GMM = loadAddon()
local ring = GMM.Ring.Glass()

-- Theme: clear is the material as built; smoked AltStable's body; class the
-- class colour shaded by 0.6, at the surface's own alpha. Live, everywhere.
local built = ring.tint.glassColor
eq(ring.tint._color[1], built[1], "clear: the ring as LibGlass built it")
GMM.Settings.SetTheme("smoked")
eq(ring.tint._color[4], 0.62, "smoked: the darker body")
local orbTint
for _, s in ipairs(GMM.Theme._test.surfaces) do if s.kind == "orb" and s.g.tint ~= nil then orbTint = s.g.tint end end
eq(orbTint._color[4], 0.62, "smoked reaches the north tab too")
GMM.Settings.SetTheme("class")
near(ring.tint._color[1], 0.25 * 0.6, "class: the class colour, shaded (r)")
near(ring.tint._color[3], 0.92 * 0.6, "class: (b)")
eq(ring.tint._color[4], built[4], "class: the surface's own alpha")
check(not GMM.Settings.SetTheme("neon"), "an unknown theme is refused")
eq(GlassMiniMapDB.theme, "class", "...and the setting kept")
-- The class colour unreadable at login: clear now, painted at PLAYER_ENTERING_WORLD.
local get = C_ClassColor.GetClassColor
C_ClassColor.GetClassColor = function() return nil end
check(not GMM.Theme.Refresh(), "an unreadable class colour is pending")
eq(ring.tint._color[1], built[1], "...the glass clear meanwhile")
C_ClassColor.GetClassColor = get
WoW.fire("PLAYER_ENTERING_WORLD", false, false)
near(ring.tint._color[1], 0.25 * 0.6, "painted once it can be read")
GMM.Settings.SetTheme("clear")

-- Zone pill: the minimap's zone name, Blizzard's PvP colours, world map on click.
local zt = GMM.Header._test.zoneText()
eq(zt._text, "Thendal Village", "the zone name")
eq(zt._textColor[1], 0.41, "sanctuary blue (the mockup's)")
WoW.zone, WoW.pvp = "Ashenvale", "contested"
WoW.fire("ZONE_CHANGED_NEW_AREA")
eq(zt._text, "Ashenvale", "follows the zone")
eq(zt._textColor[2], 0.7, "contested orange")
WoW.pvp = nil
WoW.fire("ZONE_CHANGED")
eq(zt._textColor[1], 1.0, "no PvP info: Blizzard's gold")
GMM.Header._test.zoneButton():Click("LeftButton")
eq(WoW.worldMapToggled, 1, "a click opens the world map")
-- The tooltip: Blizzard's zone lines, written by us (its Minimap_SetTooltip
-- only writes for its own button: Codex, PR #6).
local zb = GMM.Header._test.zoneButton()
WoW.zoneName, WoW.subzone, WoW.pvp = "Elwynn Forest", "Goldshire", "sanctuary"
zb._scripts.OnEnter(zb)
eq(GameTooltip._lines[1], "Elwynn Forest", "the zone")
eq(GameTooltip._lines[2], "Goldshire", "the subzone")
eq(GameTooltip._colors[2][1], 0.41, "...in the zone's PvP colour")
eq(GameTooltip._lines[3], "(Sanctuary)", "the territory line")
eq(GameTooltip._lines[4], "Click: world map", "and the click hint")
WoW.subzone, WoW.pvp = "Elwynn Forest", "contested"
zb._scripts.OnEnter(zb)
eq(GameTooltip._lines[2], "(Contested Territory)", "a subzone equal to the zone is left out")
WoW.pvp = "friendly"
zb._scripts.OnEnter(zb)
eq(GameTooltip._lines[2], "Click: world map", "friendly without a faction: the zone only")
WoW.zoneName, WoW.subzone, WoW.pvp = nil, nil, nil

-- Calendar: today's page, invites, Blizzard's click handler.
local cal = GMM.Header._test.calendar()
eq(cal.icon._atlas, "ui-hud-calendar-13-up", "today's page")
WoW.invites, WoW.monthDay = 2, 14
WoW.fire("CALENDAR_UPDATE_PENDING_INVITES")
eq(GMM.Header._test.invites()._text, "2", "pending invites shown")
GameTimeFrame_SetDate()
eq(cal.icon._atlas, "ui-hud-calendar-14-up", "re-dated with Blizzard's own button")
cal:Click("LeftButton")
eq(WoW.calendarClicked, GameTimeFrame, "the click goes through Blizzard's handler")

-- Coords: tenths by default, a dash with no position, off hides the text.
local F = GMM.Footer
local coords = F._test.coords()
eq(coords._text, "43.2, 24.8", "the mockup's coordinates")
GMM.Settings.Set("coordsTenths", false)
F._test.tick(nil, 1)
eq(coords._text, "43, 25", "whole numbers when asked")
WoW.position = nil
F._test.tick(nil, 1)
eq(coords._text, "\226\128\148", "a dash where the map has no position")
GMM.Settings.Set("coords", false)
eq(coords._shown, false, "coords off: no text")
check(F.Pill()._width < F.WIDTH, "...and a pill just for the zoom buttons")
eq(F.Pill()._scripts.OnUpdate, nil, "...and no updates")
GMM.Settings.Set("coords", true)
GMM.Settings.Set("coordsTenths", true)

-- Zoom: one step within the client's levels; the buttons follow.
local zin, zout = F._test.zoomIn(), F._test.zoomOut()
eq(zout._enabled, false, "fully out: minus disabled")
zin:Click("LeftButton")
eq(Minimap._zoom, 1, "plus zooms in")
eq(zout._enabled, true, "...minus enabled")
Minimap._zoom = 5
WoW.fire("MINIMAP_UPDATE_ZOOM")
eq(zin._enabled, false, "fully in (the wheel): plus disabled")
check(not F.Zoom(1), "...and does nothing")
zout:Click("LeftButton")
eq(Minimap._zoom, 4, "minus zooms out")

-- The day/night disc: sun by day, moon by night, from Forever's event.
local sun = GMM.Ring.Sun()
eq(sun.icon._file, GMM.MEDIA .. "sun", "day: the sun")
WoW.fire("DIEL_CYCLE_CHANGED", false)
eq(sun.icon._file, GMM.MEDIA .. "moon", "night: the moon")
eq(sun.icon._vertex[3], 1, "...pale blue")
sun:Click("LeftButton")
eq(WoW.timeManager, 1, "click: the clock and alarm")
GMM.Settings.Set("sun", false)
eq(sun._shown, false, "the disc can be turned off")
GMM.Settings.Set("sun", true)

-- The north tab: at 12 o'clock, orbiting with rotateMinimap.
local notch = GMM.Ring._test.notch()
local p = notch._points[1]
near(p[4], 0, "north up: centred")
check(p[5] > 0, "...above the map")
eq(notch._scripts.OnUpdate, nil, "no per-frame work while the map is fixed")
WoW.cvars.rotateMinimap = true
WoW.fire("CVAR_UPDATE", "rotateMinimap", "1")
check(notch._scripts.OnUpdate ~= nil, "rotating map: the tab follows the facing")
WoW.facing = math.pi / 2            -- facing west: north is to the right
WoW.tick(0.02)
p = notch._points[1]
check(p[4] > 0, "facing west: north on the right")
near(p[5], 0, "...level with the centre")
near(notch.parts.rim._rotation, -math.pi / 2, "...the roof turned to point outward")
WoW.cvars.rotateMinimap = false
WoW.fire("CVAR_UPDATE", "rotateMinimap", "0")
near(notch._points[1][4], 0, "fixed again: back at the top")

eq(next(GMM.failures), nil, "no failures")
done("test_ui")
