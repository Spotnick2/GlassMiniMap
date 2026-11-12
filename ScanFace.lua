-- ScanFace.lua: a radar over the map's spot while another addon borrows the
-- map (#59). NodeRadar's scan mode moves Minimap under the cursor for about
-- 150 ms, up to 8 times in a row (Scan.lua, docs/PUBLIC-API.md). Our glass
-- stays home (#56), but the map's spot is empty meanwhile and read as a blink
-- in game: the owner wanted a "ping" instead. So: a dark round face, range
-- rings and a crosshair, a sweep turning clockwise.
--
-- Shown at once on the first ScanBegin, in the same call, so no frame shows
-- the empty spot. After the last release it holds HOLD seconds over the
-- returned map, then fades over FADE: a run of scans reads as one ping, and a
-- Begin during the hold or the fade brings it back to full.
--
-- A child of the container like everything of ours, centred on the ring's
-- host (never on Minimap, #56), sized once at the build, mouse off. One level
-- above the map: it covers the map's return during the hold, under the ring's
-- rim, the north tab, the pills and the discs. It takes the fader's alpha with
-- the rest of the container.
--
-- Only over a visible map (Codex, #59): Blizzard's ToggleMinimap hides the map
-- alone, and the face is its sibling, so a hidden map cancels the face at
-- once, hold and all. The map's OnHide also fires when the container hides
-- (the face's only ancestor), so a stale hold never comes back later.
--
-- A scan already under way when we build (before our PLAYER_LOGIN) chose its
-- own stand-in: ScanStandIn said false. We stay out of it, hidden, and
-- advertise ours from its end on (Codex, #59).
--
-- Only when the player chose NodeRadar's radar look (its Options, scanRadar,
-- off by default: the owner, 2026-11-12). Otherwise ScanStandIn says false and
-- NodeRadar draws its own stand-in, the minimap's real ground where it can
-- (NodeRadar#117), which a look barely shows. The choice is latched on the
-- first Begin until the last release, so what ScanStandIn answered for a
-- borrow is what we draw for it, whatever the player toggles meanwhile
-- (Codex, 2026-11-12). A toggle during the hold counts from the next scan.

GlassMiniMap = GlassMiniMap or {}
local GMM = GlassMiniMap
local Theme = GMM.Theme
local Ring = GMM.Ring
local Face = {}
GMM.ScanFace = Face

Face.HOLD = 0.4        -- seconds at full after the last release
Face.FADE = 0.2        -- ...then out over this
Face.TURN = 1.2        -- seconds per turn of the sweep
Face.DARK = { 0.025, 0.03, 0.045 }   -- the body, before the theme's hue
Face.BODY_ALPHA = 0.9
Face.LINES_ALPHA = 0.35
Face.SWEEP_ALPHA = 0.6
Face.HUE = { 0.6, 0.85, 1 }          -- clear glass's: a cool cyan

local face, body, lines, sweep, spin
local built, ready = false, false
local held = 0
local latched          -- the choice for the borrow under way: nil between borrows

-- Did the player choose NodeRadar's radar look? Its NodeRadar.ScanFace.RadarLook
-- (after its 1.9.0); anything else, an older NodeRadar or none, is no.
local function chosen()
    local nr = rawget(_G, "NodeRadar")
    local sf = type(nr) == "table" and rawget(nr, "ScanFace")
    local f = type(sf) == "table" and rawget(sf, "RadarLook")
    if type(f) ~= "function" then return false end
    local ok, yes = pcall(f)
    return ok and yes == true
end

-- The theme's hue at full brightness (Ring.lua's paintRunes does the same).
local function hue(tint)
    if not tint then return Face.HUE[1], Face.HUE[2], Face.HUE[3] end
    local r, g, b = tint[1], tint[2], tint[3]
    local peak = math.max(r, g, b)
    if peak <= 0 then return Face.HUE[1], Face.HUE[2], Face.HUE[3] end
    return r / peak, g / peak, b / peak
end

-- The body stays dark whatever the theme; the lines and the sweep take its
-- hue and its wash (dimmer on smoked glass, as the runes are).
local function paint(tint, wash)
    if not built then return end
    local r, g, b = hue(tint)
    local d = Face.DARK
    local lit = math.max(0, math.min(1, type(wash) == "number" and wash or 1))
    body:SetColorTexture(d[1] + 0.05 * r, d[2] + 0.05 * g, d[3] + 0.05 * b, Face.BODY_ALPHA)
    lines:SetVertexColor(r, g, b, Face.LINES_ALPHA * lit)
    sweep:SetVertexColor(r, g, b, Face.SWEEP_ALPHA * lit)
end

-- Off at once: no hold, no fade.
local function cancel()
    face:SetScript("OnUpdate", nil)
    face:Hide()
    face:SetAlpha(1)
end

-- The hold, then the fade: an OnUpdate that runs only meanwhile.
local function step(self, elapsed)
    held = held + elapsed
    if held < Face.HOLD then return end
    local a = 1 - (held - Face.HOLD) / Face.FADE
    if a > 0 then self:SetAlpha(a); return end
    cancel()
end

-- Scan.lua, on the first ScanBegin and the last release; the map's OnShow
-- and OnHide.
function Face.Sync()
    if not built then return end
    local active = GMM.Scan.Active()
    if not ready then
        if active then return end       -- the scan that spans our build: not ours
        ready = true
    end
    if active then
        if latched == nil then latched = chosen() end
    else
        latched = nil
    end
    if not Minimap:IsVisible() or (active and not latched) then
        cancel()
    elseif active then
        face:SetScript("OnUpdate", nil)
        face:SetAlpha(1)
        face:Show()
    elseif face:IsShown() then
        held = 0
        face:SetScript("OnUpdate", step)
    end
end

-- GlassMiniMap.ScanStandIn's answer: do we draw the stand-in for a scan begun
-- now? Built, out of a scan that spans our build, and the radar chosen: the
-- latched choice while a borrow is under way, the player's current one between.
function Face.Draws()
    if not ready then return false end
    if latched ~= nil then return latched end
    return chosen()
end

local function texture(region, file)
    if region:SetTexture(GMM.MEDIA .. file) == false then
        error("scan face texture unavailable: " .. file .. ". Restart the client after texture updates.", 0)
    end
end

function Face.Build()
    local host, container = Ring.Host(), Ring.Container()
    if not (host and container) then error("no ring to put the scan face in", 0) end
    local size = host:GetWidth() - 2 * Ring.RING_WIDTH
    face = CreateFrame("Frame", nil, container)
    face:Hide()
    face:SetSize(size, size)
    face:SetPoint("CENTER", host, "CENTER", 0, 0)
    face:SetFrameLevel(Ring.AboveMap(1))
    face:EnableMouse(false)

    body = face:CreateTexture(nil, "BACKGROUND")
    body:SetAllPoints(face)
    local mask = face:CreateMaskTexture()
    mask:SetTexture(GMM.MEDIA .. "orb_mask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(face)
    body:AddMaskTexture(mask)
    -- The art is round already (Tools/make_art.py): no mask, so the sweep can
    -- turn without one.
    lines = face:CreateTexture(nil, "ARTWORK")
    lines:SetAllPoints(face)
    texture(lines, "scan_face")
    sweep = face:CreateTexture(nil, "OVERLAY")
    sweep:SetAllPoints(face)
    texture(sweep, "scan_sweep")
    sweep:SetBlendMode("ADD")

    spin = sweep:CreateAnimationGroup()
    spin:SetLooping("REPEAT")
    local turn = spin:CreateAnimation("Rotation")
    turn:SetOrigin("CENTER", 0, 0)
    turn:SetDegrees(-360)            -- clockwise
    turn:SetDuration(Face.TURN)
    turn:SetSmoothing("NONE")
    face:SetScript("OnShow", function() spin:Play() end)
    face:SetScript("OnHide", function() spin:Stop() end)
    Minimap:HookScript("OnShow", function() Face.Sync() end)
    Minimap:HookScript("OnHide", function() Face.Sync() end)

    built = true
    ready = not GMM.Scan.Active()
    Theme.OnChange(paint)
end

Face._test = {
    face = function() return face end,
    parts = function() return body, lines, sweep, spin end,
}
