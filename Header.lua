-- Header.lua: the zone pill above the ring.
--
--   [ magnifier |  Zone Name  (envelope) calendar ]
--
-- The envelope shows while there's new mail, with the pills placement (the
-- default; Mail.lua decides, #27): the zone name gives it room.
-- The magnifier opens the glass tracking menu (right-click: Blizzard's own,
-- Tracking.lua's fallback). The zone name is coloured by the zone's PvP state
-- as Blizzard colours it (Minimap.lua, Minimap_Update) and opens the world map.
-- The calendar shows today's page (Blizzard's atlas) and opens the calendar,
-- or the pending invites, through Blizzard's own click handler.
-- Our frames stay unnamed, so no minimap-button collector ever grabs them.

GlassMiniMap = GlassMiniMap or {}
local GMM = GlassMiniMap
local API = GMM.API
local Theme = GMM.Theme
local Header = {}
GMM.Header = Header

Header.WIDTH, Header.HEIGHT = 186, 24
Header.BUTTON = 22

-- Blizzard's zone colours (Minimap.lua, Minimap_Update).
Header.PVP_COLORS = {
    sanctuary = { 0.41, 0.8, 0.94 },
    arena     = { 1.0, 0.1, 0.1 },
    friendly  = { 0.1, 1.0, 0.1 },
    hostile   = { 1.0, 0.1, 0.1 },
    contested = { 1.0, 0.7, 0.0 },
}
Header.DEFAULT_COLOR = { 1.0, 0.82, 0.0 }   -- NORMAL_FONT_COLOR

local pill, zoneButton, zoneText, tracking, calendar, invites, mail

local function pvpInfo()
    if not (C_PvP and C_PvP.GetZonePVPInfo) then return nil end
    local ok, pvpType, _, faction = pcall(C_PvP.GetZonePVPInfo)
    if not ok then return nil end
    return API.Plain(pvpType), API.Plain(faction)
end

function Header.ColorFor(pvpType)
    return Header.PVP_COLORS[pvpType] or Header.DEFAULT_COLOR
end

function Header.UpdateZone()
    if not zoneText then return end
    local ok, text = pcall(GetMinimapZoneText)
    text = ok and API.Plain(text) or nil
    zoneText:SetText(type(text) == "string" and text or "")
    local c = Header.ColorFor((pvpInfo()))
    zoneText:SetTextColor(c[1], c[2], c[3])
end

