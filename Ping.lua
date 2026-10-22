-- Ping.lua: who pinged the minimap, in glass (#14;
-- docs/PLAN-zoom-ping-fader.md §2). On by default, "map".
--
-- MINIMAP_PING -> unitTarget, y, x (the 70450 dump: y before x). It's a
-- callback event: RegisterEvent refuses it ("unknown event", the owner on
-- 70450), Blizzard's MinimapDocumentation.lua flags it CallbackEvent (and
-- SecretPayloads), and Minimap.lua:127 takes it with RegisterEventCallback.
-- Blizzard's Event.RegisterCallback hands us the payload alone. It fires
-- once per alias of the pinger ("party1", "target", "focus"...), so the same
-- unit at the same spot within a second is one ping. Our own pings show
-- nothing. Another player's name and class may be secret on this client:
-- every value is made plain before anything compares it, the unit token
-- before UnitIsUnit, and a secret name shows nothing (a secret class: the
-- name in white).
--
-- "map": a small glass pill just above the ping, in the pinger's class
-- colour, for 3 s, then faded over 1 s by an Alpha animation. The ping is
-- anchored in the world and moves as the player does, so the pill follows
-- GetPingPosition while shown: the offset from the map's centre divided by
-- its width (measured: the porting guide, NodeRadar #28). "chat": one line.

GlassMiniMap = GlassMiniMap or {}
local GMM = GlassMiniMap
local API = GMM.API
local Theme = GMM.Theme
local Ping = {}
GMM.Ping = Ping

Ping.SHOW = 3
Ping.FADE = 1
Ping.THROTTLE = 1
Ping.HEIGHT = 18
Ping.LIFT = 8          -- the pill's bottom this far above the ping
Ping.EDGE = 10         -- kept this far inside the map's circle

local pill, text, fade, last

local function plain(v, kind)
    v = API.Plain(v)
    if type(v) == kind then return v end
end

local function sameUnit(a, b)
    local ok, same = pcall(UnitIsUnit, a, b)
    return ok and API.Plain(same) == true
end

-- The ping's offset from the map's centre, in the map's units, clamped
-- inside its circle; nil when unreadable.
function Ping.Offset()
    local ok, px, py = pcall(Minimap.GetPingPosition, Minimap)
    px, py = ok and plain(px, "number"), ok and plain(py, "number")
    local w = plain(Minimap:GetWidth(), "number")
    if not (px and py and w and w > 0) then return nil end
    local x, y = px * w, py * w
    local max = w / 2 - Ping.EDGE
    local d = math.sqrt(x * x + y * y)
    if d > max and d > 0 then x, y = x * max / d, y * max / d end
    return x, y
end

local function place()
    local x, y = Ping.Offset()
    pill:ClearAllPoints()
    pill:SetPoint("BOTTOM", Minimap, "CENTER", x or 0, (y or 0) + Ping.LIFT)
end

-- Show the pill for `name` (plain), coloured { r, g, b } or white.
function Ping.Show(name, color)
    if not pill then return false end
    text:SetText(name)
    local c = color or { 1, 1, 1 }
    text:SetTextColor(c[1], c[2], c[3])
    local okW, w = pcall(text.GetStringWidth, text)
    w = okW and plain(w, "number") or 60
    pill:SetWidth(math.floor(w + 16 + 0.5))
    fade:Stop()
    pill:SetAlpha(1)
    place()
    pill:Show()
    fade:Play()
    return true
end

local function say(name, color)
    local c = color or { 1, 1, 1 }
    API.Print(("ping: |cff%02x%02x%02x%s|r"):format(c[1] * 255, c[2] * 255, c[3] * 255, name))
end

-- MINIMAP_PING's payload: unitTarget, y, x.
function Ping.OnPing(unit, y, x)
    local where = GMM.Settings.PingName()
    if where == "off" then return false end
    unit = plain(unit, "string")
    x, y = plain(x, "number"), plain(y, "number")
    if not (unit and x and y) then return false end
    local okMine, mine = pcall(UnitIsUnit, unit, "player")
    if not okMine or API.Plain(mine) ~= false then return false end
    local now = GetTime()
    if last and last.x == x and last.y == y and now - last.at < Ping.THROTTLE and sameUnit(unit, last.unit) then
        return false
    end
    local okN, name = pcall(UnitName, unit)
    name = okN and plain(name, "string") or nil
    if not name or name == "" then return false end
    local r, g, b = API.ClassColor(unit)
    local color = r and { r, g, b } or nil
    if where == "chat" then say(name, color) elseif not Ping.Show(name, color) then return false end
    last = { unit = unit, x = x, y = y, at = now }
    return true
end

function Ping.Build()
    local container = GMM.Ring.Container()
    pill = CreateFrame("Frame", nil, container)
    pill:SetSize(60, Ping.HEIGHT)
    pill:SetFrameLevel(GMM.Ring.AboveMap(6))
    pill:EnableMouse(false)
    Theme.Register(GMM.Glass.Apply(pill, "small"))
    text = GMM.Glass.Font(pill, 12, "CENTER")
    text:SetPoint("CENTER", pill, "CENTER", 0, 0)
    fade = pill:CreateAnimationGroup()
    local a = fade:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0)
    a:SetStartDelay(Ping.SHOW)
    a:SetDuration(Ping.FADE)
    fade:SetScript("OnFinished", function() pill:Hide() end)
    pill:SetScript("OnUpdate", place)    -- only while shown
    local E = rawget(_G, "Event")
    local ok, handle = pcall(function()
        return E.RegisterCallback("MINIMAP_PING", function(unit, y, x) API.Try("ping", Ping.OnPing, unit, y, x) end)
    end)
    if not (ok and handle) then
        API.Fail("event:MINIMAP_PING", "ping: " .. (ok and "no handle" or tostring(handle)))
    end
    pill:Hide()
    return pill
end

function Ping.Pill() return pill end

Ping._test = { text = function() return text end, fade = function() return fade end,
    reset = function() last = nil end }
