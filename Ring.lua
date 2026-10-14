-- Ring.lua: the glass ring around the map, the north tab, and the discs that
-- sit on the ring (the day/night disc here, the drawer's launcher in
-- Drawer/Bar.lua).
--
-- The ring is ONE LibGlass disc behind the map: a square host the map's size
-- plus RING_WIDTH on every side, centred on Minimap, one level under it. The
-- map is opaque and masked round by Blizzard's own mask, so it covers the
-- disc's centre and only a glass ring shows. Our rim art (Media\ring_rim,
-- ring_dark, from Tools/make_art.py) replaces the disc's: g.top sits ABOVE the
-- map (host level + 10), so that art is perimeter-only, with a clear centre.
--
-- Parenting: everything here is a child of MinimapCluster.MinimapContainer,
-- the frame Edit Mode scales, so it inherits the minimap's scale and strata
-- (LOW). The host is sized once; a later scale arrives through the parent and
-- never needs a SetSize (LibGlass: a disc is resized with SetScale only).

GlassMiniMap = GlassMiniMap or {}
local GMM = GlassMiniMap
local API = GMM.API
local Glass = GMM.Glass
local Theme = GMM.Theme
local Ring = {}
GMM.Ring = Ring

Ring.RING_WIDTH = 10          -- glass between the map's edge and the ring's outer edge
Ring.MAP_SIZE = 198           -- Blizzard's Minimap (Minimap.xml); the art is drawn for this ratio
Ring.DISC_SIZE = 30           -- the discs on the ring (sun, launcher)
Ring.FOG_PADDING = 18        -- exterior vapor; matches Tools/make_art.py

local host, glass, notch, container
local runes, runeAnimation
local runeLayers = {}
local runeStyle, runeMotion = "etched", "sway"
local fog, fogAnimation
local runeBloom
local runeLight, runeMist
local etchedBase
local fogEnabled = false
local previewEnabled = false

