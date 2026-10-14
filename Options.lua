-- Options.lua: the pages in Esc > Options > AddOns, built with the porting
-- guide's measured recipe ("An Options page with sub-pages and an About page"):
-- plain Frames with .name, hidden at creation (or the first visit is blank),
-- controls built on the first OnShow, every value re-read on every OnShow,
-- registered at PLAYER_LOGIN from GlassMiniMap.lua, the sub-page right after
-- the main one. Choices are radio groups, never dropdowns.
--
--   Glass MiniMap         the look, the coordinates, the day/night disc, the tracking menu
--     Addon drawer        Glass MiniMap Bar's page: behaviour, layout, the button lists

GlassMiniMap = GlassMiniMap or {}
local GMM = GlassMiniMap
local API = GMM.API
local Collector = GMM.Collector
local Options = {}
GMM.Options = Options

local RADIO_ART = "Interface\\Buttons\\UI-RadioButton"

local main = CreateFrame("Frame")
main.name = "Glass MiniMap"
main:Hide()
local drawer = CreateFrame("Frame")
drawer.name = "Addon drawer"
drawer:Hide()

local mainCategory, drawerCategory
local refreshers = { [main] = {}, [drawer] = {} }

local function label(parent, text, font)
    local fs = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlight")
    fs:SetText(text)
    fs:SetJustifyH("LEFT")
    return fs
end

local function safeFrame(ftype, parent, template, proof)
    local ok, f = pcall(CreateFrame, ftype, nil, parent, template)
    if ok and f then return f, (proof == nil) or f[proof] ~= nil end
    return CreateFrame(ftype, nil, parent), false
end

local function radioButton(parent, text)
    local rb, templated = safeFrame("CheckButton", parent, "UIRadioButtonTemplate", "text")
    if templated then
        rb.text:SetFontObject("GameFontHighlight")
        rb.text:SetText(text)
        return rb
    end
    rb:SetSize(16, 16)
    rb:SetNormalTexture(RADIO_ART)
    rb:GetNormalTexture():SetTexCoord(0, 0.25, 0, 1)
    rb:SetCheckedTexture(RADIO_ART)
    rb:GetCheckedTexture():SetTexCoord(0.25, 0.5, 0, 1)
    rb:SetHighlightTexture(RADIO_ART)
    rb:GetHighlightTexture():SetTexCoord(0.5, 0.75, 0, 1)
    rb:GetHighlightTexture():SetBlendMode("ADD")
    local fs = label(parent, text)
    fs:SetPoint("LEFT", rb, "RIGHT", 4, 0)
    return rb
end

-- An on/off setting under `anchor`.
local function checkbox(page, anchor, text, get, set)
    local cb = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
    local fs = label(page, text)
    fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    local function sync() cb:SetChecked(get() == true) end
    cb:SetScript("OnClick", function() set(cb:GetChecked() == true); sync() end)
    table.insert(refreshers[page], sync)
    return cb
end

-- Mutually exclusive choices stacked under `anchor`: { {value, text}, ... }.
local function radios(page, anchor, options, get, set)
    local group = {}
    local function sync()
        local current = get()
        for _, rb in ipairs(group) do rb:SetChecked(rb.value == current) end
    end
    local prev = anchor
    for _, o in ipairs(options) do
        local rb = radioButton(page, o[2])
        rb.value = o[1]
        rb:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, prev == anchor and -8 or -4)
        rb:SetScript("OnClick", function() set(o[1]); sync() end)
        group[#group + 1] = rb
        prev = rb
    end
    table.insert(refreshers[page], sync)
    return prev, group
end

local function button(parent, text, width)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 24, 22)
    b:SetText(text)
    return b
end

local function heading(page, text, anchor, y)
    local fs = label(page, text, "GameFontNormal")
    fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, y or -16)
    return fs
end

--------------------------------------------------------------------------------
-- The main page
--------------------------------------------------------------------------------

