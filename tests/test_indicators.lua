-- Mail and the instance's size in the pills (#27, the default): an envelope
-- in the zone pill, the size in the coords pill; or, with the "ring"
-- placement, the discs (test_mail, test_difficulty). Live switching, tooltips
-- that close with their owner, the size taken with its instance type after
-- Blizzard's Update, the coords pill back to coordinates.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GMM = loadAddon()
local H, F = GMM.Header._test, GMM.Footer._test
local envelope, zone, calendar = H.mail(), H.zoneButton(), H.calendar()
local coords, hit, pill = F.coords(), F.hit(), GMM.Footer.Pill()
local mailDisc, sizeDisc = GMM.Mail.Disc(), GMM.Difficulty.Disc()
local flag = MinimapCluster.InstanceDifficulty
local DOT = " \194\183 "

local function anchoredTo(frame, point)
    for _, p in ipairs(frame._points) do if p[1] == point then return p[2] end end
end
local function enter(i) WoW.instance = i; flag:Update() end

eq(GMM.Settings.Indicators(), "pills", "the pills by default")
eq(rawget(GlassMiniMapDB, "indicators"), nil, "...not saved")

--------------------------------------------------------------------------------
-- Mail: the envelope in the zone pill
--------------------------------------------------------------------------------
eq(envelope._shown, false, "no mail: no envelope")
eq(anchoredTo(zone, "BOTTOMRIGHT"), calendar, "the zone name runs to the calendar")
WoW.mail, WoW.senders = true, { "Thrall" }
WoW.fire("UPDATE_PENDING_MAIL")
eq(envelope._shown, true, "new mail: the envelope")
eq(mailDisc._shown, false, "...and no disc")
eq(anchoredTo(zone, "BOTTOMRIGHT"), envelope, "the zone name gives it room")
eq(anchoredTo(envelope, "RIGHT"), calendar, "the envelope left of the calendar")
envelope._scripts.OnEnter(envelope)
eq(GameTooltip._owner, envelope, "hovered: Blizzard's tooltip on the envelope")
check((GameTooltip._text or ""):find("Thrall"), "...the sender")
WoW.senders = { "Thrall", "Jaina" }
WoW.fire("UPDATE_PENDING_MAIL")
check((GameTooltip._text or ""):find("Jaina"), "...redrawn when the names come")
-- The mail read while hovered: the envelope goes, and its tooltip with it.
WoW.mail = false
WoW.fire("UPDATE_PENDING_MAIL")
eq(envelope._shown, false, "mail read: no envelope")
eq(GameTooltip._shown, false, "...its tooltip closed, no OnLeave needed")
eq(anchoredTo(zone, "BOTTOMRIGHT"), calendar, "...the zone name back to the calendar")
-- Another frame's tooltip is left alone.
GameTooltip:SetOwner(UIParent, "ANCHOR_LEFT"); GameTooltip:Show()
WoW.mail = true
WoW.fire("UPDATE_PENDING_MAIL")
eq(GameTooltip._shown, true, "someone else's tooltip stays")
GameTooltip:Hide()
-- No calendar (its game rule): the envelope at the pill's edge, then the name.
WoW.mail = false
WoW.fire("UPDATE_PENDING_MAIL")
calendar:Hide()
WoW.mail = true
WoW.fire("UPDATE_PENDING_MAIL")
eq(anchoredTo(envelope, "RIGHT"), GMM.Header.Pill(), "no calendar: the envelope at the pill's edge")
eq(anchoredTo(zone, "BOTTOMRIGHT"), envelope, "...the name runs to it")
WoW.mail = false
WoW.fire("UPDATE_PENDING_MAIL")
eq(anchoredTo(zone, "BOTTOMRIGHT"), GMM.Header.Pill(), "no calendar, no mail: the name runs to the edge")
calendar:Show()
GMM.Header.ShowMail(true); GMM.Header.ShowMail(false)

--------------------------------------------------------------------------------
-- The instance's size in the coords pill
--------------------------------------------------------------------------------
F.tick(nil, 1)
eq(coords._text, "43.2, 24.8", "outside: coordinates")
eq(hit._mouse, false, "...no hover")
enter({ type = "party", maxPlayers = 5 })
eq(coords._text, "Dungeon" .. DOT .. "5", "a dungeon: its size in the pill")
eq(coords._textColor[1], 1, "...in gold")
eq(coords._textColor[3], 0, "...(b)")
eq(sizeDisc._shown, false, "...and no disc")
eq(hit._mouse, true, "...hoverable")
eq(pill._scripts.OnUpdate, nil, "...the coordinates ticker off")
hit._scripts.OnEnter(hit)
eq(GameTooltip._owner, hit, "hovered: Blizzard's tooltip on the pill")
eq(table.concat(GameTooltip._lines, "|"), "Dungeon|5 Player", "...the flag's own")
-- Into a raid: Blizzard's Update comes 0.25 s after the instance changes, the
-- ticker every 0.2 s. Until the Update, the pill keeps the old size AND type.
WoW.instance = { type = "raid", maxPlayers = 40 }
F.tick(nil, 1)
eq(coords._text, "Dungeon" .. DOT .. "5", "before Blizzard's Update: still the dungeon's, never Raid · 5")
flag:Update()
eq(coords._text, "Raid" .. DOT .. "40", "after it: the raid's")
eq(table.concat(GameTooltip._lines, "|"), "Raid|40 Player", "the hovered tooltip follows")
-- Another kind of instance: the size alone.
enter({ type = "scenario", maxPlayers = 3 })
eq(coords._text, "3", "another kind: the size alone")
-- Out: coordinates again, their colour, no hover, the ticker on, the tooltip closed.
enter({ type = "none", maxPlayers = 0 })
eq(coords._text, "43.2, 24.8", "outside again: coordinates")
eq(coords._textColor[1], 0.92, "...their colour")
eq(hit._mouse, false, "...no hover")
check(pill._scripts.OnUpdate ~= nil, "...the ticker on")
eq(GameTooltip._shown, false, "...the pill's tooltip closed")

