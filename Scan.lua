-- Scan.lua: the public scan API (#56), for addons that borrow Blizzard's
-- Minimap for a few frames. NodeRadar's scan mode (NodeRadar#91) moves it under
-- the resting cursor, at alpha 0, because on 70862 the minimap's mouseover
-- reads only under the real cursor (Minimap:UpdateMouseoverAtPoint is a
-- no-op, Stanzilla/WoWUIBugs#894). The contract is docs/PUBLIC-API.md.
--
-- Version 1 means nothing of ours is parented or anchored to Minimap: the ring
-- sits on the container's centre (Ring.lua), so a borrowed map leaves our
-- glass at home. What a scan still needs from us is quiet: the auto zoom-out
-- pauses (its SetZoom would spoil the borrower's reads), and the glass behind
-- Blizzard's LFG eye (on the map, Blizzard's anchor) hides.
--
-- What keeps it stable (Glass MiniMap Bar's rules):
--   * PUBLIC_API_VERSION changes on ANY incompatible change. Adding a function
--     does not bump it.
--   * ScanBegin refuses only a bad owner: a borrower that stops after a few
--     refusals (NodeRadar does, after three) must never see a transient one.
--   * neither function throws. They change our own state and frames only: the
--     first Begin and the last release re-sync the eye's glass (Queue.Sync,
--     which also clamps Blizzard's tip on the eye, as on every sync: #53).

GlassMiniMap = GlassMiniMap or {}
local GMM = GlassMiniMap
local API = GMM.API
local Scan = {}
GMM.Scan = Scan

GlassMiniMap.PUBLIC_API_VERSION = 1

Scan.TIMEOUT = 1          -- seconds after an owner's last ScanBegin with no ScanEnd

-- owner -> the token of its latest ScanBegin. A timer releases its owner only
-- while that token is still the owner's, so a re-Begin or an End disarms it.
local active = {}
local count, serial = 0, 0

-- The one piece of ours that follows the map: the glass behind Blizzard's LFG
-- eye, which Blizzard anchors to Minimap. Hidden while a scan is under way, so
-- an eye shown mid-scan (a queue pop) never brings our glass to the cursor
-- (Codex, #56). Our own frame, not protected: safe from any caller.
local function changed()
    local q = GMM.Queue
    if q and q.Sync then pcall(q.Sync) end
end

local function validOwner(owner)
    return type(owner) == "string" and owner ~= ""
end

local function release(owner)
    if active[owner] == nil then return false end
    active[owner] = nil
    count = count - 1
    if count == 0 then changed() end
    return true
end

local function begin(owner)
    serial = serial + 1
    local token = serial
    local first = count == 0
    if active[owner] == nil then count = count + 1 end
    active[owner] = token
    if first then changed() end
    C_Timer.After(Scan.TIMEOUT, function()
        if active[owner] ~= token then return end
        release(owner)
        API.Fail("scan:" .. owner, "no ScanEnd within " .. Scan.TIMEOUT .. " s: released")
    end)
end

-- A borrow of Minimap starts. True when acquired; false only for a bad owner
-- (not a non-empty string) or if this function failed inside. A second Begin
-- from an active owner restarts its timeout; one ScanEnd clears it.
function GlassMiniMap.ScanBegin(owner)
    if not validOwner(owner) then return false end
    return pcall(begin, owner) == true
end

-- The borrow ended. Idempotent: an unowed, repeated or late call (after the
-- self-release) does nothing.
function GlassMiniMap.ScanEnd(owner)
    if not validOwner(owner) then return end
    pcall(release, owner)
end

-- Internal: is any borrow under way?
function Scan.Active() return count > 0 end

Scan._test = { active = active, count = function() return count end }
