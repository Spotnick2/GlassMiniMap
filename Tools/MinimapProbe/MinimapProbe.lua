-- MinimapProbe: a throwaway measuring addon for Glass MiniMap (never shipped).
-- A ForeverProbe module (..\ForeverProbe\docs\GUIDE.md): its lines go to the
-- /fp console and MinimapProbeDB.log, never to chat. Answers the questions
-- docs/FOREVER-PROBE.md lists, on the live client.
--
--   /fp mm frames     the cluster's pieces, sizes, scales, the compartment's entries
--   /fp mm rules      the game rules that switch minimap features off
--   /fp mm tracking   every tracking type: name, filterID, spellID, subType, active
--   /fp mm near       what draws near the map's bottom-left (the "72" over the launcher)
--   /fp mm queue      QueueStatusButton: parent, anchor, size, shown
--   /fp mm glass      the theme and the wash of the ring and the zoom buttons (#22)
--   /fp mm discs      the mail disc (#19) and the instance disc (#21), and what they mirror
--   /fp mm restore    put back the theme and zoom a procedure changed
--
-- Procedures (/fp steps mm <name>): wash, mail, instance. The mail and instance checks
-- follow GlassMiniMap's placement setting (#27): its indicator shows, the other doesn't.

local ADDON = ...
local MAX_LOG = 3000

local Probe = ForeverProbe:Module("MinimapProbe", { api = 1, cmd = "mm" })

local function say(msg) Probe:Say(msg) end
local function str(v) return Probe.Show(v, true) end
local function secret(v) return issecretvalue ~= nil and issecretvalue(v) end

local function gmm() return rawget(_G, "GlassMiniMap") end

local function pieces()
    local c = MinimapCluster
    local list = {
        { "MinimapCluster", c },
        { "MinimapContainer", c and c.MinimapContainer },
        { "Minimap", Minimap },
        { "BorderTop", c and c.BorderTop },
        { "ZoneTextButton", c and c.ZoneTextButton },
        { "Tracking", c and c.Tracking },
        { "Tracking.Button", c and c.Tracking and c.Tracking.Button },
        { "PlayerCoords", c and c.MinimapContainer and c.MinimapContainer.PlayerCoords },
        { "DielFrame", c and c.DielFrame },
        { "GameTimeFrame", rawget(_G, "GameTimeFrame") },
        { "AddonCompartmentFrame", rawget(_G, "AddonCompartmentFrame") },
        { "TimeManagerClockButton", rawget(_G, "TimeManagerClockButton") },
        { "IndicatorFrame", c and c.IndicatorFrame },
        { "InstanceDifficulty", c and c.InstanceDifficulty },
    }
    for _, p in ipairs(list) do
        local f = p[2]
        if f then
            local w, h = f:GetSize()
            say(("%s: %sx%s scale %s eff %s level %s strata %s shown %s"):format(p[1], str(w), str(h),
                str(f.GetScale and f:GetScale()), str(f:GetEffectiveScale()), str(f.GetFrameLevel and f:GetFrameLevel()),
                str(f.GetFrameStrata and f:GetFrameStrata()), str(f:IsShown())))
        else
            say(p[1] .. ": MISSING")
        end
    end
    local a = rawget(_G, "AddonCompartmentFrame")
    if a and a.registeredAddons then
        say("compartment entries: " .. #a.registeredAddons)
        for i, d in ipairs(a.registeredAddons) do say(("  %d %s icon=%s"):format(i, str(d.text), str(d.icon))) end
    end
    local ok, z = pcall(Minimap.GetZoom, Minimap)
    local ok2, n = pcall(Minimap.GetZoomLevels, Minimap)
    say("zoom " .. str(ok and z) .. " of " .. str(ok2 and n) .. " levels; rotateMinimap=" .. str(GetCVarBool("rotateMinimap")))
end

local function rules()
    local names = { "IngameCalendarDisabled", "IngameTrackingDisabled", "MinimapDisabled", "WorldMapDisabled",
                    "UserAddonsDisabled" }
    for _, n in ipairs(names) do
        local id = Enum and Enum.GameRule and Enum.GameRule[n]
        local ok, on = false, nil
        if id ~= nil and C_GameRules and C_GameRules.IsGameRuleActive then ok, on = pcall(C_GameRules.IsGameRuleActive, id) end
        say(("%s: id=%s active=%s"):format(n, str(id), ok and str(on) or "n/a"))
    end
end

local function tracking()
    local n = C_Minimap.GetNumTrackingTypes()
    say(n .. " tracking types; showAll=" .. str(GetCVarBool("minimapTrackingShowAll")))
    for i = 1, n do
        local info = C_Minimap.GetTrackingInfo(i) or {}
        local f = C_Minimap.GetTrackingFilter(i) or {}
        local optional = MinimapConstants and MinimapConstants.OPTIONAL_FILTERS and f.filterID
            and MinimapConstants.OPTIONAL_FILTERS[f.filterID]
        say(("%d %s filter=%s spell=%s sub=%s type=%s active=%s optional=%s"):format(i, str(info.name),
            str(f.filterID), str(f.spellID), str(info.subType), str(info.type), str(info.active), str(optional)))
    end
end

-- Every visible FontString within `radius` px of the map's bottom-left
-- corner area (where the mockup draws "72" over the launcher disc).
local function near(radius)
    radius = radius or 70
    local mx, my = Minimap:GetCenter()
    local s = Minimap:GetEffectiveScale()
    local r = Minimap:GetWidth() / 2
    local tx, ty = (mx - r * 0.707) * s, (my - r * 0.707) * s
    local found = 0
    -- Visibility can be secret too (a unit aura frame's, measured on 70374): a
    -- secret or unreadable answer counts as "not visible", never truth-tested.
    local function yes(obj, method)
        local ok, v = pcall(obj[method], obj)
        if not ok or secret(v) then return false end
        return v == true
    end
    local f = EnumerateFrames()
    while f do
        if not yes(f, "IsForbidden") and yes(f, "IsVisible") then
            for _, reg in ipairs({ f:GetRegions() }) do
                if reg:IsObjectType("FontString") and yes(reg, "IsVisible") then
                    local x, y = reg:GetCenter()
                    local t = reg:GetText()
                    local es = reg:GetEffectiveScale()
                    -- Some frames' positions (and texts) are secret on this client: skip them.
                    if not (secret(x) or secret(y) or secret(t) or secret(es)) and x and t and t ~= "" then
                        local dx, dy = x * es - tx, y * es - ty
                        if dx * dx + dy * dy <= (radius * s) ^ 2 then
                            found = found + 1
                            local chain, p = {}, f
                            while p and #chain < 6 do
                                chain[#chain + 1] = p:GetName() or p:GetDebugName() or "?"
                                p = p:GetParent()
                            end
                            say(("'%s' on %s"):format(t, table.concat(chain, " < ")))
                            -- Who made it: the frame's and the text's source location.
                            local okF, srcF = pcall(f.GetSourceLocation, f)
                            local okR, srcR = pcall(reg.GetSourceLocation, reg)
                            say(("  frame from %s, text from %s, frame %sx%s, %d children"):format(
                                okF and str(srcF) or "?", okR and str(srcR) or "?", str(f:GetWidth()),
                                str(f:GetHeight()), select("#", f:GetChildren())))
                            for i = 1, f:GetNumPoints() do
                                local a, rel, b, px, py = f:GetPoint(i)
                                say(("  point %s -> %s %s (%s, %s)"):format(str(a),
                                    str(rel and (rel:GetName() or rel:GetDebugName())), str(b), str(px), str(py)))
                            end
                        end
                    end
                end
            end
        end
        f = EnumerateFrames(f)
    end
    say(found .. " text(s) near the bottom-left of the map")
end

local function queue()
    local q = rawget(_G, "QueueStatusButton")
    if not q then return say("QueueStatusButton: MISSING") end
    local p = q:GetParent()
    say("QueueStatusButton parent " .. str(p and (p:GetName() or p:GetDebugName())) .. " shown " .. str(q:IsShown())
        .. " size " .. str(q:GetWidth()) .. "x" .. str(q:GetHeight()) .. " scale " .. str(q:GetScale()))
    for i = 1, q:GetNumPoints() do
        local a, rel, b, x, y = q:GetPoint(i)
        say(("  point %s -> %s %s (%s, %s)"):format(str(a), str(rel and (rel:GetName() or rel:GetDebugName())),
            str(b), str(x), str(y)))
    end
end

--------------------------------------------------------------------------------
-- Glass MiniMap's state: readers shared by the commands and the procedures.
-- A check returns ok, then "what was read vs what was expected". Missing or
-- secret readings fail, never pass as a plain false.
--------------------------------------------------------------------------------

local TOLERANCE = 0.005
-- The wash's gradient peak per theme: LibGlass's 0.18, smoked's 0.14 (#22).
local WASH = { clear = 0.18, smoked = 0.14, class = 0.18 }

local function theme()
    local g = gmm()
    return g and g.db and g.db.theme or nil
end

local function zoom()
    local ok, z = pcall(Minimap.GetZoom, Minimap)
    if not ok or secret(z) then return nil end
    return z
end

-- A number we can compare, or nil and why not.
local function plainNumber(v)
    if secret(v) then return nil, "<secret>" end
    if type(v) ~= "number" then return nil, "MISSING" end
    return v
end

-- One surface's wash, as LibGlass r7 keeps it on the region: the peak, and
-- the dim of a disabled surface (nil while enabled: an effective 1).
local function wash(g)
    local w = type(g) == "table" and g.wash
    if not w then return { err = "no wash" } end
    local peak, why = plainNumber(w.glassPeak)
    local r = { peak = peak, err = why and ("peak " .. why) or nil }
    if w.glassDim ~= nil then
        local dim, whyDim = plainNumber(w.glassDim)
        r.dim, r.err = dim, r.err or (whyDim and ("dim " .. whyDim))
    end
    -- Hidden is a reading (it fails the check); unreadable is an error.
    local ok, shown = pcall(w.IsShown, w)
    if not ok then
        r.err = r.err or "shown ERROR"
    elseif secret(shown) then
        r.err = r.err or "shown <secret>"
    else
        r.shown = shown == true
    end
    return r
end

local function washText(r)
    if r.err then return r.err end
    return ("peak %.3f %s%s"):format(r.peak, r.dim and ("dim %.2f"):format(r.dim) or "undimmed",
        r.shown == false and " HIDDEN" or "")
end

local function surfaces()
    local g = gmm()
    local f = g and g.Footer and g.Footer._test
    return g and g.Ring and g.Ring.Glass(), f and f.zoomIn(), f and f.zoomOut()
end

-- The ring undimmed at the theme's peak; the zoom buttons at that peak too,
-- dimmed by LibGlass's disabledAlpha exactly at their end of the zoom range
-- (minus at 0, plus at the last level), as Footer.UpdateZoomButtons does.
local function washCheck()
    local name = theme()
    local want = WASH[name or ""]
    if not want then return false, "theme " .. str(name) .. ": unknown" end
    local ring, zin, zout = surfaces()
    if not (ring and zin and zout) then return false, "Glass MiniMap's ring or zoom buttons: MISSING" end
    local g = gmm()
    local disabled = g.Glass and g.Glass.STYLE and g.Glass.STYLE.disabledAlpha
    local z = zoom()
    local okL, levels = pcall(Minimap.GetZoomLevels, Minimap)
    levels = okL and plainNumber(levels) or nil
    local ok, parts = true, { "theme " .. name, "zoom " .. str(z) .. " of " .. str(levels) }
    if z == nil or levels == nil then return false, table.concat(parts, "; ") .. "; zoom unreadable" end
    local function one(label, r, wantDim)
        local good = not r.err and r.shown == true and math.abs(r.peak - want) < TOLERANCE
        if wantDim then
            good = good and r.dim ~= nil and math.abs(r.dim - wantDim) < TOLERANCE
        else
            good = good and r.dim == nil
        end
        ok = ok and good
        parts[#parts + 1] = ("%s %s (want %.3f %s)%s"):format(label, washText(r), want,
            wantDim and ("dim %.2f"):format(wantDim) or "undimmed", good and "" or " BAD")
    end
    one("ring", wash(ring))
    one("plus", wash(zin.glass), z >= levels - 1 and disabled or nil)
    one("minus", wash(zout.glass), z == 0 and disabled or nil)
    return ok, table.concat(parts, "; ")
end

local function shownState(f)
    if type(f) ~= "table" then return nil, "MISSING" end
    local ok, on = pcall(f.IsShown, f)
    if not ok then return nil, "ERROR" end
    if secret(on) then return nil, "<secret>" end
    return on == true
end

local function textOf(fs)
    if not (type(fs) == "table" and fs.GetText) then return nil, "MISSING" end
    local ok, t = pcall(fs.GetText, fs)
    if not ok then return nil, "ERROR" end
    if secret(t) then return nil, "<secret>" end
    return t
end

local function alphaOf(f)
    local ok, a = pcall(f.GetAlpha, f)
    return ok and not secret(a) and a or nil
end

-- Senders are other players' names: only their count is logged.
-- Where mail and the instance size show (#27): "pills" or "ring". The one
-- placed there must show, and the other must not (no duplicates).
local function placement()
    local g = gmm()
    return g and g.Settings and g.Settings.Indicators and g.Settings.Indicators() or nil
end

local function mailCheck()
    local g = gmm()
    local where = placement()
    local disc = g and g.Mail and g.Mail.Disc()
    local envelope = g and g.Header and g.Header.MailButton and g.Header.MailButton()
    if not (disc and envelope and where) then
        return false, "mail disc, envelope or placement: MISSING (the mail-notification game rule on?)"
    end
    local okM, has = pcall(HasNewMail)
    if not okM or secret(has) then return false, "HasNewMail: " .. (okM and "<secret>" or "ERROR") end
    local discOn, why = shownState(disc)
    if discOn == nil then return false, "disc shown: " .. why end
    local envOn, whyE = shownState(envelope)
    if envOn == nil then return false, "envelope shown: " .. whyE end
    local placed, on, other = envelope, envOn, discOn
    if where == "ring" then placed, on, other = disc, discOn, envOn end
    local senders = #g.Mail.Senders()
    -- Blizzard's icon must be faded (alpha 0): missing or unreadable fails.
    local blizz = MinimapCluster.IndicatorFrame and MinimapCluster.IndicatorFrame.MailFrame
    local blizzAlpha
    if blizz then
        local okA, a = pcall(blizz.GetAlpha, blizz)
        if not okA then blizzAlpha = "ERROR" else blizzAlpha = select(2, plainNumber(a)) or a end
    else
        blizzAlpha = "MISSING"
    end
    local detail = ("HasNewMail %s; placement %s: %s shown %s alpha %s, the other shown %s; %d sender(s) readable;"
        .. " Blizzard's mail icon alpha %s"):format(str(has), where, where == "ring" and "disc" or "envelope",
        str(on), str(alphaOf(placed)), str(other), senders, str(blizzAlpha))
    return has == true and on == true and other == false and blizzAlpha == 0, detail
end

-- Which Blizzard flag shows and its text (Difficulty.lua reads the same).
local function flagState()
    local f = MinimapCluster and MinimapCluster.InstanceDifficulty
    if not f then return { err = "InstanceDifficulty: MISSING" } end
    local s = { alpha = alphaOf(f) }
    local def, whyD = shownState(f.Default)
    local guild, whyG = shownState(f.Guild)
    if def == nil and guild == nil then s.err = "flag shown: " .. str(whyD) .. "/" .. str(whyG); return s end
    if def then
        s.which, s.text, s.why = "Default", textOf(f.Default.Text)
    elseif guild then
        s.which, s.text, s.why = "Guild", textOf(f.Guild.Instance and f.Guild.Instance.Text)
    end
    if s.why then s.err = s.which .. " text: " .. s.why end
    return s
end

-- inside: Blizzard's size shows in a party or raid instance, in its placement only
-- (the disc, or the coords pill's text);
-- outside: no instance and no disc. The flag stays faded either way.
local function instanceCheck(inside)
    local g = gmm()
    local disc = g and g.Difficulty and g.Difficulty.Disc()
    if not disc then return false, "instance disc: MISSING" end
    local _, kind, _, _, maxPlayers = GetInstanceInfo()
    if secret(kind) or secret(maxPlayers) then return false, "GetInstanceInfo: <secret>" end
    local on, why = shownState(disc)
    if on == nil then return false, "disc shown: " .. why end
    local label = textOf(g.Difficulty.Label())
    local where = placement()
    -- The pill's text counts only while shown: with Blizzard's coordinates
    -- off it's hidden, and may keep a stale size or never have had a text.
    local pill = g.Footer and g.Footer._test and g.Footer._test.coords()
    local pillShown, whyPill = shownState(pill)
    local pillText = pillShown and textOf(pill) or nil
    local sizeText = g.Difficulty.Text and g.Difficulty.Text()
    local s = flagState()
    local detail = ("instance %s, %s players; flag %s %s alpha %s; placement %s; disc shown %s label %s; pill %s")
        :format(str(kind), str(maxPlayers), str(s.which or "none"), str(s.text), str(s.alpha), str(where), str(on),
            str(label), pillShown and str(pillText) or "hidden")
    if not where then return false, detail .. "; placement: MISSING" end
    if pillShown == nil then return false, detail .. "; pill text shown: " .. str(whyPill) end
    if pillShown and type(pillText) ~= "string" then return false, detail .. "; pill text: unreadable" end
    if s.err then return false, detail .. "; " .. s.err end
    if s.alpha ~= 0 then return false, detail .. "; Blizzard's flag isn't faded" end
    local flagShows = s.which ~= nil and type(s.text) == "string" and s.text ~= ""
    if inside then
        if kind ~= "party" and kind ~= "raid" then return false, detail .. "; not in a dungeon or raid" end
        if not flagShows then return false, detail .. "; Blizzard shows no size (yet?): go Back and Check again" end
        -- The size in its place and only there.
        local inPill = type(sizeText) == "string" and pillText == sizeText
            and pillText:sub(-#s.text) == s.text
        if where == "ring" then return on == true and label == s.text and not inPill, detail end
        return on == false and inPill, detail
    end
    if kind ~= "none" then return false, detail .. "; still in an instance" end
    return on == false and not flagShows and sizeText == nil, detail
end

--------------------------------------------------------------------------------
-- What a procedure changes, saved to put back: in MinimapProbeDB, so a Stop,
-- a skip or a relog in between doesn't lose it. Never overwritten while one
-- is outstanding.
--------------------------------------------------------------------------------

local function snapshot()
    local db = MinimapProbeDB
    if db.restore then return "kept the outstanding one", db.restore.theme, db.restore.zoom end
    db.restore = { theme = theme(), zoom = zoom() }
    return "saved", db.restore.theme, db.restore.zoom
end

local function restore()
    local db = MinimapProbeDB
    local r = db and db.restore
    if not r then return "nothing to restore" end
    local g = gmm()
    if r.theme and g then g.Settings.SetTheme(r.theme) end
    local z = zoom()
    if r.zoom and z and g then g.Footer.Zoom(r.zoom - z) end
    db.restore = nil
    say("restored theme " .. str(r.theme) .. ", zoom " .. str(r.zoom))
    return "restored", r.theme, r.zoom
end

local function setTheme(name)
    return function()
        local g = gmm()
        if not (g and g.Settings.SetTheme(name)) then error("couldn't set the theme " .. name) end
        return name
    end
end

local function zoomOut()
    local g = gmm()
    local z = zoom()
    if not (g and z) then error("zoom unreadable") end
    if z > 0 then g.Footer.Zoom(-z) end
    return zoom()
end

-- A screenshot a few seconds after the button, so the owner can hover a disc
-- and hold its tooltip open: a run step completes at once, so the shot is
-- recorded here and the next step's check reads it. A shot belongs to the
-- procedure run that armed it (its record: a new one on every start), so a
-- restarted procedure never passes on an earlier run's picture.
local SHOT_DELAY = 3
local shots = {}   -- label -> { rec, pending | file | why }

local function currentRecord() return select(2, ForeverProbe.Steps.Active()) end

local function armShot(label)
    return function()
        local s = { rec = currentRecord(), pending = true }
        shots[label] = s
        C_Timer.After(SHOT_DELAY, function()
            if shots[label] ~= s or currentRecord() ~= s.rec then
                s.pending, s.why = nil, "the procedure moved on before the shot"
                return say(label .. ": no shot, the procedure moved on")
            end
            Probe:Screenshot(label, function(file, why)
                s.pending, s.file, s.why = nil, file, not file and (why or "failed") or nil
                say(label .. ": " .. (file and ("shot " .. file) or ("no shot: " .. str(why))))
            end)
        end)
        return "armed: hover now"
    end
end

local function shotCheck(label)
    return function()
        local s = shots[label]
        if not s or s.rec ~= currentRecord() then return false, "no shot in this run: go Back and press Shoot" end
        if s.pending then return false, "the shot wasn't taken yet: go Back and press Shoot again" end
        if s.file then return true, s.file end
        return false, "the shot failed: " .. str(s.why)
    end
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

Probe:Command("frames", pieces, "the cluster's pieces, sizes, scales; the compartment's entries")
Probe:Command("rules", rules, "the game rules that switch minimap features off")
Probe:Command("tracking", tracking, "every tracking type")
Probe:Command("near", function(args) near(tonumber(args)) end, "texts near the map's bottom-left [radius]")
Probe:Command("queue", queue, "QueueStatusButton's parent, anchor, size")
Probe:Command("glass", function()
    local ok, detail = washCheck()
    say("glass " .. (ok and "as expected" or "NOT as expected") .. ": " .. detail)
end, "the theme and the wash of the ring and zoom buttons")
Probe:Command("discs", function()
    local _, m = mailCheck()
    say("mail: " .. m)
    local _, kind = GetInstanceInfo()
    local _, d = instanceCheck(kind ~= "none")
    say("instance: " .. d)
end, "the mail and instance discs")
Probe:Command("restore", function() say(table.concat({ restore() }, " ")) end,
    "put back the theme and zoom a procedure changed")
Probe:Command("clear", function() Probe:ClearLog(); say("log cleared") end, "empty the saved log")

--------------------------------------------------------------------------------
-- Procedures
--------------------------------------------------------------------------------

local function SAVE()
    return { text = "Saving your theme and zoom, to put them back at the end (/fp mm restore if you stop).",
        auto = true, run = snapshot }
end
local function RESTORE() return { text = "Put your theme and zoom back.", button = "Restore", run = restore } end

Probe:Steps("wash", {
    rev = 3,
    title = "Smoked's softer wash (#22)",
    SAVE(),
    { text = "Switch to clear glass.", button = "Clear", run = setTheme("clear"), check = washCheck,
      screenshot = "wash: clear" },
    { text = "Switch to smoked glass. Look at the top of the ring, the pills and the north tab.", button = "Smoked",
      run = setTheme("smoked"), check = washCheck, screenshot = "wash: smoked" },
    { text = "Is the sheen at the top of the ring and the pills softer in smoked than it was in clear?", ask = true },
    { text = "Zoom fully out: the minus button turns disabled.", button = "Zoom out", run = zoomOut,
      check = washCheck, screenshot = "wash: smoked, zoomed out" },
    { text = "Is the minus button (below the map) dimmed?", ask = true },
    { text = "Switch to clear glass, still zoomed out.", button = "Clear", run = setTheme("clear"),
      check = washCheck, screenshot = "wash: clear, zoomed out" },
    { text = "Is the minus button still dimmed?", ask = true },
    RESTORE(),
})

Probe:Steps("mail", {
    rev = 3,
    title = "The mail disc (#19)",
    SAVE(),
    { text = "Have mail sent to this character (an alt or a friend) and wait for it. Press Done if you already have unread mail.",
      event = "UPDATE_PENDING_MAIL" },
    { text = "Wait a few seconds for the senders to load, then press Check.", button = "Check", run = function() end,
      check = mailCheck },
    { text = "Clear glass.", button = "Clear", run = setTheme("clear"), screenshot = "mail: clear" },
    { text = "Smoked glass.", button = "Smoked", run = setTheme("smoked"), screenshot = "mail: smoked" },
    { text = "Class colour glass.", button = "Class", run = setTheme("class"), screenshot = "mail: class" },
    { text = "Was the mail indicator (the envelope by the zone name, or the disc on the ring) easy to read in all three?", ask = true },
    { text = "Press Shoot, then hover the envelope (or the mail disc) and hold still until the shutter (" .. SHOT_DELAY .. " s).",
      button = "Shoot", run = armShot("mail: tooltip") },
    { text = "After the shutter: did the tooltip list the senders? (No if it only said you have unread mail.)",
      ask = true, check = shotCheck("mail: tooltip") },
    RESTORE(),
})

Probe:Steps("instance", {
    rev = 3,
    title = "The instance disc (#21)",
    { text = "Enter a dungeon or a raid.", event = "PLAYER_ENTERING_WORLD" },
    { text = "When loading has finished (wait a few seconds), press Check.", button = "Check", run = function() end,
      check = function() return instanceCheck(true) end, screenshot = "instance: inside" },
    { text = "Press Shoot, then hover the size (in the coords pill, or the disc) and hold still until the shutter ("
        .. SHOT_DELAY .. " s).", button = "Shoot", run = armShot("instance: tooltip") },
    { text = "After the shutter: did the tooltip match this instance's type and size (Dungeon / 5 Player, Raid / 40 Player...)?",
      ask = true, check = shotCheck("instance: tooltip") },
    { text = "Leave the instance.", event = "PLAYER_ENTERING_WORLD" },
    { text = "When loading has finished, press Check.", button = "Check", run = function() end,
      check = function() return instanceCheck(false) end, screenshot = "instance: outside" },
})

local boot = CreateFrame("Frame")
Probe:RegisterEvents(boot, { "ADDON_LOADED" })
boot:SetScript("OnEvent", function(_, _, name)
    if name ~= ADDON then return end
    Probe:Ready()
    if type(MinimapProbeDB) ~= "table" then MinimapProbeDB = {} end
    if type(MinimapProbeDB.log) ~= "table" then MinimapProbeDB.log = {} end
    Probe:UseLog(MinimapProbeDB.log, MAX_LOG)
    MinimapProbeDB.loads = (MinimapProbeDB.loads or 0) + 1
    say("loaded (" .. MinimapProbeDB.loads .. " loads). /fp mm for the commands, /fp steps for the procedures")
    if MinimapProbeDB.restore then
        say("a procedure's theme and zoom are still to put back: /fp mm restore")
    end
end)
