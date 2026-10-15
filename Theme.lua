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
-- (the ring, the pills, the discs, the tracking menu) by their g, and the
-- north tab (drawn the orb's way) by its tint and wash textures. Only body
-- regions are touched (tint colour, grain alpha, wash strength): the rims stay the
-- instance's. Theme.OnChange hears every repaint: Drawer.lua passes the look
-- on to Glass MiniMap Bar's glass.

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
local listeners = {}  -- fn(tint|nil, wash): tint = { r, g, b, a|nil }, nil = as built
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

-- The wash is a gradient, and a gradient texture ignores SetAlpha on this
-- client (70374; porting guide §3, LibGlass#47): its strength is the top
-- colour of its gradient. The preset's wash multiplies the built one.
local function washTop(p)
    return math.max(0, math.min(1, (Glass.STYLE.wash or 0) * (p.wash or 1)))
end

local function paintGlass(s, name, tint)
    local p = Theme.PRESETS[name]
    if tint then
        Glass.SetSurfaceTint(s.g, tint[1], tint[2], tint[3], tint[4])
    else
        Glass.SetSurfaceTint(s.g)
    end
    if s.g.grain then s.g.grain:SetAlpha(Glass.STYLE.grain or 0) end
    if s.g.wash then Glass.SetWash(s.g, washTop(p)) end
end

-- An orb is a round piece drawn without LibGlass (the north tab): a tint and a
-- wash texture of its own, built at Glass.STYLE.tint with alpha at least 0.35.
local function paintOrb(s, name, tint)
    local p = Theme.PRESETS[name]
    local base = Glass.STYLE.tint
    local c = tint or base
    local a = (tint and tint[4]) or math.max(base[4], 0.35)
    s.g.tint:SetColorTexture(c[1], c[2], c[3], a)
    if s.g.wash then
        local top = washTop(p)
        s.g.wash:SetGradient("VERTICAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, top))
        s.g.wash:SetShown(top > 0)
    end
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

-- The current look for someone else's glass: tint (nil = as built) and the
-- wash as a multiplier of the built one.
function Theme.Current()
    local name = current()
    local tint = tintFor(name)
    return tint, Theme.PRESETS[name].wash or 1
end

-- fn(tint, wash) now and on every repaint.
function Theme.OnChange(fn)
    listeners[#listeners + 1] = fn
    API.Try("theme:listener", fn, Theme.Current())
end

-- Repaint every surface. Returns false while the class colour is unreadable.
function Theme.Refresh()
    local name = current()
    local tint, known = tintFor(name)
    for _, s in ipairs(surfaces) do API.Try("theme:paint", paint, s, name, tint) end
    local wash = Theme.PRESETS[name].wash or 1
    for _, fn in ipairs(listeners) do API.Try("theme:listener", fn, tint, wash) end
    Theme.pending = not known
    return known
end

-- PLAYER_ENTERING_WORLD: the class colour can be read by now.
function Theme.Retry()
    if Theme.pending then Theme.Refresh() end
end

Theme._test = { surfaces = surfaces }
