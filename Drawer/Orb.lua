-- Orb.lua: the glass material on a round button.
--
-- Minimap buttons are circles, so the panel material (9-sliced rounded rects,
-- Glass.lua) doesn't fit them. The orb is the same recipe drawn on a circle:
-- a masked cool tint and a top-down white wash behind the icon, the icon
-- masked round, then a dark hairline and the lit rim over it. Textures come
-- from Tools/make_art.py and are this addon's own, in its Media\
-- (Glass.MEDIA is LibGlass's folder: the panel textures only).
--
-- Skinning someone else's button only ADDS regions and hides two of theirs
-- (the gold tracking border and the dark disc). Unskin() puts both back, so
-- the option can be turned off without a reload.
--
-- Glass MiniMap Bar's Orb.lua. The one change: each orb's tint and wash
-- register with Theme, so the drawer's buttons follow clear / smoked / class.

GlassMiniMap = GlassMiniMap or {}
local Orb = {}
GlassMiniMap.Orb = Orb
local Glass = GlassMiniMap.Glass

Orb.MEDIA = GlassMiniMap.MEDIA

local MASK_WRAP = "CLAMPTOBLACKADDITIVE"
Orb.ICON_FRACTION = 0.70      -- icon diameter as a share of the button
local BORDER_IDS = { [136430] = true }      -- Interface\Minimap\MiniMap-TrackingBorder
local BACKGROUND_IDS = { [136467] = true }  -- Interface\Minimap\UI-Minimap-Background

local function lower(v) return type(v) == "string" and v:lower() or nil end

-- A hand-made button may carry fields named border/background/icon that are
-- anything but textures (a flag, a colour table): only take real ones.
local function isTexture(r)
    if type(r) ~= "table" or type(r.IsObjectType) ~= "function" then return nil end
    local ok, yes = pcall(r.IsObjectType, r, "Texture")
    return (ok and yes) and r or nil
end

-- Which of a button's textures are its border, its background and its icon.
-- LibDBIcon names them (border, background, icon); anything else is found the
-- way HidingBar does: by file, by region key, then by "icon" in the path.
function Orb.Regions(btn)
    local border, background, icon = btn.border, btn.background, btn.icon
    local ok, regions = pcall(function() return { btn:GetRegions() } end)
    if not ok then regions = {} end
    for _, r in ipairs(regions) do
        if r:IsObjectType("Texture") then
            local tex = r:GetTexture()
            local path = lower(tex)
            if not border and (BORDER_IDS[tex] or path and path:find("minimap-trackingborder", 1, true)) then
                border = r
            elseif not background and (BACKGROUND_IDS[tex] or path and path:find("ui-minimap-background", 1, true)) then
                background = r
            elseif not icon and path and path:find("icon", 1, true) then
                icon = r
            end
        end
    end
    return isTexture(border), isTexture(background), isTexture(icon)
end

