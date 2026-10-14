-- Theme.lua: the three looks of the glass, repainted live on every surface.
--
-- clear   the material as LibGlass built it (cool, light)
-- smoked  AltStable's darker body (its numbers, as GlassPanel and GlassMail use them)
-- class   the clear body tinted by the player's class colour, shaded by
--         classShade: at full strength it reads as painted plastic (AltStable,
--         in game). The class colour may be unreadable early in a login; the
--         surface then stays clear and PLAYER_ENTERING_WORLD paints it again.
--
-- Every glass surface this addon builds registers here: LibGlass surfaces
-- (the ring, the pills, the discs, the tracking menu, the drawer) by their g,
-- and the drawer's orb skins by their tint and wash textures. Only body
-- regions are touched (tint colour, grain and wash alpha): the rims stay the
-- instance's.

GlassMiniMap = GlassMiniMap or {}
local GMM = GlassMiniMap
local API = GMM.API
local Glass = GMM.Glass
local Theme = {}
GMM.Theme = Theme

Theme.NAMES = { "clear", "smoked", "class" }
Theme.LABELS = { clear = "Clear glass", smoked = "Smoked glass", class = "Class colour glass" }
Theme.PRESETS = {
    clear  = { classShade = 0.6 },
    smoked = { tint = { 0.05, 0.06, 0.08, 0.62 }, wash = 0.14 / 0.18 },
    class  = { classShade = 0.6 },
}

local surfaces = {}   -- { g = , kind = "glass" | "orb" }
Theme.pending = false

function Theme.IsValid(name) return Theme.PRESETS[name] ~= nil end

local function current()
    local name = GMM.db and GMM.db.theme
    return Theme.PRESETS[name] and name or "clear"
end

-- The tint for this theme as r, g, b, a (a nil: the surface's own), or
-- nothing for "as built". Second return: false while the class colour is
-- wanted but unreadable.
local function tintFor(name)
    local p = Theme.PRESETS[name]
    if name == "class" then
        local r, g, b = API.ClassColor()
        if not r then return nil, false end
        return { r * p.classShade, g * p.classShade, b * p.classShade }, true
    end
    return p.tint, true
end

local function paintGlass(s, name, tint)
    local p = Theme.PRESETS[name]
    if tint then
        Glass.SetSurfaceTint(s.g, tint[1], tint[2], tint[3], tint[4])
    else
        Glass.SetSurfaceTint(s.g)
    end
    if s.g.grain then s.g.grain:SetAlpha(Glass.STYLE.grain or 0) end
    if s.g.wash then s.g.wash:SetAlpha(p.wash or 1) end
end

-- An orb is the drawer's round button skin: a tint and a wash texture of its
-- own (Drawer/Orb.lua), built at Glass.STYLE.tint with alpha at least 0.35.
local function paintOrb(s, name, tint)
    local p = Theme.PRESETS[name]
    local base = Glass.STYLE.tint
    local c = tint or base
    local a = (tint and tint[4]) or math.max(base[4], 0.35)
    s.g.tint:SetColorTexture(c[1], c[2], c[3], a)
    if s.g.wash then s.g.wash:SetAlpha(p.wash or 1) end
end

local function paint(s, name, tint)
    if s.kind == "orb" then paintOrb(s, name, tint) else paintGlass(s, name, tint) end
end

-- Add a surface and paint it with the current theme.
function Theme.Register(g, kind)
    if type(g) ~= "table" or not g.tint then return end
    local s = { g = g, kind = kind or "glass" }
    surfaces[#surfaces + 1] = s
    local name = current()
    local tint = tintFor(name)
    API.Try("theme:paint", paint, s, name, tint)
end

-- Repaint every surface. Returns false while the class colour is unreadable.
function Theme.Refresh()
    local name = current()
    local tint, known = tintFor(name)
    for _, s in ipairs(surfaces) do API.Try("theme:paint", paint, s, name, tint) end
    Theme.pending = not known
    return known
end

-- PLAYER_ENTERING_WORLD: the class colour can be read by now.
function Theme.Retry()
    if Theme.pending then Theme.Refresh() end
end

Theme._test = { surfaces = surfaces }
