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
Ring.EFFECT_PADDING = 18     -- bloom/vapor; Tools/make_art.py reads this value

local host, glass, notch, container
local runes, movingLayer, fog, fogAnimation, runeBloom, runeLight, runeMist, etchedBase
local runesReady, runesError = false, nil
local visibilityHooksInstalled = false
local protectRunes

local function stopRunes()
    if movingLayer and movingLayer.animation then movingLayer.animation:Stop() end
    if fogAnimation then fogAnimation:Stop() end
end

-- The map can hide independently of its container (Blizzard's ToggleMinimap).
local function playRunes()
    if runes:IsVisible() then
        if not movingLayer.animation:IsPlaying() then movingLayer.animation:Play() end
    else movingLayer.animation:Stop() end
    if runes:IsVisible() and GMM.db.runeFog then
        if not fogAnimation:IsPlaying() then fogAnimation:Play() end
    else fogAnimation:Stop() end
end

local function syncRunes()
    fog:SetShown(GMM.db.runeFog)
    local shown = GMM.db.runicMode and Minimap:IsVisible()
    if runes:IsShown() ~= shown then runes:SetShown(shown)
    else playRunes() end
end

local function paintRunes()
    local r, g, b = 1, 1, 1
    local tint, wash = Theme.Current()
    if tint then
        -- Preserve the material's hue while allowing it to emit light.
        local peak = math.max(tint[1], tint[2], tint[3])
        r, g, b = tint[1], tint[2], tint[3]
        if peak > 0 then r, g, b = r / peak, g / peak, b / peak end
    end
    local brightness = math.max(0, math.min(1, wash))
    local intensity = GMM.db.runeIntensity / 100
    etchedBase:SetVertexColor(0.35 + 0.65 * r, 0.35 + 0.65 * g, 0.35 + 0.65 * b, 0.65 * brightness)
    local glowing = GMM.db.runeStyle == "glowing"
    runeBloom:SetShown(glowing)
    runeLight:SetVertexColor(r, g, b, 0.7 * brightness * intensity)
    runeMist:SetVertexColor(0.5 + 0.5 * r, 0.5 + 0.5 * g, 0.5 + 0.5 * b, 0.5 * brightness)
    movingLayer.core:SetBlendMode(glowing and "ADD" or "BLEND")
    movingLayer.core:SetVertexColor(0.35 + 0.65 * r, 0.35 + 0.65 * g, 0.35 + 0.65 * b,
        (glowing and 0.5 * intensity or 0.65) * brightness)
    movingLayer.glow:SetShown(glowing)
    movingLayer.glow:SetVertexColor(r, g, b, 0.4 * brightness * intensity)
end

local function configureRuneMotion()
    movingLayer.animation:Stop()
    local orbit = GMM.db.runeMotion == "orbit"
    -- Owner's live pass (build not recorded) showed a reset with BOUNCE.
    -- Explicit return keeps the two-second legs and ends at the starting angle.
    movingLayer.animation:SetLooping("REPEAT")
    movingLayer.rotation:SetDegrees(orbit and 360 or 4)
    movingLayer.rotation:SetDuration(orbit and 30 or 2)
    movingLayer.rotation:SetSmoothing(orbit and "NONE" or "IN_OUT")
    movingLayer.returnRotation:SetDegrees(orbit and 0 or -4)
    movingLayer.returnRotation:SetDuration(orbit and 0 or 2)
    movingLayer.returnRotation:SetSmoothing(orbit and "NONE" or "IN_OUT")
    movingLayer.animation:SetAnimationSpeedMultiplier(orbit and GMM.db.runeSpeed / 100 or 1)
end

local function setRuneTexture(texture, file)
    if texture:SetTexture(file) == false then
        error("Runic texture unavailable: " .. file .. ". Restart the client after texture updates.", 0)
    end
end

local function buildRunes()
    -- Keep each object as soon as it is created, including partial builds.
    -- Reapplying configuration after a failure never allocates another stack.
    runes = runes or CreateFrame("Frame", nil, container)
    runes:Hide()
    runes:SetAllPoints(host)
    runes:SetFrameLevel(Ring.AboveMap(3))
    runes:EnableMouse(false)
    etchedBase = etchedBase or runes:CreateTexture(nil, "BACKGROUND")
    etchedBase:SetAllPoints(runes)
    setRuneTexture(etchedBase, GMM.MEDIA .. "ring_runes")
    etchedBase:SetBlendMode("BLEND")
    movingLayer = movingLayer or {}
    movingLayer.frame = movingLayer.frame or CreateFrame("Frame", nil, runes)
    local f = movingLayer.frame
    f:SetAllPoints(runes)
    f:SetFrameLevel(runes:GetFrameLevel())
    f:EnableMouse(false)
    movingLayer.core = movingLayer.core or f:CreateTexture(nil, "ARTWORK")
    local core = movingLayer.core
    core:SetAllPoints(f)
    setRuneTexture(core, GMM.MEDIA .. "ring_runes_moving")
    movingLayer.glow = movingLayer.glow or f:CreateTexture(nil, "BACKGROUND")
    local glow = movingLayer.glow
    glow:SetAllPoints(f)
    setRuneTexture(glow, GMM.MEDIA .. "ring_runes_glow")
    glow:SetBlendMode("ADD")
    movingLayer.animation = movingLayer.animation or f:CreateAnimationGroup()
    local animation = movingLayer.animation
    movingLayer.rotation = movingLayer.rotation or animation:CreateAnimation("Rotation")
    local rotation = movingLayer.rotation
    rotation:SetOrder(1)
    rotation:SetOrigin("CENTER", 0, 0)
    movingLayer.returnRotation = movingLayer.returnRotation or animation:CreateAnimation("Rotation")
    local returnRotation = movingLayer.returnRotation
    returnRotation:SetOrder(2)
    returnRotation:SetOrigin("CENTER", 0, 0)
    runeBloom = runeBloom or CreateFrame("Frame", nil, f)
    runeBloom:SetPoint("TOPLEFT", f, "TOPLEFT", -Ring.EFFECT_PADDING, Ring.EFFECT_PADDING)
    runeBloom:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", Ring.EFFECT_PADDING, -Ring.EFFECT_PADDING)
    runeBloom:SetFrameLevel(Ring.AboveMap(1))
    runeBloom:EnableMouse(false)
    runeLight = runeLight or runeBloom:CreateTexture(nil, "ARTWORK")
    runeLight:SetAllPoints(runeBloom)
    setRuneTexture(runeLight, GMM.MEDIA .. "ring_bloom")
    runeLight:SetBlendMode("ADD")
    fog = fog or CreateFrame("Frame", nil, runes)
    fog:SetPoint("TOPLEFT", runes, "TOPLEFT", -Ring.EFFECT_PADDING, Ring.EFFECT_PADDING)
    fog:SetPoint("BOTTOMRIGHT", runes, "BOTTOMRIGHT", Ring.EFFECT_PADDING, -Ring.EFFECT_PADDING)
    fog:SetFrameLevel(Ring.AboveMap(2))
    fog:EnableMouse(false)
    runeMist = runeMist or fog:CreateTexture(nil, "ARTWORK")
    runeMist:SetAllPoints(fog)
    setRuneTexture(runeMist, GMM.MEDIA .. "ring_fog")
    runeMist:SetBlendMode("ADD")
    fogAnimation = fogAnimation or runeMist:CreateAnimationGroup()
    fogAnimation:SetLooping("REPEAT")
    local drift = fogAnimation:GetAnimations()
    if not drift then drift = fogAnimation:CreateAnimation("Rotation") end
    drift:SetOrder(1)
    drift:SetOrigin("CENTER", 0, 0)
    drift:SetDegrees(-360)
    drift:SetDuration(80)
    drift:SetSmoothing("NONE")
    runes:SetScript("OnShow", function() protectRunes(playRunes) end)
    runes:SetScript("OnHide", function() protectRunes(stopRunes) end)
    if not visibilityHooksInstalled then
        Minimap:HookScript("OnShow", function() Ring.UpdateRunes("visibility") end)
        Minimap:HookScript("OnHide", function() Ring.UpdateRunes("visibility") end)
        visibilityHooksInstalled = true
    end
end

local function updateRunes(changed)
    if not GMM.db then return end
    if not host then
        if GMM.db.runicMode then error("Minimap ring unavailable for runic mode", 0) end
        return
    end
    if not runesReady then
        if not GMM.db.runicMode then return end
        buildRunes()
        configureRuneMotion()
        runesReady = true
    elseif changed == "runeMotion" then
        configureRuneMotion()
    elseif changed == "runeSpeed" and GMM.db.runeMotion == "orbit" then
        movingLayer.animation:SetAnimationSpeedMultiplier(GMM.db.runeSpeed / 100)
    end
    paintRunes()
    syncRunes()
end

-- Optional rendering is isolated from both core startup and saved settings.
-- A failed build stays hidden; the next settings/visibility update can retry.
protectRunes = function(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        runesError, runesReady = true, false
        API.Fail("runic mode", err)
        if runes then pcall(runes.Hide, runes) end
        if movingLayer and movingLayer.animation then pcall(movingLayer.animation.Stop, movingLayer.animation) end
        if fogAnimation then pcall(fogAnimation.Stop, fogAnimation) end
    end
    return ok
end

function Ring.UpdateRunes(changed)
    local ok = protectRunes(updateRunes, changed)
    if ok and (not GMM.db or not GMM.db.runicMode or runesReady) then
        runesError = nil
        return true
    end
    return false
end

function Ring.RunicError()
    if runesError then return "Runic effects unavailable. See /gmm failures." end
end

function Ring.RuneStatus()
    local db = GMM.db
    local playing = runesReady and movingLayer.animation:IsPlaying() or false
    local progress = runesReady and movingLayer.animation:GetProgress() or 0
    return string.format("runes: enabled=%s, visible=%s, playing=%s, progress=%.3f, built=%s, style=%s, motion=%s, fog=%s, intensity=%g%%, speed=%g%%",
        tostring(db.runicMode), tostring(runesReady and runes:IsVisible() or false),
        tostring(playing), progress, tostring(runesReady), db.runeStyle, db.runeMotion,
        db.runeFog and "on" or "off", db.runeIntensity, db.runeSpeed)
end

Theme.OnChange(function() Ring.UpdateRunes("theme") end)

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
    runes = function() return runes, movingLayer and movingLayer.animation, movingLayer end,
    fog = function() return fog, fogAnimation end,
    bloom = function() return runeBloom end,
    etchedBase = function() return etchedBase end }