-- The icon to show for a button elsewhere (the launcher's "last used" face):
-- file or atlas, plus texcoords. nil when the button has no readable icon.
function Orb.IconOf(btn)
    local _, _, icon = Orb.Regions(btn)
    if not icon and btn.GetNormalTexture then icon = btn:GetNormalTexture() end
    if not icon then return nil end
    local atlas = icon.GetAtlas and icon:GetAtlas()
    local file = icon:GetTexture()
    if not atlas and not file then return nil end
    return { atlas = atlas, file = file, coords = { icon:GetTexCoord() } }
end

-- Build the orb's own regions on `btn` once. Draw layers: body under the
-- button's ARTWORK icon, rim over everything the button draws.
local function build(btn)
    local s = {}
    local sh = btn:CreateTexture(nil, "BACKGROUND", nil, -8)
    sh:SetTexture(Orb.MEDIA .. "orb_shadow")
    sh:SetPoint("CENTER", btn, "CENTER", 0, -1)
    s.shadow = sh

    local m = btn:CreateMaskTexture()
    m:SetTexture(Orb.MEDIA .. "orb_mask", MASK_WRAP, MASK_WRAP)
    m:SetAllPoints(btn)
    s.mask = m

    local st = Glass.STYLE
    local tint = btn:CreateTexture(nil, "BACKGROUND", nil, -6)
    tint:SetAllPoints(btn)
    tint:SetColorTexture(st.tint[1], st.tint[2], st.tint[3], math.max(st.tint[4], 0.35))
    tint:AddMaskTexture(m)
    s.tint = tint

    local wash = btn:CreateTexture(nil, "BACKGROUND", nil, -5)
    wash:SetAllPoints(btn)
    wash:SetColorTexture(1, 1, 1, 1)
    wash:SetGradient("VERTICAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, st.wash))
    wash:AddMaskTexture(m)
    s.wash = wash

    local dark = btn:CreateTexture(nil, "OVERLAY", nil, 6)
    dark:SetTexture(Orb.MEDIA .. "orb_dark")
    dark:SetAllPoints(btn)
    s.dark = dark

    local rim = btn:CreateTexture(nil, "OVERLAY", nil, 7)
    rim:SetTexture(Orb.MEDIA .. "orb_rim")
    rim:SetAllPoints(btn)
    rim:SetAlpha(Glass.STYLE.rimAlpha or 1)   -- the same softened rim as the panels
    s.rim = rim

    -- The icon's own round mask, sized with the icon in Orb.Skin.
    local im = btn:CreateMaskTexture()
    im:SetTexture(Orb.MEDIA .. "orb_mask", MASK_WRAP, MASK_WRAP)
    s.iconMask = im
    return s
end

local skins = setmetatable({}, { __mode = "k" })   -- btn -> skin state, never a field on their frame

-- Skin `btn` at its own unscaled width (the bar scales the whole button).
-- Safe to call again.
function Orb.Skin(btn)
    local s = skins[btn]
    local w = btn:GetWidth()
    if type(w) ~= "number" or w <= 0 then w = 31 end
    if not s then
        s = build(btn)
        GlassMiniMap.Theme.Register({ tint = s.tint, wash = s.wash }, "orb")
        local border, background, icon = Orb.Regions(btn)
        s.border, s.background, s.icon = border, background, icon
        if icon then
            s.iconPoints = {}
            for i = 1, icon:GetNumPoints() do s.iconPoints[i] = { icon:GetPoint(i) } end
            s.iconSize = { icon:GetSize() }
        end
        skins[btn] = s
    end
    s.shadow:SetSize(w * 1.5, w * 1.5)
    for _, k in ipairs({ "shadow", "tint", "wash", "dark", "rim" }) do s[k]:Show() end
    if s.border then s.border:SetAlpha(0) end
    if s.background then s.background:SetAlpha(0) end
    local icon = s.icon
    if icon then
        local d = math.floor(w * Orb.ICON_FRACTION + 0.5)
        icon:ClearAllPoints()
        icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
        icon:SetSize(d, d)
        s.iconMask:ClearAllPoints()
        s.iconMask:SetPoint("CENTER", btn, "CENTER", 0, 0)
        s.iconMask:SetSize(d, d)
        if not s.masked then
            icon:AddMaskTexture(s.iconMask)
            s.masked = true
        end
    end
    s.on = true
end

-- Put the button's own look back.
function Orb.Unskin(btn)
    local s = skins[btn]
    if not (s and s.on) then return end
    for _, k in ipairs({ "shadow", "tint", "wash", "dark", "rim" }) do s[k]:Hide() end
    if s.border then s.border:SetAlpha(1) end
    if s.background then s.background:SetAlpha(1) end
    local icon = s.icon
    if icon then
        if s.masked then
            icon:RemoveMaskTexture(s.iconMask)
            s.masked = false
        end
        icon:ClearAllPoints()
        for _, p in ipairs(s.iconPoints) do icon:SetPoint(unpack(p)) end
        if s.iconSize[1] then icon:SetSize(s.iconSize[1], s.iconSize[2]) end
    end
    s.on = false
end

function Orb.IsSkinned(btn)
    return skins[btn] ~= nil and skins[btn].on == true
end

Orb._test = { skins = skins }