-- Runic mode. The map can hide independently of its
-- container (Blizzard's ToggleMinimap), so watch both effective visibilities.
local function syncRunes()
    if not runes then return end
    runes:SetShown(previewEnabled and Minimap:IsVisible())
    for _, layer in ipairs(runeLayers) do
        if runes:IsVisible() then
            if not layer.animation:IsPlaying() then layer.animation:Play() end
        else
            layer.animation:Stop()
        end
    end
    fog:SetShown(fogEnabled)
    if runes:IsVisible() and fogEnabled then
        if not fogAnimation:IsPlaying() then fogAnimation:Play() end
    else fogAnimation:Stop() end
end

local function paintRunes()
    -- Effects share the theme's hue, but light needs a brighter colour than
    -- the shaded glass body. Missing class colour falls back to neutral white.
    local r, g, b = 1, 1, 1
    local tint = Theme.Current()
    if GMM.db.theme == "class" and tint then
        local shade = Theme.PRESETS.class.classShade
        r, g, b = tint[1] / shade, tint[2] / shade, tint[3] / shade
    end
    local brightness = GMM.db.theme == "smoked" and 0.65 or 1
    local intensity = GMM.db.runeIntensity / 100
    -- The engraving stays fixed and readable beneath the moving light.
    etchedBase:SetVertexColor(0.35 + 0.65 * r, 0.35 + 0.65 * g, 0.35 + 0.65 * b, 0.65 * brightness)
    runeBloom:SetShown(runeStyle == "glowing")
    runeLight:SetVertexColor(r, g, b, 0.7 * brightness * intensity)
    runeMist:SetVertexColor(0.5 + 0.5 * r, 0.5 + 0.5 * g, 0.5 + 0.5 * b, 0.5 * brightness)
    for _, layer in ipairs(runeLayers) do
        local strength = brightness
        local glowing = runeStyle == "glowing"
        layer.core:SetBlendMode(glowing and "ADD" or "BLEND")
        layer.core:SetVertexColor(0.35 + 0.65 * r, 0.35 + 0.65 * g, 0.35 + 0.65 * b,
            (glowing and 0.5 * intensity or 0.65) * strength)
        layer.glow:SetShown(glowing)
        -- Additive core, glyph halo and rim bloom accumulate. Full-strength
        -- layers washed the glyphs and their bounding lines into a white band.
        layer.glow:SetVertexColor(r, g, b, 0.4 * strength * intensity)
    end
end

local function configureRuneMotion()
    for _, layer in ipairs(runeLayers) do
        layer.animation:Stop()
        local orbit = runeMotion == "orbit"
        -- Explicit return leg: the live client's bounce looked like a reset.
        -- Each cycle ends at its starting orientation, including full orbits.
        layer.animation:SetLooping("REPEAT")
        layer.rotation:SetDegrees(orbit and 360 or 4)
        layer.rotation:SetDuration(orbit and 30 * 100 / GMM.db.runeSpeed or 2)
        layer.rotation:SetSmoothing(orbit and "NONE" or "IN_OUT")
        layer.returnRotation:SetDegrees(orbit and 0 or -4)
        layer.returnRotation:SetDuration(orbit and 0 or 2)
        layer.returnRotation:SetSmoothing(orbit and "NONE" or "IN_OUT")
    end
end

function Ring.RefreshRuneTuning(key)
    if not runes then return end
    if key == "runeIntensity" then paintRunes()
    elseif key == "runeSpeed" and runeMotion == "orbit" then configureRuneMotion() end
    syncRunes()
end

function Ring.SetRunePreviewOption(kind, value)
    if not runes then return false end
    if kind == "style" and (value == "etched" or value == "glowing") then
        runeStyle = value
        paintRunes()
    elseif kind == "motion" and (value == "sway" or value == "orbit") then
        if runeMotion ~= value then
            runeMotion = value
            configureRuneMotion()
        end
    elseif kind == "fog" and (value == "on" or value == "off") then
        fogEnabled = value == "on"
    else return false end
    syncRunes()
    return true
end

function Ring.PreviewRunes(on)
    if on and not runes then return false end
    previewEnabled = on == true
    syncRunes()
    return true
end

function Ring.RuneStatus()
    if not runes then return "rune preview unavailable" end
    return string.format("runes: enabled=%s, visible=%s, playing=%s, progress=%.3f, style=%s, motion=%s, fog=%s, intensity=%g%%, speed=%g%%",
        tostring(previewEnabled), tostring(runes:IsVisible()),
        tostring(runeAnimation:IsPlaying()), runeAnimation:GetProgress(), runeStyle, runeMotion,
        fogEnabled and "on" or "off", GMM.db.runeIntensity, GMM.db.runeSpeed)
end

function Ring.RunePreviewState()
    return { enabled = previewEnabled, style = runeStyle, motion = runeMotion,
        fog = fogEnabled and "on" or "off", theme = GMM.db.theme }
end

local function buildRunes()
    runeStyle, runeMotion = GMM.db.runeStyle, GMM.db.runeMotion
    fogEnabled, previewEnabled = GMM.db.runeFog, GMM.db.runicMode
    runes = CreateFrame("Frame", nil, container)
    runes:Hide()
    runes:SetAllPoints(host)
    -- Below the north tab (+4) and discs (+6), above the map. g.top (+9)
    -- would put the moving strokes over those controls.
    runes:SetFrameLevel(Ring.AboveMap(3))
    runes:EnableMouse(false)
    etchedBase = runes:CreateTexture(nil, "BACKGROUND")
    etchedBase:SetAllPoints(runes)
    etchedBase:SetTexture(GMM.MEDIA .. "ring_runes")
    etchedBase:SetBlendMode("BLEND")
    do
        local f = CreateFrame("Frame", nil, runes)
        f:SetAllPoints(runes)
        f:SetFrameLevel(runes:GetFrameLevel())
        f:EnableMouse(false)
        local core = f:CreateTexture(nil, "ARTWORK")
        core:SetAllPoints(f)
        core:SetTexture(GMM.MEDIA .. "ring_runes_moving")
        local glow = f:CreateTexture(nil, "BACKGROUND")
        glow:SetAllPoints(f)
        glow:SetTexture(GMM.MEDIA .. "ring_runes_glow")
        glow:SetBlendMode("ADD")
        -- Rotate the frame so sharp strokes and their halo share one clock.
        local animation = f:CreateAnimationGroup()
        local rotation = animation:CreateAnimation("Rotation")
        rotation:SetOrder(1)
        rotation:SetOrigin("CENTER", 0, 0)
        local returnRotation = animation:CreateAnimation("Rotation")
        returnRotation:SetOrder(2)
        returnRotation:SetOrigin("CENTER", 0, 0)
        runeLayers[1] = { frame = f, core = core, glow = glow,
            animation = animation, rotation = rotation, returnRotation = returnRotation }
    end
    runeAnimation = runeLayers[1].animation
    -- Uneven bloom travels with the primary rune layer's animation. Parenting
    -- and anchoring to that layer keeps glyphs and light on the same clock.
    local lightParent = runeLayers[1].frame
    runeBloom = CreateFrame("Frame", nil, lightParent)
    runeBloom:SetPoint("TOPLEFT", lightParent, "TOPLEFT", -18, 18)
    runeBloom:SetPoint("BOTTOMRIGHT", lightParent, "BOTTOMRIGHT", 18, -18)
    runeBloom:SetFrameLevel(Ring.AboveMap(1))
    runeBloom:EnableMouse(false)
    local light = runeBloom:CreateTexture(nil, "ARTWORK")
    runeLight = light
    light:SetAllPoints(runeBloom)
    light:SetTexture(GMM.MEDIA .. "ring_bloom")
    light:SetBlendMode("ADD")
    fog = CreateFrame("Frame", nil, runes)
    fog:SetPoint("TOPLEFT", runes, "TOPLEFT", -Ring.FOG_PADDING, Ring.FOG_PADDING)
    fog:SetPoint("BOTTOMRIGHT", runes, "BOTTOMRIGHT", Ring.FOG_PADDING, -Ring.FOG_PADDING)
    fog:SetFrameLevel(Ring.AboveMap(2))
    fog:EnableMouse(false)
    local mist = fog:CreateTexture(nil, "ARTWORK")
    runeMist = mist
    mist:SetAllPoints(fog)
    mist:SetTexture(GMM.MEDIA .. "ring_fog")
    mist:SetBlendMode("ADD")
    fogAnimation = mist:CreateAnimationGroup()
    fogAnimation:SetLooping("REPEAT")
    local drift = fogAnimation:CreateAnimation("Rotation")
    drift:SetOrder(1)
    drift:SetOrigin("CENTER", 0, 0)
    drift:SetDegrees(-360)
    drift:SetDuration(80)
    drift:SetSmoothing("NONE")
    paintRunes()
    configureRuneMotion()
    runes:SetScript("OnShow", syncRunes)
    runes:SetScript("OnHide", function()
        for _, layer in ipairs(runeLayers) do layer.animation:Stop() end
        fogAnimation:Stop()
    end)
    Minimap:HookScript("OnShow", syncRunes)
    Minimap:HookScript("OnHide", syncRunes)
    Theme.OnChange(function()
        paintRunes()
        syncRunes()
    end)
end

-- The ring's host frame (other pieces anchor to it), its glass, and the
-- distance from the map's centre to the middle of the ring.
function Ring.Host() return host end
function Ring.Glass() return glass end
function Ring.Container() return container end
function Ring.Radius()
    local w = (Minimap and Minimap:GetWidth()) or Ring.MAP_SIZE
    if type(w) ~= "number" or w <= 0 then w = Ring.MAP_SIZE end
    return w / 2 + Ring.RING_WIDTH / 2
end

-- A level above the map, for anything that overlaps its edge.
function Ring.AboveMap(extra)
    return Minimap:GetFrameLevel() + (extra or 5)
end

--------------------------------------------------------------------------------
-- The north tab
--------------------------------------------------------------------------------

-- A small glass roof at 12 o'clock with an "N" under its arrowhead. It is
-- drawn the orb's way (a masked tint and wash, our rim on top) so Theme paints
-- it with the orbs. With rotateMinimap on, it orbits to wherever north is.
local NOTCH_W, NOTCH_H = 40, 18
Ring.NOTCH_OVERLAP = 9       -- how far the tab's base reaches into the ring

local function buildNotch()
    local f = CreateFrame("Frame", nil, container)
    f:SetSize(NOTCH_W, NOTCH_H)
    f:SetFrameLevel(Ring.AboveMap(4))
    local m = f:CreateMaskTexture()
    m:SetTexture(GMM.MEDIA .. "notch_mask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    m:SetAllPoints(f)
    local st = Glass.STYLE
    local tint = f:CreateTexture(nil, "BACKGROUND", nil, -6)
    tint:SetAllPoints(f)
    tint:SetColorTexture(st.tint[1], st.tint[2], st.tint[3], math.max(st.tint[4], 0.35))
    tint:AddMaskTexture(m)
    local wash = f:CreateTexture(nil, "BACKGROUND", nil, -5)
    wash:SetAllPoints(f)
    wash:SetColorTexture(1, 1, 1, 1)
    wash:SetGradient("VERTICAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, st.wash))
    wash:AddMaskTexture(m)
    local rim = f:CreateTexture(nil, "OVERLAY", nil, 6)
    rim:SetTexture(GMM.MEDIA .. "notch_rim")
    rim:SetAllPoints(f)
    rim:SetAlpha(0.9)
    local n = Glass.Font(f, 10, "CENTER")
    n:SetPoint("CENTER", f, "CENTER", 0, -3)
    n:SetText("N")
    n:SetTextColor(0.92, 0.95, 1)
    f.parts = { tint = tint, wash = wash, rim = rim, mask = m }
    f.label = n
    Theme.Register({ tint = tint, wash = wash }, "orb")
    return f
end

-- Where north is, as an angle clockwise from the top (radians): 0 unless the
-- minimap rotates with the player, then the player's facing (0 = north,
-- counter-clockwise; north sits that far clockwise from "ahead", which is up).
function Ring.NorthAngle(rotating, facing)
    if not rotating or type(facing) ~= "number" then return 0 end
    return facing
end

-- Put the tab at `angle` (clockwise from the top), its base on the ring.
local function placeNotch(angle)
    local r = Ring.Radius() + Ring.RING_WIDTH / 2 + NOTCH_H / 2 - Ring.NOTCH_OVERLAP
    notch:ClearAllPoints()
    notch:SetPoint("CENTER", host, "CENTER", r * math.sin(angle), r * math.cos(angle))
    -- Textures turn counter-clockwise: the roof points away from the centre.
    for _, k in ipairs({ "tint", "wash", "rim", "mask" }) do
        local t = notch.parts[k]
        if t.SetRotation then t:SetRotation(-angle) end
    end
    notch.label:ClearAllPoints()
    notch.label:SetPoint("CENTER", host, "CENTER", (r - 3) * math.sin(angle), (r - 3) * math.cos(angle))
end
Ring.PlaceNotch = function(angle) if notch then placeNotch(angle) end end

local lastAngle
local function followNorth()
    local facing = API.Plain(GetPlayerFacing())
    local angle = Ring.NorthAngle(true, facing)
    if angle ~= lastAngle then
        lastAngle = angle
        placeNotch(angle)
    end
end

-- rotateMinimap on: follow the player's facing every frame; off: north is up.
function Ring.SyncRotation()
    if not notch then return end
    if API.CVarBool("rotateMinimap") then
        notch:SetScript("OnUpdate", followNorth)
    else
        notch:SetScript("OnUpdate", nil)
        lastAngle = nil
        placeNotch(0)
    end
end

--------------------------------------------------------------------------------
-- Discs on the ring
--------------------------------------------------------------------------------

-- A round glass button centred on the ring at `angle` degrees clockwise from
-- the top. opts: size (Ring.DISC_SIZE), icon (texture, atlas or file),
-- iconCrop (true for Interface\Icons squares), radius (the ring's middle).
-- Returns the button; its glass is button.glass, its icon button.icon.
function Ring.AddDisc(angle, opts)
    opts = opts or {}
    local size = opts.size or Ring.DISC_SIZE
    local b = CreateFrame("Button", nil, container)
    b:SetSize(size, size)
    b:SetFrameLevel(Ring.AboveMap(6))
    b:RegisterForClicks("AnyUp")
    local g = Glass.Disc(b, size >= 96 and "disc" or "disc_small")
    b.glass = g
    local icon = b:CreateTexture(nil, "ARTWORK")
    local inset = math.floor(size * 0.18 + 0.5)
    icon:SetPoint("TOPLEFT", b, "TOPLEFT", inset, -inset)
    icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -inset, inset)
    icon:AddMaskTexture(Glass.Mask(b, "disc_mask_small", nil, inset))
    if opts.icon then API.SetIcon(icon, opts.icon) end
    if opts.iconCrop then icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    b.icon = icon
    -- Hover: a soft round light over the glass (the orb mask, added).
    b:SetHighlightTexture(GMM.MEDIA .. "orb_mask", "ADD")
    local hl = b:GetHighlightTexture()
    if hl then hl:SetAlpha(0.18) end
    local rad = math.rad(angle)
    local r = opts.radius or (Ring.Radius() + Ring.RING_WIDTH * 0.3)
    b:SetPoint("CENTER", host, "CENTER", r * math.sin(rad), r * math.cos(rad))
    Theme.Register(g)
    return b
end

--------------------------------------------------------------------------------
-- The day/night disc (top right): Forever's DielFrame, in glass
--------------------------------------------------------------------------------

Ring.SUN = { 1, 0.82, 0.28 }
Ring.MOON = { 0.78, 0.86, 1 }

local sun

function Ring.IsDay()
    local fn = C_DateAndTime and C_DateAndTime.IsDayTime
    if not fn then return true end
    local ok, day = pcall(fn)
    if not ok then return true end
    return API.Plain(day) ~= false
end

function Ring.UpdateDayNight(isDay)
    if not sun then return end
    if isDay == nil then isDay = Ring.IsDay() end
    local c = isDay and Ring.SUN or Ring.MOON
    sun.icon:SetTexture(GMM.MEDIA .. (isDay and "sun" or "moon"))
    sun.icon:SetVertexColor(c[1], c[2], c[3])
    sun.isDay = isDay
end

local function timeText(fn)
    local f = rawget(_G, fn)
    if type(f) ~= "function" then return nil end
    local ok, s = pcall(f, true)
    if ok and type(s) == "string" then return s end
    return nil
end

local function sunTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(self.isDay and "Day" or "Night")
    local game, here = timeText("GameTime_GetGameTime"), timeText("GameTime_GetLocalTime")
    if game then GameTooltip:AddDoubleLine("Server time", game, 1, 1, 1, 1, 1, 1) end
    if here then GameTooltip:AddDoubleLine("Local time", here, 1, 1, 1, 1, 1, 1) end
    GameTooltip:AddLine("Click: clock and alarm", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function buildSun()
    sun = Ring.AddDisc(45)
    sun:SetScript("OnEnter", sunTooltip)
    sun:SetScript("OnLeave", function() GameTooltip:Hide() end)
    sun:SetScript("OnClick", function()
        local toggle = rawget(_G, "ToggleTimeManager")
        if type(toggle) == "function" then API.Try("time manager", toggle) end
    end)
    sun:SetScript("OnEvent", function(_, event, isDay)
        if event == "DIEL_CYCLE_CHANGED" then Ring.UpdateDayNight(API.Plain(isDay)) end
    end)
    API.RegisterEvent(sun, "DIEL_CYCLE_CHANGED", "day/night disc")
    Ring.UpdateDayNight()
    sun:SetShown(GMM.db.sun ~= false)
end

function Ring.Sun() return sun end
function Ring.ShowSun(on) if sun then sun:SetShown(on) end end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

function Ring.Build()
    container = GMM.Blizzard.Container()
    if not (container and Minimap) then
        API.Fail("ring", "no minimap container on this client")
        return false
    end
    local w = Minimap:GetWidth()
    if type(w) ~= "number" or w <= 0 then w = Ring.MAP_SIZE end
    host = CreateFrame("Frame", nil, container)
    host:SetSize(w + 2 * Ring.RING_WIDTH, w + 2 * Ring.RING_WIDTH)
    host:SetPoint("CENTER", Minimap, "CENTER", 0, 0)
    host:SetFrameLevel(math.max(0, Minimap:GetFrameLevel() - 1))
    glass = Glass.Disc(host, "disc")
    glass.rim:SetTexture(GMM.MEDIA .. "ring_rim")
    glass.dark:SetTexture(GMM.MEDIA .. "ring_dark")
    Theme.Register(glass)

    buildRunes()

    notch = buildNotch()
    local ev = CreateFrame("Frame")
    ev:SetScript("OnEvent", function(_, _, name)
        if name == "rotateMinimap" then Ring.SyncRotation() end
    end)
    API.RegisterEvent(ev, "CVAR_UPDATE", "north tab")
    Ring.SyncRotation()

    buildSun()
    return true
end

Ring._test = { notch = function() return notch end,
    runes = function() return runes, runeAnimation, runeLayers end,
    fog = function() return fog, fogAnimation end,
    bloom = function() return runeBloom end,
    etchedBase = function() return etchedBase end }
