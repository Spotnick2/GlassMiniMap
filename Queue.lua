-- Queue.lua: Blizzard's LFG eye, mirrored to the top left of the ring, with a
-- glass disc behind it.
--
-- The eye (QueueStatusButton, its own Edit Mode system: GroupFinder) shows
-- while you're queued. Blizzard's default puts it at Minimap CENTER (-68, -68)
-- times the minimap's scale (Camelot\QueueStatusFrameOverrides.lua,
-- UpdateDefaultAnchor): the ring's bottom left, where the drawer's disc is
-- (the mockup's). We mirror it to (-68, +68), the top left, which also mirrors
-- the day/night disc at the top right (owner, #4).
--
-- Moving an Edit Mode system is a taint minefield (porting guide, "Edit Mode
-- systems"), so: only while the eye is in its DEFAULT position (a player who
-- moved it in Edit Mode keeps their spot), never while Edit Mode is open,
-- never inside Blizzard's call (UpdateDefaultAnchor is hooked, the move runs on
-- the next frame), out of combat if the eye is protected, and with the base
-- methods Edit Mode keeps (ClearAllPointsBase / SetPointBase), which skip its
-- snapping and anchor-change pass. Every time Blizzard places it again
-- (ApplySystemAnchor, the minimap's scale) the hook flips it again.
--
-- The glass disc is ours: a frame on UIParent (the eye's parent), centred on
-- the eye, at its scale, shown and hidden with it. The eye itself is never
-- restyled. Levels: Blizzard draws the eye's art (QueueStatusButton.Eye) one
-- level under the button (QueueStatusFrame.lua:165), and LibGlass puts a
-- disc's rims on g.top at host + 10, so the whole disc, g.top included, is
-- kept one level under the eye's art (LibGlass's Pill does the same with its
-- g.top), or the rim drew over the animated eye (Codex, PR #11).

GlassMiniMap = GlassMiniMap or {}
local GMM = GlassMiniMap
local API = GMM.API
local Queue = {}
GMM.Queue = Queue

Queue.SIZE = 44            -- the eye is 45 x 45; its round art sits inside the glass rim

local disc, glass, waiter
local scheduled = false

local function eye() return rawget(_G, "QueueStatusButton") end

local function plain(obj, method, ...)
    local ok, a, b, c, d, e = pcall(obj[method], obj, ...)
    if not ok then return nil end
    return API.Plain(a), API.Plain(b), API.Plain(c), API.Plain(d), API.Plain(e)
end

local function editModeOpen()
    local em = rawget(_G, "EditModeManagerFrame")
    return type(em) == "table" and em.IsShown ~= nil and plain(em, "IsShown") == true
end

-- Flip Blizzard's default anchor to the top: (x, y) -> (x, -y). Returns
-- whether the eye now sits at the top left. Exposed for the tests.
function Queue.Mirror()
    local e = eye()
    if not (e and e.SetPointBase and e.ClearAllPointsBase) then return false end
    if type(e.IsInDefaultPosition) == "function" and plain(e, "IsInDefaultPosition") ~= true then
        return false                 -- the player placed it in Edit Mode: theirs
    end
    if editModeOpen() then return false end
    if API.Plain(InCombatLockdown()) ~= false and plain(e, "IsProtected") ~= false then
        waiter:RegisterEvent("PLAYER_REGEN_ENABLED")
        return false
    end
    local point, rel, relPoint, x, y = plain(e, "GetPoint", 1)
    if rel ~= Minimap or type(x) ~= "number" or type(y) ~= "number" then return false end
    if y > 0 then return true end    -- already mirrored
    e:ClearAllPointsBase()
    e:SetPointBase(point, rel, relPoint, x, -y)
    return true
end

local function request()
    if scheduled then return end
    scheduled = true
    C_Timer.After(0, function()
        scheduled = false
        API.Try("eye:mirror", Queue.Mirror)
    end)
end
Queue.Request = request

-- Follow the eye: shown, scale (Edit Mode's), strata and level under it.
function Queue.Sync()
    local e = eye()
    if not (disc and e) then return end
    local scale = plain(e, "GetScale")
    if type(scale) == "number" and scale > 0 then disc:SetScale(scale) end
    local strata = plain(e, "GetFrameStrata")
    if type(strata) == "string" then disc:SetFrameStrata(strata) end
    -- Under the eye's art (Eye, at button - 1), rims included.
    local art = type(e.Eye) == "table" and e.Eye or e
    local level = plain(art, "GetFrameLevel")
    if type(level) == "number" then
        local under = math.max(0, level - 1)
        disc:SetFrameLevel(under)
        if glass and glass.top then glass.top:SetFrameLevel(under) end
    end
    disc:SetShown(plain(e, "IsShown") == true)
end

function Queue.Build()
    local e = eye()
    if not e then return false end
    disc = CreateFrame("Frame", nil, UIParent)
    disc:SetSize(Queue.SIZE, Queue.SIZE)
    disc:SetPoint("CENTER", e, "CENTER", 0, 0)
    disc:EnableMouse(false)            -- every click is the eye's
    disc:Hide()
    glass = GMM.Glass.Disc(disc, "disc_small")
    GMM.Theme.Register(glass)
    -- Script hooks see every show and hide; the scale hook follows Edit Mode.
    e:HookScript("OnShow", Queue.Sync)
    e:HookScript("OnHide", Queue.Sync)
    if type(e.SetScale) == "function" then hooksecurefunc(e, "SetScale", Queue.Sync) end
    Queue.Sync()

    -- The mirror: after every placement of Blizzard's, after Edit Mode closes
    -- and after a layout change, after combat when it had to wait.
    waiter = CreateFrame("Frame")
    waiter:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_REGEN_ENABLED" then self:UnregisterEvent(event) end
        request()
    end)
    API.RegisterEvent(waiter, "EDIT_MODE_LAYOUTS_UPDATED", "lfg eye")
    if type(e.UpdateDefaultAnchor) == "function" then
        hooksecurefunc(e, "UpdateDefaultAnchor", request)
    end
    -- Blizzard also calls it from EventRegistry's Minimap.OnScaleUpdated with
    -- the function it registered at OnLoad (QueueStatusFrame.lua:12), which the
    -- hook above doesn't wrap: listen there too (Codex, PR #11).
    local registry = rawget(_G, "EventRegistry")
    if type(registry) == "table" and type(registry.RegisterCallback) == "function" then
        API.Try("eye:scale", registry.RegisterCallback, registry, "Minimap.OnScaleUpdated", request, Queue)
    end
    local em = rawget(_G, "EditModeManagerFrame")
    if type(em) == "table" and em.HookScript then em:HookScript("OnHide", request) end
    request()
    return true
end

function Queue.Disc() return disc end
function Queue.Glass() return glass end
