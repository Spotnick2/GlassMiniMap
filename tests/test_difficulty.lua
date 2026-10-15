-- The instance disc: Blizzard's instance flag (InstanceDifficulty) faded, a
-- glass disc on the ring at 3 o'clock showing the same group size, mirrored
-- from the flag after each of Blizzard's Updates (#18).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GMM = loadAddon({ db = { indicators = "ring" } })   -- the discs; the pills: test_indicators
local flag = MinimapCluster.InstanceDifficulty
local disc, label = GMM.Difficulty.Disc(), GMM.Difficulty.Label()
local function enter(i) WoW.instance = i; flag:Update() end

check(disc ~= nil, "the disc is built")
eq(flag._alpha, 0, "Blizzard's flag stays faded")

-- On the ring at 90 degrees (3 o'clock).
local p = disc._points[1]
eq(p[2], GMM.Ring.Host(), "anchored to the ring")
check(p[4] > 0, "right of the map's centre")
near(p[5], 0, "level with it (90 degrees)")

-- Open world: no flag, no disc.
eq(disc._shown, false, "outside an instance: no disc")

-- A dungeon: Blizzard writes 5 into Default and shows it.
enter({ type = "party", maxPlayers = 5 })
eq(disc._shown, true, "in a dungeon: the disc shows")
eq(label._text, "5", "...with the group size")

-- Hovered: Blizzard's own tooltip, redrawn when the size changes.
disc._scripts.OnEnter(disc)
eq(GameTooltip._owner, disc, "the tooltip is the disc's")
eq(table.concat(GameTooltip._lines, "|"), "Dungeon|5 Player", "Blizzard's tooltip")
enter({ type = "raid", maxPlayers = 40 })
eq(label._text, "40", "a raid: 40")
eq(table.concat(GameTooltip._lines, "|"), "Raid|40 Player", "the hovered tooltip follows")

-- A size Forever's tooltip has no text for: no empty tooltip box.
disc._scripts.OnLeave(disc)
enter({ type = "raid", maxPlayers = 15 })
eq(label._text, "15", "an odd size still shows")
disc._scripts.OnEnter(disc)
eq(GameTooltip._shown, false, "...but Blizzard's tooltip adds nothing: none shown")
disc._scripts.OnLeave(disc)
enter({ type = "raid", maxPlayers = 40 })
disc._scripts.OnEnter(disc)

-- A guild group: the size moves to the Guild banner; Default keeps its stale
-- text but is hidden, so the disc reads the banner, after Update finished.
enter({ type = "raid", maxPlayers = 20, guild = true })
eq(flag.Default.Text._text, "40", "(Blizzard leaves the old size on the hidden frame)")
eq(label._text, "20", "the guild banner's size, not the stale one")
eq(disc._shown, true, "...still shown")
enter({ type = "party", maxPlayers = 5 })
eq(label._text, "5", "and back to the default flag")

-- Between instances (size 0): Blizzard shows an empty flag; no disc, and the
-- hovered tooltip goes with it.
enter({ type = "party", maxPlayers = 0 })
eq(disc._shown, false, "an empty flag: no disc")
eq(GameTooltip._shown, false, "...and its tooltip is hidden")

-- A secret size reads as none.
local secret = "5"
issecretvalue = function(v) return v == secret end
enter({ type = "party", maxPlayers = 5 })
eq(disc._shown, false, "a secret size: no disc")
issecretvalue = function() return false end
enter({ type = "party", maxPlayers = 5 })
eq(disc._shown, true, "readable again: shown")
disc._scripts.OnLeave(disc)

-- Leaving: hidden. Someone else's tooltip is left alone.
GameTooltip:SetOwner(UIParent); GameTooltip:SetText("theirs"); GameTooltip:Show()
enter({ type = "none", maxPlayers = 0 })
eq(disc._shown, false, "back outside: no disc")
eq(GameTooltip._shown, true, "another frame's tooltip: untouched")
eq(#GMM.failures, 0, "no failures")

-- Already in an instance at login: shown from the start.
GMM = loadAddon({ db = { indicators = "ring" }, before = function()
    WoW.instance = { type = "party", maxPlayers = 5 }
    MinimapCluster.InstanceDifficulty:Update()
end })
eq(GMM.Difficulty.Disc()._shown, true, "in a dungeon at login: shown at once")

done("test_difficulty")