local function buildMain()
    local title = label(main, "|cff7fd4ffGlass|r MiniMap", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", main, "TOPLEFT", 16, -16)
    local version = label(main, "", "GameFontDisableSmall")
    version:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    table.insert(refreshers[main], function()
        version:SetText("Version " .. GMM.VersionText() .. " for World of Warcraft: Forever, by Spotnick")
    end)

    local look = heading(main, "The glass", version, -16)
    local opts = {}
    for _, name in ipairs(GMM.Theme.NAMES) do opts[#opts + 1] = { name, GMM.Theme.LABELS[name] } end
    local last, group = radios(main, look, opts, function() return GMM.db.theme end, GMM.Settings.SetTheme)
    Options._test.themeRadios = group

    local map = heading(main, "Around the map", last, -16)
    local c1 = checkbox(main, map, "Show the coordinates under the map",
        function() return GMM.db.coords end, function(on) GMM.Settings.Set("coords", on) end)
    local c2 = checkbox(main, c1, "Coordinates to a tenth (43.2, 24.8)",
        function() return GMM.db.coordsTenths end, function(on) GMM.Settings.Set("coordsTenths", on) end)
    local c3 = checkbox(main, c2, "Show the day and night disc",
        function() return GMM.db.sun end, function(on) GMM.Settings.Set("sun", on) end)
    local c4 = checkbox(main, c3, "Glass tracking menu (off: Blizzard's menu)",
        function() return GMM.db.glassTracking end, function(on) GMM.Settings.Set("glassTracking", on) end)
    Options._test.checks = { c1, c2, c3, c4 }

    local hint = label(main, "The minimap moves and scales with Edit Mode. Type /gmm help for every command.",
        "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", c4, "BOTTOMLEFT", 0, -16)
end

--------------------------------------------------------------------------------
-- The drawer page (Glass MiniMap Bar's options page)
--------------------------------------------------------------------------------

local function ddb() return GMM.Drawer.DB() end

local function toggle(anchor, key, text, get, set)
    return checkbox(drawer, anchor, text, get or function() return ddb()[key] == true end,
        set or function(on) GMM.Drawer.Set(key, on) end)
end

-- A number setting with - / + steppers inside the LIMITS range.
local function stepper(anchor, key, text, fmt)
    local lim = GMM.Drawer.LIMITS[key]
    local minus = button(drawer, "-")
    minus:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
    local value = drawer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    value:SetWidth(48)
    value:SetPoint("LEFT", minus, "RIGHT", 2, 0)
    local plus = button(drawer, "+")
    plus:SetPoint("LEFT", value, "RIGHT", 2, 0)
    local fs = label(drawer, text)
    fs:SetPoint("LEFT", plus, "RIGHT", 8, 0)
    local function refresh() value:SetText(fmt:format(ddb()[key])) end
    local function step(sign)
        GMM.Drawer.Set(key, ddb()[key] + sign * lim[3])
        refresh()
    end
    minus:SetScript("OnClick", function() step(-1) end)
    plus:SetScript("OnClick", function() step(1) end)
    table.insert(refreshers[drawer], refresh)
    return minus
end

Options.DIRECTIONS = { "auto", "left", "right", "up", "down" }
local DIRECTION_TEXT = { auto = "Auto (toward the screen centre)", left = "Left", right = "Right", up = "Up", down = "Down" }

local function cycle(anchor)
    local b = button(drawer, "", 220)
    b:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
    local fs = label(drawer, "Opens toward")
    fs:SetPoint("LEFT", b, "RIGHT", 8, 0)
    local function refresh() b:SetText(DIRECTION_TEXT[ddb().direction]) end
    b:SetScript("OnClick", function()
        local cur = ddb().direction
        for i, d in ipairs(Options.DIRECTIONS) do
            if d == cur then
                GMM.Drawer.Set("direction", Options.DIRECTIONS[i % #Options.DIRECTIONS + 1])
                break
            end
        end
        refresh()
    end)
    table.insert(refreshers[drawer], refresh)
    return b
end

-- The button lists: a classic dual list box. Hidden on the left, Shown on the
-- right (in drawer order), arrows between them, Up/Down beside the shown list.
local LIST_W, ROW_H, ROWS = 240, 20, 8
local lists = {}
local arrows = {}
local selected

local function greyed(e)
    local name = e.own and (e.display .. " |cff808080(AddOns list)|r") or e.display
    return e.wanted and name or (name .. " |cff808080(hidden by its addon)|r")
end

local refreshList

local function moveAcross(name)
    if not name then return end
    GMM.Drawer.SetHidden(name, not ddb().hidden[name])
    refreshList(true)
end

local function fill(list, follow)
    local items = list.items
    local maxOffset = math.max(0, #items - ROWS)
    for i, e in ipairs(items) do
        if follow and e.name == selected then
            if i <= list.offset then list.offset = i - 1
            elseif i > list.offset + ROWS then list.offset = i - ROWS end
        end
    end
    list.offset = math.max(0, math.min(list.offset, maxOffset))
    for r, row in ipairs(list.rows) do
        local e = items[r + list.offset]
        row.name = e and e.name
        row.label:SetText(e and greyed(e) or "")
        row.mark:SetShown(e ~= nil and e.name == selected)
        row:SetShown(e ~= nil)
    end
    list.empty:SetShown(#items == 0)
end

local function makeList(key, title, anchor, x, emptyText)
    local f = CreateFrame("Frame", nil, drawer)
    f:SetSize(LIST_W, ROWS * ROW_H + 8)
    f:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x, -30)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    bg:SetColorTexture(0, 0, 0, 0.45)
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = f:CreateTexture(nil, "BORDER")
        t:SetColorTexture(0.62, 0.5, 0.22, 0.9)
        if side == "TOP" or side == "BOTTOM" then
            t:SetHeight(1); t:SetPoint(side .. "LEFT"); t:SetPoint(side .. "RIGHT")
        else
            t:SetWidth(1); t:SetPoint("TOP" .. side); t:SetPoint("BOTTOM" .. side)
        end
    end
    local head = label(f, title, "GameFontNormal")
    head:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 2, 4)
    local empty = label(f, emptyText, "GameFontDisable")
    empty:SetPoint("CENTER")

    local list = { frame = f, rows = {}, items = {}, offset = 0, empty = empty }
    for r = 1, ROWS do
        local row = CreateFrame("Button", nil, f)
        row:SetSize(LIST_W - 8, ROW_H)
        row:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -4 - (r - 1) * ROW_H)
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(row)
        hl:SetColorTexture(1, 1, 1, 0.08)
        local mark = row:CreateTexture(nil, "ARTWORK")
        mark:SetAllPoints(row)
        mark:SetColorTexture(0.85, 0.68, 0.12, 0.35)
        mark:Hide()
        row.mark = mark
        local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        text:SetPoint("LEFT", row, "LEFT", 6, 0)
        text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        text:SetJustifyH("LEFT")
        row.label = text
        row:SetScript("OnClick", function(self)
            selected = self.name
            refreshList(true)
        end)
        row:SetScript("OnDoubleClick", function(self) moveAcross(self.name) end)
        list.rows[r] = row
    end
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta)
        list.offset = list.offset - delta
        fill(list, false)
    end)
    lists[key] = list
    return f
end

function refreshList(follow)
    local hidden = ddb().hidden
    local h, s, found = {}, {}, false
    for _, e in ipairs(Collector.entries) do
        if hidden[e.name] then h[#h + 1] = e else s[#s + 1] = e end
        if e.name == selected then found = true end
    end
    if not found then selected = nil end
    lists.hidden.items, lists.shown.items = h, s
    lists.shown.empty:SetText(#Collector.entries == 0 and "No buttons collected yet (/gmm scan)"
        or "All buttons are hidden")
    fill(lists.hidden, follow)
    fill(lists.shown, follow)
    local movable, at = selected and Collector.Movable(hidden, selected) or {}, nil
    for i, n in ipairs(movable) do if n == selected then at = i end end
    arrows.show:SetEnabled(selected ~= nil and hidden[selected] == true)
    arrows.hide:SetEnabled(selected ~= nil and not hidden[selected])
    arrows.up:SetEnabled(at ~= nil and at > 1)
    arrows.down:SetEnabled(at ~= nil and at < #movable)
end

local function buildLists(anchor)
    local top = heading(drawer, "Buttons", anchor, -18)
    local hint = label(drawer, "Select a button, then use the arrows to show or hide it (or double-click it). "
        .. "Up / Down set its place in the drawer.", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, -4)

    local left = makeList("hidden", "Hidden", top, 0, "No hidden buttons")
    local right = makeList("shown", "Shown in the drawer", top, LIST_W + 56, "No buttons collected yet (/gmm scan)")

    arrows.show = button(drawer, ">", 36)
    arrows.show:SetPoint("BOTTOM", left, "RIGHT", 28, 4)
    arrows.show:SetScript("OnClick", function() moveAcross(selected) end)
    arrows.hide = button(drawer, "<", 36)
    arrows.hide:SetPoint("TOP", left, "RIGHT", 28, -4)
    arrows.hide:SetScript("OnClick", function() moveAcross(selected) end)

    arrows.up = button(drawer, "Up", 60)
    arrows.up:SetPoint("BOTTOMLEFT", right, "RIGHT", 8, 4)
    arrows.up:SetScript("OnClick", function()
        if selected then GMM.Drawer.MoveButton(selected, -1) end
        refreshList(true)
    end)
    arrows.down = button(drawer, "Down", 60)
    arrows.down:SetPoint("TOPLEFT", right, "RIGHT", 8, -4)
    arrows.down:SetScript("OnClick", function()
        if selected then GMM.Drawer.MoveButton(selected, 1) end
        refreshList(true)
    end)
end

local function buildDrawer()
    local title = label(drawer, "Addon drawer", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    local sub = label(drawer, "", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    sub:SetWidth(600)
    table.insert(refreshers[drawer], function()
        if GMM.Drawer.IsActive() then
            sub:SetText("The disc at the bottom left of the map opens a glass drawer with your addons' minimap "
                .. "buttons and Blizzard's AddOns list. Right-click the disc for this page "
                .. "(shift-right-click when it repeats the last button).")
        else
            sub:SetText("|cffff8040The drawer is off while Glass MiniMap Bar is enabled.|r Disable it in the "
                .. "AddOns list and /reload: its settings have been copied here.")
        end
    end)

    local h = heading(drawer, "Behaviour", sub, -18)
    local a = toggle(h, "openOn", "Open when the mouse is over the disc (off: open on click)",
        function() return ddb().openOn == "hover" end,
        function(on) GMM.Drawer.Set("openOn", on and "hover" or "click") end)
    a = toggle(a, "lastUsed", "The disc shows the last button used; right-click it to use it again")
    a = toggle(a, "skin", "Glass skin on the collected buttons")
    a = toggle(a, "animate", "Animate the drawer growing out of the disc")
    a = stepper(a, "hideDelay", "Seconds before the drawer closes", "%.2f")

    h = heading(drawer, "Layout", a, -18)
    a = cycle(h)
    a = stepper(a, "perRow", "Buttons per row", "%d")
    a = stepper(a, "buttonSize", "Button size", "%d")

    buildLists(a)
end

--------------------------------------------------------------------------------
-- Registration
--------------------------------------------------------------------------------

local function showing(page, build)
    page:SetScript("OnShow", function()
        if not page.built then
            page.built = true
            API.Try("options:" .. page.name, build)
        end
        for _, refresh in ipairs(refreshers[page]) do API.Try("options:refresh", refresh) end
        if page == drawer and arrows.down then API.Try("options:lists", refreshList, false) end
    end)
end
showing(main, buildMain)
showing(drawer, buildDrawer)

-- Called on every drawer change; a no-op until the drawer page is built.
function Options.RefreshDrawer()
    if not (arrows.down and drawer:IsShown()) then return end
    for _, refresh in ipairs(refreshers[drawer]) do refresh() end
    refreshList(false)
end

-- Called once at PLAYER_LOGIN by GlassMiniMap.lua: the main page, then its sub-page.
function Options.Register()
    if mainCategory then return end
    mainCategory = API.RegisterSettingsPanel(main, main.name)
    if mainCategory then drawerCategory = API.RegisterSettingsPanel(drawer, drawer.name, mainCategory) end
end

-- Open a page ("drawer", or the main one); false when the Settings framework can't.
function Options.Open(which)
    local ok = API.OpenSettings(which == "drawer" and drawerCategory or mainCategory)
    if not ok then API.Print("Esc > Options > AddOns > Glass MiniMap") end
    return ok
end

Options._test = { main = main, drawer = drawer, lists = lists, arrows = arrows,
                  selected = function() return selected end }
