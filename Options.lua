-- Options.lua: the page in Esc > Options > AddOns, built with the porting
-- guide's measured recipe ("An Options page with sub-pages and an About page"):
-- a plain Frame with .name, hidden at creation (or the first visit is blank),
-- controls built on the first OnShow, every value re-read on every OnShow,
-- registered once at PLAYER_LOGIN from GlassMiniMap.lua. Choices are radio
-- groups, never dropdowns. The drawer's own options are Glass MiniMap Bar's
-- page (a button here opens it).

GlassMiniMap = GlassMiniMap or {}
local GMM = GlassMiniMap
local API = GMM.API
local Options = {}
GMM.Options = Options

local RADIO_ART = "Interface\\Buttons\\UI-RadioButton"

local panel = CreateFrame("Frame")
panel.name = "Glass MiniMap"
panel:Hide()

-- Everything sits in a scroll child: the page outgrew the Settings canvas
-- (#13-#15). The recipe's GlassUnitFrames\Options.lua; without the template a
-- plain ScrollFrame still clips, and scrolls by wheel.
local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -4)
scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -26, 4)
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(620, 1000)
scroll:SetScrollChild(content)
if not scroll.ScrollBar then
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange() or 0
        local y = math.max(0, math.min(range, (self:GetVerticalScroll() or 0) - delta * 40))
        self:SetVerticalScroll(y)
    end)
end

local category
local refreshers = {}

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
    rb.text = fs
    return rb
end

