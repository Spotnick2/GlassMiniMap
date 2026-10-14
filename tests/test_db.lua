-- Saved variables: only what the player set is saved, junk repaired, the
-- drawer's own table kept whole.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GMM = loadAddon()
local db = GlassMiniMapDB
eq(rawget(db, "theme"), nil, "defaults aren't written")
eq(db.theme, "clear", "...but read through")
eq(db.coords, true, "coords on by default")
eq(db.coordsTenths, true, "tenths by default (the mockup's 43.2, 24.8)")
eq(type(db.drawer), "table", "the drawer's table")
eq(db.drawer.openOn, "hover", "drawer default: open on hover")
eq(db.drawer.skin, true, "drawer default: glass orbs")
eq(db, GMM.db, "the addon uses the saved table itself")

GMM.Settings.SetTheme("smoked")
eq(rawget(db, "theme"), "smoked", "a change is saved")
GMM.Settings.SetTheme("clear")
eq(rawget(db, "theme"), nil, "back to the default: dropped again")
check(not GMM.Settings.Set("bogus", true), "an unknown setting is refused")

GMM = loadAddon({ db = { theme = "neon", coords = "yes", sun = false,
    drawer = { hidden = { LibDBIcon10_DBM = true }, openOn = "sideways", perRow = 500, buttonSize = "big",
               direction = "north", last = { mouse = "LeftButton" }, order = { "LibDBIcon10_DBM", 7, false } } } })
db = GlassMiniMapDB
eq(db.theme, "clear", "an unknown theme falls back")
eq(rawget(db, "coords"), nil, "a non-boolean is dropped")
eq(db.sun, false, "a real choice is kept")
local d = db.drawer
eq(d.hidden.LibDBIcon10_DBM, true, "hidden buttons kept")
eq(d.openOn, "hover", "bad openOn repaired")
eq(d.perRow, 30, "perRow clamped")
eq(d.buttonSize, 28, "non-number size reset")
eq(d.direction, "auto", "bad direction repaired")
eq(d.last, nil, "a 'last' without a name is dropped")
eq(table.concat(d.order, ","), "LibDBIcon10_DBM", "order kept, junk entries dropped")
eq(GMM.Collector.orderOf(), d.order, "the collector sorts by the saved order itself")
GMM.Drawer.Set("buttonSize", 3)
eq(d.buttonSize, 20, "Set clamps to the limits")
eq(GMM.Ring.Sun()._shown, false, "the saved sun setting applies at login")

done("test_db")
