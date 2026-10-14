-- The LFG eye (QueueStatusButton): mirrored from Blizzard's bottom-left
-- default to the top left, the porting guide's way, with a glass disc of ours
-- behind it, shown and scaled with it (#4).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GMM = loadAddon()
local eye = QueueStatusButton
local function at()
    local p = eye._points[1]
    return p[1], p[2], p[3], p[4], p[5]
end

-- Mirrored at login, on the next frame (never inside Blizzard's call).
local point, rel, relPoint, x, y = at()
eq(rel, Minimap, "still anchored to the minimap")
eq(x, -68, "same side (left)")
eq(y, 68, "mirrored to the top: the day/night disc's mirror image")
eq(#eye._points, 1, "one point")
check((eye._baseMoves or 0) >= 1, "moved with SetPointBase, not Edit Mode's override")

-- Blizzard places it again (ApplySystemAnchor, a minimap scale change):
-- flipped again on the next frame, not inside the call.
eye:UpdateDefaultAnchor()
eq(select(5, at()), -68, "Blizzard's own call puts it back (untouched inside it)")
WoW.flushTimers(0)
eq(select(5, at()), 68, "...and the next frame mirrors it again")

-- A minimap scale change: Blizzard calls its EventRegistry copy, which the
-- hook doesn't wrap; our own callback mirrors it again (Codex, PR #11).
EventRegistry:TriggerEvent("Minimap.OnScaleUpdated", 1.2)
eq(select(5, at()), -68, "the scale callback puts it back")
WoW.flushTimers(0)
eq(select(5, at()), 68, "...and the next frame mirrors it again")

-- Edit Mode open: hands off (the player sees Blizzard's default there).
EditModeManagerFrame = CreateFrame("Frame", "EditModeManagerFrame", UIParent)
eye:UpdateDefaultAnchor()
WoW.flushTimers(0)
eq(select(5, at()), -68, "Edit Mode open: not moved")
EditModeManagerFrame:Hide()
WoW.flushTimers(0)
check(GMM.Queue.Mirror(), "Edit Mode closed: mirrored")
eq(select(5, at()), 68, "...at the top left")
EditModeManagerFrame = nil

-- A player who placed the eye in Edit Mode keeps their spot.
eye.inDefault = false
eye:ClearAllPoints(); eye:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 300, -200)
eye:UpdateDefaultAnchor()
eye:ClearAllPoints(); eye:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 300, -200)
WoW.flushTimers(0)
eq(select(2, at()), UIParent, "placed by the player: never touched")
eye.inDefault = true

-- In combat, a protected eye waits for combat to end.
eye:UpdateDefaultAnchor()
WoW.combat, eye._protected = true, true
WoW.flushTimers(0)
eq(select(5, at()), -68, "in combat and protected: not moved")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
WoW.flushTimers(0)
eq(select(5, at()), 68, "after combat: mirrored")
eye._protected = nil

-- The glass disc: hidden until queued, centred on the eye, under it, its scale.
local d = GMM.Queue.Disc()
check(d ~= nil, "the eye's glass disc is built")
eq(d._shown, false, "not queued: hidden, like the eye")
eq(d._parent, UIParent, "on UIParent, like the eye")
eq(d._points[1][2], eye, "centred on the eye (follows it wherever it goes)")
eq(d._mouse, false, "takes no clicks: they're the eye's")
eye:Show()
eq(d._shown, true, "queued: shown with the eye")
check(d._level < eye.Eye._level, "...under the eye's art (Eye, at button - 1)")
check(GMM.Queue.Glass().top._level < eye.Eye._level, "...its rims too (g.top, not host + 10)")
eye:SetScale(1.3)
eq(d._scale, 1.3, "Edit Mode's scale followed")
eye:Hide()
eq(d._shown, false, "leaving the queue: hidden with it")

-- Themed like every other surface.
GMM.Settings.SetTheme("smoked")
local found = false
for _, s in ipairs(GMM.Theme._test.surfaces) do
    if s.g.tint and s.g.tint._parent == d and s.g.tint._color[4] == 0.62 then found = true end
end
check(found, "the eye's disc takes the theme")
eq(next(GMM.failures), nil, "no failures")

-- A client without the eye: nothing built, nothing failed.
GMM = loadAddon({ before = function() QueueStatusButton = nil end })
eq(GMM.Queue.Disc(), nil, "no eye: no disc")
eq(next(GMM.failures), nil, "...and no failure")

done("test_queue")
