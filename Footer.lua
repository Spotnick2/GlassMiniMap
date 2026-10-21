-- Footer.lua: the coordinates pill under the ring, with the zoom buttons.
--
--   [ (-)  43.2, 24.8  (+) ]       zoom = "pill" (the default)
--        [ 43.2, 24.8 ]            zoom = "ring": + and - are discs on the ring
--
-- The pill hangs as far under the ring as the zone pill sits over it, clear
-- of the ring and over the runic vapor, the text centered under the map
-- (#42, the owner's mockup on 70450). Tucked under the ring, it cut the rim
-- (#39) and the vapor drew over its text.
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
Footer.TEXT_WIDTH = 112      -- zoom on the ring: the text alone
Footer.GAP = 9               -- under the ring: the zone pill's gap over it (Header.lua)
Footer.ZOOM_SIZE = 18
Footer.INTERVAL = 0.2
-- Zoom on the ring: + over -, at the bottom right (the owner's mockup).
-- With the indicators on the ring, the mail disc has 135 degrees: lower down.
Footer.ZOOM_ANGLES = { pills = { 122, 138 }, ring = { 153, 167 } }
Footer.FADE_DELAY = 1        -- zoom on the ring: seconds shown after the mouse leaves
Footer.FADE_TIME = 0.25      -- ...then faded out over this

local pill, coords, hit, zoomIn, zoomOut, fader
local since = 0
local idle, fade = 0, 1
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

local function zoomButton(symbol, step)
    local b = CreateFrame("Button", nil, pill)
    b:SetSize(Footer.ZOOM_SIZE, Footer.ZOOM_SIZE)
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

local function setFade(a)
    fade = a
    zoomIn:SetAlpha(a)
    zoomOut:SetAlpha(a)
end

-- Zoom on the ring: shown while the mouse is over the ring (the map included)
-- or a disc, faded out a moment after it leaves, as Blizzard's zoom buttons
-- show and hide (Minimap.lua, MinimapMixin:OnEnter/OnLeave; the owner,
-- 70450). Faded, they keep the mouse: hovering their spot brings them back.
local function fadeTick(_, elapsed)
    local over = GMM.Ring.Host():IsMouseOver() or zoomIn:IsMouseOver() or zoomOut:IsMouseOver()
    idle = over and 0 or idle + elapsed
    local target = idle < Footer.FADE_DELAY and 1 or 0
    if fade == target then return end
    local step = elapsed / Footer.FADE_TIME
    setFade(target > fade and math.min(1, fade + step) or math.max(0, fade - step))
end

-- The zoom buttons: at the pill's ends, or discs on the ring.
local function placeZoom(onRing)
    for i, b in ipairs({ zoomIn, zoomOut }) do
        b:ClearAllPoints()
        if onRing then
            local container, host = GMM.Ring.Container(), GMM.Ring.Host()
            b:SetParent(container)
            b:SetFrameLevel(GMM.Ring.AboveMap(6))
            local rad = math.rad(Footer.ZOOM_ANGLES[GMM.Settings.Indicators()][i])
            local r = GMM.Ring.Radius() + GMM.Ring.RING_WIDTH * 0.3
            b:SetPoint("CENTER", host, "CENTER", r * math.sin(rad), r * math.cos(rad))
        else
            b:SetParent(pill)
            b:SetFrameLevel(GMM.Glass.ContentLevel(pill))
        end
    end
    if not onRing then
        zoomOut:SetPoint("LEFT", pill, "LEFT", 4, 0)
        zoomIn:SetPoint("RIGHT", pill, "RIGHT", -4, 0)
    end
    -- Shown at once either way; on the ring, fading from there.
    idle = 0
    setFade(1)
    fader:SetScript("OnUpdate", onRing and fadeTick or nil)
    -- The text between the buttons, or across the pill: centered either way.
    local left, right = onRing and pill or zoomOut, onRing and pill or zoomIn
    coords:ClearAllPoints()
    coords:SetPoint("LEFT", left, onRing and "LEFT" or "RIGHT", 4, 0)
    coords:SetPoint("RIGHT", right, onRing and "RIGHT" or "LEFT", -4, 0)
    hit:ClearAllPoints()
    hit:SetPoint("TOPLEFT", left, onRing and "TOPLEFT" or "TOPRIGHT", 4, 0)
    hit:SetPoint("BOTTOMRIGHT", right, onRing and "BOTTOMRIGHT" or "BOTTOMLEFT", -4, 0)
    hit:SetPoint("TOP", pill, "TOP", 0, 0)
    hit:SetPoint("BOTTOM", pill, "BOTTOM", 0, 0)
end

-- Lay the pill out: text and buttons, or buttons only (or, with zoom on the
-- ring, text only, else no pill). The text shows the coordinates (Blizzard's
-- setting, ticking) or the instance's size (static, hoverable). Called on the
-- coordinates CVars, from Difficulty.Sync and the zoom and indicators
-- settings, and calls UpdateCoords, never the other way round.
function Footer.Layout()
    if not pill then return end
    local size = instanceText()
    local show = size ~= nil or API.CVarBool("minimapShowPlayerCoords")
    local onRing = GMM.Settings.Zoom() == "ring"
    placeZoom(onRing)
    local zoomW = 2 * Footer.ZOOM_SIZE + 3 + 8
    if onRing then
        pill:SetWidth(Footer.TEXT_WIDTH)
    else
        pill:SetWidth(show and Footer.WIDTH or (zoomW + 4))
    end
    pill:SetShown(show or not onRing)
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
    -- Clear of the ring, so it never cuts the rim, and level with the zone
    -- pill, over the runic vapor and runes (AboveMap 2 and 3).
    pill:SetPoint("TOP", host, "BOTTOM", 0, -Footer.GAP)
    pill:SetFrameLevel(GMM.Ring.AboveMap(4))
    Theme.Register(GMM.Glass.Apply(pill, "small"))

    fader = CreateFrame("Frame", nil, container)
    zoomIn = zoomButton("+", 1)
    zoomOut = zoomButton("\226\136\146", -1)   -- minus sign

    coords = GMM.Glass.Font(pill, 14, "CENTER")
    coords:SetTextColor(COORD_COLOR[1], COORD_COLOR[2], COORD_COLOR[3])
    -- Over the text only (never the zoom buttons), mouse on while the size shows.
    hit = CreateFrame("Frame", nil, pill)
    hit:SetFrameLevel(GMM.Glass.ContentLevel(pill))
    hit:EnableMouse(false)
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
    fader = function() return fader end, fade = fadeTick,
}
