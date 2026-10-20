-- Optional rendering must not interrupt core startup or saved preferences.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local setOrder = WoW.Methods.SetOrder
local function failRotation(a, value)
    if a._type == "Rotation" then error("injected rune animation failure", 0) end
    return setOrder(a, value)
end

local GMM = loadAddon({ gmb = true, before = function() WoW.Methods.SetOrder = failRotation end })
eq(GMM.Ring._test.runes(), nil, "disabled startup builds no runic frames")
eq(next(GMM.failures), nil, "disabled startup never reaches optional animation")
check(GMM.Header._test.zoneButton() and GMM.Footer.Pill() and GMM.Ring.Sun(), "core pieces are built")

GMM = loadAddon({ db = { runicMode = true }, gmb = true })
check(GMM.failures["runic mode"] ~= nil, "optional animation error recorded")
check(GMM.Ring._test.notch() and GMM.Ring.Sun(), "north tab and sun survive rune failure")
check(GMM.Header._test.zoneButton() and GMM.Footer.Pill(), "pills survive rune failure")
check(GMM.Queue.Disc() and GMM.Tracking._test.popup(), "queue and tracking survive rune failure")
check(GlassMiniMapBar.launcher ~= nil, "drawer survives rune failure")
local root = GMM.Ring._test.runes()
check(root and not root:IsShown(), "partial render stays hidden")
GMM.Options._test.panel:Show()
local frameCount, groupCount = #WoW.frames, #WoW.animGroups
local function subresourceCount()
    local textures, animations = 0, 0
    for _, frame in ipairs(WoW.frames) do textures = textures + #frame._regions end
    for _, group in ipairs(WoW.animGroups) do animations = animations + #group._animations end
    return textures, animations
end
local textureCount, animationCount = subresourceCount()
for _ = 1, 3 do
    check(not GMM.Settings.SetRunicMode(true), "failed enable reports rendering failure")
    eq(GMM.Ring._test.runes(), root, "failed retry reuses root")
end
eq(#WoW.frames, frameCount, "failed retries allocate no additional frames")
eq(#WoW.animGroups, groupCount, "failed retries allocate no additional animation groups")
local textures, animations = subresourceCount()
eq(textures, textureCount, "failed retries allocate no additional textures")
eq(animations, animationCount, "failed retries allocate no additional animations")
GMM._test.slash("runes on")
check(WoW.chat[#WoW.chat]:find("unavailable", 1, true), "failed command explains unavailable rendering")
check(GMM.Options._test.runic.status._text:find("unavailable", 1, true), "settings display rendering failure")
check(GMM.Options._test.runic.style[2]:GetChecked(), "UI reads glowing default despite render failure")
check(GMM.Options._test.runic.vapor:GetChecked(), "UI reads vapor default despite render failure")
check(GMM.Settings.SetRuneOption("style", "etched"), "style accepted after render failure")
eq(GlassMiniMapDB.runeStyle, "etched", "choice saved independently of render")
check(GMM.Options._test.runic.style[1]:GetChecked(), "UI shows saved choice after render failure")
WoW.Methods.SetOrder = setOrder
GMM.Settings.SetTheme("smoked")
local readyRoot, animation = GMM.Ring._test.runes()
check(readyRoot:IsVisible() and animation:IsPlaying(), "theme update retries rendering after recovery")
eq(readyRoot, root, "recovery keeps the existing root")
eq(GMM.Options._test.runic.status._text, "", "recovery clears visible failure")

-- A fully built stack also stays allocated once across runtime errors/retries.
local _, _, moving = GMM.Ring._test.runes()
frameCount, groupCount = #WoW.frames, #WoW.animGroups
textureCount, animationCount = subresourceCount()
local vertexColor = moving.core.SetVertexColor
moving.core.SetVertexColor = function() error("injected runtime paint failure", 0) end
GMM.Settings.SetRuneOption("motion", "orbit")
for _ = 1, 3 do GMM.Settings.SetRunicMode(true) end
eq(#WoW.frames, frameCount, "runtime retries allocate no additional frames")
eq(#WoW.animGroups, groupCount, "runtime retries allocate no additional animations")
textures, animations = subresourceCount()
eq(textures, textureCount, "runtime retries reuse textures")
eq(animations, animationCount, "runtime retries reuse animation objects")
moving.core.SetVertexColor = vertexColor
GMM.Settings.SetRuneOption("style", "glowing")
check(readyRoot:IsVisible() and animation:IsPlaying(), "style update recovers without mode toggle")

-- A core ring failure also leaves the settings page and choices usable.
GMM = loadAddon({ before = function()
    GlassMiniMap.Ring.Build = function() error("injected core ring failure", 0) end
end })
check(GMM.Settings.SetRuneOption("motion", "orbit"), "choice accepted when core ring is unavailable")
eq(GMM.db.runeMotion, "orbit", "motion saved without ring")
GMM.Options._test.panel:Show()
check(not GMM.Settings.SetRunicMode(true), "missing core ring reports unavailable effects")
check(GMM.Options._test.runic.motion[2]:GetChecked(), "UI reads saved motion without ring")

-- A control-refresh error is contained and does not leave the slider's
-- callback guard stuck, so later real drags still update settings.
GMM = loadAddon({ db = { runicMode = true } })
GMM.Options._test.panel:Show()
local slider = GMM.Options._test.intensity
local valueMethod = slider.SetValue
local failRefresh = true
slider.SetValue = function(self, value)
    if failRefresh then error("injected control refresh failure", 0) end
    valueMethod(self, value)
end
check(pcall(GMM.Settings.SetTheme, "smoked"), "theme command contains control refresh error")
check(GMM.failures["options:refresh"] ~= nil, "control error recorded")
eq(GMM.Theme.Name(), "smoked", "theme remains saved after UI failure")
check(pcall(GMM.Settings.SetRunicMode, false), "mode toggle contains control error")
check(not GMM.Options._test.runic.controls:IsShown(), "other controls refresh after one fails")
GMM.Settings.SetRunicMode(true)
failRefresh = false
WoW.dragSlider(slider, 45)
eq(GMM.db.runeIntensity, 45, "drag works after failed refresh")
check(GMM.Options._test.speed:IsMouseEnabled(), "speed slider accepts mouse input")
done("test_runic_failures")
