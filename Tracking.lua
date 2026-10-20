-- Tracking.lua: the glass tracking menu (the magnifier on the zone pill).
--
-- What it lists and how a click acts is Blizzard's own tracking menu
-- (Blizzard_Minimap\Mainline\Minimap.lua, MiniMapTrackingButtonMixin:OnLoad),
-- only drawn in glass:
-- - an entry shows when MinimapConstants.OPTIONAL_FILTERS has its filterID
--   or it has a spellID (CanDisplayTrackingInfo), unless the
--   minimapTrackingShowAll CVar is on, which shows everything, drops
--   "Uncheck All" and puts townsfolk under their own heading;
-- - a hunter's own tracking (subType 1) gets a heading only when there is
--   more than one; low-priority spells sort last, then by index;
-- - "Uncheck All" clears everything, then turns the ALWAYS_ON and
--   CONDITIONAL filters back on;
-- - a click goes through MinimapUtil.SetTrackingFilterByFilterIndex, which
--   routes the two filters that have Settings entries through Settings.
-- Some tracking only turns on once a spell cast completes, so the clicked
-- state is kept (predicted) while the menu stays open, as Blizzard's does,
-- and the real state is read again when it closes or reopens.
-- Right-click on the magnifier opens Blizzard's menu instead (always there).

GlassMiniMap = GlassMiniMap or {}
local GMM = GlassMiniMap
local API = GMM.API
local Theme = GMM.Theme
local Tracking = {}
GMM.Tracking = Tracking

Tracking.NAME = "GlassMiniMapTrackingPopup"
Tracking.WIDTH = 236
Tracking.ROW = 22
Tracking.HUNTER = 1        -- HUNTER_TRACKING
Tracking.TOWNSFOLK = 2     -- TOWNSFOLK_TRACKING
Tracking.LOW_PRIORITY = { [261764] = true }   -- Track Warboards
Tracking.ATLAS = {         -- TRACKING_SPELL_OVERRIDE_ATLAS
    [43308] = "professions_tracking_fish", [2580] = "professions_tracking_ore",
    [8388] = "professions_tracking_ore", [2383] = "professions_tracking_herb",
    [8387] = "professions_tracking_herb", [122026] = "WildBattlePetCapturable",
}

local predicted = {}       -- index -> wanted, while the menu is open

local function text(global, fallback)
    local v = rawget(_G, global)
    return type(v) == "string" and v or fallback
end

local function constants() return rawget(_G, "MinimapConstants") or {} end

local function numTypes()
    local ok, n = pcall(C_Minimap.GetNumTrackingTypes)
    n = ok and API.Plain(n) or 0
    return type(n) == "number" and n or 0
end

local function filterOf(index)
    local ok, f = pcall(C_Minimap.GetTrackingFilter, index)
    return ok and type(f) == "table" and f or nil
end

local function infoOf(index)
    local ok, info = pcall(C_Minimap.GetTrackingInfo, index)
    return ok and type(info) == "table" and info or nil
end

-- CanDisplayTrackingInfo.
local function displayable(index)
    local f = filterOf(index)
    if not f then return false end
    local optional = constants().OPTIONAL_FILTERS
    return (optional and f.filterID ~= nil and optional[f.filterID]) or f.spellID ~= nil
end

local function isHunter()
    local ok, _, class = pcall(UnitClass, "player")
    return ok and API.Plain(class) == "HUNTER"
end

