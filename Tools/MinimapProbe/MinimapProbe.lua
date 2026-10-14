-- MinimapProbe: a throwaway measuring addon for Glass MiniMap (never shipped).
-- Answers the questions docs/FOREVER-PROBE.md lists, on the live client.
--
--   /mmprobe frames     the cluster's pieces, sizes, scales, the compartment's entries
--   /mmprobe rules      the game rules that switch minimap features off
--   /mmprobe tracking   every tracking type: name, filterID, spellID, subType, active
--   /mmprobe near       what draws near the map's bottom-left (the "72" over the launcher)
--   /mmprobe queue      QueueStatusButton: parent, anchor, size, shown

local function say(...) print("|cff7fd4ffmmprobe|r", ...) end

local function str(v)
    if issecretvalue and issecretvalue(v) then return "<secret>" end
    return tostring(v)
end

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
    local f = EnumerateFrames()
    while f do
        if not f:IsForbidden() and f:IsVisible() then
            for _, reg in ipairs({ f:GetRegions() }) do
                if reg:IsObjectType("FontString") and reg:IsVisible() then
                    local x, y = reg:GetCenter()
                    local t = reg:GetText()
                    local es = reg:GetEffectiveScale()
                    -- Some frames' positions (and texts) are secret on this client: skip them.
                    local secret = issecretvalue and (issecretvalue(x) or issecretvalue(y) or issecretvalue(t)
                        or issecretvalue(es))
                    if not secret and x and t and t ~= "" then
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

SLASH_MMPROBE1 = "/mmprobe"
SlashCmdList.MMPROBE = function(msg)
    local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if cmd == "frames" then pieces()
    elseif cmd == "rules" then rules()
    elseif cmd == "tracking" then tracking()
    elseif cmd == "near" then near(tonumber(arg))
    elseif cmd == "queue" then queue()
    else say("/mmprobe frames | rules | tracking | near [radius] | queue") end
end
