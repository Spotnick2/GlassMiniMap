-- The drawer: Glass MiniMap Bar's bar on our bottom-left disc, through its
-- public API (version 1); nothing without it, or with another version.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- Without Glass MiniMap Bar: no disc, no failure, Blizzard's AddOns button untouched.
local GMM = loadAddon()
eq(disc(), nil, "no Glass MiniMap Bar: no disc")
eq(next(GMM.failures), nil, "...and nothing to report")
eq(AddonCompartmentFrame:GetParent(), MinimapCluster, "the AddOns button is never ours")

-- With it: the disc is its launcher.
GMM = loadAddon({ gmb = true })
local gmb = GlassMiniMapBar
local d = disc()
check(d ~= nil, "Glass MiniMap Bar: the disc is there")
eq(gmb.launcher, d, "...handed to UseLauncher")
local p = d._points[1]
check(p[4] > 0 and p[5] < 0, "...at the bottom right of the ring (the eye has the bottom left: #4)")
near(p[4], -p[5], "...at 135 degrees")
check(GMM.Drawer.IsActive(), "the drawer is active")
eq(AddonCompartmentFrame:GetParent(), MinimapCluster, "Glass MiniMap itself still never touches the AddOns button")

-- Its scripts call the API's handlers with the disc.
d:Click("RightButton")
d._scripts.OnEnter(d)
d._scripts.OnLeave(d)
eq(gmb.calls[1][1], "click", "a click goes to LauncherClick")
eq(gmb.calls[1][2], d, "...with the disc")
eq(gmb.calls[1][3], "RightButton", "...and the mouse button")
eq(gmb.calls[2][1], "enter", "hover: LauncherEnter")
eq(gmb.calls[3][1], "leave", "leaving: LauncherLeave")

-- The face the bar sends.
eq(d.icon._file, "Interface\\Icons\\misc_arrowleft", "the bar's arrow on the disc")
eq(d.icon._coords[1], 0.08, "...cropped inside the round mask")
gmb.opts.setIcon("Interface\\Icons\\DBM", { 0.1, 0.9, 0.2, 0.8 })
eq(d.icon._file, "Interface\\Icons\\DBM", "the last button used")
eq(d.icon._coords[3], 0.2, "...with its own coords")

-- Our theme reaches the bar's glass.
eq(gmb.tint.n, 0, "clear: the bar as built (SetGlassTint with no arguments)")
GMM.Settings.SetTheme("smoked")
eq(gmb.tint[4], 0.62, "smoked: the smoked body")
near(gmb.tint[5], 0.14 / 0.18, "...and its wash multiplier")
GMM.Settings.SetTheme("class")
near(gmb.tint[1], 0.25 * 0.6, "class: the shaded class colour")
eq(gmb.tint[4], nil, "...keeping each surface's own alpha")
eq(gmb.tint[5], 1, "...and the built wash")
GMM.Settings.SetTheme("clear")
eq(gmb.tint.n, 0, "clear again: as built")

-- The options page's button opens Glass MiniMap Bar's page.
GMM.Options._test.panel:Show()
local b = GMM.Options._test.drawerButton
eq(b._shown, true, "the Drawer options button shows")
b:Click("LeftButton")
eq(gmb.optionsOpened, 1, "...and opens Glass MiniMap Bar's options")

-- Another API version: no disc, and /gmm failures says why.
GMM = loadAddon({ gmb = 2 })
eq(disc(), nil, "an API version we don't speak: no disc")
check(GMM.failures.drawer and GMM.failures.drawer:find("version 2", 1, true), "...and the failure says which version")
GMM.Options._test.panel:Show()
eq(GMM.Options._test.drawerButton._shown, false, "...no Drawer options button")

done("test_drawer")
