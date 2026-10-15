-- Live tuning must preserve playback, and controls must reflect saved values.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local paintCount = 0
local vertexColor = WoW.Methods.SetVertexColor
local GMM = loadAddon({ db = { runicMode = true, runeMotion = "orbit" }, before = function()
    WoW.Methods.SetVertexColor = function(texture, ...)
        if texture._file and texture._file:find("ring_runes_moving", 1, true) then paintCount = paintCount + 1 end
        vertexColor(texture, ...)
    end
end })
eq(paintCount, 1, "login constructs and paints runic effects once")
WoW.Methods.SetVertexColor = vertexColor
local _, animation = GMM.Ring._test.runes()
animation._progress = 0.42
local plays, stops = animation._plays, animation._stops
for speed = 105, 200, 5 do
    GMM._test.slash("runes speed " .. speed)
    near(animation:GetAnimationSpeedMultiplier(), speed / 100, "speed changes native clock multiplier")
end
eq(animation._plays, plays, "speed drag never restarts playback")
eq(animation._stops, stops, "speed drag never stops playback")
near(animation:GetProgress(), 0.42, "speed change preserves current progress")
GMM.Options._test.panel:Show()
local slider = GMM.Options._test.intensity
local setValue = slider.SetValue
local refreshCount = 0
slider.SetValue = function(self, value) refreshCount = refreshCount + 1; setValue(self, value) end
WoW.dragSlider(slider, 40)
eq(refreshCount, 2, "drag has one input and one panel refresh")
refreshCount = 0
GMM.Options._test.runic.style[1]:Click("LeftButton")
eq(refreshCount, 1, "radio click refreshes panel once")
refreshCount = 0
GMM.Options._test.runic.vapor:SetChecked(false)
GMM.Options._test.runic.vapor:Click("LeftButton")
eq(refreshCount, 1, "checkbox click refreshes panel once")
GMM._test.slash("runes speed 33")
eq(GMM.db.runeSpeed, 35, "command uses the slider's five-percent steps")
eq(GMM.Options._test.speed._value, 35, "thumb matches saved speed")
check(WoW.chat[#WoW.chat]:find("35%", 1, true), "command reports actual saved speed")
GMM._test.slash("runes intensity 98")
eq(GMM.db.runeIntensity, 100, "intensity rounds to the same steps")
eq(rawget(GlassMiniMapDB, "runeIntensity"), nil, "rounded default is not stored")
GMM.Settings.SetRuneOption("style", "glowing")
local light = GMM.Ring._test.bloom():GetRegions()
GMM.Theme.PRESETS.smoked = { tint = { 0.8, 0.2, 0.1, 0.6 }, wash = 0.4 }
GMM.Settings.SetTheme("smoked")
near(light._vertex[1], 1, "light follows updated theme hue (red)")
near(light._vertex[2], 0.25, "light follows updated theme hue (green)")
near(light._vertex[3], 0.125, "light follows updated theme hue (blue)")
near(light._vertex[4], 0.7 * 0.4, "light follows updated theme wash")

GMM = loadAddon({ db = { runeSpeed = 33, runeIntensity = 98 } })
eq(GMM.db.runeSpeed, 35, "saved off-step speed is normalized")
eq(GMM.db.runeIntensity, 100, "saved off-step intensity is normalized")
eq(rawget(GlassMiniMapDB, "runeIntensity"), nil, "saved rounded default is omitted")

local setTexture = WoW.Methods.SetTexture
WoW.Methods.SetTexture = function(texture, file, ...)
    if type(file) == "string" and file:find("ring_runes", 1, true) then return false end
    return setTexture(texture, file, ...)
end
check(not GMM.Settings.SetRunicMode(true), "missing texture is reported as render failure")
check(GMM.failures["runic mode"]:find("Restart the client", 1, true), "missing texture explains restart requirement")
WoW.Methods.SetTexture = setTexture
GMM.Settings.SetRuneOption("motion", "orbit")
check(GMM.Ring._test.runes():IsVisible(), "later settings update retries missing texture")
done("test_runic_round2")
