-- Saved variables: only what the player set is saved, junk repaired, the
-- drawer's own table kept whole.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GMM = loadAddon()
local db = GlassMiniMapDB
eq(rawget(db, "theme"), nil, "defaults aren't written")
eq(db.theme, "clear", "...but read through")
eq(rawget(db, "drawer"), nil, "no drawer settings: they're Glass MiniMap Bar's")
eq(db, GMM.db, "the addon uses the saved table itself")

GMM.Settings.SetTheme("smoked")
eq(rawget(db, "theme"), "smoked", "a change is saved")
GMM.Settings.SetTheme("clear")
eq(rawget(db, "theme"), nil, "back to the default: dropped again")
check(not GMM.Settings.Set("bogus", true), "an unknown setting is refused")

GMM = loadAddon({ db = { theme = "neon", coords = false, glassTracking = "yes", sun = false, drawer = { perRow = 9 } } })
db = GlassMiniMapDB
eq(db.theme, "clear", "an unknown theme falls back")
eq(rawget(db, "glassTracking"), nil, "a non-boolean is dropped")
eq(rawget(db, "coords"), nil, "the pre-release coords setting is dropped (Blizzard's CVar now)")
eq(db.sun, false, "a real choice is kept")
eq(rawget(db, "drawer"), nil, "a pre-release build's drawer table is dropped")
eq(GMM.Ring.Sun()._shown, false, "the saved sun setting applies at login")

done("test_db")
