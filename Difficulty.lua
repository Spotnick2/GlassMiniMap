-- Difficulty.lua: the instance's group size as a glass disc on the ring, at
-- 3 o'clock (#18).
--
-- Blizzard's instance flag (MinimapCluster.InstanceDifficulty) hangs from the
-- zone header we fade, over the right end of our zone pill, so it is faded
-- (Blizzard.lua) and this disc shows the same thing. Forever has no
-- difficulties: its flag shows only the group size, 5 to 40
-- (Camelot\InstanceDifficultyOverrides.lua).
--
-- The disc MIRRORS the flag rather than re-deriving it: Blizzard's Update
-- decides (the InstanceDifficultyBannerDisabled game rule, interiors, open
-- world, its deferred update on entering) and writes the size into the frame
-- it shows, Default or, in a guild group, Guild.Instance. A hook after each
-- Update reads the finished result, never the half-switched frames.
-- The tooltip is the flag's own (GetDifficultyTooltip); the guild banner's
-- guild details are not reproduced.

GlassMiniMap = GlassMiniMap or {}
local GMM = GlassMiniMap
local API = GMM.API
local Glass = GMM.Glass
local Difficulty = {}
GMM.Difficulty = Difficulty

-- Right: clear of the sun (45) and the mail (135); the north tab orbits past
-- it like every disc when the minimap rotates.
Difficulty.ANGLE = 90

local disc, label

local function flag() return MinimapCluster and MinimapCluster.InstanceDifficulty end

local function shown(f)
    if type(f) ~= "table" then return false end
    local ok, on = pcall(f.IsShown, f)
    return ok and API.Plain(on) == true
end

-- The size Blizzard shows, or nil when its flag shows none.
function Difficulty.Size()
    local f = flag()
    if not f then return nil end
    local text
    if shown(f.Default) then
        text = f.Default.Text
    elseif shown(f.Guild) and type(f.Guild.Instance) == "table" then
        text = f.Guild.Instance.Text
    end
    if not (text and text.GetText) then return nil end
    local ok, s = pcall(text.GetText, text)
    s = ok and API.Plain(s) or nil
    if type(s) == "number" then s = tostring(s) end
    if type(s) ~= "string" or s == "" then return nil end
    return s
end

-- Blizzard's tooltip for the flag, on our disc. Forever's override adds
-- nothing for a size of 0 (between instances): then there's no tooltip.
local function tooltip(self)
    local _, _, difficulty, _, maxPlayers, _, _, _, groupSize, lfgID = GetInstanceInfo()
    difficulty, maxPlayers = API.Plain(difficulty), API.Plain(maxPlayers)
    local f = flag()
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    if f and type(f.GetDifficultyTooltip) == "function" and type(maxPlayers) == "number" and maxPlayers > 0 then
        f:GetDifficultyTooltip(maxPlayers, API.Plain(groupSize), "", nil, API.Plain(lfgID), difficulty)
    end
    if (GameTooltip:NumLines() or 0) > 0 then GameTooltip:Show() else GameTooltip:Hide() end
end

function Difficulty.Sync()
    if not disc then return end
    local size = Difficulty.Size()
    if size then label:SetText(size) end
    disc:SetShown(size ~= nil)
    if GameTooltip:IsOwned(disc) then
        if size then API.Try("difficulty:tooltip", tooltip, disc) else GameTooltip:Hide() end
    end
end

function Difficulty.Build()
    local f = flag()
    if not (f and type(f.Update) == "function") then return false end
    disc = GMM.Ring.AddDisc(Difficulty.ANGLE)
    label = Glass.Font(disc, 11, "CENTER")
    label:SetPoint("CENTER", disc, "CENTER", 0, 0)
    label:SetTextColor(1, 0.82, 0)
    disc:SetScript("OnEnter", function(self) API.Try("difficulty:tooltip", tooltip, self) end)
    disc:SetScript("OnLeave", function() GameTooltip:Hide() end)
    hooksecurefunc(f, "Update", function() API.Try("difficulty:sync", Difficulty.Sync) end)
    Difficulty.Sync()
    return true
end

function Difficulty.Disc() return disc end
function Difficulty.Label() return label end
