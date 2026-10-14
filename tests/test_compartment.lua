-- The AddOns compartment in the drawer: both registration paths, removal,
-- duplicates, clicks, and the coexistence gate with Glass MiniMap Bar.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GMM = loadAddon({
    before = function()
        WoW.LDBI():Register("DBM", { icon = "dbm", OnClick = function() end }, {})
        WoW.LDBI():Register("BugSack", { icon = "bug", OnClick = function() end }, { hide = true })
    end,
    -- The bulk TOC registration at PLAYER_ENTERING_WORLD (after our login).
    tocAddons = {
        { title = "|cff7fd4ffGlass|r Mail", icon = "Interface\\Icons\\INV_Letter_15" },
        { title = "Gnomesweeper", icon = "Interface\\Icons\\gnome" },
        { title = "DBM" },                        -- same name as a drawer button: a duplicate
    },
})
local C, Compartment = GMM.Collector, GMM.Compartment

-- Bulk entries arrive through the UpdateDisplay hook, reconciled next frame.
check(entry("AddOns:Glass Mail") ~= nil, "a TOC compartment entry is in the drawer (colour codes dropped)")
check(entry("AddOns:Gnomesweeper") ~= nil, "...every one of them")
eq(entry("AddOns:Glass Mail").display, "Glass Mail", "shown by its plain title")
eq(entry("AddOns:Glass Mail").btn.icon._file, "Interface\\Icons\\INV_Letter_15", "with its icon")
check(entry("AddOns:DBM") == nil, "a title matching exactly one drawer button is that button: left out")
check(GMM.Orb.IsSkinned(entry("AddOns:Gnomesweeper").btn), "compartment buttons wear the orb too")

-- A runtime RegisterAddon.
local opened = {}
AddonCompartmentFrame:RegisterAddon({ text = "Late Addon", icon = "late",
    func = function(_, input, menu) table.insert(opened, { input.buttonName, menu }) end })
WoW.flushTimers(0)
local late = entry("AddOns:Late Addon")
check(late ~= nil, "RegisterAddon at runtime reaches the drawer")
eq(late.btn.icon._file, "late", "...with its icon")

-- Click: func(nil, { buttonName = mouse }, ourButton).
late.btn:Click("RightButton")
eq(opened[1][1], "RightButton", "the entry's func hears the mouse button")
eq(opened[1][2], late.btn, "...and gets our button as the anchor (LibDBIcon's OnClick frame)")
local toc = entry("AddOns:Gnomesweeper").btn
toc:Click("LeftButton")
eq(WoW.compartmentCalls[1].title, "Gnomesweeper", "a TOC wrapper is called")
eq(WoW.compartmentCalls[1].button, "LeftButton", "...with buttonName")
eq(GMM.Drawer.DB().last.name, "AddOns:Gnomesweeper", "a compartment click counts as last used")

-- Tooltips: the entry's own, or its title.
local entered
AddonCompartmentFrame:RegisterAddon({ text = "Tippy", func = function() end,
    funcOnEnter = function(b) entered = b end, funcOnLeave = function() entered = "left" end })
WoW.flushTimers(0)
local tippy = entry("AddOns:Tippy").btn
tippy._scripts.OnEnter(tippy)
eq(entered, tippy, "funcOnEnter gets our button")
tippy._scripts.OnLeave(tippy)
eq(entered, "left", "funcOnLeave runs")
toc._scripts.OnEnter(toc)
eq(GameTooltip._lines[1], "Gnomesweeper", "no funcOnEnter: the title as tooltip")

-- LibDBIcon's own compartment entry for a button already in the drawer:
-- known identity, left out. For a button its addon hides: kept.
local lib = WoW.LDBI()
lib:AddButtonToCompartment("DBM")
lib:AddButtonToCompartment("BugSack")
WoW.flushTimers(0)
eq(entry("AddOns:DBM"), nil, "LibDBIcon's compartmentData for a shown drawer button: one button, not two")
check(entry("AddOns:BugSack") ~= nil, "...but kept when the minimap button is hidden by its addon")
local dup = Compartment._test.duplicates(Compartment.List())
check(dup[lib.objects.DBM.compartmentData], "duplicate found by identity")

