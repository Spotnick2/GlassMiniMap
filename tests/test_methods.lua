-- Every widget method the addon calls must exist on this client.
--
-- The stub answers any Capitalised method call (a no-op for ones it does not
-- implement), so a call to a method Forever lacks would otherwise pass
-- silently. This checks each recorded "Type:Method" against the API dump's
-- widget-method walk. Keep it exercising every handler the addon installs.
-- It does NOT prove argument contracts, event behaviour or protection rules:
-- that is the in-game pass (docs/FOREVER-PROBE.md).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local f = io.open(WoW.DUMP, "r")
if not f then
    io.write("test_methods: SKIPPED (no API dump at " .. WoW.DUMP .. ")\n")
    os.exit(0)
end
local widget, documented = {}, {}
for line in f:lines() do
    local wm = line:match("^(%a+:%a+)%s*$")
    if wm then widget[wm] = true end
    local fn = line:match("^([%a_]+)%(")
    if fn then documented[fn] = true end
end
f:close()

WoW.methodsCalled = {}
local GMM = loadAddon({
    db = { drawer = { lastUsed = true } },
    before = function()
        WoW.LDBI():Register("DBM", { icon = "dbm", OnClick = function() end }, {})
        WoW.MinimapButton({ name = "HandMadeMinimapButton", script = "OnMouseUp" })
    end,
    tocAddons = { { title = "Gnomesweeper", icon = "Interface\\Icons\\gnome" } },
})

-- The drawer and its launcher.
local L = launcher()
L._cx, L._cy = 900, 700
L._scripts.OnEnter(L); L._scripts.OnLeave(L)
entry("LibDBIcon10_DBM").btn:Click("LeftButton")
L:Click("RightButton")
L:Click("LeftButton")
WoW.tick(2)
WoW.fire("GLOBAL_MOUSE_DOWN", "LeftButton")
WoW.finishAnimations()
local hand = entry("HandMadeMinimapButton").btn
hand._scripts.OnMouseUp(hand, "RightButton")
L:Click("RightButton")
local gnome = entry("AddOns:Gnomesweeper").btn
gnome:Click("LeftButton"); gnome._scripts.OnEnter(gnome); gnome._scripts.OnLeave(gnome)
WoW.LDBI():AddButtonToCompartment("DBM")
WoW.LDBI():RemoveButtonFromCompartment("DBM")
WoW.flushTimers()
for _, k in ipairs({ "skin", "lastUsed" }) do GMM.Drawer.Set(k, false); GMM.Drawer.Set(k, true) end
for _, d in ipairs({ "left", "right", "up", "down", "auto" }) do GMM.Drawer.Set("direction", d) end

-- The pills, the discs, the tracking menu.
local H, F = GMM.Header._test, GMM.Footer._test
H.zoneButton():Click("LeftButton"); H.zoneButton()._scripts.OnEnter(H.zoneButton())
H.calendar():Click("LeftButton"); H.calendar()._scripts.OnEnter(H.calendar())
H.tracking()._scripts.OnEnter(H.tracking())
H.tracking():Click("LeftButton")
for _, row in ipairs(GMM.Tracking._test.rows) do if row._shown then row:Click("LeftButton") end end
WoW.fire("MINIMAP_UPDATE_TRACKING")
WoW.fire("GLOBAL_MOUSE_DOWN", "LeftButton")
H.tracking():Click("RightButton")
F.zoomIn():Click("LeftButton"); F.zoomOut():Click("LeftButton")
F.tick(nil, 1)
local sun = GMM.Ring.Sun()
sun._scripts.OnEnter(sun); sun:Click("LeftButton")
WoW.fire("DIEL_CYCLE_CHANGED", false)
WoW.cvars.rotateMinimap = true
WoW.fire("CVAR_UPDATE", "rotateMinimap", "1")
WoW.tick(0.02)
for _, t in ipairs(GMM.Theme.NAMES) do GMM.Settings.SetTheme(t) end
for _, k in ipairs({ "coords", "coordsTenths", "sun", "glassTracking" }) do
    GMM.Settings.Set(k, false); GMM.Settings.Set(k, true)
end

-- The options pages: every control's OnClick.
local O = GMM.Options._test
for _, page in ipairs({ O.main, O.drawer }) do
    page:Show()
    for _, w in ipairs(WoW.frames) do
        if w._parent == page and w._scripts.OnClick then w._scripts.OnClick(w, "LeftButton") end
    end
end
for _, list in pairs(O.lists) do
    for _, row in ipairs(list.rows) do
        if row._shown then
            row._scripts.OnClick(row, "LeftButton")
            row._scripts.OnDoubleClick(row, "LeftButton")
        end
    end
    list.frame._scripts.OnMouseWheel(list.frame, -1)
end
for _, k in ipairs({ "up", "down", "show", "hide" }) do O.arrows[k]._scripts.OnClick(O.arrows[k], "LeftButton") end
for _, cmd in ipairs({ "scan", "failures", "drawer", "options", "version", "theme smoked", "coords off",
                       "sun on", "help", "" }) do
    GMM._test.slash(cmd)
end
WoW.flushTimers()

local n = 0
for name in pairs(WoW.methodsCalled) do
    n = n + 1
    local method = name:match(":(%a+)$")
    check(widget[name] or documented[method], "method exists on Forever: " .. name)
end
check(n > 60, "recorded a realistic number of methods (" .. n .. ")")
eq(next(GMM.failures), nil, "no failures recorded while exercising everything")
for k, v in pairs(GMM.failures) do io.write("    " .. k .. ": " .. v .. "\n") end
done("test_methods")
