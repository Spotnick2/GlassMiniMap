-- Queue.lua: a glass disc behind Blizzard's LFG eye.
--
-- The eye (QueueStatusButton, its own Edit Mode system) shows while you're
-- queued, at Minimap CENTER (-68, -68) by default: on the ring at the bottom
-- left (measured on 70374; issue #4). It is left exactly where and how
-- Blizzard puts it, and only gets a glass disc of ours behind it so it
-- matches the other discs: a frame on UIParent (the eye's parent), centred on
-- the eye, one level under it, at its scale, shown and hidden with it. The
-- drawer's disc moved to the bottom right to make room (Drawer.lua).

GlassMiniMap = GlassMiniMap or {}
local GMM = GlassMiniMap
local API = GMM.API
local Glass = GMM.Glass
local Queue = {}
GMM.Queue = Queue

Queue.SIZE = 44            -- the eye is 45 x 45; its round art sits inside the glass rim

local disc

local function eye() return rawget(_G, "QueueStatusButton") end

local function plain(obj, method)
    local ok, v = pcall(obj[method], obj)
    if not ok then return nil end
    return API.Plain(v)
end

-- Follow the eye: shown, scale (Edit Mode's), strata and level under it.
function Queue.Sync()
    local e = eye()
    if not (disc and e) then return end
    local scale = plain(e, "GetScale")
    if type(scale) == "number" and scale > 0 then disc:SetScale(scale) end
    local strata = plain(e, "GetFrameStrata")
    if type(strata) == "string" then disc:SetFrameStrata(strata) end
    local level = plain(e, "GetFrameLevel")
    if type(level) == "number" then disc:SetFrameLevel(math.max(0, level - 1)) end
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
    GMM.Theme.Register(Glass.Disc(disc, "disc_small"))
    -- Script hooks see every show and hide (Show, SetShown, a parent's); the
    -- scale hook follows Edit Mode. Nothing of the eye's is replaced.
    e:HookScript("OnShow", Queue.Sync)
    e:HookScript("OnHide", Queue.Sync)
    if type(e.SetScale) == "function" then hooksecurefunc(e, "SetScale", Queue.Sync) end
    Queue.Sync()
    return true
end

function Queue.Disc() return disc end
