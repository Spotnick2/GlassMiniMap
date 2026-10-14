-- Blizzard.lua: Blizzard's own minimap art steps aside for the glass.
--
-- The minimap cluster is an Edit Mode system and a taint minefield (porting
-- guide, "Edit Mode systems"). So nothing here moves, reparents or Hide()s
-- Minimap or MinimapCluster, and no Blizzard method or global is replaced:
-- each stock piece our glass replaces is FADED (API.Fade: alpha 0, mouse
-- off, re-faded when Blizzard shows it again). Its code keeps running where
-- Blizzard put it; Edit Mode keeps moving and scaling the cluster, and our
-- frames, parented to the map's container, follow.
--
-- Pieces we replace, by parentKey or by the global the client names:
--   compass ring art      MinimapCompassTexture (+ Underlay), MinimapBackdrop.StaticOverlayTexture
--   zone header           MinimapCluster.BorderTop, .ZoneTextButton
--   tracking button       MinimapCluster.Tracking and .Tracking.Button (mouse off on the
--                         button itself: an invisible dropdown must not take clicks;
--                         its menu still opens from our right-click)
--   zoom                  Minimap.ZoomIn / ZoomOut / ZoomHitArea (the wheel still zooms)
--   coordinates           MinimapCluster.MinimapContainer.PlayerCoords
--   calendar              GameTimeFrame
--   day/night ring        MinimapCluster.DielFrame (Forever's Camelot\Diel.lua)
--   new mail              MinimapCluster.IndicatorFrame.MailFrame (hung under the faded
--                         tracking button, over our zone pill; Mail.lua shows it in glass)
--   instance difficulty   MinimapCluster.InstanceDifficulty and its .Guild banner (both take
--                         the mouse). Forever has no difficulties: in an instance it shows
--                         only the group size (Camelot\InstanceDifficultyOverrides.lua),
--                         hung from the faded header over the right end of our zone pill.
--                         Not replaced (owner, #18).
-- Left alone: QueueStatusButton (its own Edit Mode system), the crafting-order
-- indicator, the clock, and
-- AddonCompartmentFrame (the "AddOns" button: Glass MiniMap Bar, when
-- installed, lists its entries and hides it; Glass MiniMap never touches it).
--
-- The map's mask is Blizzard's own round one (ui-hud-minimap-frame-generic-mask,
-- re-applied by Camelot\Skin.lua on every rotateMinimap change): the glass
-- ring is built to its 198 px circle, so it is not replaced.

GlassMiniMap = GlassMiniMap or {}
local GMM = GlassMiniMap
local API = GMM.API
local Blizzard = {}
GMM.Blizzard = Blizzard

-- Resolvers: a missing piece (another client build) is skipped, not an error.
local function cluster() return rawget(_G, "MinimapCluster") end
local function key(root, ...)
    local t = root
    for i = 1, select("#", ...) do
        if type(t) ~= "table" then return nil end
        t = t[select(i, ...)]
    end
    return t
end

Blizzard.FADED = {
    { "compass",       function() return rawget(_G, "MinimapCompassTexture") end },
    { "compass under", function() return rawget(_G, "MinimapCompassTextureUnderlay") end },
    { "static overlay", function() return key(rawget(_G, "MinimapBackdrop"), "StaticOverlayTexture") end },
    { "border top",    function() return key(cluster(), "BorderTop") end },
    { "zone text",     function() return key(cluster(), "ZoneTextButton") end },
    { "tracking",      function() return key(cluster(), "Tracking") end },
    { "tracking button", function() return key(cluster(), "Tracking", "Button") end },
    { "zoom in",       function() return key(rawget(_G, "Minimap"), "ZoomIn") end },
    { "zoom out",      function() return key(rawget(_G, "Minimap"), "ZoomOut") end },
    { "zoom hit area", function() return key(rawget(_G, "Minimap"), "ZoomHitArea") end },
    { "coords",        function() return key(cluster(), "MinimapContainer", "PlayerCoords") end },
    { "calendar",      function() return rawget(_G, "GameTimeFrame") end },
    { "day cycle",     function() return key(cluster(), "DielFrame") end },
    { "mail",          function() return key(cluster(), "IndicatorFrame", "MailFrame") end },
    { "difficulty",    function() return key(cluster(), "InstanceDifficulty") end },
    { "guild difficulty", function() return key(cluster(), "InstanceDifficulty", "Guild") end },
}

-- Fade every piece we replace. Returns how many were found.
function Blizzard.Start()
    local n = 0
    for _, piece in ipairs(Blizzard.FADED) do
        local ok, region = pcall(piece[2])
        if ok and region then
            if API.Try("fade:" .. piece[1], API.Fade, region) then n = n + 1 end
        end
    end
    Blizzard.faded = n
    return n
end

-- The tracking dropdown's own menu (the glass menu's fallback, and right-click).
function Blizzard.TrackingButton()
    return key(cluster(), "Tracking", "Button")
end

function Blizzard.OpenTrackingMenu(anchor)
    local b = Blizzard.TrackingButton()
    if not (b and b.OpenMenu) then return false end
    if anchor and b.SetMenuAnchor and rawget(_G, "AnchorUtil") and AnchorUtil.CreateAnchor then
        pcall(b.SetMenuAnchor, b, AnchorUtil.CreateAnchor("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2))
    end
    return pcall(b.OpenMenu, b) and true or false
end

-- Where our glass frames live: the container Blizzard scales with Edit Mode.
function Blizzard.Container()
    return key(cluster(), "MinimapContainer") or (rawget(_G, "Minimap") and Minimap:GetParent())
end