-- An on/off setting under `anchor`.
local function checkbox(anchor, text, get, set, parent)
    parent = parent or content
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
    local fs = label(parent, text)
    fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    fs:SetWidth(275)
    local function sync() cb:SetChecked(get() == true) end
    cb:SetScript("OnClick", function() set(cb:GetChecked() == true) end)
    refreshers[#refreshers + 1] = sync
    return cb
end

-- Off, and seen to be, or back on: the radio art has no disabled look and the
-- label is a FontString of ours, so SetEnabled alone shows nothing (GRF
-- measured both staying bright).
local function dim(rb, off)
    rb:SetEnabled(not off)
    rb:SetAlpha(off and 0.5 or 1)
    local c = off and 0.5 or 1
    if rb.text then rb.text:SetTextColor(c, c, c) end
end

-- Mutually exclusive choices stacked under `anchor`: { {value, text}, ... }.
local function radios(anchor, options, get, set, parent)
    parent = parent or content
    local group = {}
    local function sync()
        local current = get()
        for _, rb in ipairs(group) do rb:SetChecked(rb.value == current) end
    end
    local prev = anchor
    for _, o in ipairs(options) do
        local rb = radioButton(parent, o[2])
        rb.value = o[1]
        rb:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, prev == anchor and -8 or -4)
        rb:SetScript("OnClick", function() set(o[1]) end)
        group[#group + 1] = rb
        prev = rb
    end
    refreshers[#refreshers + 1] = sync
    return prev, group
end

local function heading(text, anchor, y)
    local fs = label(content, text, "GameFontNormal")
    fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, y or -16)
    return fs
end

local function runeSlider(title, key, lo, hi, y, parent)
    local text = label(parent, "", "GameFontHighlight")
    text:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    local slider = CreateFrame("Slider", nil, parent)
    slider:EnableMouse(true)
    slider:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -8)
    slider:SetSize(220, 16)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(lo, hi)
    slider:SetValueStep(5)
    slider:SetObeyStepOnDrag(true)
    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT", slider, "LEFT", 0, 0)
    track:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
    track:SetHeight(4)
    track:SetColorTexture(0.4, 0.4, 0.4, 0.8)
    slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    local updating = false
    local function refresh()
        updating = true
        local ok, err = pcall(function()
            slider:SetValue(GMM.db[key])
            text:SetText(string.format("%s: %g%%", title, GMM.db[key]))
        end)
        updating = false
        if not ok then error(err, 0) end
    end
    slider:SetScript("OnValueChanged", function(_, value)
        if not updating then
            GMM.Settings.SetRuneTuning(key, value)
        end
    end)
    refreshers[#refreshers + 1] = refresh
    return slider
end

-- A slider under `anchor`: its label reads fmt with the value.
local function valueSlider(anchor, fmt, lo, hi, step, get, set)
    local text = label(content, "", "GameFontHighlight")
    text:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -10)
    local slider = CreateFrame("Slider", nil, content)
    slider:EnableMouse(true)
    slider:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -8)
    slider:SetSize(220, 16)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(lo, hi)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT", slider, "LEFT", 0, 0)
    track:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
    track:SetHeight(4)
    track:SetColorTexture(0.4, 0.4, 0.4, 0.8)
    slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    local updating = false
    refreshers[#refreshers + 1] = function()
        updating = true
        local ok, err = pcall(function()
            slider:SetValue(get())
            text:SetText(fmt:format(get()))
        end)
        updating = false
        if not ok then error(err, 0) end
    end
    slider:SetScript("OnValueChanged", function(_, value)
        if not updating then set(math.floor(value / step + 0.5) * step) end
    end)
    slider.label = text
    return slider
end

local function refreshControls()
    if Options.built and panel:IsShown() then
        for _, refresh in ipairs(refreshers) do API.Try("options:refresh", refresh) end
    end
end

function Options.RefreshRunicControls()
    API.Try("options:refresh", refreshControls)
end

-- Every control shows the saved settings again (a radio's click only sets).
function Options.Refresh()
    API.Try("options:refresh", refreshControls)
end

local function buildRunicSettings()
    local enable = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    enable:SetSize(24, 24)
    enable:SetPoint("TOPLEFT", content, "TOPLEFT", 335, -65)
    local title = label(content, "Runic mode", "GameFontNormal")
    title:SetPoint("LEFT", enable, "RIGHT", 4, 0)
    enable:SetScript("OnClick", function(self) GMM.Settings.Set("runicMode", self:GetChecked() == true) end)
    local controls = CreateFrame("Frame", nil, content)
    controls:SetPoint("TOPLEFT", content, "TOPLEFT", 335, -105)
    controls:SetSize(260, 280)
    local styleLabel = label(controls, "Style", "GameFontNormal")
    styleLabel:SetPoint("TOPLEFT", controls, "TOPLEFT", 0, 0)
    local lastStyle, style = radios(styleLabel, {{"etched", "Etched"}, {"glowing", "Glowing"}},
        function() return GMM.db.runeStyle end,
        function(v) GMM.Settings.SetRuneOption("style", v) end, controls)
    local motionLabel = label(controls, "Motion", "GameFontNormal")
    motionLabel:SetPoint("TOPLEFT", controls, "TOPLEFT", 135, 0)
    local _, motion = radios(motionLabel, {{"sway", "Sway"}, {"orbit", "Orbit"}},
        function() return GMM.db.runeMotion end,
        function(v) GMM.Settings.SetRuneOption("motion", v) end, controls)
    local vapor = checkbox(lastStyle, "Exterior vapor",
        function() return GMM.db.runeFog end,
        function(on) GMM.Settings.Set("runeFog", on) end, controls)
    Options._test.intensity = runeSlider("Glow intensity", "runeIntensity", 0, 100, -114, controls)
    Options._test.speed = runeSlider("Orbit speed", "runeSpeed", 25, 200, -174, controls)
    local note = label(controls, "Uses the selected glass theme.\n100% orbit speed: one turn in 30 seconds.", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", controls, "TOPLEFT", 0, -232)
    note:SetWidth(250)
    local status = label(controls, "", "GameFontHighlightSmall")
    status:SetPoint("TOPLEFT", controls, "TOPLEFT", 0, -264)
    status:SetWidth(250)
    status:SetTextColor(1, 0.4, 0.3)
    refreshers[#refreshers + 1] = function()
        enable:SetChecked(GMM.db.runicMode)
        controls:SetShown(GMM.db.runicMode)
        status:SetText(GMM.Ring.RunicError() or "")
    end
    Options._test.runic = { enable = enable, controls = controls, style = style, motion = motion, vapor = vapor, status = status }
end

local function build()
    local title = label(content, "|cff7fd4ffGlass|r MiniMap", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -16)
    local version = label(content, "", "GameFontDisableSmall")
    version:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    refreshers[#refreshers + 1] = function()
        version:SetText("Version " .. GMM.VersionText() .. " for World of Warcraft: Forever, by Spotnick")
    end

    -- The tint and the material. Glass UI's while following, as GlassPanel's
    -- and GUF's are: ours are kept, shown grayed out, and can't be changed
    -- here ("Set in Glass UI" opens its page).
    local look = heading("The glass", version)
    local Suite = GMM.Suite
    local opts = {}
    for _, name in ipairs(GMM.Theme.NAMES) do opts[#opts + 1] = { name, GMM.Theme.LABELS[name] } end
    local last, group = radios(look, opts, function() return GMM.Theme.Own() or "clear" end, GMM.Settings.SetTheme)
    Options._test.themeRadios = group
    local tstatus = label(content, "", "GameFontHighlightSmall")
    tstatus:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -4)
    tstatus:SetWidth(295)
    refreshers[#refreshers + 1] = function()
        for _, rb in ipairs(group) do dim(rb, Suite.LookFollowing()) end
        tstatus:SetText(Suite.TintStatus() or "")
    end
    Options._test.tintStatus = tstatus

    local mlabel = label(content, "Material (applies after /reload):", "GameFontHighlight")
    mlabel:SetPoint("TOPLEFT", tstatus, "BOTTOMLEFT", 0, -10)
    local lastMaterial, materials = radios(mlabel, { { "pearl", "Pearl" }, { "clean", "Clean" } },
        GMM.Settings.Material, function(name)
            if GMM.Settings.SetMaterial(name) then API.Print("material " .. name .. ": applies after /reload") end
            Options.Refresh()
        end)
    local suiteButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    suiteButton:SetSize(120, 22)
    suiteButton:SetText("Set in Glass UI")
    suiteButton:SetPoint("LEFT", materials[1], "RIGHT", 110, 0)
    suiteButton:SetScript("OnClick", function() Suite.Open() end)
    local mstatus = label(content, "", "GameFontHighlightSmall")
    mstatus:SetPoint("TOPLEFT", lastMaterial, "BOTTOMLEFT", 0, -4)
    mstatus:SetWidth(295)
    refreshers[#refreshers + 1] = function()
        local following = Suite.Following()
        for _, rb in ipairs(materials) do dim(rb, following) end
        suiteButton:SetShown(following and Suite.CanOpen())
        mstatus:SetText(Suite.MaterialStatus() or "")
    end
    Options._test.material = { radios = materials, button = suiteButton, status = mstatus }
    buildRunicSettings()

    local map = heading("Around the map", mstatus)
    local c3 = checkbox(map, "Show the day and night disc",
        function() return GMM.db.sun end, function(on) GMM.Settings.Set("sun", on) end)
    local c4 = checkbox(c3, "Glass tracking menu (off: Blizzard's menu)",
        function() return GMM.db.glassTracking end, function(on) GMM.Settings.Set("glassTracking", on) end)
    Options._test.checks = { c3, c4 }
    local where = label(content, "New mail and the instance's size:", "GameFontHighlight")
    where:SetPoint("TOPLEFT", c4, "BOTTOMLEFT", 0, -10)
    local lastWhere, whereGroup = radios(where, {
        { "pills", "In the pills (envelope by the zone, size by the coordinates)" },
        { "ring", "On the ring, as discs" },
    }, GMM.Settings.Indicators, GMM.Settings.SetIndicators)
    Options._test.indicatorRadios = whereGroup
    local zoomWhere = label(content, "Zoom buttons:", "GameFontHighlight")
    zoomWhere:SetPoint("TOPLEFT", lastWhere, "BOTTOMLEFT", 0, -10)
    local lastZoom, zoomGroup = radios(zoomWhere, {
        { "pill", "At the ends of the coordinates pill" },
        { "ring", "On the ring, as discs" },
    }, GMM.Settings.Zoom, GMM.Settings.SetZoom)
    Options._test.zoomRadios = zoomGroup
    local cnote = label(content, "Coordinates: Options > Interface, \"Player Minimap Coordinates\" and "
        .. "\"Coordinates by Tenths\".", "GameFontHighlightSmall")
    cnote:SetPoint("TOPLEFT", lastZoom, "BOTTOMLEFT", 0, -8)
    cnote:SetWidth(295)

    -- Behaviour (#13, #14, #15): each on by default.
    local S = GMM.Settings
    local behaviour = heading("Behaviour", cnote)
    local autoZoom = valueSlider(behaviour, "Zoom back out after %d s (0: never)", 0, 30, 1,
        S.AutoZoomOut, S.SetAutoZoomOut)
    local pingLabel = label(content, "Who pinged the map:", "GameFontHighlight")
    pingLabel:SetPoint("TOPLEFT", autoZoom, "BOTTOMLEFT", 0, -14)
    local lastPing, pingGroup = radios(pingLabel, {
        { "map", "On the map, by the ping" },
        { "chat", "In chat" },
        { "off", "Off" },
    }, S.PingName, S.SetPingName)
    local faderCheck = checkbox(lastPing, "Fade the minimap until the mouse is over it",
        S.Fader, S.SetFader)
    local opacity = valueSlider(faderCheck, "Opacity while faded: %d%%", 20, 100, 5,
        S.FaderOpacity, S.SetFaderOpacity)
    Options._test.behaviour = { autoZoom = autoZoom, ping = pingGroup, fader = faderCheck, opacity = opacity }

    -- The drawer: Glass MiniMap Bar's, when it's installed.
    local drawer = heading("Addon drawer", opacity)
    local note = label(content, "", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", drawer, "BOTTOMLEFT", 0, -6)
    note:SetWidth(295)
    local button = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    button:SetSize(160, 22)
    button:SetText("Drawer options")
    button:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -6)
    button:SetScript("OnClick", function() GMM.Drawer.OpenOptions() end)
    Options._test.drawerButton = button
    refreshers[#refreshers + 1] = function()
        local active = GMM.Drawer.IsActive()
        button:SetShown(active)
        note:SetText(active
            and "The disc at the bottom left of the map opens Glass MiniMap Bar's drawer: your addons' "
                .. "minimap buttons and Blizzard's AddOns list. Its own options:"
            or "Install Glass MiniMap Bar for an addon drawer on the disc at the bottom left of the map.")
    end

    local hint = label(content, "The minimap moves and scales with Edit Mode. Type /gmm help for every command.",
        "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -16)
    hint:SetWidth(295)
    -- The scroll child as tall as what it holds, once laid out.
    refreshers[#refreshers + 1] = function()
        local top, bottom = content:GetTop(), hint:GetBottom()
        if type(top) == "number" and type(bottom) == "number" and top > bottom then
            content:SetHeight(top - bottom + 24)
        end
    end
end

panel:SetScript("OnShow", function()
    if not Options.built then
        Options.built = true
        API.Try("options", build)
    end
    for _, refresh in ipairs(refreshers) do API.Try("options:refresh", refresh) end
end)

-- Called once at PLAYER_LOGIN by GlassMiniMap.lua.
function Options.Register()
    if category then return end
    category = API.RegisterSettingsPanel(panel, panel.name)
end

-- Open the page; false when the Settings framework can't.
function Options.Open()
    local ok = API.OpenSettings(category)
    if not ok then API.Print("Esc > Options > AddOns > Glass MiniMap") end
    return ok
end

Options._test = { panel = panel, scroll = scroll, content = content }
