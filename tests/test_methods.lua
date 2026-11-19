-- Every widget method the addon calls exists on that widget type in the
-- pinned build (WowTestKit's Kit.checkMethods, tests/kit.pin's build).
--
-- The core's widgets answer only the methods their type has on that build (or
-- one the stubs implement), so a call to a method Forever lacks fails where
-- it's made; a method the stubs implement, called on the wrong type, is what
-- the check below catches. Keep the exercise reaching every handler the addon
-- installs. It does NOT prove argument contracts, event behaviour or
-- protection rules: that is the in-game pass (docs/FOREVER-PROBE.md).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

WoW.version = "dev"
local GMM = loadAddon({ gmb = true })
WoW.fireAllRegistered()
WoW.tick()
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

-- The mail disc.
WoW.mail, WoW.senders = true, { "Thrall" }
WoW.fire("UPDATE_PENDING_MAIL")
local mail = GMM.Mail.Disc()
mail._scripts.OnEnter(mail); WoW.fire("UPDATE_PENDING_MAIL"); mail._scripts.OnLeave(mail)

-- The instance disc.
WoW.instance = { type = "party", maxPlayers = 5 }
MinimapCluster.InstanceDifficulty:Update()
local inst = GMM.Difficulty.Disc()
inst._scripts.OnEnter(inst); MinimapCluster.InstanceDifficulty:Update(); inst._scripts.OnLeave(inst)

-- The LFG eye's disc.
QueueStatusButton:Show(); QueueStatusButton:SetScale(1.2); QueueStatusButton:Hide()

-- The options page: every control's OnClick.
local panel = GMM.Options._test.panel
panel:Show()
for _, group in ipairs({GMM.Options._test.runic.style, GMM.Options._test.runic.motion}) do
    for _, button in ipairs(group) do button:Click("LeftButton") end
end
GMM.Options._test.runic.vapor:SetChecked(false)
GMM.Options._test.runic.vapor:Click("LeftButton")
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
eq(next(GMM.failures), nil, "no failures recorded while exercising everything")

-- Following Glass UI's suite (#37): its options, a live tint change. A load
-- resets the client (WoW.reset), and the core's reset forgets the methods
-- called so far: keep the first session's for the check.
local first = WoW.methodsCalled
local ui
GMM, ui = loadAddon({ suite = true, gmb = true })
GMM.Options._test.panel:Show()
for _, w in ipairs(WoW.frames) do
    if w._parent == GMM.Options._test.panel and w._scripts.OnClick then w._scripts.OnClick(w, "LeftButton") end
end
ui.SetTint("smoked")
for _, cmd in ipairs({ "suite", "material clean", "theme suite", "help" }) do GMM._test.slash(cmd) end

for pair in pairs(first) do WoW.methodsCalled[pair] = true end

local recorded = Kit.checkMethods()
-- The floor: 164 recorded when this was written (on 70959), rounded down.
check(recorded >= 160, "the exercise reached the pills, discs, menus and options (" .. recorded .. " recorded)")
eq(next(GMM.failures), nil, "no failures recorded while exercising everything")
for k, v in pairs(GMM.failures) do io.write("    " .. k .. ": " .. v .. "\n") end
done("test_methods")
