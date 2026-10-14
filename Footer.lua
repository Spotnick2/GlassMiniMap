-- Footer.lua: the coordinates pill under the ring, with the zoom buttons.
--
--   [  43.2, 24.8   (-) (+) ]
--
-- Coordinates as Blizzard's own PlayerCoords computes them (Minimap.lua,
-- MinimapPlayerCoordsMixin), updated five times a second while shown; a dash
-- where the map has no position (most instances). Shown and rounded by
-- Blizzard's own settings (Options > Interface: "Player Minimap Coordinates",
-- the minimapShowPlayerCoords CVar, and "Coordinates by Tenths",
-- coordsByTenths), which the faded stock text no longer shows: one setting,
-- not two (owner, 70374). Zoom goes
-- through Minimap:SetZoom within GetZoomLevels(), and the buttons follow
-- MINIMAP_UPDATE_ZOOM (the mouse wheel zooms too).

GlassMiniMap = GlassMiniMap or {}
local GMM = GlassMiniMap
local API = GMM.API
local Glass = GMM.Glass
local Theme = GMM.Theme
local Footer = {}
GMM.Footer = Footer

Footer.HEIGHT = 22
Footer.WIDTH = 158
Footer.ZOOM_SIZE = 18
Footer.INTERVAL = 0.2

local pill, coords, zoomIn, zoomOut
local since = 0

-- "43.2, 24.8" (tenths) or "43, 25", or nil when there is no position.
function Footer.CoordText(x, y, tenths)
    if type(x) ~= "number" or type(y) ~= "number" then return nil end
    if tenths then return ("%.1f, %.1f"):format(x * 100, y * 100) end
    return ("%d, %d"):format(math.floor(x * 100 + 0.5), math.floor(y * 100 + 0.5))
end

function Footer.PlayerXY()
    local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
    mapID = ok and API.Plain(mapID) or nil
    if not mapID then return nil end
    local ok2, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if not ok2 or not pos then return nil end
    local ok3, x, y = pcall(pos.GetXY, pos)
    if not ok3 then return nil end
    return API.Plain(x), API.Plain(y)
end

function Footer.UpdateCoords()
    if not coords then return end
    local x, y = Footer.PlayerXY()
    coords:SetText(Footer.CoordText(x, y, API.CVarBool("coordsByTenths")) or "\226\128\148")   -- em dash
end

local function onUpdate(_, elapsed)
    since = since + elapsed
    if since < Footer.INTERVAL then return end
    since = 0
    Footer.UpdateCoords()
end

-- Zoom one step (+1 in, -1 out), within the client's levels.
function Footer.Zoom(step)
    local okZ, z = pcall(Minimap.GetZoom, Minimap)
    local okL, levels = pcall(Minimap.GetZoomLevels, Minimap)
    z, levels = okZ and API.Plain(z), okL and API.Plain(levels)
    if type(z) ~= "number" or type(levels) ~= "number" then return false end
    local target = math.max(0, math.min(levels - 1, z + step))
    if target == z then return false end
    Minimap:SetZoom(target)
    Footer.UpdateZoomButtons()
    return true
end

function Footer.UpdateZoomButtons()
    if not zoomIn then return end
    local okZ, z = pcall(Minimap.GetZoom, Minimap)
    local okL, levels = pcall(Minimap.GetZoomLevels, Minimap)
    z, levels = okZ and API.Plain(z), okL and API.Plain(levels)
    if type(z) ~= "number" or type(levels) ~= "number" then return end
    zoomIn:SetEnabled(z < levels - 1)
    zoomOut:SetEnabled(z > 0)
    Glass.SetSurfaceEnabled(zoomIn.glass, z < levels - 1)
    Glass.SetSurfaceEnabled(zoomOut.glass, z > 0)
end

local function zoomButton(symbol, step)
    local b = CreateFrame("Button", nil, pill)
    b:SetSize(Footer.ZOOM_SIZE, Footer.ZOOM_SIZE)
    b:SetFrameLevel(Glass.ContentLevel(pill))
    b.glass = Glass.Disc(b, "disc_small")
    b.glass.grain:SetAlpha(0)
    b.glass.shadow:SetAlpha(0)
    Theme.Register(b.glass)
    local fs = Glass.Font(b.glass.top, 15, "CENTER")
    fs:SetPoint("CENTER", b, "CENTER", 0, 1)
    fs:SetText(symbol)
    fs:SetTextColor(0.92, 0.95, 1)
    b.label = fs
    b:SetHighlightTexture(GMM.MEDIA .. "orb_mask", "ADD")
    local hl = b:GetHighlightTexture()
    if hl then hl:SetAlpha(0.2) end
    b:SetScript("OnClick", function() Footer.Zoom(step) end)
    return b
end

-- Lay the pill out for the coordinates setting: text and buttons, or buttons only.
function Footer.Layout()
    if not pill then return end
    local show = API.CVarBool("minimapShowPlayerCoords")
    local zoomW = 2 * Footer.ZOOM_SIZE + 3 + 8
    pill:SetWidth(show and Footer.WIDTH or (zoomW + 4))
    coords:SetShown(show)
    pill:SetScript("OnUpdate", show and onUpdate or nil)
    if show then Footer.UpdateCoords() end
end

function Footer.Build()
    local container, host = GMM.Ring.Container(), GMM.Ring.Host()
    pill = CreateFrame("Frame", nil, container)
    pill:SetSize(Footer.WIDTH, Footer.HEIGHT)
    -- Tucked 4 px into the ring's bottom: the quest tracker starts at the
    -- cluster's bottom edge, 14 px under the ring (measured on 70374), and a
    -- pill hanging lower sat on its header.
    pill:SetPoint("TOP", host, "BOTTOM", 0, 4)
    pill:SetFrameLevel(GMM.Ring.AboveMap(4))
    Theme.Register(Glass.Apply(pill, "small"))

    zoomIn = zoomButton("+", 1)
    zoomIn:SetPoint("RIGHT", pill, "RIGHT", -4, 0)
    zoomOut = zoomButton("\226\136\146", -1)   -- minus sign
    zoomOut:SetPoint("RIGHT", zoomIn, "LEFT", -3, 0)

    coords = Glass.Font(pill, 14, "CENTER")
    coords:SetPoint("LEFT", pill, "LEFT", 8, 0)
    coords:SetPoint("RIGHT", zoomOut, "LEFT", -4, 0)
    coords:SetTextColor(0.92, 0.94, 0.97)

    pill:SetScript("OnEvent", function(_, event, name)
        if event == "MINIMAP_UPDATE_ZOOM" then
            Footer.UpdateZoomButtons()
        elseif name == "minimapShowPlayerCoords" or name == "coordsByTenths" then
            Footer.Layout()
        end
    end)
    API.RegisterEvents(pill, { "MINIMAP_UPDATE_ZOOM", "CVAR_UPDATE" }, "coords pill")
    Footer.Layout()
    Footer.UpdateZoomButtons()
    return pill
end

function Footer.Pill() return pill end

Footer._test = {
    coords = function() return coords end, zoomIn = function() return zoomIn end,
    zoomOut = function() return zoomOut end, tick = onUpdate,
}
