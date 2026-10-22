-- Fader.lua: the minimap at a lower opacity until hovered (#15;
-- docs/PLAN-zoom-ping-fader.md §3). Off by default, 60 % when on.
--
-- One alpha on MinimapCluster.MinimapContainer fades the map, our glass and
-- other addons' pins alike. Blizzard never sets or reads that frame's alpha
-- (Blizzard_Minimap, Blizzard_EditMode on the forever branch); Edit Mode only
-- scales it, and its selection overlay is the cluster's, so it stays
-- readable. Hover holds us at full while Edit Mode is open. The queue eye's
-- glass backing is a UIParent child (Queue.lua) and takes the alpha by hand;
-- Blizzard's eye itself is left alone. Off puts the container back to 1.

GlassMiniMap = GlassMiniMap or {}
local GMM = GlassMiniMap
local Fader = {}
GMM.Fader = Fader

Fader.DELAY = 1       -- seconds after the mouse leaves
Fader.TIME = 0.25     -- ...then faded over this

local anim = CreateFrame("Frame")
local alpha, goal, span = 1, 1, 1

local function apply(a)
    alpha = a
    local c = GMM.Blizzard.Container()
    if c then c:SetAlpha(a) end
    local q = GMM.Queue.Disc()
    if q then q:SetAlpha(a) end
end

local function target()
    if not GMM.Settings.Fader() then return 1 end
    if GMM.Hover.Idle() < Fader.DELAY then return 1 end      -- 0 while held too
    return GMM.Settings.FaderOpacity() / 100
end

-- Per frame, only while moving towards the goal: TIME for the whole way,
-- however far it is.
local function step(_, elapsed)
    local d = span * elapsed / Fader.TIME
    local a = goal > alpha and math.min(goal, alpha + d) or math.max(goal, alpha - d)
    apply(a)
    if a == goal then anim:SetScript("OnUpdate", nil) end
end

-- Hover's tick: a new goal starts the fade towards it.
function Fader.Update()
    local t = target()
    if t == goal then return end
    goal = t
    span = math.abs(goal - alpha)
    anim:SetScript("OnUpdate", step)
end

-- A setting changed: at once, no fade (off puts the container back to 1).
function Fader.Refresh()
    goal = target()
    anim:SetScript("OnUpdate", nil)
    apply(goal)
end

function Fader.Start()
    GMM.Hover.OnTick(Fader.Update)
    Fader.Refresh()
end

function Fader.Alpha() return alpha end

Fader._test = { anim = anim, step = step }
