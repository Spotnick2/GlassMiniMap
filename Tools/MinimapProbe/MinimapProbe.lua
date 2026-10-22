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
--   /fp mm glass      the tint and the wash of the ring and the zoom buttons (#22)
--   /fp mm discs      the mail disc (#19) and the instance disc (#21), and what they mirror
--   /fp mm restore    put back the tint and zoom a procedure changed
--
-- Procedures (/fp steps mm <name>): wash, mail, instance, edges, zoomring, extras, checklist,
-- suite, suiteoff. extras is #13-#15; checklist is what #2 still had open. The mail
-- and instance checks follow GlassMiniMap's placement setting (#27): its indicator shows, the
-- other doesn't. suite and suiteoff are Glass UI's suite (#37), followed and not.

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
-- The tint in effect: the player's own, else Glass UI's, else clear (#37).
local function theme()
    local g = gmm()
    return g and g.Theme and g.Theme.Name() or nil
end

-- The wash's gradient peak for the tint in effect: the material's as built
-- (Clean 0.18, Pearl 0.10) times the tint's factor (smoked 0.14 / 0.18, #22;
-- Glass UI's while following).
local function wantedWash()
    local g = gmm()
    local base = g and g.Glass and g.Glass.STYLE and g.Glass.STYLE.wash
    if type(base) ~= "number" then return nil end
    local _, factor = g.Theme.Current()
    return math.max(0, math.min(1, base * (factor or 1)))
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
    local want = name and wantedWash()
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
-- is outstanding. The tint is saved by its source (#37): the player's own
-- (look.tint) or "none". While Glass MiniMap follows Glass UI's look its own
-- tint can't be set (putting it back is refused), and no procedure changes it.
--------------------------------------------------------------------------------

local function ownTint()
    local g = gmm()
    return g and g.Theme and g.Theme.Own() or nil
end

-- A step's zoom stays put: no auto zoom-out during a run (#13; extras turns
-- it on), on every Save, a kept snapshot's too (Codex, #44).
local function pauseAutoZoom()
    local S = gmm() and gmm().Settings
    if S and S.SetAutoZoomOut then S.SetAutoZoomOut(0) end
end

local function snapshot()
    local db = MinimapProbeDB
    if db.restore then
        pauseAutoZoom()
        return "kept the outstanding one", db.restore.tint, db.restore.zoom
    end
    local g = gmm()
    local S = g and g.Settings
    db.restore = { tint = ownTint() or "none", zoom = zoom(), place = S and S.Zoom and S.Zoom(),
        autoZoomOut = S and S.AutoZoomOut and S.AutoZoomOut(), pingName = S and S.PingName and S.PingName(),
        fader = S and S.Fader and S.Fader(), faderOpacity = S and S.FaderOpacity and S.FaderOpacity() }
    pauseAutoZoom()
    return "saved", db.restore.tint, db.restore.zoom
end

local function restore()
    local db = MinimapProbeDB
    local r = db and db.restore
    if not r then return "nothing to restore" end
    local g = gmm()
    -- A snapshot from before #37 kept the theme itself, always the player's.
    local tint = r.tint or r.theme
    if tint and g then
        if tint == "none" then g.Settings.ClearTheme() else g.Settings.SetTheme(tint) end
    end
    local z = zoom()
    if r.zoom and z and g then g.Footer.Zoom(r.zoom - z) end
    if r.place and g and g.Settings.SetZoom then g.Settings.SetZoom(r.place) end
    -- The behaviour settings (#13-#15), when the snapshot has them.
    local S = g and g.Settings
    if S and S.SetAutoZoomOut then
        if r.autoZoomOut ~= nil then S.SetAutoZoomOut(r.autoZoomOut) end
        if r.pingName ~= nil then S.SetPingName(r.pingName) end
        if r.fader ~= nil then S.SetFader(r.fader) end
        if r.faderOpacity ~= nil then S.SetFaderOpacity(r.faderOpacity) end
    end
    db.restore = nil
    say("restored tint " .. str(tint) .. ", zoom " .. str(r.zoom) .. ", zoom buttons " .. str(r.place))
    return "restored", tint, r.zoom
end

local function setTheme(name)
    return function()
        local g = gmm()
        if g and g.Suite.LookFollowing() then
            error("Glass MiniMap follows Glass UI's tint: turn that off (then /reload), or type /glassui look tint " .. name)
        end
        if not (g and g.Settings.SetTheme(name)) then error("couldn't set the theme " .. name) end
        return name
    end
end

-- For a procedure whose tint is only scenery (edges): while following Glass
-- UI's tint, keep it rather than stop the procedure.
local function sceneryTheme(name)
    local set = setTheme(name)
    return function()
        local g = gmm()
        if g and g.Suite.LookFollowing() then return "kept Glass UI's " .. str(g.Theme.Name()) .. " (following)" end
        return set()
    end
end

-- Glass UI's suite (#37), read from Glass MiniMap's own state: following, the
-- material built, the tint in effect, and the wash that goes with them.
local function suiteState()
    local g = gmm()
    if not (g and g.Suite) then return nil, "Glass MiniMap: MISSING" end
    local okW, wdetail = washCheck()
    return {
        following = g.Suite.Following(), lookFollowing = g.Suite.LookFollowing(),
        built = g.GlassPreset, own = g.Theme.Own(), suiteTint = g.Suite.Tint(), tint = g.Theme.Name(),
        washOk = okW, failure = g.Suite.Failure(),
    }, ("following %s (look %s), built %s, tint %s (own %s, suite's %s)%s; %s"):format(
        str(g.Suite.Following()), str(g.Suite.LookFollowing()), str(g.GlassPreset), str(g.Theme.Name()),
        str(g.Theme.Own()), str(g.Suite.Tint()), g.Suite.Failure() and (", failed: " .. g.Suite.Failure()) or "",
        wdetail)
end

local function followingCheck()
    local st, detail = suiteState()
    if not st then return false, detail end
    return st.following and st.lookFollowing and st.built == "pearl" and st.washOk, detail
end

-- The tint in effect is the suite's, and it is `want`.
local function tintCheck(want)
    return function()
        local st, detail = suiteState()
        if not st then return false, detail end
        return st.tint == want and st.suiteTint == want and st.washOk, detail
    end
end

-- While following, our own tint can't be set or cleared ("set in Glass UI"),
-- and the one saved stays as it was.
local function tintRefusedCheck()
    local g = gmm()
    if not (g and g.Suite) then return false, "Glass MiniMap: MISSING" end
    local before = g.Theme.Own()
    local okSet, why = g.Settings.SetTheme(before == "class" and "smoked" or "class")
    local okClear = g.Settings.ClearTheme()
    local st, detail = suiteState()
    local kept = g.Theme.Own() == before
    return st.lookFollowing and not okSet and not okClear and kept and st.tint == (st.suiteTint or "clear"),
        ("set %s (%s), clear %s, own %s kept %s; %s"):format(str(okSet), str(why), str(okClear), str(before),
        str(kept), detail)
end

-- Our own look back: the material saved and the tint saved (or clear).
local function ownLookCheck()
    local st, detail = suiteState()
    if not st then return false, detail end
    local g = gmm()
    return not st.following and st.built == g.Settings.Material() and st.tint == (st.own or "clear") and st.washOk, detail
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
-- The ring's edges (#39, #40, #42): the coords pill hanging clear of the
-- ring (so its rim stays closed) by the zone pill's gap over it, drawn over
-- the runic vapor with its text and zoom buttons, and the dark well under the
-- day/night glyph.
local function edgesCheck()
    local g = gmm()
    local host = g and g.Ring and g.Ring.Host()
    local pill = g and g.Footer and g.Footer.Pill()
    local zone = g and g.Header and g.Header.Pill()
    local sun = g and g.Ring and g.Ring.Sun()
    if not (host and pill and zone and sun) then return false, "the ring, a pill or the sun: MISSING" end
    local R, F = g.Ring._test, g.Footer._test
    local runes, fog = R.runes(), R.fog()
    if not (runes and runes:IsVisible() and fog and fog:IsShown()) then
        return false, "the runic ring or its vapor is off: /gmm runes on, /gmm runes fog on, then Check again"
    end
    local p, rel, _, _, y = pill:GetPoint(1)
    local gap = (p == "TOP" and rel == host and type(y) == "number") and -y or nil
    local zp, zrel, _, _, zy = zone:GetPoint(1)
    local zoneGap = (zp == "BOTTOM" and zrel == host) and zy or nil
    local placed = gap ~= nil and gap == zoneGap
    local over = math.max(runes:GetFrameLevel(), fog:GetFrameLevel())
    local pl = pill:GetFrameLevel()
    local zl = math.min(F.zoomIn():GetFrameLevel(), F.zoomOut():GetFrameLevel())
    local levelsOk = pl > over and zl > over and F.coords():GetParent() == pill
    local well = sun.backing
    local wellShown = well and well:IsShown() and well:GetAlpha() > 0
    return placed and levelsOk and wellShown == true,
        ("coords pill %s under the ring, the zone pill %s over it%s; pill level %s, zoom %s, over the runes and vapor %s%s; sun's well %s; Minimap level %s"):format(
            str(gap), str(zoneGap), placed and "" or " (WANT THE SAME GAP)", str(pl), str(zl), str(over),
            levelsOk and "" or " (WANT OVER)", well and (wellShown and "shown" or "HIDDEN") or "MISSING",
            str(Minimap:GetFrameLevel()))
end

-- The zoom buttons as discs on the ring (#42's zoom = "ring").
local function setZoomPlace(where)
    return function()
        local g = gmm()
        if not (g and g.Settings.SetZoom(where)) then error("couldn't put the zoom buttons: " .. where) end
        return where
    end
end

local function zoomRingCheck()
    local g = gmm()
    local F = g and g.Footer and g.Footer._test
    if not F then return false, "the coords pill: MISSING" end
    local c, zin, zout = g.Ring.Container(), F.zoomIn(), F.zoomOut()
    local onRing = zin:GetParent() == c and zout:GetParent() == c
    local shown = zin:IsVisible() and zout:IsVisible()
    return onRing and shown,
        ("zoom %s; + and - on the ring %s, shown %s"):format(str(g.Settings.Zoom()), str(onRing), str(shown))
end

-- The zoom discs on the ring, clicked (#42: "zoom no, hover yes" on 70450,
-- with the map at its closest zoom, where + does nothing). What's under the
-- mouse names our discs, else the frame in the way.
local function focusName()
    local g = gmm()
    local fn = rawget(_G, "GetMouseFoci")
    local ok, foci = pcall(fn)
    local f = ok and type(foci) == "table" and foci[1] or nil
    local F = g and g.Footer and g.Footer._test
    if F and f == F.zoomIn() then return "our + disc" end
    if F and f == F.zoomOut() then return "our - disc" end
    local okName, name = pcall(function() return f:GetDebugName() end)
    return okName and str(name) or str(f)
end

local function ringZoomReady()
    local g = gmm()
    local z = zoom()
    if not (g and z) then error("zoom unreadable") end
    if not g.Settings.SetZoom("ring") then error("couldn't put the zoom buttons on the ring") end
    g.Footer.Zoom(2 - z)
    return zoom()
end

local function clickCheck(want)
    return function()
        local z = zoom()
        return z == want, ("map zoom %s (want %s); under the mouse: %s"):format(str(z), str(want), focusName())
    end
end

local function fadedCheck()
    local g = gmm()
    local F = g and g.Footer and g.Footer._test
    if not F then return false, "the zoom buttons: MISSING" end
    local a, b = F.zoomIn():GetAlpha(), F.zoomOut():GetAlpha()
    return a == 0 and b == 0, ("the zoom discs at alpha %s and %s (want 0, the mouse away)"):format(str(a), str(b))
end

-- The behaviour settings (#13, #14, #15), at their defaults for a run.
local function behaviourDefaults()
    local S = gmm() and gmm().Settings
    if not (S and S.SetAutoZoomOut) then error("Glass MiniMap without #13-#15") end
    S.SetAutoZoomOut(5); S.SetPingName("map"); S.SetFader(true); S.SetFaderOpacity(60)
    return "auto zoom-out 5 s, ping names on the map, fader on at 60 %"
end

local function container() return MinimapCluster and MinimapCluster.MinimapContainer end

local function protectedState(f)
    if not (f and f.IsProtected) then return "n/a" end
    local ok, p, explicit = pcall(f.IsProtected, f)
    return ok and (str(p) .. "/" .. str(explicit)) or "error"
end

local function about(a, b) return type(a) == "number" and math.abs(a - b) < 0.01 end

-- The fader at rest, the mouse away (#15).
local function faderCheck()
    local g, c = gmm(), container()
    if not (g and c) then return false, "Glass MiniMap or the container: MISSING" end
    local a = c:GetAlpha()
    local q = g.Queue.Disc()
    local qa = q and q:GetAlpha()
    local ok = about(a, 0.6) and (q == nil or about(qa, 0.6))
    return ok, ("container alpha %s (want 0.6), queue backing %s, Minimap %s; protected: container %s, Minimap %s, cluster %s"):format(
        str(a), str(qa), str(Minimap:GetAlpha()), protectedState(c), protectedState(Minimap), protectedState(MinimapCluster))
end

local function faderHeldCheck()
    local g, c = gmm(), container()
    if not (g and c) then return false, "MISSING" end
    local open = g.Tracking.IsOpen()
    return open and c:GetAlpha() == 1, ("tracking menu open %s, container alpha %s (want 1)"):format(str(open), str(c:GetAlpha()))
end

-- What the minimap's events said, for the checks and the log: each zoom
-- event with the zoom and indoors (#13), each ping with its payload and the
-- pinger's name when plain (#14), and the container's alpha range in combat.
local seen = { zooms = 0, pings = {}, combat = nil }
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("MINIMAP_UPDATE_ZOOM")
watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
watcher:SetScript("OnEvent", function(_, event, a, b, c)
    if event == "MINIMAP_UPDATE_ZOOM" then
        seen.zooms = seen.zooms + 1
        local okI, indoors = pcall(IsIndoors)
        say(("zoom event: zoom %s, indoors %s"):format(str(zoom()), str(okI and indoors)))
    elseif event == "MINIMAP_PING" then
        say(("ping payload secret: unit %s, y %s, x %s"):format(str(secret(a)), str(secret(b)), str(secret(c))))
        local mine = false
        if not secret(a) then
            local ok, m = pcall(UnitIsUnit, a, "player")
            mine = ok and not secret(m) and m == true
        end
        local okN, name = false, nil
        if not secret(a) then okN, name = pcall(UnitName, a) end
        if not okN or secret(name) then name = nil end
        local okP, px, py = pcall(Minimap.GetPingPosition, Minimap)
        local entry = { unit = not secret(a) and a or "(secret)", mine = mine, name = name }
        seen.pings[#seen.pings + 1] = entry
        say(("ping: unit %s (ours %s, name %s), y %s, x %s; GetPingPosition %s, %s; map width %s"):format(
            str(entry.unit), str(mine), str(name), str(b), str(c), str(okP and px), str(okP and py), str(Minimap:GetWidth())))
    elseif event == "PLAYER_REGEN_DISABLED" then
        seen.combat = { min = 1, max = 0, changes = 0, last = nil }
    elseif event == "PLAYER_REGEN_ENABLED" and seen.combat then
        local k = seen.combat
        say(("combat: container alpha %s to %s, %s changes"):format(str(k.min), str(k.max), str(k.changes)))
        seen.lastCombat, seen.combat = k, nil
    end
end)
-- MINIMAP_PING is a callback event: RegisterEvent refuses it (70450, the
-- owner's error), Event.RegisterCallback hands over the payload alone.
do
    local onEvent = watcher:GetScript("OnEvent")
    local ok, why = pcall(function()
        return Event.RegisterCallback("MINIMAP_PING", function(...) onEvent(watcher, "MINIMAP_PING", ...) end)
    end)
    if not ok or not why then say("MINIMAP_PING: no callback (" .. str(why) .. ")") end
end
watcher:SetScript("OnUpdate", function()
    local k, c = seen.combat, container()
    if not (k and c) then return end
    local a = c:GetAlpha()
    if k.last and a ~= k.last then k.changes = k.changes + 1 end
    k.last, k.min, k.max = a, math.min(k.min, a), math.max(k.max, a)
end)

local function zoomedIn() local z = zoom(); return z ~= nil and z > 0, "zoom " .. str(z) end
local function zoomedOut() local z = zoom(); return z == 0, "zoom " .. str(z) end

local function ownPing()
    local before = #seen.pings
    Minimap:PingLocation(40, 25)
    return before
end

local function ownPingCheck()
    local g = gmm()
    local last = seen.pings[#seen.pings]
    local shown = g and g.Ping.Pill() and g.Ping.Pill():IsShown()
    return last ~= nil and last.mine and not shown,
        ("last ping ours %s, the label shown %s (want no label)"):format(str(last and last.mine), str(shown))
end

local function showOwnLabel()
    local g = gmm()
    local ok, name = pcall(UnitName, "player")
    local r, gr, b = g.API.ClassColor()
    if not (ok and g.Ping.Show(name, r and { r, gr, b } or nil)) then error("the label couldn't be shown") end
    return name
end

local function labelShown()
    local g = gmm()
    local pill = g and g.Ping.Pill()
    return pill ~= nil and pill:IsShown(), "label shown " .. str(pill and pill:IsShown())
end

-- A real ping from someone else: the label names them.
local function otherPingCheck()
    local g = gmm()
    local last
    for i = #seen.pings, 1, -1 do
        if not seen.pings[i].mine then last = seen.pings[i]; break end
    end
    if not last then return false, "no ping from another player seen" end
    local text = g.Ping._test.text():GetText()
    local ok = last.name ~= nil and text == last.name
    return ok, ("their ping: unit %s, name %s; the label says %s"):format(str(last.unit), str(last.name), str(text))
end

local function failuresCheck()
    local g = gmm()
    local n = 0
    for _ in pairs(g and g.failures or {}) do n = n + 1 end
    return n == 0, n .. " failure(s) (/gmm failures)"
end

-- The fader changed the container's alpha in combat with no failure.
local function combatFaderCheck()
    local k = seen.lastCombat
    local okF, f = failuresCheck()
    if not k then return false, "no fight seen (PLAYER_REGEN_DISABLED then ENABLED)" end
    return k.changes > 0 and okF, ("in combat the container's alpha went %s to %s, %s changes; %s"):format(
        str(k.min), str(k.max), str(k.changes), f)
end

-- The checklist (#2): the map at a scale, and rotation.
local function scaleCheck()
    local c, g = container(), gmm()
    if not (c and g) then return false, "MISSING" end
    local host = g.Ring.Host()
    local ce, he, me = c:GetEffectiveScale(), host:GetEffectiveScale(), Minimap:GetEffectiveScale()
    local w, h = c:GetSize()
    local ok = about(he, ce) and about(me, ce)
    return ok, ("container %sx%s scale %s eff %s; Minimap %sx%s eff %s; ring eff %s (want the container's)"):format(
        str(w), str(h), str(c:GetScale()), str(ce), str(Minimap:GetWidth()), str(Minimap:GetHeight()), str(me), str(he))
end

local function rotationCheck(want)
    return function()
        local on = GetCVarBool("rotateMinimap")
        return on == want, "rotateMinimap " .. str(on) .. " (want " .. str(want) .. ")"
    end
end

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
end, "the tint and the wash of the ring and zoom buttons")
Probe:Command("discs", function()
    local _, m = mailCheck()
    say("mail: " .. m)
    local _, kind = GetInstanceInfo()
    local _, d = instanceCheck(kind ~= "none")
    say("instance: " .. d)
end, "the mail and instance discs")
Probe:Command("focus", function() say("under the mouse: " .. focusName()) end, "what's under the mouse")
Probe:Command("restore", function() say(table.concat({ restore() }, " ")) end,
    "put back the tint and zoom a procedure changed")
Probe:Command("clear", function() Probe:ClearLog(); say("log cleared") end, "empty the saved log")

--------------------------------------------------------------------------------
-- Procedures
--------------------------------------------------------------------------------

local function SAVE()
    return { text = "Saving your tint, zoom and settings, to put them back at the end (/fp mm restore if you stop). Auto zoom-out is paused for the run.",
        auto = true, run = snapshot }
end
local function RESTORE() return { text = "Put your tint and zoom back.", button = "Restore", run = restore } end

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

Probe:Steps("edges", {
    rev = 3,
    title = "The ring's edges: the coords pill under the ring, the zoom buttons (#42)",
    SAVE(),
    { text = "With the runic ring and its vapor on (/gmm runes on, /gmm runes fog on), go somewhere bright (a desert, snow), then press Check.",
      button = "Check", run = sceneryTheme("clear"), check = edgesCheck, screenshot = "edges: bright, zoom in the pill" },
    { text = "Does the coordinates pill sit as far under the ring as the zone name sits over it, the coordinates centered under the map, - and + at its ends?",
      ask = true },
    { text = "Is the ring's rim a closed circle at the bottom, with the vapor behind the pill, not over it?", ask = true },
    { text = "Is the pill clear of the quest tracker (All Objectives) under it?", ask = true },
    { text = "Now the zoom buttons on the ring (the new setting).", button = "Ring", run = setZoomPlace("ring"),
      check = zoomRingCheck, screenshot = "edges: bright, zoom on the ring" },
    { text = "Are + and - on the ring at the bottom right, like your mockup's A, and do they zoom when clicked?", ask = true },
    { text = "Go somewhere dark (a cave, a forest at night), then press Shoot.", button = "Shoot",
      run = sceneryTheme("clear"), screenshot = "edges: dark, zoom on the ring" },
    { text = "On dark ground: do the pill, its text and the zoom discs read well?", ask = true },
    { text = "Put your tint, zoom and zoom buttons back.", button = "Restore", run = restore },
})

Probe:Steps("zoomring", {
    rev = 1,
    title = "The zoom discs on the ring: clicks and the fade (#42)",
    SAVE(),
    { text = "Zoom buttons on the ring, and the map's zoom to the middle (so + and - both work).", button = "Ring",
      run = ringZoomReady, check = zoomRingCheck },
    { text = "Move the mouse off the minimap, wait 2 seconds, then press Check.", button = "Check",
      run = function() end, check = fadedCheck, screenshot = "zoomring: faded" },
    { text = "Hover the minimap: do + and - fade in, and fade out a moment after the mouse leaves?", ask = true },
    { text = "Click - on the ring (bottom right). Nothing happens? Hover it, type /fp mm focus, then Skip.",
      event = "MINIMAP_UPDATE_ZOOM", check = clickCheck(1) },
    { text = "Click + on the ring.", event = "MINIMAP_UPDATE_ZOOM", check = clickCheck(2) },
    { text = "Put your tint, zoom and zoom buttons back.", button = "Restore", run = restore },
})

Probe:Steps("extras", {
    rev = 1,
    title = "Auto zoom-out, who pinged, the fader (#13, #14, #15)",
    SAVE(),
    { text = "The three settings at their defaults for this run.", auto = true, run = behaviourDefaults },
    { text = "Move the mouse off the minimap, wait 2 seconds, then press Check.", button = "Check",
      run = function() end, check = faderCheck, screenshot = "extras: faded" },
    { text = "Hover the minimap: does it come to full, and fade back a second after the mouse leaves?", ask = true },
    { text = "Hover just outside the ring, in the corner between the ring and the zone pill's end: does it stay faded?",
      ask = true },
    { text = "Open the tracking menu (click the magnifier), move the mouse off it and the map, wait 3 seconds, then press Check.",
      button = "Check", run = function() end, check = faderHeldCheck },
    { text = "Close the menu. Zoom in with the mouse wheel, then move the mouse off the minimap and leave it there.",
      event = "MINIMAP_UPDATE_ZOOM" },
    { text = "Wait: the map zooms back out about 5 seconds after the mouse left.", wait = zoomedOut, timeout = 15 },
    { text = "Zoom in again and keep the mouse on the map for about 8 seconds, then press Check (still on the map).",
      button = "Check", run = function() end, check = zoomedIn },
    { text = "Now move the mouse off the minimap and wait.", wait = zoomedOut, timeout = 15 },
    { text = "Optional: zoom in, walk into a building and back out, then press Done (Skip if none is near). Each zoom event is logged.",
      button = "Done", run = function() return seen.zooms end },
    { text = "The probe pings the map itself (your own ping: no label).", button = "Ping", run = ownPing,
      check = ownPingCheck },
    { text = "The probe shows your name the way a group member's would be shown, by that ping.", button = "Show",
      run = showOwnLabel, check = labelShown, screenshot = "extras: ping label" },
    { text = "Was your name by the ping, readable, then fading out after about 3 seconds?", ask = true },
    { text = "In a group: have someone ping the minimap, then press Check. Alone? Skip (#14 stays open until this passes).",
      button = "Check", run = function() end, check = otherPingCheck, screenshot = "extras: their ping" },
    { text = "Type /console scriptErrors 1. Open Edit Mode, move and scale the minimap, close Edit Mode, then press Check.",
      button = "Check", run = function() end, check = failuresCheck },
    { text = "Fight something, moving the mouse on and off the minimap during the fight. The step ends when the fight does.",
      event = "PLAYER_REGEN_ENABLED", check = combatFaderCheck },
    { text = "No Lua error and no blocked or forbidden action message, all along?", ask = true },
    { text = "Put your tint, zoom and settings back.", button = "Restore", run = restore },
})

Probe:Steps("checklist", {
    rev = 1,
    title = "What #2 still has open: rotation, Edit Mode scale, tracking, the drawer, taint",
    SAVE(),
    { text = "Turn Rotate Minimap on (Options > Interface, or /console rotateMinimap 1), then press Check.",
      button = "Check", run = function() end, check = rotationCheck(true), screenshot = "checklist: rotating" },
    { text = "Turn around: is the map round inside the ring, the north tab moving round it, and no stock compass art?",
      ask = true },
    { text = "Turn Rotate Minimap off, then press Check.", button = "Check", run = function() end,
      check = rotationCheck(false), screenshot = "checklist: fixed" },
    { text = "Is the map's mask still round and filling the ring?", ask = true },
    { text = "Edit Mode: set the minimap's size to its smallest (80 % or what it offers), close Edit Mode, then press Check.",
      button = "Check", run = function() end, check = scaleCheck, screenshot = "checklist: small" },
    { text = "Edit Mode: set it to its largest (120 % or what it offers), close Edit Mode, then press Check.",
      button = "Check", run = function() end, check = scaleCheck, screenshot = "checklist: large" },
    { text = "At both sizes, did the ring, the pills and the discs follow the map? (Put the size back after.)", ask = true },
    { text = "Tracking: in our menu (click the magnifier) turn a tracking on (Find Herbs, say), then right-click the magnifier for Blizzard's menu. Does it agree? Then Uncheck All in ours, and check again.",
      ask = true },
    { text = "The drawer: is each addon there once (a LibDBIcon one, and a compartment-only one such as Gnomesweeper), and do left and right clicks reach both kinds?",
      ask = true },
    { text = "Taint pass: Edit Mode, move, scale and rotate the minimap, close; then fight using your action bars and a macro. The step ends when the fight does.",
      event = "PLAYER_REGEN_ENABLED", check = failuresCheck },
    { text = "No Lua error and no blocked or forbidden action message, all along?", ask = true },
    { text = "Put your tint, zoom and settings back.", button = "Restore", run = restore },
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

Probe:Steps("suite", {
    rev = 2,
    title = "Following Glass UI's suite (#37)",
    SAVE(),
    { text = "With Glass UI loaded and \"Use Glass UI appearance\" on for Glass MiniMap (then /reload), press Check: Pearl, following the suite's look.",
      button = "Check", run = function() end, check = followingCheck, screenshot = "suite: following" },
    { text = "Press Check: Glass MiniMap's own tint can't be set while following, and the one saved is kept.",
      button = "Check", run = function() end, check = tintRefusedCheck },
    { text = "Open Esc > Options > AddOns > Glass MiniMap. Press Shoot.", button = "Shoot", run = armShot("suite: options") },
    { text = "After the shutter: are the tint and the material choices grayed out, with \"Following Glass UI\" and a Set in Glass UI button, as GlassPanel's are?",
      ask = true, check = shotCheck("suite: options") },
    { text = "Close the options. Type /glassui look tint smoked, then press Check.", button = "Check", run = function() end,
      check = tintCheck("smoked"), screenshot = "suite: smoked" },
    { text = "Type /glassui look tint class, then press Check.", button = "Check", run = function() end,
      check = tintCheck("class"), screenshot = "suite: class" },
    { text = "Type /glassui look tint clear, then press Check.", button = "Check", run = function() end,
      check = tintCheck("clear"), screenshot = "suite: clear" },
    { text = "Did the ring, the pills, the discs and the north tab (and the drawer's bar) repaint at each change, with no lag?", ask = true },
    { text = "Start a fight (a training dummy), and while in combat type /glassui look tint smoked. After the fight, press Check.",
      button = "Check", run = function() end, check = tintCheck("smoked"), screenshot = "suite: after combat" },
    { text = "Did the minimap repaint during the fight, with no error or blocked action (scriptErrors, BugSack)?", ask = true },
    { text = "Put Glass MiniMap's tint and zoom back. Put Glass UI's tint back yourself (/glassui look tint ...).",
      button = "Restore", run = restore },
})

Probe:Steps("suiteoff", {
    rev = 2,
    title = "Not following Glass UI (#37)",
    { text = "Turn \"Use Glass UI appearance\" off for Glass MiniMap in Glass UI (or disable Glass UI), /reload, start this again, and press Check: our own material and tint (the one saved, or clear).",
      button = "Check", run = function() end, check = ownLookCheck, screenshot = "suite: own look" },
    { text = "Are the material and the tint the ones you had before following (Glass MiniMap's options page)?", ask = true },
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
        say("a procedure's tint and zoom are still to put back: /fp mm restore")
    end
end)
