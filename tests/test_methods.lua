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
WoW.version = "dev"
local GMM = loadAddon({ gmb = true })
GMM._test.slash("runes on")
GMM._test.slash("runes status")
GMM._test.slash("runes style glowing")
GMM._test.slash("runes motion orbit")
GMM._test.slash("runes fog on")
GMM._test.slash("runes")
Minimap:Hide(); Minimap:Show()
MinimapCluster:Hide(); MinimapCluster:Show()
GMM._test.slash("runes off")

-- The drawer disc (Glass MiniMap Bar's launcher).
local D = disc()
D:Click("LeftButton"); D._scripts.OnEnter(D); D._scripts.OnLeave(D)
GlassMiniMapBar.opts.setIcon("Interface\\Icons\\DBM", { 0.1, 0.9, 0.1, 0.9 })

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
WoW.fire("CVAR_UPDATE", "minimapShowPlayerCoords", "1")
for _, k in ipairs({ "sun", "glassTracking" }) do
    GMM.Settings.Set(k, false); GMM.Settings.Set(k, true)
end

-- The LFG eye's disc.
QueueStatusButton:Show(); QueueStatusButton:SetScale(1.2); QueueStatusButton:Hide()

-- The options page: every control's OnClick.
local panel = GMM.Options._test.panel
panel:Show()
for _, group in pairs(GMM.Options._test.runic.buttons) do
    for _, button in ipairs(group) do button:Click("LeftButton") end
end
GMM.Options._test.intensity:SetValue(50)
GMM.Options._test.speed:SetValue(150)
for _, w in ipairs(WoW.frames) do
    if w._parent == panel and w._scripts.OnClick then w._scripts.OnClick(w, "LeftButton") end
end
for _, cmd in ipairs({ "failures", "options", "version", "theme smoked",
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
