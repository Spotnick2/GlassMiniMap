-- Theme.lua: the three looks of the glass, repainted live on every surface.
--
-- clear   the material as LibGlass built it (cool, light)
-- smoked  AltStable's darker body (its numbers, as GlassPanel and GlassMail use them)
-- class   the clear body tinted by the player's class colour, shaded by
--         classShade: at full strength it reads as painted plastic (AltStable,
--         in game). The class colour may be unreadable early in a login; the
--         surface then stays clear and PLAYER_ENTERING_WORLD paints it again.
--
-- The tint in effect (#37): Glass UI's suite tint while we follow its look,
-- else the player's own (GlassMiniMapDB.look.tint, kept and unused while
-- following, like the material), else clear. While following, the numbers
-- are Glass UI's (Suite.Body: its clear has a tint of its own); otherwise
-- ours, below. Every consumer (Register, Current,
-- Refresh) goes through recipe(), so they can't disagree.
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
local Theme = {}
GMM.Theme = Theme

Theme.NAMES = { "clear", "smoked", "class" }
Theme.LABELS = { clear = "Clear glass", smoked = "Smoked glass", class = "Class colour glass" }
Theme.PRESETS = {
    clear  = {},
    smoked = { tint = { 0.05, 0.06, 0.08, 0.62 }, wash = 0.14 / 0.18 },
    class  = { classShade = 0.6 },
}

local surfaces = {}   -- { g = , kind = "glass" | "orb" }
local listeners = {}  -- fn(tint|nil, wash): tint = { r, g, b, a|nil }, nil = as built
Theme.pending = false

function Theme.IsValid(name) return Theme.PRESETS[name] ~= nil end

-- The player's own tint, or nil. Read raw: GlassMiniMapDB.look is never
-- pruned against a default, so a chosen clear survives.
function Theme.Own()
    local look = GMM.db and rawget(GMM.db, "look")
    local v = type(look) == "table" and rawget(look, "tint") or nil
    return Theme.PRESETS[v] and v or nil
end

-- The tint in effect.
function Theme.Name()
    if GMM.Suite.LookFollowing() then return GMM.Suite.Tint() or "clear" end
    return Theme.Own() or "clear"
end

-- A tint's numbers: Glass UI's while following, else ours.
local function recipe(name)
    return GMM.Suite.Body(name) or Theme.PRESETS[name]
end

-- The tint for a recipe as r, g, b, a (a nil: the surface's own), or nothing
-- for "as built". Second return: false while the class colour is wanted but
-- unreadable.
local function tintFor(name, p)
    if p.tint then return p.tint, true end
    if name == "class" and p.classShade then
        local r, g, b = API.ClassColor()
        if not r then return nil, false end
        return { r * p.classShade, g * p.classShade, b * p.classShade }, true
    end
    return nil, true
end

-- The wash is a gradient, and a gradient texture ignores SetAlpha on this
-- client (70374; porting guide §3, LibGlass#47): its strength is the top
-- colour of its gradient. The recipe's wash multiplies the built one.
local function washTop(p)
    return math.max(0, math.min(1, (GMM.Glass.STYLE.wash or 0) * (p.wash or 1)))
end

local function paintGlass(s, p, tint)
    local Glass = GMM.Glass
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
local function paintOrb(s, p, tint)
    local base = GMM.Glass.STYLE.tint
    local c = tint or base
    local a = (tint and tint[4]) or math.max(base[4], 0.35)
    s.g.tint:SetColorTexture(c[1], c[2], c[3], a)
    if s.g.wash then
        local top = washTop(p)
        s.g.wash:SetGradient("VERTICAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, top))
        s.g.wash:SetShown(top > 0)
    end
end

local function paint(s, p, tint)
    if s.kind == "orb" then paintOrb(s, p, tint) else paintGlass(s, p, tint) end
end

-- Add a surface and paint it with the current theme.
function Theme.Register(g, kind)
    if type(g) ~= "table" or not g.tint then return end
    local s = { g = g, kind = kind or "glass" }
    surfaces[#surfaces + 1] = s
    local name = Theme.Name()
    local p = recipe(name)
    API.Try("theme:paint", paint, s, p, (tintFor(name, p)))
end

-- The current look for someone else's glass: tint (nil = as built) and the
-- wash as a multiplier of the built one.
function Theme.Current()
    local name = Theme.Name()
    local p = recipe(name)
    local tint = tintFor(name, p)
    return tint, p.wash or 1
end

-- fn(tint, wash) now and on every repaint.
function Theme.OnChange(fn)
    listeners[#listeners + 1] = fn
    API.Try("theme:listener", fn, Theme.Current())
end

-- Repaint every surface. Returns false while the class colour is unreadable.
function Theme.Refresh()
    local name = Theme.Name()
    local p = recipe(name)
    local tint, known = tintFor(name, p)
    for _, s in ipairs(surfaces) do API.Try("theme:paint", paint, s, p, tint) end
    local wash = p.wash or 1
    for _, fn in ipairs(listeners) do API.Try("theme:listener", fn, tint, wash) end
    Theme.pending = not known
    return known
end

-- PLAYER_ENTERING_WORLD: the class colour can be read by now.
function Theme.Retry()
    if Theme.pending then Theme.Refresh() end
end

Theme._test = { surfaces = surfaces }
