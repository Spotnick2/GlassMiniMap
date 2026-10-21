-- MinimapProbe: a ForeverProbe module (the host loaded from its checkout,
-- harness.lua's loadForeverProbe). Every command runs on the stubbed client
-- and logs what it read, never to chat; the wash, mail and instance
-- procedures' checks pass on the right state and fail on the wrong one; a
-- procedure's theme and zoom are put back, even after a Stop.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- What the probe and its host touch beyond the shared stub (all in the 70374 dump).
local clock = 100
rawset(_G, "GetTime", function() return clock end)
rawset(_G, "EnumerateFrames", function() return nil end)
rawset(_G, "Screenshot", function() WoW.shots = (WoW.shots or 0) + 1 end)

-- Clean, the material the wash numbers below were measured with (r7, #22);
-- Pearl's are checked at the end.
local GMM = loadAddon({ db = { material = "clean" } })
Minimap._cx, Minimap._cy, Minimap._effScale = 500, 400, 1
local FP = loadForeverProbe()
loadProbe()
local S = FP.Steps
local db = MinimapProbeDB

-- The newest line with this text, in the probe's saved log.
local function logged(pattern)
    for i = #db.log, 1, -1 do if db.log[i]:find(pattern) then return db.log[i] end end
end
local function errors()
    local n = 0
    for _, l in ipairs(db.log) do if l:find("ERROR") then n = n + 1 end end
    return n
end
local function fp(cmd) SlashCmdList.FOREVERPROBE(cmd) end
-- Let queued screenshots happen: the host's driver runs on OnUpdate and
-- waits for the client's answer.
local function settle()
    for _ = 1, 30 do
        clock = clock + 1.5
        WoW.tick(1.5)
        WoW.fire("SCREENSHOT_SUCCEEDED")
    end
end
local function record(name) return FP.db.steps.records["MinimapProbe/" .. name] end
local function result(name, i) return record(name).results[i] end

check(logged("loaded %(1 loads%)"), "loaded, its log bound")

-- The old commands, now /fp mm ...
for _, cmd in ipairs({ "frames", "rules", "tracking", "near", "queue" }) do fp("mm " .. cmd) end
check(logged("Minimap: 198x198"), "frames: the map's size")
check(logged("IngameTrackingDisabled: id="), "rules")
check(logged("tracking types; showAll="), "tracking")
check(logged("0 text%(s%) near the bottom%-left"), "near")
check(logged("QueueStatusButton parent"), "queue")
eq(errors(), 0, "no command threw")
eq(#WoW.chat, 0, "nothing in chat")

-- glass: as built (clear, zoom 0: the minus button disabled).
fp("mm glass")
check(logged("glass as expected: theme clear; zoom 0 of 6; ring peak 0.180 undimmed"), "glass: clear, as built")
check(logged("minus peak 0%.180 dim 0%.25"), "...the minus button dimmed at zoom 0")
-- A wash painted the old way (SetAlpha, so its peak stayed) is caught.
GMM.Settings.SetTheme("smoked")
GMM.Ring.Glass().wash.glassPeak = 0.18
fp("mm glass")
check(logged("glass NOT as expected: theme smoked.*ring peak 0%.180 undimmed %(want 0%.140 undimmed%) BAD"),
    "glass: a wash left at clear's peak fails")
GMM.Settings.SetTheme("clear")
-- A secret peak fails, never passes as a plain value.
local issecret = issecretvalue
local peakSecret = {}
issecretvalue = function(v) return v == peakSecret end
GMM.Ring.Glass().wash.glassPeak = peakSecret
fp("mm glass")
check(logged("glass NOT as expected.*ring peak <secret>"), "glass: a secret peak fails")
issecretvalue = issecret
GMM.Settings.SetTheme("clear")
-- An enabled button dimmed fails too (r7 clears glassDim when enabling).
local plusWash = GMM.Footer._test.zoomIn().glass.wash
plusWash.glassDim = 0.25
fp("mm glass")
check(logged("glass NOT as expected.*plus peak 0%.180 dim 0%.25 %(want 0%.180 undimmed%) BAD"),
    "glass: an enabled button dimmed fails")
plusWash.glassDim = nil
-- A hidden wash fails (hidden is a reading); an unreadable one fails too.
plusWash:Hide()
fp("mm glass")
check(logged("glass NOT as expected.*plus peak 0%.180 undimmed HIDDEN"), "glass: a hidden wash fails")
plusWash:Show()
issecretvalue = function(v) return v == true end      -- IsShown answers a secret
fp("mm glass")
check(logged("glass NOT as expected.*ring shown <secret>"), "glass: a secret visibility fails")
issecretvalue = issecret
-- Fully zoomed in: the plus button is the disabled one, and that's right.
Minimap._zoom = Minimap:GetZoomLevels() - 1
WoW.fire("MINIMAP_UPDATE_ZOOM")
fp("mm glass")
check(logged("glass as expected: theme clear; zoom 5 of 6.*plus peak 0%.180 dim 0%.25.*minus peak 0%.180 undimmed"),
    "glass: fully zoomed in, plus dimmed and minus not")
Minimap._zoom = 0
WoW.fire("MINIMAP_UPDATE_ZOOM")

-- discs: outside an instance, no mail.
fp("mm discs")
check(logged("mail: HasNewMail false; placement pills: envelope shown false"), "discs: no mail")
check(logged("instance: instance none, 0 players; flag none"), "discs: no instance")
eq(errors(), 0, "still no command threw")

--------------------------------------------------------------------------------
-- wash
--------------------------------------------------------------------------------
Minimap._zoom = 2
WoW.fire("MINIMAP_UPDATE_ZOOM")
GMM.Settings.SetTheme("class")
fp("steps mm wash")
eq(record("wash").status, "active", "wash: started")
eq(db.restore.tint, "class", "the tint saved first")
eq(db.restore.zoom, 2, "...and the zoom")
S.Run(); settle()                                      -- clear
eq(result("wash", 2).check, "PASS", "clear: the wash at 0.18")
check(result("wash", 2).screenshots, "...with a screenshot")
S.Run(); settle()                                      -- smoked
eq(result("wash", 3).check, "PASS", "smoked: the wash at 0.14")
S.Answer(true)
S.Run(); settle()                                      -- zoom out
eq(Minimap._zoom, 0, "zoomed fully out")
eq(result("wash", 5).check, "PASS", "the minus button dimmed, at smoked's peak")
S.Answer(true)
S.Run(); settle()                                      -- clear, zoomed out
eq(result("wash", 7).check, "PASS", "clear, zoomed out: still dimmed, at clear's peak")
S.Answer(true)
S.Run()                                                -- restore
eq(GlassMiniMapDB.look.tint, "class", "the tint put back")
eq(Minimap._zoom, 2, "...and the zoom")
eq(db.restore, nil, "nothing left to restore")
eq(record("wash").status, "done", "wash: done")

-- Stopped halfway: /fp mm restore puts it back; a second start keeps the
-- first snapshot.
GMM.Settings.SetTheme("class")
fp("steps mm wash")
S.Run(); settle()                                      -- clear
fp("steps stop")
fp("steps mm wash")
eq(db.restore.tint, "class", "a new start keeps the outstanding snapshot")
check(logged("kept the outstanding one"), "...and says so")
fp("steps stop")
eq(GlassMiniMapDB.look.tint, "clear", "stopped: still clear")
fp("mm restore")
eq(GlassMiniMapDB.look.tint, "class", "/fp mm restore: back to class")
eq(db.restore, nil, "...snapshot cleared")
fp("mm restore")
check(logged("nothing to restore"), "a second restore does nothing")

-- No tint of the player's own: saved as "none", and put back as none (no
-- override left behind, #37). The snapshot is in MinimapProbeDB, so a reload
-- in between changes nothing.
GMM.Settings.ClearTheme()
fp("steps mm wash")
eq(db.restore.tint, "none", "no own tint: saved as none")
S.Run(); settle()                                      -- clear: an override now
eq(GlassMiniMapDB.look.tint, "clear", "...the procedure set one")
fp("steps stop")
fp("mm restore")
eq(rawget(GlassMiniMapDB, "look"), nil, "restored: no override")
-- A snapshot from before #37 (the theme itself) still restores.
MinimapProbeDB.restore = { theme = "smoked", zoom = Minimap._zoom }
fp("mm restore")
eq(GlassMiniMapDB.look.tint, "smoked", "an old snapshot's theme put back")
GMM.Settings.SetTheme("clear")

-- The check fails on a wrong wash (the minus button not dimmed at zoom 0).
fp("steps mm wash")
S.Run(); settle(); S.Run(); settle(); S.Answer(true)
GMM.Footer.UpdateZoomButtons = function() end          -- the buttons never told
S.Run(); settle()
eq(result("wash", 5).check, "FAIL", "minus not dimmed at zoom 0: FAIL")
fp("steps stop")
fp("mm restore")

--------------------------------------------------------------------------------
-- mail
--------------------------------------------------------------------------------

fp("steps mm mail")
S.DoneByHand()                                         -- no mail yet, pressed Done
S.Run()
eq(result("mail", 3).check, "FAIL", "no mail: FAIL")
S.Back()
WoW.mail, WoW.senders = true, { "Alt" }
WoW.fire("UPDATE_PENDING_MAIL")
S.Run()
eq(result("mail", 3).check, "PASS", "mail: the disc shows")
check(result("mail", 3).checkDetail:find("1 sender%(s%) readable"), "...the senders counted")
check(not result("mail", 3).checkDetail:find("Alt"), "...never named")
-- Blizzard's own icon must be faded: unfaded or missing fails.
local mailCheck = FP.procedures["MinimapProbe/mail"].steps[3].check
local blizzMail = MinimapCluster.IndicatorFrame.MailFrame
blizzMail._alpha = 1
local okMail, why = mailCheck()
check(okMail == false and why:find("Blizzard's mail icon alpha 1"), "Blizzard's icon unfaded: FAIL")
blizzMail._alpha = 0
MinimapCluster.IndicatorFrame.MailFrame = false
okMail, why = mailCheck()
check(okMail == false and why:find("Blizzard's mail icon alpha MISSING"), "Blizzard's icon missing: FAIL")
MinimapCluster.IndicatorFrame.MailFrame = blizzMail
eq(select(1, mailCheck()), true, "...and faded again: PASS")
-- Each placement: its own indicator, never both.
local envelope = GMM.Header.MailButton()
GMM.Mail.Disc():Show()
eq(select(1, mailCheck()), false, "pills, the disc showing too: FAIL")
GMM.Mail.Disc():Hide()
GMM.Settings.SetIndicators("ring")
local okRing, whyRing = mailCheck()
check(okRing and whyRing:find("placement ring: disc shown true"), "ring: the disc")
envelope:Show()
eq(select(1, mailCheck()), false, "ring, the envelope showing too: FAIL")
GMM.Settings.SetIndicators("pills")
eq(select(1, mailCheck()), true, "back in the pills: PASS")
S.Run(); settle(); S.Run(); settle(); S.Run(); settle()
eq(GlassMiniMapDB.look.tint, "class", "the three themes, in turn")
S.Answer(true)
S.Skip()                                               -- Shoot skipped
S.Answer(true)                                         -- answered without a shot
eq(result("mail", 9).check, "FAIL", "no tooltip shot: FAIL")
S.Back()
S.Back()
S.Run()                                                -- Shoot: armed
S.Answer(true)                                         -- answered before the shutter
eq(result("mail", 9).check, "FAIL", "the shot not taken yet: FAIL")
check(result("mail", 9).checkDetail:find("wasn't taken yet"), "...says so")
S.Back()
WoW.flushTimers()
settle()
S.Answer(true)
eq(result("mail", 9).check, "PASS", "the tooltip shot taken")
check(result("mail", 9).checkDetail:find("WoWScrnShot_"), "...its file recorded")
S.Run()
eq(GMM.db.look.tint, "clear", "mail: the tint put back")
eq(record("mail").status, "done", "mail: done")

--------------------------------------------------------------------------------
-- instance
--------------------------------------------------------------------------------
local flag = MinimapCluster.InstanceDifficulty
fp("steps mm instance")
WoW.instance = { type = "party", maxPlayers = 5 }
WoW.fire("PLAYER_ENTERING_WORLD", false, false)      -- Blizzard's Update comes 0.25 s later
S.Run(); settle()
eq(result("instance", 2).check, "FAIL", "checked before Blizzard's flag: FAIL")
check(result("instance", 2).checkDetail:find("go Back and Check again"), "...says to check again")
S.Back()
flag:Update()
S.Run(); settle()
eq(result("instance", 2).check, "PASS", "in a dungeon: the coords pill shows Blizzard's 5")
check(result("instance", 2).checkDetail:find("instance party, 5 players; flag Default 5 alpha 0; placement pills; "
    .. "disc shown false label 5; pill \"?Dungeon \194\183 5"), "...what was read")
local insideCheck = FP.procedures["MinimapProbe/instance"].steps[2].check
-- The disc showing as well (a duplicate) fails; so does a pill without the size.
GMM.Difficulty.Disc():Show()
eq(select(1, insideCheck()), false, "pills, the disc showing too: FAIL")
GMM.Difficulty.Disc():Hide()
local pillCoords = GMM.Footer._test.coords()
pillCoords:SetText("\226\128\148")
eq(select(1, insideCheck()), false, "pills, the size missing from the pill: FAIL")
GMM.Footer.Layout()
-- On the ring: the disc with Blizzard's size, and not in the pill.
GMM.Settings.SetIndicators("ring")
eq(select(1, insideCheck()), true, "ring: the disc shows Blizzard's 5")
GMM.Difficulty.Label():SetText("40")
eq(select(1, insideCheck()), false, "ring, a label that isn't Blizzard's size: FAIL")
GMM.Difficulty.Label():SetText("5")
pillCoords:SetText(GMM.Difficulty.Text())
eq(select(1, insideCheck()), false, "ring, the size in the pill too: FAIL")
GMM.Settings.SetIndicators("pills")
-- Blizzard's coordinates off: the pill's text shows only for the size. Switched
-- to the ring, it hides and keeps the size as text: not a duplicate.
WoW.cvars.minimapShowPlayerCoords = false
WoW.fire("CVAR_UPDATE", "minimapShowPlayerCoords")
eq(select(1, insideCheck()), true, "pills, coordinates off: the size in the widened pill")
GMM.Settings.SetIndicators("ring")
eq(pillCoords._shown, false, "ring, coordinates off: the pill's text hidden")
eq(pillCoords._text, GMM.Difficulty.Text(), "...still holding the size")
local okHidden, whyHidden = insideCheck()
check(okHidden and whyHidden:find("pill hidden"), "...not a duplicate: PASS")
-- A hidden text never set (logged in on the ring with coordinates off).
pillCoords._text = nil
eq(select(1, insideCheck()), true, "ring, a hidden text never set: PASS")
GMM.Settings.SetIndicators("pills")
WoW.cvars.minimapShowPlayerCoords = true
WoW.fire("CVAR_UPDATE", "minimapShowPlayerCoords")
S.Run(); WoW.flushTimers(); settle()
S.Answer(true)
eq(result("instance", 4).check, "PASS", "the tooltip shot")
WoW.instance = { type = "none", maxPlayers = 0 }
WoW.fire("PLAYER_ENTERING_WORLD", false, false)
flag:Update()
S.Run(); settle()
eq(result("instance", 6).check, "PASS", "outside: no disc")
eq(record("instance").status, "done", "instance: done")
-- A disc left showing outside fails.
GMM.Difficulty.Disc():Show()
local ok = select(1, FP.procedures["MinimapProbe/instance"].steps[6].check())
eq(ok, false, "a disc left showing outside: FAIL")
GMM.Difficulty.Disc():Hide()

-- Restarted: the last run's tooltip shot doesn't count for this one.
fp("steps mm instance")
S.DoneByHand(); S.Run(); settle()
S.Skip()                                               -- Shoot skipped
S.Answer(true)
eq(result("instance", 4).check, "FAIL", "a restart, Shoot skipped: the old shot doesn't count")
check(result("instance", 4).checkDetail:find("no shot in this run"), "...says so")
-- Armed, then restarted before the shutter: the old run's shot is never taken.
S.Back(); S.Back()
S.Run()                                                -- Shoot: armed
local shotsBefore = WoW.shots
fp("steps stop")
fp("steps mm instance")
WoW.flushTimers(); settle()
eq(WoW.shots, shotsBefore, "the old run's shot not taken")
S.DoneByHand(); S.Run(); settle(); S.Skip(); S.Answer(true)
eq(result("instance", 4).check, "FAIL", "...and doesn't count for the new run")
fp("steps stop")

--------------------------------------------------------------------------------
-- edges (#39, #40, #42)
--------------------------------------------------------------------------------
GMM.Settings.SetTheme("class")
fp("steps mm edges")
S.Run(); settle()
eq(result("edges", 2).check, "FAIL", "edges with the runic ring off: FAIL")
check(result("edges", 2).checkDetail:find("/gmm runes on", 1, true), "...saying how to turn it on")
S.Back()
GMM.Settings.SetRunicMode(true)
GMM.Settings.SetRuneOption("fog", "off")
S.Run(); settle()
eq(result("edges", 2).check, "FAIL", "...and with its vapor off")
S.Back()
GMM.Settings.SetRuneOption("fog", "on")
S.Run(); settle()
eq(result("edges", 2).check, "PASS", "edges: the pill under the ring by the zone pill's gap, over the vapor, the sun's well")
check(result("edges", 2).checkDetail:find("coords pill 9 under the ring, the zone pill 9 over it", 1, true), "...the gaps logged")
check(result("edges", 2).screenshots, "...with a screenshot")
S.Back()
local pill = GMM.Footer.Pill()
local function moved(y, msg)
    local p = { pill:GetPoint(1) }
    pill:ClearAllPoints(); pill:SetPoint("TOP", GMM.Ring.Host(), "BOTTOM", 0, y)
    S.Run(); settle()
    eq(result("edges", 2).check, "FAIL", msg)
    check(result("edges", 2).checkDetail:find("WANT THE SAME GAP", 1, true), "...said so")
    pill:ClearAllPoints(); pill:SetPoint(unpack(p))
    S.Back()
end
moved(4, "the pill tucked into the ring again: FAIL")
moved(-5, "a gap other than the zone pill's: FAIL")
local level = pill:GetFrameLevel()
pill:SetFrameLevel(GMM.Ring.Host():GetFrameLevel() - 1)
S.Run(); settle()
eq(result("edges", 2).check, "FAIL", "the pill under the vapor: FAIL")
check(result("edges", 2).checkDetail:find("WANT OVER", 1, true), "...said so")
pill:SetFrameLevel(level)
S.Back()
local zoomOut = GMM.Footer._test.zoomOut()
local zoomLevel = zoomOut:GetFrameLevel()
zoomOut:SetFrameLevel(GMM.Ring.Host():GetFrameLevel())
S.Run(); settle()
eq(result("edges", 2).check, "FAIL", "a zoom button under the vapor: FAIL")
zoomOut:SetFrameLevel(zoomLevel)
S.Back()
local coordsText = GMM.Footer._test.coords()
coordsText:SetParent(GMM.Footer._test.hit())
S.Run(); settle()
eq(result("edges", 2).check, "FAIL", "the text off the pill: FAIL")
coordsText:SetParent(pill)
S.Back()
GMM.Settings.SetRunicMode(false)
S.Run(); settle()
eq(result("edges", 2).check, "FAIL", "the runic ring turned off after it was built: FAIL")
GMM.Settings.SetRunicMode(true)
S.Back()
GMM.Ring.Sun().backing:SetAlpha(0)
S.Run(); settle()
eq(result("edges", 2).check, "FAIL", "the sun's well invisible: FAIL")
GMM.Ring.Sun().backing:SetAlpha(1)
S.Back()
S.Run(); settle()
eq(result("edges", 2).check, "PASS", "...and passing again, all put back")
S.Answer(true); S.Answer(true); S.Answer(true)
local realSetZoom = GMM.Settings.SetZoom
GMM.Settings.SetZoom = function() return true end       -- claims it, moves nothing
S.Run(); settle()
eq(result("edges", 6).check, "FAIL", "zoom on the ring claimed but not done: FAIL")
GMM.Settings.SetZoom = realSetZoom
S.Back()
local realLayout = GMM.Footer.Layout
GMM.Footer.Layout = function() end                     -- the setting stored, nothing moved
S.Run(); settle()
eq(result("edges", 6).check, "FAIL", "the setting on the ring, the buttons still in the pill: FAIL")
GMM.Footer.Layout = realLayout
GMM.Settings.SetZoom("pill")
S.Back()
GMM.Footer._test.zoomOut():Hide()
S.Run(); settle()
eq(result("edges", 6).check, "FAIL", "a zoom disc hidden: FAIL")
GMM.Footer._test.zoomOut():Show()
GMM.Settings.SetZoom("pill")
S.Back()
S.Run(); settle()
eq(result("edges", 6).check, "PASS", "the zoom buttons on the ring")
eq(GMM.Settings.Zoom(), "ring", "...the setting on the ring")
check(result("edges", 6).screenshots, "...with a screenshot")
S.Answer(true)
S.Run(); settle()                                      -- dark
S.Answer(true)
S.Run()                                                -- restore
eq(GlassMiniMapDB.look.tint, "class", "edges: the tint put back")
eq(GMM.Settings.Zoom(), "pill", "...and the zoom buttons back in the pill")
eq(rawget(GlassMiniMapDB, "zoom"), nil, "...not saved")
eq(record("edges").status, "done", "edges: done")

eq(#WoW.chat, 0, "nothing in chat, all along")

-- Pearl, our default material: the wash expected is its own (0.10), times
-- smoked's factor.
GMM = loadAddon()
loadForeverProbe()
loadProbe()
db = MinimapProbeDB
fp("mm glass")
check(logged("glass as expected: theme clear; zoom 0 of 6; ring peak 0%.100 undimmed"), "Pearl: clear at its wash")
GMM.Settings.SetTheme("smoked")
fp("mm glass")
check(logged("glass as expected: theme smoked.*ring peak 0%.078 undimmed"), "Pearl: smoked at 0.10 x 0.14 / 0.18")

--------------------------------------------------------------------------------
-- suite, suiteoff (#37): following Glass UI's suite, then not
--------------------------------------------------------------------------------
local ui
GMM, ui = loadAddon({ suite = { tint = "smoked" }, db = { look = { tint = "class" } } })
FP = loadForeverProbe()
S = FP.Steps
loadProbe()
db = MinimapProbeDB
fp("steps mm suite")
eq(db.restore.tint, "class", "suite: the own tint saved first")
GMM.GlassPreset = "clean"
S.Run(); settle()
eq(result("suite", 2).check, "FAIL", "following, but not on Pearl: FAIL")
S.Back()
GMM.GlassPreset = "pearl"
S.Run(); settle()
eq(result("suite", 2).check, "PASS", "following: Pearl and the suite's look")
-- The refusal: a Settings that took the tint would fail it.
local setTheme = GMM.Settings.SetTheme
GMM.Settings.SetTheme = function() return true end
S.Run(); settle()
eq(result("suite", 3).check, "FAIL", "our tint accepted while following: FAIL")
GMM.Settings.SetTheme = setTheme
S.Back()
S.Run(); settle()
eq(result("suite", 3).check, "PASS", "our tint refused while following, and kept")
eq(GlassMiniMapDB.look.tint, "class", "...still class")
S.Run(); WoW.flushTimers(); settle()                   -- the options, shot
S.Answer(true)
eq(result("suite", 5).check, "PASS", "the options: shot and answered")
S.Run(); settle()
eq(result("suite", 6).check, "PASS", "smoked: the suite's (our saved class unused)")
S.Run(); settle()
eq(result("suite", 7).check, "FAIL", "class asked, the suite still smoked: FAIL (ours is class)")
S.Back()
ui.SetTint("class")
S.Run(); settle()
eq(result("suite", 7).check, "PASS", "class: the suite's")
-- Clear asked while the suite says class (class's wash is clear's, so only
-- the tint tells): the tint in effect and the suite's must both be clear.
local name, tintOf = GMM.Theme.Name, GMM.Suite.Tint
GMM.Theme.Name = function() return "clear" end
S.Run(); settle()
eq(result("suite", 8).check, "FAIL", "clear in effect, the suite's class: FAIL")
S.Back()
GMM.Theme.Name = function() return "class" end
GMM.Suite.Tint = function() return "clear" end
S.Run(); settle()
eq(result("suite", 8).check, "FAIL", "the suite's clear, class in effect: FAIL")
GMM.Theme.Name, GMM.Suite.Tint = name, tintOf
S.Back()
ui.SetTint("clear")
S.Run(); settle()
eq(result("suite", 8).check, "PASS", "clear: the suite's")
S.Answer(true)
WoW.combat = true
ui.SetTint("smoked")
WoW.combat = false
S.Run(); settle()
eq(result("suite", 10).check, "PASS", "after combat: the suite's smoked")
S.Answer(true)
S.Run()
eq(GlassMiniMapDB.look.tint, "class", "suite: our own tint untouched")
eq(record("suite").status, "done", "suite: done")

-- edges while following: its tints are scenery, the suite's is kept.
GMM.Settings.SetRunicMode(true)
fp("steps mm edges")
S.Run(); settle()
eq(result("edges", 2).check, "PASS", "edges while following: runs, the suite's tint kept")
eq(result("edges", 2).lastError, nil, "...with no error")
check(result("edges", 2).detail:find("following", 1, true), "...and says so")
eq(GMM.Theme.Name(), "smoked", "...the suite's smoked still in effect")
fp("steps stop")
GMM.Settings.SetRunicMode(false)

-- Not following: the probe's check fails while following, passes after.
fp("steps mm suiteoff")
S.Run(); settle()
eq(result("suiteoff", 1).check, "FAIL", "suiteoff while still following: FAIL")
fp("steps stop")
GMM, ui = loadAddon({ db = GlassMiniMapDB, suite = { answer = function() return nil, "not-following" end } })
FP = loadForeverProbe()
S = FP.Steps
loadProbe({ db = db })
db = MinimapProbeDB
fp("steps mm suiteoff")
local name = GMM.Theme.Name
GMM.Theme.Name = function() return "clear" end           -- class's wash: only the tint differs
S.Run(); settle()
eq(result("suiteoff", 1).check, "FAIL", "not following, but not our own tint: FAIL")
GMM.Theme.Name = name
S.Back()
S.Run(); settle()
eq(result("suiteoff", 1).check, "PASS", "not following: our own material and tint")
check(result("suiteoff", 1).checkDetail:find("built pearl, tint class"), "...Pearl (ours) and our class")
S.Answer(true)
eq(record("suiteoff").status, "done", "suiteoff: done")
done("test_probe")
