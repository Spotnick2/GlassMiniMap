-- Glass.lua: this addon's instance of the "liquid glass" material.
--
-- The material lives in the embedded library LibGlass-1.0
-- (Libs\LibGlass-1.0, from github.com/Spotnick2/LibGlass through .pkgmeta
-- externals; the TOC loads it first). Material changes are LibGlass PRs, not
-- edits here.
--
-- An instance, not the library itself: its tuning and font registry are
-- Glass MiniMap's own and never touch another glass addon's surfaces. Two
-- materials: Pearl (r11; the clean material with a softer wash, gloss and
-- frost, Glass UI's suite theme) and clean (r6: thin rectangular rims, no
-- grain). The instance is built once, at ADDON_LOADED, after Suite.lua has
-- asked Glass UI which one (#37): nothing may read GMM.Glass at file scope.
-- The body's tint is Theme.lua's (clear / smoked / class), repainted live.
-- Glass.MEDIA is the library's folder; our own textures are GlassMiniMap.MEDIA.

local ADDON = ...
GlassMiniMap = GlassMiniMap or {}
local GMM = GlassMiniMap
GMM.MEDIA = "Interface\\AddOns\\" .. (ADDON or "GlassMiniMap") .. "\\Media\\"
GMM.PEARL_MINOR = 11
GMM.MATERIALS = { pearl = true, clean = true }

-- Build the instance with `preset`, once. Returns true, or false and why:
-- "library-too-old" (the LibGlass that won LibStub predates Pearl) or
-- "build-failed" (New errored). After a failure the instance is the clean
-- material. GMM.GlassPreset is what was built, GMM.GlassMinor the library's
-- MINOR at the attempt.
function GMM.BuildGlass(preset)
    if GMM.Glass then return true end
    local lib, minor = LibStub("LibGlass-1.0")
    GMM.GlassMinor = minor
    local why
    if preset == "pearl" and (type(minor) ~= "number" or minor < GMM.PEARL_MINOR) then
        why = "library-too-old"
    else
        local ok, made = pcall(lib.New, lib, { preset = preset })
        if ok and made then
            GMM.Glass, GMM.GlassPreset = made, preset
            return true
        end
        why = "build-failed"
    end
    GMM.Glass, GMM.GlassPreset = lib:New({ preset = "clean" }), "clean"
    return false, why
end
