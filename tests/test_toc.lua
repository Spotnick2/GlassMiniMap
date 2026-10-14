-- The manifest, the pinned build, and the media the addon names.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local toc = io.open("GlassMiniMap.toc"):read("*a")
check(toc:find("## Interface: 16001", 1, true), "interface 16001 (1.60.1; 11601 is the transposed-digit bug)")
check(toc:find("## Version: @project-version@", 1, true), "packager version token kept")
check(toc:find("## SavedVariables: GlassMiniMapDB", 1, true), "saved variables declared")
check(toc:find("## X-Curse-Project-ID: 1744024", 1, true), "CurseForge project ID (1744024)")
check(toc:find("## X-License: GPL-3.0", 1, true), "GPLv3 (the drawer is HidingBar-derived)")
check(not toc:find("AddonCompartmentFunc", 1, true), "no compartment entry of our own (the drawer replaces the compartment)")
for _, f in ipairs(tocFiles()) do
    check(io.open(f, "r") ~= nil, "TOC file exists: " .. f)
end
eq(tocLines()[1], LIBGLASS_XML, "LibGlass-1.0 loads first")
eq(tocFiles()[1], "Compat.lua", "Compat is the first addon file")
eq(tocFiles()[#tocFiles()], "GlassMiniMap.lua", "bootstrap loads last")
-- The packager replaces its tokens in EVERY file: never write one whole in Lua.
for _, f in ipairs(tocFiles()) do
    local src = io.open(f, "rb"):read("*a")
    local token = src:match("@project%-[%w-]+@") or src:match("@file%-[%w-]+@")
    check(not token, f .. " holds no packager token (found " .. tostring(token) .. ")")
end
local seen = {}
for _, f in ipairs(tocFiles()) do
    check(not seen[f], "TOC lists each file once: " .. f)
    seen[f] = true
end

local GMM = loadAddon()
eq(GMM.MEASURED_ON_BUILD, "1.60.1.70374", "MEASURED_ON_BUILD")

-- Every texture the library names ships with it; ours are in Media/.
local root = libGlassRoot()
for size, S in pairs(GMM.Glass.SIZES) do
    for _, key in ipairs({ "mask", "rim", "dark", "shadow" }) do
        local f = root .. "/Media/" .. S[key] .. ".tga"
        check(io.open(f, "rb") ~= nil, size .. " texture exists: " .. f)
    end
end
local OURS = { "orb_mask", "orb_rim", "orb_dark", "orb_shadow", "ring_rim", "ring_dark", "notch_mask",
               "notch_rim", "sun", "moon", "magnifier" }
for _, t in ipairs(OURS) do
    check(io.open("Media/" .. t .. ".tga", "rb") ~= nil, "our texture exists: " .. t)
end
-- Every texture of ours the code names is one of those.
local named = {}
for _, f in ipairs(tocFiles()) do
    local src = io.open(f, "rb"):read("*a")
    for t in src:gmatch('MEDIA %.%. %(?"([%w_]+)"') do named[t] = true end
    for a, b in src:gmatch('MEDIA %.%. %(isDay and "([%w_]+)" or "([%w_]+)"%)') do named[a], named[b] = true, true end
end
local known = {}
for _, t in ipairs(OURS) do known[t] = true end
for t in pairs(named) do check(known[t], "named texture is shipped: " .. t) end
check(next(named) ~= nil, "found the textures the code names")
-- Media/ holds our own art only.
for _, t in ipairs({ "grain", "rim5", "body_mask", "disc_mask" }) do
    check(io.open("Media/" .. t .. ".tga", "rb") == nil, "no copy of the library's " .. t .. " in Media/")
end
eq(GMM.Glass.MEDIA, "Interface\\AddOns\\GlassMiniMap\\Libs\\LibGlass-1.0\\Media\\", "Glass.MEDIA is the embedded copy's")
eq(GMM.MEDIA, "Interface\\AddOns\\GlassMiniMap\\Media\\", "our Media folder")
eq(GMM.Orb.MEDIA, GMM.MEDIA, "the orb draws from our Media")
check(GMM.Glass ~= LibStub("LibGlass-1.0"), "Glass is our own instance, not the library")

-- The dev-build notice: a deployed dev copy on another build says so once at login.
WoW.build, WoW.version = "70400", "dev"
loadAddon()
check(table.concat(WoW.chat, "\n"):find("differs from the one this addon was measured on", 1, true), "dev copy warns")
WoW.build, WoW.version = "70400", "v0.1.0"
loadAddon()
check(not table.concat(WoW.chat, "\n"):find("differs", 1, true), "a release keeps quiet")
WoW.build = "70374"

done("test_toc")
