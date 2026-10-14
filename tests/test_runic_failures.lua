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
check(GMM.Options._test.runic.style[2]:GetChecked(), "UI reads glowing default despite render failure")
check(GMM.Options._test.runic.vapor:GetChecked(), "UI reads vapor default despite render failure")
check(GMM.Settings.SetRuneOption("style", "etched"), "style accepted after render failure")
eq(GlassMiniMapDB.runeStyle, "etched", "choice saved independently of render")
check(GMM.Options._test.runic.style[1]:GetChecked(), "UI shows saved choice after render failure")
WoW.Methods.SetOrder = setOrder
GMM.Settings.SetRunicMode(false)
GMM.Settings.SetRunicMode(true)
local readyRoot, animation = GMM.Ring._test.runes()
check(readyRoot:IsVisible() and animation:IsPlaying(), "toggle retries rendering after recovery")

-- A core ring failure also leaves the settings page and choices usable.
GMM = loadAddon({ before = function()
    GlassMiniMap.Ring.Build = function() error("injected core ring failure", 0) end
end })
check(GMM.Settings.SetRuneOption("motion", "orbit"), "choice accepted when core ring is unavailable")
eq(GMM.db.runeMotion, "orbit", "motion saved without ring")
GMM.Options._test.panel:Show()
GMM.Settings.SetRunicMode(true)
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
eq(GMM.db.theme, "smoked", "theme remains saved after UI failure")
check(pcall(GMM.Settings.SetRunicMode, false), "mode toggle contains control error")
check(not GMM.Options._test.runic.controls:IsShown(), "other controls refresh after one fails")
GMM.Settings.SetRunicMode(true)
failRefresh = false
WoW.dragSlider(slider, 45)
eq(GMM.db.runeIntensity, 45, "drag works after failed refresh")
check(GMM.Options._test.speed:IsMouseEnabled(), "speed slider accepts mouse input")
done("test_runic_failures")
