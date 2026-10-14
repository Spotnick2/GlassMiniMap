-- Mail.lua: the new-mail disc, on the ring at the bottom right (#18).
--
-- Blizzard's mail icon (MinimapCluster.IndicatorFrame.MailFrame) hangs under
-- the tracking button, which we fade, so it floated over the zone pill. It is
-- faded too (Blizzard.lua) and keeps doing its own work; this disc shows the
-- same thing in glass: shown while HasNewMail(), Blizzard's tooltip (the last
-- three senders) on hover. Like Blizzard's, it has no click, and it follows
-- Blizzard's own gate, the IngameMailNotificationDisabled game rule
-- (Minimap.lua:446-452).

GlassMiniMap = GlassMiniMap or {}
local GMM = GlassMiniMap
local API = GMM.API
local Mail = {}
GMM.Mail = Mail

-- Bottom right: clear of the sun (45), the drawer (225) and the eye (315), and
-- of the north tab (0) unless the minimap rotates; then the tab orbits past
-- every disc, as it does past the others.
Mail.ANGLE = 135
Mail.ICON = "Interface\\Icons\\INV_Letter_15"

local disc

local function hasMail()
    local ok, on = pcall(HasNewMail)
    return ok and API.Plain(on) == true
end

-- The latest senders we can read: Blizzard's helper concatenates them, so a
-- secret value never reaches it (GlassMail's Comforts.lua does the same).
function Mail.Senders()
    local list, got = {}, { GetLatestThreeSenders() }
    for i = 1, 3 do
        local name = got[i]
        if not API.IsSecret(name) and type(name) == "string" and name ~= "" then list[#list + 1] = name end
    end
    return list
end

-- Blizzard's MinimapMailFrameUpdate (Minimap.lua:485-490), on our disc. The
-- names can come a moment after the mail (a second UPDATE_PENDING_MAIL), so a
-- tooltip still showing is redrawn on each one.
local function tooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    local senders = Mail.Senders()
    local header = #senders >= 1 and (rawget(_G, "HAVE_MAIL_FROM") or "Unread mail from:")
        or (rawget(_G, "HAVE_MAIL") or "You have unread mail")
    FormatUnreadMailTooltip(GameTooltip, header, senders)
    GameTooltip:Show()
end

function Mail.Update()
    if not disc then return end
    local on = hasMail()
    disc:SetShown(on)
    if on and GameTooltip:IsOwned(disc) then API.Try("mail:tooltip", tooltip, disc) end
end

function Mail.Build()
    if API.GameRule("IngameMailNotificationDisabled") then return false end
    disc = GMM.Ring.AddDisc(Mail.ANGLE, { icon = Mail.ICON, iconCrop = true })
    disc:SetScript("OnEnter", function(self) API.Try("mail:tooltip", tooltip, self) end)
    disc:SetScript("OnLeave", function() GameTooltip:Hide() end)
    disc:SetScript("OnEvent", Mail.Update)
    API.RegisterEvent(disc, "UPDATE_PENDING_MAIL", "mail disc")
    Mail.Update()
    return true
end

function Mail.Disc() return disc end
