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
    return rb
end

-- An on/off setting under `anchor`.
local function checkbox(anchor, text, get, set)
    local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
    local fs = label(panel, text)
    fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    local function sync() cb:SetChecked(get() == true) end
    cb:SetScript("OnClick", function() set(cb:GetChecked() == true); sync() end)
    refreshers[#refreshers + 1] = sync
    return cb
end

-- Mutually exclusive choices stacked under `anchor`: { {value, text}, ... }.
local function radios(anchor, options, get, set)
    local group = {}
    local function sync()
        local current = get()
        for _, rb in ipairs(group) do rb:SetChecked(rb.value == current) end
    end
    local prev = anchor
    for _, o in ipairs(options) do
        local rb = radioButton(panel, o[2])
        rb.value = o[1]
        rb:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, prev == anchor and -8 or -4)
        rb:SetScript("OnClick", function() set(o[1]); sync() end)
        group[#group + 1] = rb
        prev = rb
    end
    refreshers[#refreshers + 1] = sync
    return prev, group
end

local function heading(text, anchor, y)
    local fs = label(panel, text, "GameFontNormal")
    fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, y or -16)
    return fs
end

local function build()
    local title = label(panel, "|cff7fd4ffGlass|r MiniMap", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
    local version = label(panel, "", "GameFontDisableSmall")
    version:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    refreshers[#refreshers + 1] = function()
        version:SetText("Version " .. GMM.VersionText() .. " for World of Warcraft: Forever, by Spotnick")
    end

    local look = heading("The glass", version)
    local opts = {}
    for _, name in ipairs(GMM.Theme.NAMES) do opts[#opts + 1] = { name, GMM.Theme.LABELS[name] } end
    local last, group = radios(look, opts, function() return GMM.db.theme end, GMM.Settings.SetTheme)
    Options._test.themeRadios = group

    local map = heading("Around the map", last)
    local c3 = checkbox(map, "Show the day and night disc",
        function() return GMM.db.sun end, function(on) GMM.Settings.Set("sun", on) end)
    local c4 = checkbox(c3, "Glass tracking menu (off: Blizzard's menu)",
        function() return GMM.db.glassTracking end, function(on) GMM.Settings.Set("glassTracking", on) end)
    Options._test.checks = { c3, c4 }
    local cnote = label(panel, "Coordinates: Options > Interface, \"Player Minimap Coordinates\" and "
        .. "\"Coordinates by Tenths\".", "GameFontHighlightSmall")
    cnote:SetPoint("TOPLEFT", c4, "BOTTOMLEFT", 0, -8)

    -- The drawer: Glass MiniMap Bar's, when it's installed.
    local drawer = heading("Addon drawer", cnote)
    local note = label(panel, "", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", drawer, "BOTTOMLEFT", 0, -6)
    note:SetWidth(560)
    local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    button:SetSize(160, 22)
    button:SetText("Drawer options")
    button:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -6)
    button:SetScript("OnClick", function() GMM.Drawer.OpenOptions() end)
    Options._test.drawerButton = button
    refreshers[#refreshers + 1] = function()
        local active = GMM.Drawer.IsActive()
        button:SetShown(active)
        note:SetText(active
            and "The disc at the bottom right of the map opens Glass MiniMap Bar's drawer: your addons' "
                .. "minimap buttons and Blizzard's AddOns list. Its own options:"
            or "Install Glass MiniMap Bar for an addon drawer on the disc at the bottom right of the map.")
    end

    local hint = label(panel, "The minimap moves and scales with Edit Mode. Type /gmm help for every command.",
        "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -16)
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

Options._test = { panel = panel }
