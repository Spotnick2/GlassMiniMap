-- Compartment.lua: Blizzard's "AddOns" compartment, as buttons in the drawer.
--
-- The compartment (Blizzard_Minimap\Mainline\AddonCompartment.lua) is a list,
-- AddonCompartmentFrame.registeredAddons, of { text, icon, func, funcOnEnter,
-- funcOnLeave }: one per addon whose TOC names an AddonCompartmentFunc (filled
-- in bulk by RegisterAddons at PLAYER_ENTERING_WORLD), plus any added by
-- RegisterAddon at runtime (LibDBIcon's AddButtonToCompartment among them).
-- Every path that changes the list ends in UpdateDisplay (RegisterAddons,
-- RegisterAddon, and LibDBIcon's RemoveButtonFromCompartment, which removes
-- its entry directly), so a hook there, reconciled on the next frame, sees
-- all of them. Opening the drawer reconciles too, as a backstop.
--
-- Each entry becomes an orb of ours in the drawer. Its click calls the
-- entry's own func the way the two known callers expect:
--   func(nil, { buttonName = mouse }, ourButton)
-- Blizzard's TOC wrapper reads only buttonName (it loads a demand-loaded
-- addon and calls its global); LibDBIcon's passes the third argument to the
-- broker's OnClick as the frame to anchor to. Nothing beyond those two is
-- promised: another custom entry gets the same call, as best effort.
--
-- Duplicates: a LibDBIcon button that also put itself in the compartment is
-- the same addon twice. When its minimap button is in the drawer (collected
-- and shown by its addon), the compartment copy is left out: known identity
-- first (the button's own compartmentData IS the entry), then an exact title
-- match, only when exactly one drawer button has that name. A compartment
-- entry is kept whenever its minimap button isn't in the drawer.

GlassMiniMap = GlassMiniMap or {}
local GMM = GlassMiniMap
local API = GMM.API
local Collector = GMM.Collector
local Compartment = {}
GMM.Compartment = Compartment

Compartment.PREFIX = "AddOns:"   -- entry names in the hidden/order lists
Compartment.SIZE = 31            -- a LibDBIcon button's size: the drawer scales every button alike

local byData = setmetatable({}, { __mode = "k" })   -- entry data -> entry name
local pool = {}                                     -- spare buttons
local scheduled = false

local function frame() return rawget(_G, "AddonCompartmentFrame") end

-- "|cff7fd4ffGlass|r Mail" -> "Glass Mail".
function Compartment.CleanText(s)
    if type(s) ~= "string" then return nil end
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", "")
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    return s ~= "" and s or nil
end

local function norm(s)
    return (s or ""):lower():gsub("[^%w]", "")
end

-- The compartment's list as it stands (plain tables only).
function Compartment.List()
    local f = frame()
    local list = f and rawget(f, "registeredAddons")
    if type(list) ~= "table" then return {} end
    local out = {}
    for _, data in ipairs(list) do
        if type(data) == "table" then out[#out + 1] = data end
    end
    return out
end

-- The compartment entries that already have their minimap button in the
-- drawer: { [data] = true }.
local function duplicates(list)
    local dup = {}
    local lib = LibStub and LibStub("LibDBIcon-1.0", true)
    if lib and type(lib.objects) == "table" then
        for _, btn in pairs(lib.objects) do
            local data = type(btn) == "table" and rawget(btn, "compartmentData")
            local name = data and API.W.GetName(btn)
            local e = name and Collector.byName[name]
            if e and e.wanted and not e.own then dup[data] = true end
        end
    end
    -- Exact titles, unambiguous only: one shown minimap button with that name.
    local count, which = {}, {}
    for _, e in ipairs(Collector.entries) do
        if not e.own and e.wanted then
            local k = norm(e.display)
            count[k] = (count[k] or 0) + 1
            which[k] = e
        end
    end
    for _, data in ipairs(list) do
        if not dup[data] then
            local k = norm(Compartment.CleanText(data.text))
            if k ~= "" and count[k] == 1 then dup[data] = true end
        end
    end
    return dup
end

--------------------------------------------------------------------------------
-- Our buttons
--------------------------------------------------------------------------------

local function onClick(self, mouse)
    local data = self.compartmentData
    if not data then return end
    GameTooltip:Hide()
    if type(data.func) == "function" then
        API.Try("compartment:" .. tostring(self.entryName), data.func, nil, { buttonName = mouse }, self)
    end
    local e = Collector.byName[self.entryName]
    if e then API.Try("click", Collector.onClick, e, mouse) end
end

local function onEnter(self)
    local data = self.compartmentData
    if not data then return end
    if type(data.funcOnEnter) == "function" then
        API.Try("compartment:enter", data.funcOnEnter, self)
    else
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(Compartment.CleanText(data.text) or "?")
        GameTooltip:Show()
    end
end

local function onLeave(self)
    local data = self.compartmentData
    if data and type(data.funcOnLeave) == "function" then
        API.Try("compartment:leave", data.funcOnLeave, self)
    else
        GameTooltip:Hide()
    end
end

-- A button shaped like a LibDBIcon one (border, background, icon), so the
-- orb skin and the drawer's layout treat it like every other button.
local function newButton()
    local b = table.remove(pool)
    if b then return b end
    b = CreateFrame("Button", nil, Collector.host)
    b:SetSize(Compartment.SIZE, Compartment.SIZE)
    b:RegisterForClicks("AnyUp")
    b.background = b:CreateTexture(nil, "BACKGROUND")
    b.background:SetTexture(136467)                -- Interface\Minimap\UI-Minimap-Background
    b.background:SetSize(24, 24)
    b.background:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(18, 18)
    b.icon:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.border = b:CreateTexture(nil, "OVERLAY")
    b.border:SetTexture(136430)                    -- Interface\Minimap\MiniMap-TrackingBorder
    b.border:SetSize(50, 50)
    b.border:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    b:SetHighlightTexture(136477)                  -- Interface\Minimap\UI-Minimap-ZoomButton-Highlight
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", onEnter)
    b:SetScript("OnLeave", onLeave)
    return b
end

local function uniqueName(text)
    local base = Compartment.PREFIX .. (Compartment.CleanText(text) or "?")
    local name, n = base, 1
    while Collector.byName[name] do
        n = n + 1
        name = base .. " (" .. n .. ")"
    end
    return name
end

local function add(data)
    local b = newButton()
    b.compartmentData = data
    if data.icon then
        API.SetIcon(b.icon, data.icon)
    else
        b.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end
    local name = uniqueName(data.text)
    b.entryName = name
    if Collector.AddOwn(b, name, Compartment.CleanText(data.text) or "?") then
        byData[data] = name
    else
        b.compartmentData = nil
        pool[#pool + 1] = b
    end
end

local function remove(data)
    local name = byData[data]
    byData[data] = nil
    local e = name and Collector.byName[name]
    if e and Collector.RemoveOwn(name) then
        e.btn.compartmentData = nil
        pool[#pool + 1] = e.btn
    end
end

-- Make the drawer's compartment buttons match the compartment. Returns
-- whether anything changed.
function Compartment.Sync()
    scheduled = false
    if not Collector.host then return false end
    local list = Compartment.List()
    local dup = duplicates(list)
    local want, changed = {}, false
    for _, data in ipairs(list) do
        if not dup[data] then
            want[data] = true
            if not byData[data] then add(data); changed = true end
        end
    end
    local gone = {}
    for data in pairs(byData) do
        if not want[data] then gone[#gone + 1] = data end
    end
    for _, data in ipairs(gone) do remove(data); changed = true end
    if changed then Collector.Changed() end
    return changed
end

function Compartment.Request()
    if scheduled then return end
    scheduled = true
    C_Timer.After(0, function() API.Try("compartment:sync", Compartment.Sync) end)
end

-- Called once at login, after the drawer's frame exists.
function Compartment.Start()
    local f = frame()
    if not f then return false end
    if type(f.UpdateDisplay) == "function" then
        hooksecurefunc(f, "UpdateDisplay", function() Compartment.Request() end)
    end
    Compartment.Request()
    return true
end

Compartment._test = { byData = byData, pool = pool, duplicates = duplicates }