-- Hidden by the user in OUR drawer: still the same button, no copy appears.
GMM.Drawer.SetHidden("LibDBIcon10_DBM", true)
WoW.flushTimers(0)
eq(entry("AddOns:DBM"), nil, "hiding the drawer button doesn't bring the compartment copy in")
GMM.Drawer.SetHidden("LibDBIcon10_DBM", false)

-- Removal (LibDBIcon removes its entry directly, then UpdateDisplay).
lib:RemoveButtonFromCompartment("BugSack")
WoW.flushTimers(0)
eq(entry("AddOns:BugSack"), nil, "a removed entry leaves the drawer")
eq(#Compartment._test.pool, 1, "its button goes back to the pool")
AddonCompartmentFrame:RegisterAddon({ text = "Reuse", func = function() end })
WoW.flushTimers(0)
eq(#Compartment._test.pool, 0, "the pool is used for the next one")

-- Ambiguous titles never dedupe: two drawer buttons named the same.
WoW.MinimapButton({ name = "TwinMinimapButton" })
WoW.MinimapButton({ name = "Twin_MinimapButton" })
C.Scan()
AddonCompartmentFrame:RegisterAddon({ text = "Twin", func = function() end })
WoW.flushTimers(0)
check(entry("AddOns:Twin") ~= nil, "an ambiguous title match keeps the compartment entry")

-- Opening the drawer reconciles too (a list changed with no UpdateDisplay).
table.insert(AddonCompartmentFrame.registeredAddons, { text = "Sneaky", func = function() end })
GMM.Drawer.Open()
check(entry("AddOns:Sneaky") ~= nil, "opening the drawer catches an entry added without UpdateDisplay")

-- Blizzard's AddOns button is out of sight while the drawer lists its entries.
check(GMM.Blizzard._test.compartment().IsHidden(), "the AddOns button is hidden")
eq(next(GMM.failures), nil, "no failures")

-- Coexistence: with the standalone Glass MiniMap Bar loaded, our drawer stays
-- off and Blizzard's AddOns button stays put; its settings are copied once.
local old = { perRow = 7, hidden = { LibDBIcon10_DBM = true }, order = { "LibDBIcon10_DBM" }, openOn = "click",
              minimap = { minimapPos = 200 } }
GMM = loadAddon({ barLoaded = true, barDB = old, tocAddons = { { title = "Gnomesweeper" } } })
check(not GMM.Drawer.IsActive(), "drawer off beside Glass MiniMap Bar")
eq(GMM.Drawer.Launcher(), nil, "...no launcher disc")
eq(AddonCompartmentFrame:GetParent(), MinimapCluster, "...Blizzard's AddOns button left where it is")
local d = GlassMiniMapDB.drawer
eq(d.imported, true, "settings imported")
eq(d.perRow, 7, "...perRow")
eq(d.openOn, "click", "...openOn")
eq(d.hidden.LibDBIcon10_DBM, true, "...the hidden list")
check(d.hidden ~= old.hidden, "...copied, not shared")
eq(d.minimap, nil, "...not the launcher's ring position (no LibDBIcon launcher here)")
check(table.concat(WoW.chat, "\n"):find("disable Glass MiniMap Bar", 1, true), "the player is told what to do")

-- Next session, still both enabled: no second import, a quieter note at most once.
local saved = GlassMiniMapDB
saved.drawer.perRow = 9
GMM = loadAddon({ barLoaded = true, db = saved, barDB = old })
eq(GlassMiniMapDB.drawer.perRow, 9, "no second import over the player's own changes")
check(not table.concat(WoW.chat, "\n"):find("copied", 1, true), "...and no second import message")

-- Bar disabled: the drawer runs with the imported settings.
GMM = loadAddon({ db = saved })
check(GMM.Drawer.IsActive(), "drawer on once Glass MiniMap Bar is disabled")
eq(GMM.Drawer.DB().perRow, 9, "...with the settings carried over")

done("test_compartment")
