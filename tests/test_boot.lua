-- Boot: every piece builds at login with no failure, and Blizzard's art steps aside.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GMM = loadAddon()
eq(next(GMM.failures), nil, "no failures at login")
for k, v in pairs(GMM.failures) do io.write("    " .. k .. ": " .. v .. "\n") end
check(GMM.Ring.Host() ~= nil, "the ring is built")
check(GMM.Header.Pill() ~= nil, "the zone pill is built")
check(GMM.Footer.Pill() ~= nil, "the coords pill is built")
check(GMM.Tracking._test.popup() ~= nil, "the tracking menu is built")
check(not GMM.Drawer.IsActive(), "no drawer without Glass MiniMap Bar")
eq(disc(), nil, "...and no disc")

-- Faded, never hidden or moved.
eq(MinimapCompassTexture._alpha, 0, "compass art faded")
eq(MinimapCompassTexture._shown, true, "...not hidden")
eq(MinimapCluster.Tracking.Button._mouse, false, "the tracking dropdown takes no clicks")
eq(MinimapCluster.ZoneTextButton._alpha, 0, "zone header faded")
eq(MinimapCluster.MinimapContainer.PlayerCoords._alpha, 0, "Blizzard's coords faded")
eq(GameTimeFrame._alpha, 0, "calendar faded")
eq(GameTimeFrame._mouse, false, "...and takes no clicks")
eq(MinimapCluster.DielFrame._alpha, 0, "day/night ring faded")
eq(Minimap:GetParent(), MinimapCluster.MinimapContainer, "the map stays in its container")
eq(#Minimap._points, 0, "the map is never re-anchored")
-- Blizzard showing a piece again: faded again.
Minimap.ZoomIn:Hide(); Minimap.ZoomIn:Show()
eq(Minimap.ZoomIn._alpha, 0, "zoom button re-faded after Blizzard shows it")
Minimap.ZoomIn:SetAlpha(1)
eq(Minimap.ZoomIn._alpha, 0, "...and after Blizzard fades it in")

-- Blizzard's AddOns button is never ours to touch.
eq(AddonCompartmentFrame:GetParent(), MinimapCluster, "the AddOns button stays where Blizzard put it")
eq(AddonCompartmentFrame._alpha, 1, "...as it was")

-- Our frames live in the container Edit Mode scales.
eq(GMM.Ring.Host():GetParent(), MinimapCluster.MinimapContainer, "ring parented to the container")
eq(GMM.Ring.Host()._width, 198 + 2 * GMM.Ring.RING_WIDTH, "ring: the map plus the glass")
eq(GMM.Ring.Host()._level, Minimap._level - 1, "ring under the map")
eq(GMM.Header.Pill():GetParent(), MinimapCluster.MinimapContainer, "zone pill in the container")

done("test_boot")
