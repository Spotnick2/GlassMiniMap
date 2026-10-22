-- The hover, the fader (#15), the auto zoom-out (#13), their settings and the
-- options page's Behaviour section (docs/PLAN-zoom-ping-fader.md). The auto
-- zoom-out on by default, the fader off. Who pinged (#14) is out: the client keeps MINIMAP_PING from addons.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GMM = loadAddon()
local host, container = GMM.Ring.Host(), GMM.Blizzard.Container()
host._cx, host._cy = 600, 400
local half = host._width / 2

local function wait(seconds)
    for _ = 1, math.floor(seconds / 0.05 + 0.5) do
        WoW.now = WoW.now + 0.05
        WoW.tick(0.05)
    end
end
local function away() WoW.cursor = { -1000, -1000 }; WoW.mouseOver = {} end
local function onMap() WoW.cursor = { 600, 400 } end
local function settle() away(); wait(GMM.Fader.DELAY + GMM.Fader.TIME + 0.2) end

--------------------------------------------------------------------------------
-- Defaults
--------------------------------------------------------------------------------
local S = GMM.Settings
eq(S.AutoZoomOut(), 5, "auto zoom-out: 5 s by default")
eq(S.Fader(), false, "the fader: off by default")
eq(S.FaderOpacity(), 60, "...at 60 %")
for _, k in ipairs({ "autoZoomOut", "fader", "faderOpacity" }) do
    eq(rawget(GlassMiniMapDB, k), nil, k .. ": not saved")
end

--------------------------------------------------------------------------------
-- Hover
--------------------------------------------------------------------------------
local H = GMM.Hover
away(); wait(0.2)
eq(H.Over(), false, "hover: the mouse away")
check(H.Idle() > 0, "...idle counting")
onMap(); wait(0.1)
eq(H.Over(), true, "over the map's centre")
eq(H.Idle(), 0, "...idle 0")
WoW.cursor = { 600 + half * 0.8, 400 + half * 0.8 }; wait(0.1)
eq(H.Over(), false, "a corner of the ring's square, off its circle: not over")
away()
for name, f in pairs({ ["the zone pill"] = GMM.Header.Pill(), ["the coords pill"] = GMM.Footer.Pill(),
                       ["the sun"] = GMM.Ring.Sun(), ["the north tab"] = GMM.Ring.Notch() }) do
    WoW.mouseOver = { [f] = true }; wait(0.1)
    eq(H.Over(), true, "over " .. name)
    f:Hide(); wait(0.1)
    eq(H.Over(), false, "..." .. name .. " hidden: not")
    f:Show()
end
away()
GMM.Tracking.Open(GMM.Header.TrackingButton()); wait(0.1)
eq(H.Held(), true, "the tracking menu open: held")
eq(H.Idle(), 0, "...not idle")
GMM.Tracking.Close(); wait(0.1)
eq(H.Held(), false, "closed: not held")
rawset(_G, "EditModeManagerFrame", { IsEditModeActive = function() return true end })
wait(0.1)
eq(H.Held(), true, "Edit Mode active: held")
rawset(_G, "EditModeManagerFrame", { IsEditModeActive = function() error("boom") end })
wait(0.1)
eq(H.Held(), false, "...its query throwing: not held, no error")
rawset(_G, "EditModeManagerFrame", nil)

--------------------------------------------------------------------------------
-- The fader
--------------------------------------------------------------------------------
local queue = GMM.Queue.Disc()
check(queue ~= nil, "the queue backing built")
settle()
eq(container:GetAlpha(), 1, "off by default: the container at full with the mouse away")
check(S.SetFader(true), "the fader on")
eq(rawget(GlassMiniMapDB, "fader"), true, "...saved")
settle()
near(container:GetAlpha(), 0.6, 1e-9, "fader: the container at 60 % with the mouse away")
near(queue:GetAlpha(), 0.6, 1e-9, "...the queue backing too (a UIParent child)")
eq(Minimap._alpha, 1, "...the map's own alpha untouched (it inherits)")
onMap(); wait(0.1)
check(container:GetAlpha() > 0.6, "hovered: fading in")
wait(GMM.Fader.TIME)
eq(container:GetAlpha(), 1, "...to full")
away(); wait(GMM.Fader.DELAY - 0.1)
eq(container:GetAlpha(), 1, "the mouse gone just under the delay: still full")
wait(0.1); wait(GMM.Fader.TIME / 2)
check(container:GetAlpha() < 1 and container:GetAlpha() > 0.6, "...then fading")
settle()
GMM.Tracking.Open(GMM.Header.TrackingButton()); wait(0.5)
eq(container:GetAlpha(), 1, "the tracking menu open: full")
wait(3)
eq(container:GetAlpha(), 1, "...and it stays")
GMM.Tracking.Close(); settle()
near(container:GetAlpha(), 0.6, 1e-9, "closed: faded again")
check(S.SetFaderOpacity(40), "opacity 40 %")
near(container:GetAlpha(), 0.4, 1e-9, "...applied at once")
eq(rawget(GlassMiniMapDB, "faderOpacity"), 40, "...saved")
for _, bad in ipairs({ 15, 42, 105, "40", 0 / 0 }) do
    check(not S.SetFaderOpacity(bad), "opacity " .. tostring(bad) .. " refused")
end
eq(S.FaderOpacity(), 40, "...left as it was")
check(S.SetFader(false), "the fader off")
eq(container:GetAlpha(), 1, "...the container back to 1 at once")
eq(queue:GetAlpha(), 1, "...the queue backing too")
eq(rawget(GlassMiniMapDB, "fader"), nil, "...the default, not saved")
settle()
eq(container:GetAlpha(), 1, "...and it stays, the mouse away")
check(not S.SetFader("yes"), "a non-boolean refused")
check(S.SetFader(true), "on again")
eq(rawget(GlassMiniMapDB, "fader"), true, "...saved")
WoW.combat = true
onMap(); wait(0.5); away(); settle()
near(container:GetAlpha(), 0.4, 1e-9, "in combat: still fades")
WoW.combat = false
check(S.SetFaderOpacity(60), "back to 60 %")

--------------------------------------------------------------------------------
-- Auto zoom-out
--------------------------------------------------------------------------------
local function zoomTo(z) Minimap:SetZoom(z); WoW.fire("MINIMAP_UPDATE_ZOOM") end
away()
zoomTo(3)
eq(GMM.Footer.Countdown(), 5, "zoomed in: the countdown starts at the delay")
wait(4.8)
eq(Minimap:GetZoom(), 3, "...still zoomed just under it")
wait(0.3)
eq(Minimap:GetZoom(), 0, "...then zoomed all the way out")
WoW.fire("MINIMAP_UPDATE_ZOOM")                      -- our own zoom-out's event
eq(GMM.Footer.Countdown(), nil, "...whose event starts nothing")
zoomTo(2)
onMap(); wait(8)
eq(Minimap:GetZoom(), 2, "the mouse on the map 8 s: still zoomed")
away(); wait(4.8)
eq(Minimap:GetZoom(), 2, "...left: the full delay again")
wait(0.3)
eq(Minimap:GetZoom(), 0, "...then out")
zoomTo(2); wait(3)
zoomTo(3); wait(3)
eq(Minimap:GetZoom(), 3, "a new zoom restarts the countdown")
wait(2.2)
eq(Minimap:GetZoom(), 0, "...then out")
zoomTo(2)
GMM.Tracking.Open(GMM.Header.TrackingButton()); wait(8)
eq(Minimap:GetZoom(), 2, "the tracking menu open: held")
GMM.Tracking.Close(); wait(5.2)
eq(Minimap:GetZoom(), 0, "...closed: out after the delay")
GMM.Footer.Zoom(1)
WoW.fire("MINIMAP_UPDATE_ZOOM")
eq(GMM.Footer.Countdown(), 5, "our + starts it too")
check(S.SetAutoZoomOut(10), "the delay to 10 s")
eq(GMM.Footer.Countdown(), 10, "...the countdown taken over")
check(S.SetAutoZoomOut(0), "off")
eq(GMM.Footer.Countdown(), nil, "...no countdown")
zoomTo(2); wait(40)
eq(Minimap:GetZoom(), 2, "...nothing zooms out")
eq(rawget(GlassMiniMapDB, "autoZoomOut"), 0, "...saved")
for _, bad in ipairs({ -1, 31, 2.5, "5" }) do
    check(not S.SetAutoZoomOut(bad), "delay " .. tostring(bad) .. " refused")
end
check(S.SetAutoZoomOut(5), "back to 5")
eq(rawget(GlassMiniMapDB, "autoZoomOut"), nil, "...the default, not saved")
WoW.combat = true
zoomTo(2); away(); wait(5.2)
eq(Minimap:GetZoom(), 0, "in combat: still zooms out")
WoW.combat = false

--------------------------------------------------------------------------------
-- The options page
--------------------------------------------------------------------------------
local O = GMM.Options._test
O.panel:Show()
local B = O.behaviour
check(B and B.autoZoom and B.fader and B.opacity, "options: the Behaviour section built")
local panelChildren = 0
for _, c in ipairs(O.panel._children) do panelChildren = panelChildren + 1; eq(c, O.scroll, "the panel holds the scroll frame only") end
eq(panelChildren, 1, "...one child")
eq(B.autoZoom._parent, O.content, "the controls on the scroll child")
eq(O.themeRadios[1]._parent, O.content, "...the older ones too")
eq(O.runic.controls._parent, O.content, "...the runic group too")
eq(B.autoZoom._value, 5, "the delay slider at 5")
check(B.autoZoom.label._text:find("5 s", 1, true), "...labelled")
B.autoZoom._scripts.OnValueChanged(B.autoZoom, 7.4)
eq(S.AutoZoomOut(), 7, "dragged: 7 s, on the step")
eq(B.fader:GetChecked(), true, "the fader checked")
B.fader:SetChecked(false); B.fader:Click()
eq(S.Fader(), false, "...unchecked: off")
B.fader:SetChecked(true); B.fader:Click()
eq(S.Fader(), true, "...on again")
B.opacity._scripts.OnValueChanged(B.opacity, 72)
eq(S.FaderOpacity(), 70, "the opacity slider on its 5 % step")
check(B.opacity.label._text:find("70%", 1, true), "...labelled")

--------------------------------------------------------------------------------
-- Saved values
--------------------------------------------------------------------------------
GMM = loadAddon({ db = { autoZoomOut = 31, fader = "yes", faderOpacity = 42 } })
for _, k in ipairs({ "autoZoomOut", "fader", "faderOpacity" }) do
    eq(rawget(GlassMiniMapDB, k), nil, "junk " .. k .. " dropped")
end
GMM = loadAddon({ db = { autoZoomOut = 0, fader = false, faderOpacity = 30 } })
eq(GMM.Settings.AutoZoomOut(), 0, "saved: never zoom out")
eq(GMM.Settings.Fader(), false, "saved: no fader")
eq(GMM.Blizzard.Container():GetAlpha(), 1, "...the container at full from the start")
eq(GMM.Settings.FaderOpacity(), 30, "saved: 30 %")
GMM = loadAddon({ db = { fader = true } })
eq(GMM.Settings.Fader(), true, "saved: the fader on")

eq(next(GMM.failures), nil, "no failures")
done("test_extras")