-- With Blizzard's coordinates off: the pill holds the zoom buttons only, and
-- widens for the size.
WoW.cvars.minimapShowPlayerCoords = false
WoW.fire("CVAR_UPDATE", "minimapShowPlayerCoords")
local narrow = pill._width
check(narrow < GMM.Footer.WIDTH, "coordinates off: a narrow pill")
eq(coords._shown, false, "...no text")
enter({ type = "party", maxPlayers = 5 })
eq(pill._width, GMM.Footer.WIDTH, "a dungeon: widened for the size")
eq(coords._shown, true, "...shown")
eq(coords._text, "Dungeon" .. DOT .. "5", "...the size")
enter({ type = "none", maxPlayers = 0 })
eq(pill._width, narrow, "out: narrow again")
eq(coords._shown, false, "...no text")
eq(pill._scripts.OnUpdate, nil, "...no ticker")
WoW.cvars.minimapShowPlayerCoords = true
WoW.fire("CVAR_UPDATE", "minimapShowPlayerCoords")

--------------------------------------------------------------------------------
-- Switching live
--------------------------------------------------------------------------------
WoW.mail = true
WoW.fire("UPDATE_PENDING_MAIL")
enter({ type = "party", maxPlayers = 5 })
hit._scripts.OnEnter(hit)
check(GMM.Settings.SetIndicators("ring"), "to the ring")
eq(rawget(GlassMiniMapDB, "indicators"), "ring", "...saved")
eq(mailDisc._shown, true, "the mail disc")
eq(envelope._shown, false, "...no envelope")
eq(sizeDisc._shown, true, "the size disc")
eq(coords._text, "43.2, 24.8", "...the pill back to coordinates (the stub has a position)")
eq(coords._textColor[1], 0.92, "...in the coordinates' colour")
eq(hit._mouse, false, "...no hover")
eq(GameTooltip._shown, false, "the pill's tooltip closed")
sizeDisc._scripts.OnEnter(sizeDisc)
eq(GameTooltip._owner, sizeDisc, "the disc's tooltip")
check(GMM.Settings.SetIndicators("pills"), "back to the pills")
eq(rawget(GlassMiniMapDB, "indicators"), nil, "...the default, not saved")
eq(GameTooltip._shown, false, "the disc's tooltip closed")
eq(sizeDisc._shown, false, "no size disc")
eq(mailDisc._shown, false, "no mail disc")
eq(envelope._shown, true, "the envelope")
eq(coords._text, "Dungeon" .. DOT .. "5", "the size in the pill")
check(not GMM.Settings.SetIndicators("left"), "an unknown placement is refused")
eq(GMM.Settings.Indicators(), "pills", "...and nothing changes")

-- The options page: one radio checked, following the setting.
GMM.Options._test.panel:Show()
local radios = GMM.Options._test.indicatorRadios
local function checked()
    local on = {}
    for _, rb in ipairs(radios) do if rb:GetChecked() then on[#on + 1] = rb.value end end
    return table.concat(on, ",")
end
eq(checked(), "pills", "options: the pills checked")
radios[2]:Click()
eq(GMM.Settings.Indicators(), "ring", "the ring radio: the ring")
eq(checked(), "ring", "...only it checked")
radios[2]:Click()
eq(checked(), "ring", "clicked again: still only it")
radios[1]:Click()
eq(checked(), "pills", "back: only the pills")

--------------------------------------------------------------------------------
-- Saved values
--------------------------------------------------------------------------------
GMM = loadAddon({ db = { indicators = "left" } })
eq(rawget(GlassMiniMapDB, "indicators"), nil, "an unknown saved placement is dropped")
eq(GMM.Settings.Indicators(), "pills", "...the default")
GMM = loadAddon({ db = { indicators = "ring" }, before = function() WoW.mail = true end })
eq(GMM.Settings.Indicators(), "ring", "the ring kept")
eq(GMM.Mail.Disc()._shown, true, "...mail at login: the disc")
eq(GMM.Header._test.mail()._shown, false, "...no envelope")

done("test_indicators")
