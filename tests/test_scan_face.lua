-- The scan face (#59): a radar over the map's spot while another addon borrows
-- the map. Shown on the first ScanBegin, held then faded after the last
-- release, cancelled by a hidden map, and advertised by GlassMiniMap.ScanStandIn.
-- Only when the player chose NodeRadar's radar look (its RadarLook), latched
-- for each borrow; otherwise NodeRadar draws the real ground, on a map we
-- declare round (GetMinimapShape).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- NodeRadar with the radar look chosen (radar) or not; nil: not loaded.
local radar = true
local function fakeNodeRadar(scanFace)
    rawset(_G, "NodeRadar", { ScanFace = scanFace or { RadarLook = function() return radar end } })
end

local GMM = loadAddon({ gmb = true })
fakeNodeRadar()
local Face, Scan = GMM.ScanFace, GMM.Scan
local face = Face._test.face()
local body, lines, sweep, spin = Face._test.parts()
local function Begin(o) return GlassMiniMap.ScanBegin(o or "NodeRadar") end
local function End(o) GlassMiniMap.ScanEnd(o or "NodeRadar") end
-- One rendered frame of `dt` seconds.
local function frames(seconds, dt)
    dt = dt or 0.05
    for _ = 1, math.floor(seconds / dt + 0.5) do
        WoW.now = WoW.now + dt
        WoW.tick(dt)
    end
end

--------------------------------------------------------------------------------
-- Where it is
--------------------------------------------------------------------------------
local host, container = GMM.Ring.Host(), GMM.Ring.Container()
eq(face._parent, container, "a child of the container, not of the map")
local p = face._points[1]
check(#face._points == 1 and p[1] == "CENTER" and p[2] == host and p[3] == "CENTER" and p[4] == 0 and p[5] == 0,
    "centred on the ring's host")
eq(face._width, GMM.Ring.MAP_SIZE, "the map's resting size")
eq(face._level, Minimap:GetFrameLevel() + 1, "one level above the map")
check(face._level < GMM.Ring._test.notch()._level, "...under the north tab")
eq(face:IsMouseEnabled(), false, "mouse off")
eq(face:IsShown(), false, "hidden at rest")
eq(sweep._blendMode, "ADD", "the sweep is light")
local turn = spin:GetAnimations()
eq(turn._degrees, -360, "the sweep turns clockwise")
eq(turn._duration, Face.TURN, "...one turn per TURN seconds")
eq(spin._looping, "REPEAT", "...for as long as it shows")
check(lines._file:find("scan_face$") and sweep._file:find("scan_sweep$"), "the generated art")
eq(#body._masks, 1, "the body masked round")

--------------------------------------------------------------------------------
-- The public answer
--------------------------------------------------------------------------------
eq(GlassMiniMap.ScanStandIn(), true, "built, the radar chosen: Glass MiniMap draws its own stand-in")

--------------------------------------------------------------------------------
-- A scan: on at once, the hold, the fade
--------------------------------------------------------------------------------
WoW.timers = {}
Begin()
eq(face:IsShown(), true, "the first ScanBegin shows it, in the same call")
eq(face:GetAlpha(), 1, "...at full")
eq(spin:IsPlaying(), true, "...the sweep turning")
Begin("Other")
eq(face:GetAlpha(), 1, "a second owner: no change")
End("Other")
eq(face:GetScript("OnUpdate"), nil, "one owner still scanning: no hold yet")
End()
eq(face:IsShown(), true, "the last ScanEnd: still shown")
frames(0.35)
eq(face:GetAlpha(), 1, "...at full through the hold")
frames(0.15)
check(face:GetAlpha() < 1 and face:GetAlpha() > 0, "...then fading (" .. face:GetAlpha() .. ")")
frames(0.15)
eq(face:IsShown(), false, "...gone by HOLD + FADE")
eq(face:GetAlpha(), 1, "...its alpha back to 1 for next time")
eq(face:GetScript("OnUpdate"), nil, "...no OnUpdate left")
eq(spin:IsPlaying(), false, "...the sweep stopped")

-- A Begin during the hold, and during the fade, brings it back to full.
WoW.timers = {}
Begin(); End()
frames(0.2)
Begin()
eq(face:GetScript("OnUpdate"), nil, "a Begin mid-hold: the hold cancelled")
frames(1)
eq(face:IsShown(), true, "...still shown while that scan runs")
End()
frames(0.5)
check(face:GetAlpha() < 1, "fading")
Begin()
eq(face:GetAlpha(), 1, "a Begin mid-fade: back to full")
eq(face:GetScript("OnUpdate"), nil, "...the fade cancelled")
End()
frames(0.7)
eq(face:IsShown(), false, "...ended: gone after its own hold and fade")

-- A timeout release holds and fades too.
WoW.timers = {}
Begin()
table.remove(WoW.timers, 1).fn()
GMM.failures["scan:NodeRadar"] = nil
eq(Scan.Active(), false, "released by the timeout")
eq(face:IsShown(), true, "...still shown: the hold")
frames(0.7)
eq(face:IsShown(), false, "...then gone")

--------------------------------------------------------------------------------
-- Only over a visible map (Blizzard's ToggleMinimap hides the map alone)
--------------------------------------------------------------------------------
WoW.timers = {}
Minimap:Hide()
Begin()
eq(face:IsShown(), false, "the map hidden: no face")
End()
frames(0.7)
eq(face:IsShown(), false, "...nor after")
Minimap:Show()

Begin()
eq(face:IsShown(), true, "shown")
Minimap:Hide()
eq(face:IsShown(), false, "the map hidden mid-scan: gone at once")
End()
eq(face:IsShown(), false, "...and the end starts no hold")
eq(face:GetScript("OnUpdate"), nil, "...no OnUpdate left waiting")
Minimap:Show()
eq(face:IsShown(), false, "the map back after the scan: nothing to show")

Begin(); End()
frames(0.1)
Minimap:Hide()
eq(face:IsShown(), false, "the map hidden mid-hold: gone at once")
eq(face:GetScript("OnUpdate"), nil, "...the hold cancelled")
Minimap:Show()
eq(face:IsShown(), false, "...and it doesn't come back with the map")

-- The container hidden mid-hold (an ancestor): the hold doesn't resume later.
Begin(); End()
frames(0.1)
container:Hide()
eq(face:IsShown(), false, "the container hidden mid-hold: the face is done")
eq(face:GetScript("OnUpdate"), nil, "...no hold left")
frames(5)
container:Show()
eq(face:IsVisible(), false, "...the container back much later: no stale ping")
eq(face:GetAlpha(), 1, "...alpha ready for next time")
WoW.timers = {}

--------------------------------------------------------------------------------
-- The theme: the lines and the sweep take its hue and wash; the body stays dark
--------------------------------------------------------------------------------
GMM.Settings.SetTheme("smoked")
local lc = lines._vertex
check(lc and lc[4] < Face.LINES_ALPHA, "smoked: the lines dimmer (" .. tostring(lc and lc[4]) .. ")")
check(sweep._vertex[4] < Face.SWEEP_ALPHA, "...the sweep too")
check(body._color and body._color[4] == Face.BODY_ALPHA and body._color[1] < 0.1, "...the body dark")
GMM.Settings.SetTheme("class")
local sc = sweep._vertex
local mage = { 0.25, 0.78, 0.92 }
near(sc[1], mage[1] / 0.92, 1e-6, "class: the sweep in the class's hue")
near(sc[2], mage[2] / 0.92, 1e-6, "...at full brightness")
GMM.Settings.SetTheme("clear")
lc = lines._vertex
eq(lc[1], Face.HUE[1], "clear: the cool default hue")
eq(lc[4], Face.LINES_ALPHA, "...at full strength")

--------------------------------------------------------------------------------
-- The player's choice: ours only with NodeRadar's radar look
--------------------------------------------------------------------------------
WoW.timers = {}
rawset(_G, "NodeRadar", nil)
eq(GlassMiniMap.ScanStandIn(), false, "no NodeRadar: not ours, the borrower draws its own")
Begin()
eq(face:IsShown(), false, "...and no face of ours on its scan")
End()
eq(face:GetScript("OnUpdate"), nil, "...nor a hold after it")
fakeNodeRadar({})
eq(GlassMiniMap.ScanStandIn(), false, "a NodeRadar without RadarLook (1.9.0): not ours")
fakeNodeRadar({ RadarLook = function() error("boom") end })
eq(GlassMiniMap.ScanStandIn(), false, "RadarLook throwing: not ours, no error")
fakeNodeRadar({ RadarLook = function() return 1 end })
eq(GlassMiniMap.ScanStandIn(), false, "RadarLook not exactly true: not ours")
fakeNodeRadar()
radar = false
eq(GlassMiniMap.ScanStandIn(), false, "the real ground chosen (the default): not ours")
radar = true
eq(GlassMiniMap.ScanStandIn(), true, "the radar chosen: ours")

-- Latched for each borrow: the answer at the first Begin holds until the last
-- release, so NodeRadar and we never disagree mid-borrow (Codex).
radar = false
Begin()
eq(face:IsShown(), false, "the ground chosen: no face")
radar = true
eq(GlassMiniMap.ScanStandIn(), false, "the radar chosen mid-borrow: still not ours for this one")
Begin("Other")
eq(face:IsShown(), false, "...another owner's Begin meanwhile: still none")
Minimap:Hide(); Minimap:Show()
eq(face:IsShown(), false, "...nor when the map comes back meanwhile")
End("Other"); End()
eq(face:GetScript("OnUpdate"), nil, "...released: no hold of a face never shown")
eq(GlassMiniMap.ScanStandIn(), true, "...ours from the next borrow")
Begin()
eq(face:IsShown(), true, "...which gets it")
radar = false
eq(GlassMiniMap.ScanStandIn(), true, "the ground chosen mid-borrow: still ours for this one")
Minimap:Hide(); Minimap:Show()
eq(face:IsShown(), true, "...the map back meanwhile: ours again")
End()
frames(0.2)
eq(face:IsShown(), true, "...the toggle doesn't cut the hold")
frames(0.5)
eq(face:IsShown(), false, "...which ends as usual")
eq(GlassMiniMap.ScanStandIn(), false, "...and the ground from the next borrow")
Begin()
eq(face:IsShown(), false, "...which shows none of ours")
End()
radar = true
WoW.timers = {}

--------------------------------------------------------------------------------
-- The shape and the stacking NodeRadar's ground needs
--------------------------------------------------------------------------------
eq(type(rawget(_G, "GetMinimapShape")), "function", "GetMinimapShape declared")
eq(GetMinimapShape(), "ROUND", "...round, as Blizzard's mask")
local square = function() return "SQUARE" end
loadAddon({ before = function() rawset(_G, "GetMinimapShape", square) end })
eq(rawget(_G, "GetMinimapShape"), square, "a skin's own declaration left alone")
GMM = loadAddon()
fakeNodeRadar()
-- NodeRadar's stand-in sits at MinimapBackdrop's level, the map's + 1 (it has
-- none of its own in Minimap.xml): everything of ours over the map is above it.
local backdrop = Minimap:GetFrameLevel() + 1
GMM.Settings.SetRunicMode(true)      -- the runes are built only on demand
local runes, _, layer = GMM.Ring._test.runes()
for name, f in pairs({ bloom = GMM.Ring._test.bloom(), fog = GMM.Ring._test.fog(), runes = runes,
        ["moving runes"] = layer.frame, ["north tab"] = GMM.Ring._test.notch() }) do
    check(f._level > backdrop, name .. " above NodeRadar's stand-in (" .. f._level .. ")")
end

--------------------------------------------------------------------------------
-- A scan that spans our build chose its own stand-in: we stay out of it
--------------------------------------------------------------------------------
GMM = loadAddon({ before = function()
    eq(GlassMiniMap.ScanStandIn(), false, "before our build: no stand-in of ours")
    GlassMiniMap.ScanBegin("NodeRadar")
end })
fakeNodeRadar()
Face = GMM.ScanFace
face = Face._test.face()
eq(GlassMiniMap.ScanStandIn(), false, "built during a scan: not advertised yet")
eq(face:IsShown(), false, "...and not drawn over that scan's own stand-in")
GlassMiniMap.ScanBegin("NodeRadar")
GlassMiniMap.ScanBegin("Other")
eq(face:IsShown(), false, "...nor on a repeated or another owner's Begin while it lasts")
Minimap:Hide(); Minimap:Show()
eq(face:IsShown(), false, "...nor when the map comes back meanwhile")
eq(GlassMiniMap.ScanStandIn(), false, "...still not advertised")
GlassMiniMap.ScanEnd("NodeRadar")
eq(GlassMiniMap.ScanStandIn(), false, "...one owner still scanning: still not")
GlassMiniMap.ScanEnd("Other")
eq(face:IsShown(), false, "the spanning scan ended: no hold of a face never shown")
eq(face:GetScript("OnUpdate"), nil, "...no OnUpdate left waiting")
eq(GlassMiniMap.ScanStandIn(), true, "...and ours from now on")
GlassMiniMap.ScanBegin("NodeRadar")
eq(face:IsShown(), true, "...the next scan gets it")
GlassMiniMap.ScanEnd("NodeRadar")
WoW.timers = {}

--------------------------------------------------------------------------------
-- A failed build (the art missing until a client restart): no stand-in
--------------------------------------------------------------------------------
local setTexture = WoW.Methods.SetTexture
WoW.Methods.SetTexture = function(t, file)
    if type(file) == "string" and file:find("scan_sweep$") then return false end
    return setTexture(t, file)
end
GMM = loadAddon()
WoW.Methods.SetTexture = setTexture
check(GMM.failures["scan face"], "the failure recorded")
eq(GlassMiniMap.ScanStandIn(), false, "a failed build: no stand-in, the borrower draws its own")
eq(Begin(), true, "...scans still acquired")
check(GMM.Ring.Host() and GMM.Header.Pill(), "...and the rest of the minimap built")
End()

-- Never throws, whatever happens inside.
GMM.ScanFace.Draws = function() error("boom") end
eq(GlassMiniMap.ScanStandIn(), false, "Draws throwing: false, no error")
GMM.ScanFace = nil
eq(GlassMiniMap.ScanStandIn(), false, "no face module: false")

done("test_scan_face")
