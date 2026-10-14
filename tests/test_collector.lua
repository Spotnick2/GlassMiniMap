-- Which minimap children are collected, and what grabbing one does to it.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local made = {}
loadAddon({ before = function()
    -- LibDBIcon buttons made before we loaded (never fire our callback).
    WoW.LDBI():Register("DBM", { icon = "dbm" }, {})
    WoW.LDBI():Register("BugSack", { icon = "bug" }, { hide = true })
    -- A hand-made button, with only OnMouseUp.
    made.alt = WoW.MinimapButton({ name = "AltStableMinimapButton", script = "OnMouseUp" })
    -- Not ours to take:
    made.zoom = WoW.MinimapButton({ name = "MinimapZoomIn" })
    made.nameless = WoW.MinimapButton({})
    made.secure = WoW.MinimapButton({ name = "SecureThing", protected = true })
    made.big = WoW.MinimapButton({ name = "BigPanel", size = 110 })
    made.dead = WoW.MinimapButton({ name = "Decoration", noClick = true })
    made.pin = WoW.MinimapButton({ name = "GatherMatePin12" })
    made.backdrop = WoW.MinimapButton({ name = "Leatrix_Backdropped", parent = MinimapBackdrop })
end })
local C = GlassMiniMap.Collector

eq(names(), "AltStableMinimapButton,LibDBIcon10_BugSack,LibDBIcon10_DBM,Leatrix_Backdropped",
   "collected, sorted by display name")
check(not entry("LibDBIcon10_GlassMiniMapBar"), "the standalone bar's launcher is never collected")
for _, k in ipairs({ "zoom", "nameless", "secure", "big", "dead", "pin" }) do
    check(not C._test.entryOf[made[k]], "not collected: " .. k)
end
eq(C.DisplayName("LibDBIcon10_DBM"), "DBM", "display name drops the LibDBIcon prefix")
eq(C.DisplayName("AltStableMinimapButton"), "AltStable", "display name drops MinimapButton")

