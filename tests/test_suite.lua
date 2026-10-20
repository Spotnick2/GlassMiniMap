-- Following Glass UI's suite (#37; Glass UI's docs/SUITE.md and
-- docs/SUITE-LOOK.md, API 1; docs/PLAN-suite.md): asked once at ADDON_LOADED
-- before any glass, Pearl built, our material suspended but kept, the suite's
-- tint live with the player's override winning, Glass UI's body numbers (no
-- backing) on every surface, the report, Glass MiniMap Bar's single driver,
-- the options by source, and a reload with following off.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- The decision comes before any glass: nothing is built at file scope.
local atFiles, askedAtBuild
local GMM, ui = loadAddon({ suite = { tint = "smoked" }, db = { material = "clean" }, before = function()
    atFiles = GlassMiniMap.Glass
    local build = GlassMiniMap.BuildGlass
    GlassMiniMap.BuildGlass = function(...)
        askedAtBuild = #GlassUI.Suite._asked
        return build(...)
    end
    GlassUI.Suite._asked = {}
    local theme = GlassUI.Suite.Theme
    GlassUI.Suite.Theme = function(addon)
        table.insert(GlassUI.Suite._asked, addon)
        return theme(addon)
    end
end })
eq(atFiles, nil, "no glass while the files load")
eq(askedAtBuild, 1, "Glass UI was asked before the glass was built")
eq(#ui.asked, 1, "asked once")
eq(ui.asked[1], "GlassMiniMap", "...by our name")
eq(next(GMM.failures), nil, "nothing failed")
for k, v in pairs(GMM.failures) do io.write("    " .. k .. ": " .. v .. "\n") end
WoW.fire("PLAYER_LOGIN")
GMM.Suite.Start()
eq(#ui.asked, 1, "starting again doesn't ask again: one answer per session")

-- The material: Glass UI's Pearl; ours kept and refused.
check(GMM.Suite.Following(), "following")
eq(GMM.GlassPreset, "pearl", "Pearl built, though our own is Clean")
near(GMM.Glass.STYLE.wash, 0.10, "...Pearl's wash")
eq(GMM.db.material, "clean", "our material still saved")
local ok, why = GMM.Settings.SetMaterial("pearl")
check(not ok and why == "set in Glass UI", "setting the material: refused, set in Glass UI")
eq(GMM.db.material, "clean", "...and untouched")
GMM._test.slash("material pearl")
check(WoW.chat[#WoW.chat]:find("Following Glass UI", 1, true), "/gmm material says it follows Glass UI")
eq(GMM.db.material, "clean", "...and changes nothing")

-- The report: plain values, Glass UI's names.
local r = ui.LastReport()
eq(ui.reports[#ui.reports].addon, "GlassMiniMap", "reported as GlassMiniMap")
eq(r.api, 1, "report: api 1")
eq(r.built, "pearl", "...built pearl")
eq(r.reason, nil, "...no reason")
eq(r.minor, GMM.GlassMinor, "...LibGlass's minor")
check(type(r.minor) == "number" and r.minor >= 11, "...at least r11")
eq(r.look.tint, "smoked", "...the tint in effect")
eq(r.own.tint, nil, "...not our own")
eq(r.own.backing, true, "...and our own backing (none: a ring over the map)")
check(type(r.options) == "function", "...a way to open our options")
r.options()
check(WoW.settingsOpened ~= nil, "...which opens them")

-- The suite's tint and Glass UI's numbers on our surfaces.
local ring = GMM.Ring.Glass()
local built = ring.tint.glassColor
eq(GMM.Theme.Name(), "smoked", "the suite's tint")
eq(ring.tint._color[4], 0.62, "smoked: Glass UI's body")
near(ring.wash._gradient[3].a, 0.10 * 0.14 / 0.18, "...its wash factor of our Pearl wash")
local backed = false
for _, s in ipairs(GMM.Theme._test.surfaces) do
    for _, region in pairs(s.g) do
        if type(region) == "table" and region._color and region._color[1] == 0.04 and region._color[2] == 0.05 then backed = true end
    end
end
check(not backed, "Glass UI's backing painted nowhere")

-- Live: a fresh payload, copied (mutating it afterwards changes nothing), re-reported.
local reports = #ui.reports
local payload = { tint = "clear" }
EventRegistry:TriggerEvent("GlassUI.Suite.LookChanged", payload)
payload.tint = "class"
eq(GMM.Theme.Name(), "clear", "LookChanged: clear, copied")
near(ring.tint._color[1], 0.13, "...Glass UI's clear tint (LibGlass's built one)")
eq(ring.tint._color[4], 0.24, "...at its alpha")
near(ring.wash._gradient[3].a, 0.10, "...and the wash as built")
eq(#ui.reports, reports + 1, "...re-reported")
eq(ui.LastReport().look.tint, "clear", "...with the new tint")
check(ui.LastReport() ~= r and ui.LastReport().look ~= r.look, "...in fresh tables")
-- One resolution path: a surface registered late, and the drawer's reading,
-- take Glass UI's numbers (made distinct from ours here to tell them apart).
ui.BODY.clear = { tint = { 0.3, 0.2, 0.1, 0.5 }, wash = 0.5, backing = 0.35 }
local late = GMM.Glass.Apply(CreateFrame("Frame", nil, UIParent), "small")
GMM.Theme.Register(late)
near(late.tint._color[1], 0.3, "a surface built later: Glass UI's numbers")
eq(late.tint._color[4], 0.5, "...its alpha")
near(late.wash._gradient[3].a, 0.10 * 0.5, "...its wash factor")
local tint, wash = GMM.Theme.Current()
near(tint[1], 0.3, "Theme.Current: the same tint")
eq(wash, 0.5, "...and wash factor")
GMM.Theme.Refresh()
eq(ring.tint._color[4], 0.5, "Theme.Refresh: the same")
ui.BODY.clear = { tint = { 0.13, 0.16, 0.22, 0.24 }, wash = 1, backing = 0.35 }
ui.SetTint("class")
near(ring.tint._color[1], 0.25 * 0.6, "class: our class colour times Glass UI's shade")
eq(ring.tint._color[4], built[4], "...at the surface's built alpha")
-- An unknown tint: our default, not the last one.
ui.SetTint("smoked")
ui.SetTint("neon")
eq(GMM.Theme.Name(), "clear", "an unknown tint: our default, clear")
-- In combat: only our own textures change, at once.
WoW.combat = true
ui.SetTint("smoked")
eq(ring.tint._color[4], 0.62, "in combat: repainted at once")
eq(next(GMM.failures), nil, "...nothing failed")
WoW.combat = false

-- The player's override wins, and "suite" clears it.
check(GMM.Settings.SetTheme("class"), "an override")
eq(GMM.db.look.tint, "class", "...saved in look")
check(ui.LastReport().own.tint == true and ui.LastReport().look.tint == "class", "...reported as our own")
ui.SetTint("clear")
eq(GMM.Theme.Name(), "class", "...it holds while the suite changes")
GMM.Settings.SetTheme("smoked")
ui.SetTint("neon")
eq(GMM.Theme.Name(), "smoked", "an unknown suite tint: the override still wins")
ui.SetTint("clear")
check(GMM.Settings.SetTheme("suite"), "\"suite\": follow Glass UI's tint again")
eq(rawget(GMM.db, "look"), nil, "...the override cleared")
eq(GMM.Theme.Name(), "clear", "...the suite's")
eq(ui.LastReport().own.tint, nil, "...reported")
GMM._test.slash("theme suite")
check(WoW.chat[#WoW.chat]:find("theme suite", 1, true), "/gmm theme suite")
GMM._test.slash("suite")
check(WoW.chat[#WoW.chat]:find("following Glass UI", 1, true), "/gmm suite says so")

-- The options: "Glass UI" first, selected by source; the material suspended.
ui.SetTint("smoked")
local panel = GMM.Options._test.panel
panel:Show()
local radios = GMM.Options._test.themeRadios
eq(radios[1].value, "suite", "the tint choices start with Glass UI")
eq(radios[1].text._text, "Glass UI (Smoked glass)", "...naming the suite's tint")
check(radios[1]:GetChecked(), "...selected while there's no override")
GMM.Settings.SetTheme("smoked")
panel:Hide(); panel:Show()
check(not radios[1]:GetChecked() and radios[3]:GetChecked(), "an override equal to the suite's shows as our own")
radios[1]:Click("LeftButton")
eq(rawget(GMM.db, "look"), nil, "clicking Glass UI clears it")
local m = GMM.Options._test.material
eq(m.radios[1]:IsEnabled(), false, "the material choices are disabled")
check(m.radios[2]:GetChecked(), "...showing our own, kept")
eq(m.status._text, "Following Glass UI (Pearl): set in Glass UI", "...and why")
eq(m.button._shown, true, "a Set in Glass UI button")
m.button:Click("LeftButton")
eq(ui.opened, 1, "...opens Glass UI's page")

-- Glass MiniMap Bar: our tint, until it says it follows the suite itself.
GMM, ui = loadAddon({ suite = { tint = "smoked" }, gmb = true })
local gmb = GlassMiniMapBar
eq(gmb.tint[4], 0.62, "the bar wears our tint (the suite's)")
gmb.FollowsSuite = function() return true end
gmb.tint = nil
ui.SetTint("clear")
eq(gmb.tint, nil, "...not once it follows the suite itself: one driver")
gmb.FollowsSuite = function() return "yes" end
ui.SetTint("smoked")
eq(gmb.tint and gmb.tint[4], 0.62, "anything but true: still ours")
gmb.FollowsSuite = function() error("boom") end
gmb.tint = nil
ui.SetTint("clear")
check(gmb.tint ~= nil, "...a throwing FollowsSuite too")
eq(next(GMM.failures), nil, "...harmlessly")

-- Follow on with our own Clean and smoked override, reload with follow off:
-- exactly our own look back.
GMM, ui = loadAddon({ suite = true, db = { material = "clean", look = { tint = "smoked" } } })
eq(GMM.GlassPreset, "pearl", "following: Pearl")
local saved = GlassMiniMapDB
GMM, ui = loadAddon({ db = saved, suite = { answer = function() return nil, "not-following" end } })
check(not GMM.Suite.Following(), "follow off")
eq(GMM.GlassPreset, "clean", "...our own Clean again")
eq(GMM.Theme.Name(), "smoked", "...our own tint")
eq(ui.LastReport().built, nil, "...reported as our own look")
eq(ui.LastReport().look.tint, "smoked", "...with our tint")
check(not GMM.Settings.SetTheme("suite"), "\"suite\" is refused while not following")
check(GMM.Settings.SetMaterial("pearl"), "our material can be set again")

-- An older API 1 without Look, Body or Open.
GMM, ui = loadAddon({ suite = { noLook = true, noBody = true, noOpen = true, tint = "smoked" } })
check(GMM.Suite.Following() and not GMM.Suite.LookFollowing(), "no Look: Pearl, our own tint")
eq(GMM.GlassPreset, "pearl", "...Pearl built")
eq(GMM.Theme.Name(), "clear", "...our default tint")
eq(GMM.Ring.Glass().tint._color[1], GMM.Ring.Glass().tint.glassColor[1], "no Body: our clear, as built")
check(not GMM.Settings.SetTheme("suite"), "...no Glass UI choice")
GMM.Options._test.panel:Show()
eq(GMM.Options._test.themeRadios[1].value, "clear", "...nor on the page")
eq(GMM.Options._test.material.button._shown, false, "no Open: no Set in Glass UI button")
eq(GMM.Options._test.material.radios[1]:IsEnabled(), false, "...the material still suspended")

done("test_suite")
