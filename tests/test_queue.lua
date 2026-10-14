-- The LFG eye (QueueStatusButton): left where Blizzard puts it, with a glass
-- disc of ours behind it, shown and scaled with it (#4).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GMM = loadAddon()
local eye = QueueStatusButton
local d = GMM.Queue.Disc()
check(d ~= nil, "the eye's glass disc is built")
eq(d._shown, false, "not queued: hidden, like the eye")
eq(d._parent, UIParent, "on UIParent, like the eye")
local p = d._points[1]
eq(p[1], "CENTER", "centred...")
eq(p[2], eye, "...on the eye")
eq(d._mouse, false, "takes no clicks: they're the eye's")
eq(#eye._points, 1, "the eye itself is never moved")

eye:Show()
eq(d._shown, true, "queued: shown with the eye")
eq(d._level, eye._level - 1, "...one level under it")
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

-- A client without the eye: nothing built, nothing failed.
QueueStatusButton = nil
GMM = loadAddon({ before = function() QueueStatusButton = nil end })
eq(GMM.Queue.Disc(), nil, "no eye: no disc")
eq(next(GMM.failures), nil, "...and no failure")

done("test_queue")