-- The zone tooltip's lines, as Blizzard's Minimap_SetTooltip writes them
-- (Minimap.lua:179-215). Not called: it only writes when GameTooltip is owned
-- by MinimapCluster.ZoneTextButton, so on our pill it added nothing (Codex,
-- PR #6). Returns { { text, r, g, b }, ... }.
local function gs(name, fallback)
    local v = rawget(_G, name)
    return type(v) == "string" and v or fallback
end

local function plainText(fn)
    local f = rawget(_G, fn)
    if type(f) ~= "function" then return nil end
    local ok, v = pcall(f)
    v = ok and API.Plain(v) or nil
    return type(v) == "string" and v or nil
end

function Header.TooltipLines(pvpType, faction, zone, subzone)
    if subzone == zone then subzone = "" end
    local lines = { { zone or "", 1, 1, 1 } }
    local function add(text, c) lines[#lines + 1] = { text, c[1], c[2], c[3] } end
    local c = Header.PVP_COLORS[pvpType]
    local hasFaction = type(faction) == "string" and faction ~= ""
    local controlled = gs("FACTION_CONTROLLED_TERRITORY", "(%s Territory)")
    if pvpType == "sanctuary" then
        add(subzone, c); add(gs("SANCTUARY_TERRITORY", "(Sanctuary)"), c)
    elseif pvpType == "arena" then
        add(subzone, c); add(gs("FREE_FOR_ALL_TERRITORY", "(PvP Area)"), c)
    elseif (pvpType == "friendly" or pvpType == "hostile") then
        if hasFaction then add(subzone, c); add(controlled:format(faction), c) end
    elseif pvpType == "contested" then
        add(subzone, c); add(gs("CONTESTED_TERRITORY", "(Contested Territory)"), c)
    elseif pvpType == "combat" then
        local red = { 1.0, 0.1, 0.1 }
        add(subzone, red); add(gs("COMBAT_ZONE", "(Combat Zone)"), red)
    else
        add(subzone, Header.DEFAULT_COLOR)
    end
    return lines
end

local function zoneTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    local pvpType, faction = pvpInfo()
    local zone = plainText("GetZoneText") or zoneText:GetText() or ""
    local subzone = plainText("GetSubZoneText") or ""
    for _, l in ipairs(Header.TooltipLines(pvpType, faction, zone, subzone)) do
        if l[1] ~= "" then GameTooltip:AddLine(l[1], l[2], l[3], l[4]) end
    end
    GameTooltip:AddLine("Click: world map", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- Calendar
--------------------------------------------------------------------------------

function Header.Today()
    local fn = C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime
    if not fn then return nil end
    local ok, t = pcall(fn)
    if not ok or type(t) ~= "table" then return nil end
    local day = API.Plain(t.monthDay)
    return type(day) == "number" and day or nil
end

function Header.UpdateCalendar()
    if not calendar then return end
    local day = Header.Today()
    if day then
        API.SetIcon(calendar.icon, ("ui-hud-calendar-%d-up"):format(day))
    end
    local n = 0
    if C_Calendar and C_Calendar.GetNumPendingInvites then
        local ok, v = pcall(C_Calendar.GetNumPendingInvites)
        n = ok and API.Plain(v) or 0
        if type(n) ~= "number" then n = 0 end
    end
    invites:SetText(n > 0 and tostring(n) or "")
    invites:SetShown(n > 0)
end

local function openCalendar()
    local click = rawget(_G, "GameTimeFrame_OnClick")
    local frame = rawget(_G, "GameTimeFrame")
    if type(click) == "function" and frame then
        API.Try("calendar", click, frame)
    elseif type(rawget(_G, "ToggleCalendar")) == "function" then
        API.Try("calendar", ToggleCalendar)
    end
    Header.UpdateCalendar()
end

--------------------------------------------------------------------------------
-- Mail
--------------------------------------------------------------------------------

-- The right end of the pill, right to left: the calendar (unless its game
-- rule hides it), the envelope while shown, then the zone name.
local function layoutRight()
    local edge, point = pill, "RIGHT"
    if calendar:IsShown() then edge, point = calendar, "LEFT" end
    mail:ClearAllPoints()
    mail:SetPoint("RIGHT", edge, point, edge == pill and -3 or 0, 0)
    if mail:IsShown() then edge, point = mail, "LEFT" end
    zoneButton:ClearAllPoints()
    zoneButton:SetPoint("TOPLEFT", tracking, "TOPRIGHT", 4, 0)
    if edge == pill then
        zoneButton:SetPoint("BOTTOMRIGHT", pill, "BOTTOMRIGHT", -6, 0)
    else
        zoneButton:SetPoint("BOTTOMRIGHT", edge, "BOTTOMLEFT", -2, 0)
    end
end

function Header.ShowMail(on)
    if not mail or mail:IsShown() == (on == true) then return end
    mail:SetShown(on == true)
    layoutRight()
end

function Header.MailButton() return mail end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

local function iconButton(parent, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b:RegisterForClicks("AnyUp")
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("CENTER")
    icon:SetSize(size - 6, size - 6)
    b.icon = icon
    b:SetHighlightTexture(GMM.MEDIA .. "orb_mask", "ADD")
    local hl = b:GetHighlightTexture()
    if hl then hl:SetAlpha(0.15) end
    return b
end

function Header.Build()
    local container, host = GMM.Ring.Container(), GMM.Ring.Host()
    pill = CreateFrame("Frame", nil, container)
    pill:SetSize(Header.WIDTH, Header.HEIGHT)
    -- Its bottom on the north tab's tip: with the cluster at the screen's top
    -- edge (Edit Mode's default), its top stays inside the cluster.
    pill:SetPoint("BOTTOM", host, "TOP", 0, 9)
    pill:SetFrameLevel(GMM.Ring.AboveMap(4))
    local g = GMM.Glass.Apply(pill, "small")
    Theme.Register(g)
    local content = GMM.Glass.ContentLevel(pill)

    tracking = iconButton(pill, Header.BUTTON)
    tracking:SetPoint("LEFT", pill, "LEFT", 3, 0)
    tracking:SetFrameLevel(content)
    tracking.icon:SetTexture(GMM.MEDIA .. "magnifier")
    tracking.icon:SetSize(15, 15)
    tracking.icon:SetVertexColor(0.88, 0.92, 1)
    tracking:SetScript("OnClick", function(self, mouse)
        if mouse == "RightButton" then
            GMM.Tracking.Close()
            GMM.Blizzard.OpenTrackingMenu(pill)
        else
            GMM.Tracking.Toggle(pill)
        end
    end)
    tracking:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Tracking")
        GameTooltip:AddLine("Click: what the minimap shows", 1, 1, 1)
        GameTooltip:AddLine("Right-click: Blizzard's menu", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    tracking:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- The hairline divider after the magnifier (the mockup's).
    local div = pill:CreateTexture(nil, "ARTWORK")
    div:SetColorTexture(1, 1, 1, 0.14)
    div:SetSize(1, Header.HEIGHT - 10)
    div:SetPoint("LEFT", tracking, "RIGHT", 2, 0)

    calendar = iconButton(pill, Header.BUTTON)
    calendar:SetPoint("RIGHT", pill, "RIGHT", -3, 0)
    calendar:SetFrameLevel(content)
    calendar.icon:SetSize(17, 17)
    calendar:SetScript("OnClick", openCalendar)
    calendar:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Calendar")
        GameTooltip:Show()
    end)
    calendar:SetScript("OnLeave", function() GameTooltip:Hide() end)
    invites = GMM.Glass.Font(calendar, 10, "CENTER")
    invites:SetPoint("BOTTOMRIGHT", calendar, "BOTTOMRIGHT", 2, -2)
    invites:SetTextColor(1, 0.82, 0)
    if API.GameRule("IngameCalendarDisabled") then calendar:Hide() end
    if API.GameRule("IngameTrackingDisabled") then tracking:Hide() end

    -- The envelope: Mail.lua shows it and gives it Blizzard's tooltip.
    mail = iconButton(pill, Header.BUTTON)
    mail:SetFrameLevel(content)
    mail.icon:SetTexture(GMM.Mail.ICON)
    mail.icon:SetSize(15, 15)
    mail.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local mask = mail:CreateMaskTexture()
    mask:SetTexture(GMM.MEDIA .. "orb_mask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(mail.icon)
    mail.icon:AddMaskTexture(mask)
    mail:SetScript("OnEnter", function(self) API.Try("mail:tooltip", GMM.Mail.Tooltip, self) end)
    mail:SetScript("OnLeave", function() GameTooltip:Hide() end)
    mail:Hide()

    zoneButton = CreateFrame("Button", nil, pill)
    zoneButton:SetFrameLevel(content)
    layoutRight()
    zoneText = GMM.Glass.Font(zoneButton, 14, "CENTER")
    zoneText:SetAllPoints(zoneButton)
    zoneButton:SetScript("OnClick", function()
        if type(rawget(_G, "ToggleWorldMap")) == "function" then API.Try("world map", ToggleWorldMap) end
    end)
    zoneButton:SetScript("OnEnter", zoneTooltip)
    zoneButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    pill:SetScript("OnEvent", function(_, event)
        if event == "CALENDAR_UPDATE_PENDING_INVITES" then Header.UpdateCalendar()
        else Header.UpdateZone() end
    end)
    API.RegisterEvents(pill, { "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA",
                               "PLAYER_ENTERING_WORLD", "CALENDAR_UPDATE_PENDING_INVITES" }, "zone pill")
    -- Blizzard re-dates its own button at midnight and at login: follow it.
    if type(rawget(_G, "GameTimeFrame_SetDate")) == "function" then
        hooksecurefunc("GameTimeFrame_SetDate", function() Header.UpdateCalendar() end)
    end
    Header.UpdateZone()
    Header.UpdateCalendar()
    return pill
end

function Header.Pill() return pill end
function Header.TrackingButton() return tracking end

Header._test = {
    zoneText = function() return zoneText end, tracking = function() return tracking end,
    calendar = function() return calendar end, invites = function() return invites end,
    zoneButton = function() return zoneButton end, mail = function() return mail end,
}
