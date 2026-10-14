-- The new-mail disc: Blizzard's mail icon (IndicatorFrame.MailFrame) faded,
-- a glass disc on the ring at the bottom right instead, shown only while
-- there's mail, with Blizzard's tooltip (#18).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GMM = loadAddon()
local blizz = MinimapCluster.IndicatorFrame.MailFrame
local disc = GMM.Mail.Disc()

-- Blizzard's icon: faded, mouse off, and it stays faded when Blizzard shows it.
check(disc ~= nil, "the disc is built")
eq(blizz._alpha, 0, "Blizzard's mail icon is faded")
eq(blizz._mouse, false, "...and takes no mouse")
blizz:Show()
eq(blizz._alpha, 0, "Blizzard showing it on new mail: still faded")
eq(blizz._shown, true, "...never hidden: Blizzard's own code keeps running")

-- On the ring at 135 degrees (bottom right), parented like the other discs.
local p = disc._points[1]
eq(p[2], GMM.Ring.Host(), "anchored to the ring")
check(p[4] > 0 and p[5] < 0, "bottom right of the map's centre")
near(p[4], -p[5], "on the diagonal (135 degrees)")
eq(disc._parent, GMM.Ring.Container(), "in the minimap's container (Edit Mode's scale)")

-- Shown only while there's mail. The client sends the mail first and the
-- senders' names with a second UPDATE_PENDING_MAIL (GlassMail's probe).
eq(disc._shown, false, "no mail: no disc")
WoW.mail, WoW.senders = true, {}
WoW.fire("UPDATE_PENDING_MAIL")
eq(disc._shown, true, "new mail: the disc shows")

-- Blizzard's tooltip: the plain header until the names arrive...
disc._scripts.OnEnter(disc)
eq(GameTooltip._owner, disc, "the tooltip is the disc's")
eq(GameTooltip._text, "You have unread mail", "no senders yet: the plain header")
-- ...then, still hovered, it's redrawn with them.
WoW.senders = { "Thrall", "Jaina" }
WoW.fire("UPDATE_PENDING_MAIL")
eq(GameTooltip._text, "Unread mail from:\nThrall\nJaina", "the latest senders, redrawn")
disc._scripts.OnLeave(disc)

-- A secret name never reaches Blizzard's concatenation.
local secret = "Thrall (secret)"   -- a secret is a string the addon may not read
issecretvalue = function(v) return v == secret end
WoW.senders = { secret, "Jaina" }
disc._scripts.OnEnter(disc)
eq(GameTooltip._text, "Unread mail from:\nJaina", "a secret sender is left out")
WoW.senders = { secret }
disc._scripts.OnEnter(disc)
eq(GameTooltip._text, "You have unread mail", "only secrets: the plain header")
issecretvalue = function() return false end
disc._scripts.OnLeave(disc)

-- Someone else's tooltip is left alone.
GameTooltip:SetOwner(UIParent); GameTooltip:SetText("theirs")
WoW.fire("UPDATE_PENDING_MAIL")
eq(GameTooltip._text, "theirs", "another frame's tooltip: untouched")

WoW.mail = false
WoW.fire("UPDATE_PENDING_MAIL")
eq(disc._shown, false, "mail read: the disc goes")
eq(#GMM.failures, 0, "no failures")

-- Mail at login: shown from the start.
GMM = loadAddon({ before = function() WoW.mail = true end })
eq(GMM.Mail.Disc()._shown, true, "mail waiting at login: shown at once")

-- Blizzard's game rule off-switch: no disc, as Blizzard shows no icon.
GMM = loadAddon({ before = function()
    Enum.GameRule = { IngameMailNotificationDisabled = 7 }
    C_GameRules.IsGameRuleActive = function(id) return id == 7 end
end })
eq(GMM.Mail.Disc(), nil, "mail notifications disabled by the game: no disc")
Enum.GameRule, C_GameRules.IsGameRuleActive = nil, function() return false end

done("test_mail")
