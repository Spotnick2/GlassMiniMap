-- The glass tracking menu: what it lists (Blizzard's rules), what a click
-- does, the predicted state, and the fallbacks to Blizzard's own menu.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GMM = loadAddon()
local T = GMM.Tracking

local function rowNames()
    local t = {}
    for _, r in ipairs(T.Rows()) do t[#t + 1] = r.kind == "entry" and r.name or ("[" .. r.kind .. "]") end
    return table.concat(t, ",")
end

-- Filters: OPTIONAL_FILTERS[filterID] or a spellID. Quest POIs (false in
-- OPTIONAL), Target and the unknown filter are not listed.
eq(rowNames(), "[uncheck],Auctioneer,Innkeeper,Find Herbs", "listed as Blizzard lists them")
local herbs
for _, r in ipairs(T.Rows()) do if r.name == "Find Herbs" then herbs = r end end
eq(herbs.atlas, "professions_tracking_herb", "Find Herbs takes Blizzard's override atlas")

-- Show all: everything, no Uncheck All, townsfolk under a heading.
WoW.cvars.minimapTrackingShowAll = true
eq(rowNames(), "[heading],Auctioneer,Innkeeper,Find Herbs,Quest POIs,Target,Hidden thing",
   "show-all: every entry, townsfolk under their heading, no Uncheck All")
WoW.cvars.minimapTrackingShowAll = false

-- Hunters: their own tracking under a heading only when there is more than one.
WoW.class = "HUNTER"
WoW.tracking[3].subType = 1
eq(rowNames(), "[uncheck],Find Herbs,Auctioneer,Innkeeper", "one hunter entry: first, no heading")
table.insert(WoW.tracking, { name = "Track Beasts", texture = 7, active = false, type = "spell", subType = 1, spellID = 1494 })
eq(rowNames(), "[uncheck],[heading],Find Herbs,Track Beasts,Auctioneer,Innkeeper", "two: under a heading")
check(T.Rows()[3].indent, "...indented")
table.remove(WoW.tracking)
WoW.tracking[3].subType = -1
WoW.class = "MAGE"

-- Low-priority spells sort last.
table.insert(WoW.tracking, 1, { name = "Track Warboards", texture = 8, active = false, type = "spell",
                                subType = -1, spellID = 261764 })
eq(rowNames(), "[uncheck],Auctioneer,Innkeeper,Find Herbs,Track Warboards", "low priority last")
table.remove(WoW.tracking, 1)

-- Opening from the magnifier.
local mag = GMM.Header._test.tracking()
mag:Click("LeftButton")
check(T.IsOpen(), "the magnifier opens the glass menu")
local rows = T._test.rows
eq(rows[1].label._text, "Uncheck All", "first row: Uncheck All")
eq(rows[3].label._text, "Innkeeper", "rows in order")
eq(rows[3].check._shown, true, "an active filter is checked")
eq(rows[2].check._shown, false, "an inactive one isn't")
eq(rows[4].icon._atlas, "professions_tracking_herb", "Find Herbs drawn from its override atlas")
check(UISpecialFrames[1] == T.NAME, "Escape closes it (UISpecialFrames, by name)")

-- A click goes through MinimapUtil, and the clicked state holds while open.
rows[2]:Click("LeftButton")
eq(WoW.trackingCalls[1][1], "util", "through MinimapUtil.SetTrackingFilterByFilterIndex")
eq(WoW.trackingCalls[1][3], true, "...turning Auctioneer on")
eq(rows[2].check._shown, true, "checked at once")
-- A spell that hasn't taken effect yet stays as clicked while the menu is open.
rows[4]:Click("LeftButton")                      -- Find Herbs off
WoW.tracking[3].active = true                    -- the client still says on
WoW.fire("MINIMAP_UPDATE_TRACKING")
eq(rows[4].check._shown, false, "predicted state survives a tracking update while open")
T.Close()
mag:Click("LeftButton")
eq(T._test.rows[4].check._shown, true, "reopened: the real state again")

-- Uncheck All: clear, then the always-on and conditional filters back on.
WoW.trackingCalls = {}
rows[1]:Click("LeftButton")
eq(WoW.trackingCalls[1][1], "clear", "ClearAllTracking first")
local back = {}
for _, c in ipairs(WoW.trackingCalls) do if c[1] == "util" then back[#back + 1] = c[2] end end
eq(table.concat(back, ","), "4,5", "then Quest POIs and Target back on")
eq(rows[3].check._shown, false, "everything optional unchecked")

-- Outside click closes; a click inside doesn't.
WoW.mouseOver[T._test.popup()] = true
WoW.fire("GLOBAL_MOUSE_DOWN", "LeftButton")
check(T.IsOpen(), "a click inside keeps it")
WoW.mouseOver[T._test.popup()] = nil
WoW.fire("GLOBAL_MOUSE_DOWN", "LeftButton")
check(not T.IsOpen(), "a click elsewhere closes it")
eq(next(T._test.popup()._events), nil, "no events while closed")

-- Right-click: Blizzard's own menu, always.
mag:Click("RightButton")
eq(WoW.blizzardMenuOpened, 1, "right-click opens Blizzard's menu")
check(not T.IsOpen(), "...not ours")
-- With the glass menu turned off, the left click is Blizzard's too.
GMM.Settings.Set("glassTracking", false)
mag:Click("LeftButton")
eq(WoW.blizzardMenuOpened, 2, "glass menu off: Blizzard's menu on left-click")
check(not T.IsOpen(), "...and ours stays closed")
GMM.Settings.Set("glassTracking", true)

eq(next(GMM.failures), nil, "no failures")
done("test_tracking")
