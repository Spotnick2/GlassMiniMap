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
--
-- In an instance there are no coordinates, and with the pills placement (the
-- default, #27) the text shows the instance's size instead of the dash, in
-- gold with Blizzard's tooltip: "Dungeon · 5". Even with Blizzard's
-- coordinates off: the pill then widens for it.

GlassMiniMap = GlassMiniMap or {}
local GMM = GlassMiniMap
local API = GMM.API
local Theme = GMM.Theme
local Footer = {}
GMM.Footer = Footer

Footer.HEIGHT = 22
Footer.WIDTH = 158
Footer.ZOOM_SIZE = 18
Footer.INTERVAL = 0.2

local pill, coords, hit, zoomIn, zoomOut
local since = 0
local COORD_COLOR, SIZE_COLOR = { 0.92, 0.94, 0.97 }, { 1, 0.82, 0 }

-- The instance's size, when the pill shows it (Difficulty.lua takes it after
-- Blizzard's Update), else nil.
local function instanceText()
    if GMM.Settings.Indicators() == "ring" then return nil end
    return GMM.Difficulty and GMM.Difficulty.Text()
end

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
    local size = instanceText()
    local c = size and SIZE_COLOR or COORD_COLOR
    coords:SetTextColor(c[1], c[2], c[3])
    if size then return coords:SetText(size) end
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
    GMM.Glass.SetSurfaceEnabled(zoomIn.glass, z < levels - 1)
    GMM.Glass.SetSurfaceEnabled(zoomOut.glass, z > 0)
end

-- The text and the zoom buttons sit over the runic ring's vapor and runes
-- (Ring.lua, AboveMap 2 and 3), which reach EFFECT_PADDING past the ring and
-- across the pill's top since it went under the ring (#39): at the pill's own
-- content level they were dimmed by it (#42, the owner on 70450). Level with
-- the north tab, under the ring's discs and both rims.
local function contentLevel() return GMM.Ring.AboveMap(4) end

local function zoomButton(symbol, step)
    local b = CreateFrame("Button", nil, pill)
    b:SetSize(Footer.ZOOM_SIZE, Footer.ZOOM_SIZE)
    b:SetFrameLevel(contentLevel())
    b.glass = GMM.Glass.Disc(b, "disc_small")
    b.glass.grain:SetAlpha(0)
    b.glass.shadow:SetAlpha(0)
    Theme.Register(b.glass)
    local fs = GMM.Glass.Font(b.glass.top, 15, "CENTER")
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

-- Lay the pill out: text and buttons, or buttons only. The text shows the
-- coordinates (Blizzard's setting, ticking) or the instance's size (static,
-- hoverable). Called on the coordinates CVars and from Difficulty.Sync, and
-- calls UpdateCoords, never the other way round.
function Footer.Layout()
    if not pill then return end
    local size = instanceText()
    local show = size ~= nil or API.CVarBool("minimapShowPlayerCoords")
    local zoomW = 2 * Footer.ZOOM_SIZE + 3 + 8
    pill:SetWidth(show and Footer.WIDTH or (zoomW + 4))
    coords:SetShown(show)
    pill:SetScript("OnUpdate", (show and not size) and onUpdate or nil)
    hit:EnableMouse(size ~= nil)
    if GameTooltip:IsOwned(hit) then
        if size then API.Try("difficulty:tooltip", GMM.Difficulty.Tooltip, hit) else GameTooltip:Hide() end
    end
    if show then Footer.UpdateCoords() end
end

function Footer.Build()
    local container, host = GMM.Ring.Container(), GMM.Ring.Host()
    pill = CreateFrame("Frame", nil, container)
    pill:SetSize(Footer.WIDTH, Footer.HEIGHT)
    -- Tucked 4 px into the ring's bottom: the quest tracker starts at the
    -- cluster's bottom edge, 14 px under the ring (measured on 70374), and a
    -- pill hanging lower sat on its header. Drawn under the ring (#39): over
    -- it, the pill cut the ring's rim open; under it, the rim stays a closed
    -- circle and the pill tucks behind. Only the pill's top middle is under
    -- the ring: its text and zoom buttons (lifted, contentLevel) are clear of it.
    pill:SetPoint("TOP", host, "BOTTOM", 0, 4)
    pill:SetFrameLevel(math.max(0, host:GetFrameLevel() - 1))
    Theme.Register(GMM.Glass.Apply(pill, "small"))

    zoomIn = zoomButton("+", 1)
    zoomIn:SetPoint("RIGHT", pill, "RIGHT", -4, 0)
    zoomOut = zoomButton("\226\136\146", -1)   -- minus sign
    zoomOut:SetPoint("RIGHT", zoomIn, "LEFT", -3, 0)

    -- Over the text only (never the zoom buttons), mouse on while the size
    -- shows. It carries the text, so both are lifted together.
    hit = CreateFrame("Frame", nil, pill)
    hit:SetPoint("TOPLEFT", pill, "TOPLEFT", 8, 0)
    hit:SetPoint("BOTTOM", pill, "BOTTOM", 0, 0)
    hit:SetPoint("RIGHT", zoomOut, "LEFT", -4, 0)
    hit:SetFrameLevel(contentLevel())
    hit:EnableMouse(false)
    coords = GMM.Glass.Font(hit, 14, "CENTER")
    coords:SetPoint("LEFT", pill, "LEFT", 8, 0)
    coords:SetPoint("RIGHT", zoomOut, "LEFT", -4, 0)
    coords:SetTextColor(COORD_COLOR[1], COORD_COLOR[2], COORD_COLOR[3])
    hit:SetScript("OnEnter", function(self)
        if instanceText() then API.Try("difficulty:tooltip", GMM.Difficulty.Tooltip, self) end
    end)
    hit:SetScript("OnLeave", function() GameTooltip:Hide() end)

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
    zoomOut = function() return zoomOut end, tick = onUpdate, hit = function() return hit end,
}