-- Grabbed: parented to the bar, and the owner can no longer move it.
local dbm = entry("LibDBIcon10_DBM").btn
eq(dbm:GetParent(), bar(), "parented to the bar")
local before = #dbm._points
dbm:SetPoint("CENTER", Minimap, "CENTER", 1, 2)
dbm:ClearAllPoints()
dbm:SetParent(Minimap)
eq(#dbm._points, before, "owner's SetPoint/ClearAllPoints are no-ops")
eq(dbm:GetParent(), bar(), "owner's SetParent is a no-op")
eq(#dbm._drag, 0, "no longer draggable around the ring")

-- The owner's Show/Hide say whether it wants the button, and the bar follows.
eq(entry("LibDBIcon10_BugSack").wanted, false, "hidden by its own addon")
GlassMiniMap.Drawer.Open()
eq(entry("LibDBIcon10_BugSack").btn._shown, false, "an unwanted button isn't placed")
entry("LibDBIcon10_BugSack").btn:Show()
eq(entry("LibDBIcon10_BugSack").wanted, true, "owner Show recorded")
eq(entry("LibDBIcon10_BugSack").btn._shown, false, "...but nothing done inside the owner's call")
WoW.flushTimers(0)
eq(entry("LibDBIcon10_BugSack").btn._shown, true, "...and the bar placed it")
eq(entry("LibDBIcon10_BugSack").btn:IsShown(), true, "IsShown answers the owner's wish")
dbm:Hide()
WoW.flushTimers(0)
eq(dbm._shown, false, "owner Hide takes it out of the bar")
dbm:Show()
WoW.flushTimers(0)

-- LibDBIcon buttons made after us arrive through the callback.
WoW.LDBI():Register("Attune_Broker", { icon = "a" }, {})
check(entry("LibDBIcon10_Attune_Broker") ~= nil, "late LibDBIcon button collected")
-- Hand-made ones are found by the next scan (timers, or opening the bar).
WoW.MinimapButton({ name = "RXPGuidesLate" })
WoW.flushTimers()
check(entry("RXPGuidesLate") ~= nil, "late hand-made button collected by a timed scan")

-- The scan report explains the skips.
local _, rejects = C.Scan(true)
local why = {}
for _, r in ipairs(rejects) do why[r.name] = r.reason end
eq(why.MinimapZoomIn, "Blizzard", "zoom: Blizzard")
eq(why.SecureThing, "protected", "protected")
eq(why.BigPanel, "too large", "too large")
eq(why.Decoration, "not clickable", "not clickable")
eq(why.GatherMatePin12, "ignored", "ignored pattern")

-- Clicks are heard (OnClick, or OnMouseUp when that's all there is).
local heard
C.onClick = function(e, mouse) heard = e.name .. "/" .. mouse end
dbm._scripts.OnClick(dbm, "RightButton")
eq(heard, "LibDBIcon10_DBM/RightButton", "OnClick heard")
made.alt._scripts.OnMouseUp(made.alt, "LeftButton")
eq(heard, "AltStableMinimapButton/LeftButton", "OnMouseUp heard")

-- Replay clicks the button again with the same mouse button.
local alt = made.alt
alt.clicks = {}
check(C.Replay("AltStableMinimapButton", "RightButton"), "replay OnMouseUp button")
eq(alt.clicks[1], "RightButton", "replayed with the recorded mouse button")
check(not C.Replay("Gone", "LeftButton"), "replay of an unknown button is refused")

-- The glass skin: ring and disc hidden, icon enlarged and masked round;
-- turning it off gives the button its own look back.
local Orb = GlassMiniMap.Orb
check(Orb.IsSkinned(dbm), "skinned by default")
eq(dbm.border._alpha, 0, "gold ring hidden")
eq(dbm.background._alpha, 0, "dark disc hidden")
eq(dbm.icon._width, math.floor(31 * Orb.ICON_FRACTION + 0.5), "icon enlarged into the orb")
eq(#dbm.icon._masks, 1, "icon masked round")
eq(Orb._test.skins[dbm].rim._alpha, GlassMiniMap.Glass.STYLE.rimAlpha, "orb rim as soft as the panel rim")
GlassMiniMap.Drawer.Set("skin", false)
check(not Orb.IsSkinned(dbm), "unskinned")
eq(dbm.border._alpha, 1, "ring back")
eq(dbm.icon._width, 18, "icon size back")
eq(#dbm.icon._masks, 0, "mask removed")
GlassMiniMap.Drawer.Set("skin", true)
eq(#dbm.icon._masks, 1, "skin again: one mask, not two")

-- Review fixes (PR #2).

-- Drag scripts: cleared at grab, and LibDBIcon can't set them again.
eq(dbm._scripts.OnDragStart, nil, "OnDragStart cleared")
dbm:SetScript("OnDragStart", function() end)
eq(dbm._scripts.OnDragStart, nil, "owner SetScript OnDragStart refused")
dbm:HookScript("OnDragStop", function() end)
eq(dbm._scripts.OnDragStop, nil, "owner HookScript OnDragStop refused")
local enter = function() end
dbm:SetScript("OnEnter", enter)
eq(dbm._scripts.OnEnter, enter, "other scripts still go through")

-- Fields named like regions that aren't textures don't break the skin.
local odd = WoW.MinimapButton({ name = "OddMinimapButton", ring = false })
odd.border, odd.background, odd.icon = true, { 1, 0, 0 }, "icon"
C.Scan()
check(entry("OddMinimapButton") ~= nil, "odd button collected")
check(GlassMiniMap.Orb.IsSkinned(odd), "...and skinned without touching its fake regions")
eq(next(GlassMiniMap.failures), nil, "no failures from the odd fields")

-- A grab that fails half-way puts the button back where it was.
local broken = WoW.MinimapButton({ name = "BrokenMinimapButton" })
broken._scripts.OnClick = nil
broken._scripts.OnMouseUp = function() end
local W = GlassMiniMap.API.W
local origHook = W.HookScript
W.HookScript = function() error("hook refused") end
check(C.Grab(broken) == nil, "grab reports failure")
W.HookScript = origHook
eq(broken:GetParent(), Minimap, "rolled back onto the minimap")
eq(rawget(broken, "SetPoint"), nil, "overrides removed")
eq(broken._shown, true, "shown again")
check(#broken._points > 0, "points restored")
check(GlassMiniMap.failures["grab:BrokenMinimapButton"], "failure recorded")

-- Codex review (PR #2): a named frame whose CHILD button handles the click.
local parentFrame = WoW.MinimapButton({ name = "CompositeMinimapFrame", frameType = "Frame", noClick = true, ring = false })
local child = CreateFrame("Button", nil, parentFrame)
child.clicks = {}
child._scripts.OnClick = function(self, mouse) table.insert(self.clicks, mouse) end
C.Scan()
check(entry("CompositeMinimapFrame") ~= nil, "composite frame collected")
local lastHeard
C.onClick = function(e, mouse) lastHeard = e.name .. "/" .. mouse end
child:Click("LeftButton")
eq(lastHeard, "CompositeMinimapFrame/LeftButton", "a click on the child counts for the entry")
check(C.Replay("CompositeMinimapFrame", "RightButton"), "replay reports success")
eq(child.clicks[2], "RightButton", "...and the replay clicked the child")
-- Nothing to run: replay says so instead of claiming success.
child._scripts.OnClick = nil
check(not C.Replay("CompositeMinimapFrame", "LeftButton"), "replay with no handler left reports failure")

done("test_collector")