-- The menu's rows, in order: { kind = "uncheck" | "heading" | "entry", ... }.
-- Entries carry index, name, texture, atlas, isSpell, indent.
function Tracking.Rows()
    local showAll = API.CVarBool("minimapTrackingShowAll")
    local hunter, townsfolk, regular = {}, {}, {}
    local hunterClass = isHunter()
    for index = 1, numTypes() do
        if showAll or displayable(index) then
            local info = infoOf(index)
            if info then
                local f = filterOf(index) or {}
                local spellID = API.Plain(info.spellID) or f.spellID
                local e = { kind = "entry", index = index, name = API.Plain(info.name) or "?",
                            texture = API.Plain(info.texture), isSpell = info.type == "spell",
                            atlas = spellID and Tracking.ATLAS[spellID], low = Tracking.LOW_PRIORITY[f.spellID] or false }
                if hunterClass and info.subType == Tracking.HUNTER then
                    hunter[#hunter + 1] = e
                elseif info.subType == Tracking.TOWNSFOLK then
                    townsfolk[#townsfolk + 1] = e
                else
                    regular[#regular + 1] = e
                end
            end
        end
    end
    local function sort(list)
        table.sort(list, function(a, b)
            if a.low ~= b.low then return not a.low end
            return a.index < b.index
        end)
    end
    sort(hunter); sort(townsfolk); sort(regular)

    local rows = {}
    if not showAll then rows[#rows + 1] = { kind = "uncheck", name = text("UNCHECK_ALL", "Uncheck All") } end
    local function add(list, heading)
        if heading then rows[#rows + 1] = { kind = "heading", name = heading } end
        for _, e in ipairs(list) do
            e.indent = heading ~= nil
            rows[#rows + 1] = e
        end
    end
    if #hunter > 0 then add(hunter, #hunter > 1 and text("HUNTER_TRACKING_TEXT", "Hunter Tracking") or nil) end
    if #townsfolk > 0 then add(townsfolk, showAll and text("TOWNSFOLK_TRACKING_TEXT", "Townsfolk") or nil) end
    add(regular, nil)
    return rows
end

function Tracking.IsChecked(index)
    if predicted[index] ~= nil then return predicted[index] end
    local info = infoOf(index)
    return info ~= nil and API.Plain(info.active) == true
end

local function setTracking(index, on)
    predicted[index] = on
    local util = rawget(_G, "MinimapUtil")
    if util and util.SetTrackingFilterByFilterIndex then
        API.Try("tracking:set", util.SetTrackingFilterByFilterIndex, index, on)
    else
        API.Try("tracking:set", C_Minimap.SetTracking, index, on)
    end
end

function Tracking.ToggleEntry(index)
    setTracking(index, not Tracking.IsChecked(index))
end

function Tracking.UncheckAll()
    for index = 1, numTypes() do predicted[index] = false end
    API.Try("tracking:clear", C_Minimap.ClearAllTracking)
    local c = constants()
    local always, conditional = c.ALWAYS_ON_FILTERS or {}, c.CONDITIONAL_FILTERS or {}
    for index = 1, numTypes() do
        local f = filterOf(index)
        if f and f.filterID ~= nil and (always[f.filterID] or conditional[f.filterID]) then
            setTracking(index, true)
        end
    end
end

--------------------------------------------------------------------------------
-- The popup
--------------------------------------------------------------------------------

local popup, rowFrames = nil, {}

local function paintRow(row, data)
    row.data = data
    row.check:SetShown(data.kind == "entry")
    row.box:SetShown(data.kind == "entry")
    row.icon:SetShown(data.kind == "entry")
    row.label:ClearAllPoints()
    if data.kind == "entry" then
        local x = data.indent and 16 or 4
        row.box:ClearAllPoints()
        row.box:SetPoint("LEFT", row, "LEFT", x, 0)
        row.label:SetPoint("LEFT", row.box, "RIGHT", 6, 0)
        row.label:SetPoint("RIGHT", row.icon, "LEFT", -4, 0)
        row.label:SetTextColor(0.95, 0.96, 1)
        row.check:SetShown(Tracking.IsChecked(data.index))
        row.icon:SetTexCoord(0, 1, 0, 1)
        if data.atlas then
            API.SetIcon(row.icon, data.atlas)
        else
            row.icon:SetTexture(data.texture)
            if data.isSpell then row.icon:SetTexCoord(0.0625, 0.9, 0.0625, 0.9) end
        end
        row:EnableMouse(true)
    elseif data.kind == "heading" then
        row.label:SetPoint("LEFT", row, "LEFT", 4, 0)
        row.label:SetTextColor(1, 0.82, 0)
        row:EnableMouse(false)
    else
        row.label:SetPoint("LEFT", row, "LEFT", 4, 0)
        row.label:SetTextColor(0.95, 0.96, 1)
        row:EnableMouse(true)
    end
    row.label:SetText(data.name)
end

local function makeRow(i)
    local row = CreateFrame("Button", nil, popup)
    row:SetHeight(Tracking.ROW)
    local inset = GMM.Glass.Inset("large") + 2
    row:SetPoint("TOPLEFT", popup, "TOPLEFT", inset, -inset - (i - 1) * Tracking.ROW)
    row:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -inset, -inset - (i - 1) * Tracking.ROW)
    row:SetFrameLevel(GMM.Glass.ContentLevel(popup))
    row:RegisterForClicks("AnyUp")
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(row)
    hl:SetColorTexture(1, 1, 1, 0.08)
    -- The checkbox: a small glass square, the stock check mark over it.
    local box = CreateFrame("Frame", nil, row)
    box:SetSize(14, 14)
    row.box = box
    local g = GMM.Glass.Apply(box, "small")
    g.shadow:SetAlpha(0)
    Theme.Register(g)
    local check = row:CreateTexture(nil, "OVERLAY")
    check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    check:SetSize(20, 20)
    check:SetPoint("CENTER", box, "CENTER", 1, 1)
    row.check = check
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    row.icon = icon
    local label = GMM.Glass.Font(row, 13, "LEFT")
    row.label = label
    row:SetScript("OnClick", function(self)
        local d = self.data
        if not d then return end
        if d.kind == "uncheck" then Tracking.UncheckAll()
        elseif d.kind == "entry" then Tracking.ToggleEntry(d.index) end
        Tracking.Refresh()
    end)
    rowFrames[i] = row
    return row
end

-- Rebuild the rows from the client's tracking list (it changes with spells).
function Tracking.Refresh()
    if not (popup and popup:IsShown()) then return end
    local rows = Tracking.Rows()
    for i, data in ipairs(rows) do
        local row = rowFrames[i] or makeRow(i)
        paintRow(row, data)
        row:Show()
    end
    for i = #rows + 1, #rowFrames do rowFrames[i]:Hide() end
    local inset = GMM.Glass.Inset("large") + 2
    popup:SetHeight(inset * 2 + math.max(1, #rows) * Tracking.ROW)
end

local function outside()
    if popup:IsMouseOver() then return false end
    local tb = GMM.Header.TrackingButton()
    return not (tb and tb:IsMouseOver())
end

local function onEvent(_, event, arg)
    if event == "GLOBAL_MOUSE_DOWN" then
        if outside() then Tracking.Close() end
    elseif event == "CVAR_UPDATE" then
        if arg == "minimapTrackedInfov4" or arg == "minimapTrackingShowAll" then Tracking.Refresh() end
    else
        Tracking.Refresh()
    end
end

function Tracking.Build()
    popup = CreateFrame("Frame", Tracking.NAME, UIParent)
    popup:SetSize(Tracking.WIDTH, 100)
    popup:SetFrameStrata("DIALOG")
    popup:SetToplevel(true)
    popup:SetClampedToScreen(true)
    popup:EnableMouse(true)
    popup:Hide()
    local g = GMM.Glass.Apply(popup, "large")
    Theme.Register(g)
    -- An opaque backing under the glass (GlassPanel's dialogs): the glass is
    -- made for the world, and over the map and the quest tracker their text
    -- showed through the menu (owner's screenshot, 70374). Above the shadow
    -- (-8), under the tint (-6), clipped by the glass's own mask.
    local backing = popup:CreateTexture(nil, "BACKGROUND", nil, -7)
    backing:SetAllPoints(popup)
    backing:SetColorTexture(0.05, 0.06, 0.08, 0.92)
    backing:AddMaskTexture(g.mask)
    -- Escape closes it, like Blizzard's menus.
    local special = rawget(_G, "UISpecialFrames")
    if type(special) == "table" then table.insert(special, Tracking.NAME) end
    popup:SetScript("OnEvent", onEvent)
    popup:SetScript("OnShow", function(self)
        API.RegisterEvents(self, { "GLOBAL_MOUSE_DOWN", "MINIMAP_UPDATE_TRACKING", "SPELLS_CHANGED", "CVAR_UPDATE" },
            "tracking menu")
    end)
    popup:SetScript("OnHide", function(self)
        self:UnregisterAllEvents()
        wipe(predicted)          -- read the real state next time
    end)
    return popup
end

function Tracking.Open(anchor)
    if not popup then return end
    wipe(predicted)
    popup:ClearAllPoints()
    if anchor then
        -- Beside the map, like Blizzard's tracking menu, not over it.
        popup:SetPoint("TOPRIGHT", anchor, "BOTTOMLEFT", -4, -4)
    else
        popup:SetPoint("CENTER", UIParent, "CENTER")
    end
    popup:Show()
    Tracking.Refresh()
end

function Tracking.Close()
    if popup and popup:IsShown() then popup:Hide() end
end

function Tracking.IsOpen() return popup ~= nil and popup:IsShown() end

-- The magnifier's click: the glass menu, or Blizzard's when the glass one
-- can't be built (GMM.db.glassTracking off, or the build failed).
function Tracking.Toggle(anchor)
    if Tracking.IsOpen() then return Tracking.Close() end
    if popup and GMM.db.glassTracking ~= false then
        Tracking.Open(anchor)
    else
        GMM.Blizzard.OpenTrackingMenu(anchor)
    end
end

Tracking._test = { predicted = predicted, rows = rowFrames, popup = function() return popup end }
