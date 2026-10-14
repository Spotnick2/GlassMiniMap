-- Drawer.lua: the addon drawer is Glass MiniMap Bar's bar, opened from our
-- bottom-left disc.
--
-- Glass MiniMap Bar (a separate addon, ## OptionalDeps) collects the addons'
-- minimap buttons and Blizzard's AddOns list into one glass bar. Through its
-- public API (its docs/PUBLIC-API.md, version 1) the bar opens from our disc
-- instead of its own minimap button, and its glass follows our theme. Without
-- it, or with an API version we don't know, there is no disc and nothing else
-- changes (Blizzard's AddOns button included: we never touch it).

GlassMiniMap = GlassMiniMap or {}
local GMM = GlassMiniMap
local API = GMM.API
local Drawer = {}
GMM.Drawer = Drawer

-- The disc's place on the ring (degrees clockwise from the top): the bottom
-- right. The mockup's bottom left is where Blizzard's LFG eye sits while
-- queued (Queue.lua, issue #4).
Drawer.ANGLE = 135
Drawer.API_VERSION = 1              -- Glass MiniMap Bar's PUBLIC_API_VERSION we speak
Drawer.ARROW = "Interface\\Icons\\misc_arrowleft"
local CROP = { 0.08, 0.92, 0.08, 0.92 }   -- Interface\Icons squares, inside the round mask

local disc

-- Glass MiniMap Bar's API, or nil (not loaded, or a version we don't speak).
function Drawer.Bar()
    local gmb = rawget(_G, "GlassMiniMapBar")
    if type(gmb) ~= "table" or gmb.PUBLIC_API_VERSION ~= Drawer.API_VERSION then return nil end
    if type(gmb.UseLauncher) ~= "function" then return nil end
    return gmb
end

-- The bar tells us its launcher's face: the last button used, or its arrow.
local function setIcon(icon, coords)
    if not disc then return end
    API.SetIcon(disc.icon, icon)
    local c = (type(coords) == "table" and #coords >= 4) and coords or CROP
    disc.icon:SetTexCoord(c[1], c[2], c[3], c[4])
end

-- Our theme, on the bar's glass: tint nil is the look as built.
local function pushTint(tint, wash)
    local gmb = Drawer.Bar()
    if not (gmb and gmb.SetGlassTint) then return end
    if tint then
        gmb.SetGlassTint(tint[1], tint[2], tint[3], tint[4], wash)
    elseif wash ~= 1 then
        local base = GMM.Glass.STYLE.tint
        gmb.SetGlassTint(base[1], base[2], base[3], nil, wash)
    else
        gmb.SetGlassTint()
    end
end

local function call(name, ...)
    local gmb = Drawer.Bar()
    if gmb and type(gmb[name]) == "function" then API.Try("drawer:" .. name, gmb[name], ...) end
end

-- At PLAYER_LOGIN, after the ring. Returns whether the drawer is there.
function Drawer.Start()
    local gmb = Drawer.Bar()
    if not gmb then
        local other = rawget(_G, "GlassMiniMapBar")
        if type(other) == "table" then
            API.Fail("drawer", "Glass MiniMap Bar's API version " .. tostring(other.PUBLIC_API_VERSION)
                .. " (this Glass MiniMap speaks " .. Drawer.API_VERSION .. "): update both")
        end
        return false
    end
    disc = GMM.Ring.AddDisc(Drawer.ANGLE, { icon = Drawer.ARROW, iconCrop = true })
    disc:SetScript("OnClick", function(self, mouse) call("LauncherClick", self, mouse) end)
    disc:SetScript("OnEnter", function(self) call("LauncherEnter", self) end)
    disc:SetScript("OnLeave", function(self) call("LauncherLeave", self) end)
    local ok, why = gmb.UseLauncher(disc, { setIcon = setIcon })
    if not ok then
        API.Fail("drawer", why or "UseLauncher refused")
        disc:Hide()
        return false
    end
    GMM.Theme.OnChange(pushTint)
    return true
end

function Drawer.IsActive() return disc ~= nil and disc:IsShown() end
function Drawer.Disc() return disc end

-- Glass MiniMap Bar's options page (the options page's "Drawer options").
function Drawer.OpenOptions()
    local gmb = Drawer.Bar()
    if gmb and type(gmb.OpenOptions) == "function" then
        API.Try("drawer:OpenOptions", gmb.OpenOptions)
        return true
    end
    return false
end
