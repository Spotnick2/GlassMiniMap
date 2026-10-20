-- Saved variables: only what the player set is saved, junk repaired, the
-- drawer's own table kept whole; the tint in look (never pruned), a saved
-- theme moved in once, the material saved sparse (#37).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GMM = loadAddon()
local db = GlassMiniMapDB
eq(rawget(db, "look"), nil, "no tint saved until one is chosen")
eq(GMM.Theme.Name(), "clear", "...clear meanwhile")
eq(rawget(db, "material"), nil, "defaults aren't written")
eq(db.material, "pearl", "...but read through: Pearl, our default")
eq(GMM.GlassPreset, "pearl", "...and built")
eq(rawget(db, "drawer"), nil, "no drawer settings: they're Glass MiniMap Bar's")
eq(db, GMM.db, "the addon uses the saved table itself")

GMM.Settings.SetTheme("smoked")
eq(db.look.tint, "smoked", "a tint is saved in look")
GMM.Settings.SetTheme("clear")
eq(db.look.tint, "clear", "...the default too: the player chose it")
GMM = loadAddon({ db = db })
eq(GlassMiniMapDB.look.tint, "clear", "...and it survives a reload (look is never pruned)")
check(not GMM.Settings.SetTheme("suite"), "\"suite\" is refused without Glass UI")
check(not GMM.Settings.Set("bogus", true), "an unknown setting is refused")

-- The material: saved for the next /reload, sparse.
check(GMM.Settings.SetMaterial("clean"), "a material is saved")
eq(rawget(GlassMiniMapDB, "material"), "clean", "...as set")
eq(GMM.GlassPreset, "pearl", "...not applied before /reload")
check(not GMM.Settings.SetMaterial("classic"), "an unknown material is refused")
GMM = loadAddon({ db = GlassMiniMapDB })
eq(GMM.GlassPreset, "clean", "a saved Clean is built at the next load")
GMM.Settings.SetMaterial("pearl")
eq(rawget(GlassMiniMapDB, "material"), nil, "back to the default: dropped again")

-- The one-time move of a saved theme into look.
GMM = loadAddon({ db = { theme = "smoked" } })
eq(GlassMiniMapDB.look.tint, "smoked", "a saved theme moves into look")
eq(rawget(GlassMiniMapDB, "theme"), nil, "...and the old key goes")
eq(GMM.Theme.Name(), "smoked", "...painted")
GMM = loadAddon({ db = GlassMiniMapDB })
eq(GlassMiniMapDB.look.tint, "smoked", "the move is idempotent")
GMM = loadAddon({ db = { theme = "class", look = { tint = "smoked" } } })
eq(GlassMiniMapDB.look.tint, "smoked", "a saved look.tint wins over a legacy theme")
eq(rawget(GlassMiniMapDB, "theme"), nil, "...the old key still goes")
GMM = loadAddon({ db = { theme = "neon", look = { tint = "plaid", other = 1 } } })
eq(rawget(GlassMiniMapDB, "look"), nil, "junk tints are dropped")
eq(GMM.Theme.Name(), "clear", "...clear")
GMM = loadAddon({ db = { look = "smoked", material = "glossy" } })
eq(rawget(GlassMiniMapDB, "look"), nil, "a look that isn't a table is dropped")
eq(rawget(GlassMiniMapDB, "material"), nil, "an unknown material is dropped")

GMM = loadAddon({ db = { coords = false, glassTracking = "yes", sun = false, drawer = { perRow = 9 } } })
db = GlassMiniMapDB
eq(rawget(db, "glassTracking"), nil, "a non-boolean is dropped")
eq(rawget(db, "coords"), nil, "the pre-release coords setting is dropped (Blizzard's CVar now)")
eq(db.sun, false, "a real choice is kept")
eq(rawget(db, "drawer"), nil, "a pre-release build's drawer table is dropped")
eq(GMM.Ring.Sun()._shown, false, "the saved sun setting applies at login")

done("test_db")
