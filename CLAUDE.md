# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Glass MiniMap is a **liquid-glass minimap for World of Warcraft: Forever 1.60.1** (Interface
`16001`), written in **Lua 5.1**. It has a single owner (Spotnick) and uses the same stack and
conventions as the sibling Forever addons: `..\GlassMail` (the template for tooling, tests, CI),
`..\GlassPanel` (the clear/smoked/class glass), `..\GlassMiniMapBar` (the addon drawer, a separate
addon used through its public API) and `..\PortalRoulette` (glass discs). When this file doesn't cover something,
check how those handle it before you invent a new idiom.

**The look** is `docs/mockups/glass-minimap.png`: a round map in a glass ring with a north tab, a
zone pill above (tracking magnifier, zone name, calendar), a day/night disc top right, the drawer's
launcher disc bottom left (Blizzard's LFG eye, which defaults there too, is mirrored to the top left: `Queue.lua`, #4), a coordinates pill with zoom below. The reviewed plan (Codex
`gpt-6-astra`, two rounds, consensus) is [docs/PLAN.md](docs/PLAN.md), revised by
[docs/PLAN-public-api.md](docs/PLAN-public-api.md) (the drawer stays Glass MiniMap Bar's, also two
rounds to consensus); measured client facts go in [docs/FOREVER-PROBE.md](docs/FOREVER-PROBE.md).

**The drawer** is Glass MiniMap Bar (`## OptionalDeps`). With its `PUBLIC_API_VERSION == 1`
(its `docs/PUBLIC-API.md`), `Drawer.lua` hands it the bottom-left disc as its launcher and passes the
theme on (`SetGlassTint`). Without it there is no disc. Glass MiniMap Bar owns its bar, the button
collection and Blizzard's AddOns compartment; Glass MiniMap never touches `AddonCompartmentFrame`.
The same API is how GlassMaps (the next addon, replacing Leatrix Maps) will integrate.

**Glass UI** (`## OptionalDeps`) is the optional suite orchestrator: its `GlassUI.Suite`, API 1
(its `docs/SUITE.md`, `docs/SUITE-LOOK.md`), spoken by `Suite.lua` as
[docs/PLAN-suite.md](docs/PLAN-suite.md) says (#37). While following: its Pearl material (our
own `material` suspended but kept) and its tint (our `GlassMiniMapDB.look.tint` suspended but
kept too, grayed out on the page like GlassPanel's: the owner, 70450). Asked once, at our `ADDON_LOADED`, so **the LibGlass instance is built there,
never at file scope**: read `GMM.Glass` at build or paint time. Contract questions go to Glass
UI's own session.

**Status: v0.1.0 written (PR #6), first probe run on 70374.** Offline tests are green; the rest of
the in-game checklist in docs/FOREVER-PROBE.md is #2.

## The UI contract (non-negotiable)

**Reskin Blizzard's minimap; never replace or move it.** `MinimapCluster` is an Edit Mode system
and a taint minefield (`..\References\Docs\PORTING-TBC-TO-FOREVER.md`, "Edit Mode systems").
- Never reparent, move, `Hide()` or resize `Minimap` / `MinimapCluster`. Edit Mode positions and
  scales them; our frames are children of `MinimapCluster.MinimapContainer` (the frame Edit Mode
  scales) and follow.
- Stock pieces we replace are **faded** (`API.Fade`: alpha 0, mouse off, re-faded from
  `hooksecurefunc` on Show/SetShown/SetAlpha). State in our own weak tables, never a field on
  their frames. The list is `Blizzard.FADED`.
- `AddonCompartmentFrame` is never ours: Glass MiniMap Bar manages it when installed.
- The one Blizzard frame we move is `QueueStatusButton`, the porting guide's way: only in its
  default position, with `ClearAllPointsBase`/`SetPointBase`, from a deferred hook on
  `UpdateDefaultAnchor`, never with Edit Mode open or (if protected) in combat.
- Never reassign a Blizzard global or method. `hooksecurefunc` and our own frames only.
- Our one Blizzard alpha is `MinimapCluster.MinimapContainer`'s, set by the fader only
  (`Fader.lua`, #15), and put back to 1 when the fader is off. Blizzard never sets or reads it;
  Edit Mode only scales it. Its taint in combat is measured by `/fp steps mm extras`.
- The map's mask stays Blizzard's (round, re-applied by `Camelot\Skin.lua` on `rotateMinimap`).
- Our own frames stay **unnamed** (minimap-button collectors grab named square children of
  `Minimap`), except `GlassMiniMapTrackingPopup` (UIParent child, for `UISpecialFrames`).

## Layout

| File | What |
|---|---|
| `Compat.lua` | `API.*`: failures, events, version, `Fade`, `GameRule`, `ClassColor`, `SetIcon`, Settings registration |
| `Glass.lua` | `GMM.BuildGlass(preset)`: our LibGlass instance (Pearl by default, or clean), built once at `ADDON_LOADED`; `GMM.MEDIA` |
| `Theme.lua` | clear / smoked / class: the tint in effect (`Theme.Name`: Glass UI's while following its look, else the player's own, else clear) and its numbers (Glass UI's `Body` while following); every surface registers (`Theme.Register(g, kind)`), `Theme.Refresh()` repaints live, `Theme.OnChange` listeners |
| `Suite.lua` | Glass UI's suite: the once-per-session decision, the build, `LookChanged`, `Body` without its backing, `Report`, `Open` (all `rawget` + `pcall`) |
| `Blizzard.lua` | fades stock art, opens Blizzard's tracking menu |
| `Ring.lua` | the ring (one `Glass.Disc` behind the map), the north tab, `Ring.AddDisc`, the day/night disc |
| `Header.lua` | zone pill: magnifier, zone name (PvP colours), the new-mail envelope (pills placement), calendar |
| `Footer.lua` | coordinates pill under the ring (the zone pill's gap), Blizzard's coords CVars, or the instance size there (pills placement); zoom − / + at its ends, or discs on the ring (`zoom`) |
| `Queue.lua` | Blizzard's LFG eye (`QueueStatusButton`) mirrored to the top left while in its default position (base methods, deferred, out of Edit Mode and combat), with a glass disc behind it |
| `Mail.lua` | new mail while `HasNewMail()`: the zone pill's envelope, or with `indicators = "ring"` a disc (bottom right, 135°); Blizzard's tooltip; Blizzard's `IndicatorFrame.MailFrame` is faded |
| `Difficulty.lua` | the instance size, mirrored from Blizzard's faded `InstanceDifficulty` after each of its `Update`s (with its own tooltip method): the coords pill's text ("Dungeon · 5"), or with `indicators = "ring"` a disc (right, 90°) |
| `Tracking.lua` | the glass tracking menu, a copy of Blizzard's menu logic (`Minimap.lua:636-772`) |
| `Drawer.lua` | the bottom-left disc as Glass MiniMap Bar's launcher, through its public API |
| `Hover.lua` | is the mouse over the minimap (the ring's circle, our visible pieces), held while our tracking menu or Edit Mode is open: one throttled OnUpdate, no hooks on Blizzard's frames |
| `Fader.lua` | the fader (#15): the container's alpha down to `faderOpacity` until hovered |
| `Options.lua` | Esc > Options > AddOns > Glass MiniMap, in a scroll frame ("Drawer options" opens Glass MiniMap Bar's page) |
| `GlassMiniMap.lua` | bootstrap, `GlassMiniMapDB`, `GMM.Settings`, `/gmm` |
| `Tools\make_art.py` | generates every texture in `Media\` (uses ..\LibGlass\Tools primitives) |
| `Tools\MinimapProbe\` | throwaway measuring addon, a ForeverProbe module (`/fp mm`, procedures `/fp steps mm <name>`) |

## Minimap facts for this client

From `..\wow-ui-source` (branch `forever`, 70338) and the 70374 API dump:
- Forever runs the **Mainline** minimap plus `Camelot\` overrides. Classic names
  (`MiniMapTracking`, `MinimapZoomIn`, `MiniMapBattlefieldFrame`, `MinimapBorder`) don't exist.
- `Minimap` is 198×198 in `MinimapCluster.MinimapContainer`; `MinimapBackdrop` (compass art) is
  a child of `Minimap`.
- Tracking is `C_Minimap.*` with `MinimapConstants` and `MinimapUtil`; Blizzard's menu uses the
  Menu API (`MinimapCluster.Tracking.Button:OpenMenu()`). No `UIDropDownMenu`.
- The compartment: `AddonCompartmentFrame.registeredAddons`; every change ends in `UpdateDisplay`.
- Day/night: `C_DateAndTime.IsDayTime()`, `DIEL_CYCLE_CHANGED`; Blizzard's ring is
  `MinimapCluster.DielFrame`.

## References

- `..\References\Docs\PORTING-TBC-TO-FOREVER.md`: Edit Mode systems, options-page recipe, packaging.
- `..\References\Forever\api\forever-api-1.60.1.70374.md`: does an API exist?
- `..\References\Docs\RELEASING.md`, `..\References\Docs\LIBGLASS-MIGRATION.md`.
- `..\References\Addons\MapMinimap\SexyMap`: a full minimap addon (borders, rotating ring textures, HUD, button
  handling). "All Rights Reserved": ideas only, never its code.
- `..\LibGlass\docs\GLASS-MATERIAL.md`: the material, discs, region fields.

## Toolchain and commands

Lua 5.1 at `C:\Program Files (x86)\Lua\5.1\` (`lua.exe`, `luac.exe`). No build step.

```powershell
pwsh tests\run.ps1                                                   # luac -p on the TOC files + probe, then every tests\test_*.lua (needs ..\LibGlass or $env:LIBGLASS)
& 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_boot.lua      # one test, from the repo root
pwsh Tools\deploy.ps1 -Probe                                         # copy the addon (+ ForeverProbe, MinimapProbe) into AddOns
python Tools\make_art.py                                             # regenerate Media\*.tga
```

- Default AddOns path: `C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns`.
- In game: `/console scriptErrors 1`, then `/reload`. A new addon folder with new textures needs a
  client restart.
- **Shell heredocs here collapse `\\` to `\`**: write files that contain Lua backslash escapes or
  Windows paths with the Write/Edit tools.

## Testing

Glass MiniMap Bar's harness, extended: `tests\wow_stubs.lua` (strict globals as an allowlist of
APIs verified in the dump, event names validated against the dump, every widget method recorded,
the Forever minimap cluster, `C_Minimap` tracking, a fake Glass MiniMap Bar public API),
`tests\harness.lua` (`check`, `eq`, `near`, `loadAddon`, `loadForeverProbe`, `loadProbe`),
`test_methods.lua` (every method called exists on this client), `test_probe.lua` (MinimapProbe on
`..\ForeverProbe`: local only, CI skips it with `FOREVERPROBE_OPTIONAL=1` because the host is
private). **Mutation-test every new test.** Offline tests can't cover taint, rendering or the live
client's data: that's the probe's procedures and the in-game checklist.

## Workflow and releasing

- Issue → branch off `main` → PR. Never commit to `main`; commit or push only when asked.
  `luac -p` clean and tests green before committing.
- **The owner merges and closes PRs and launches reviews.**
- **Plans** get an adversarial review before coding: Codex via the `codex-consult` skill,
  `gpt-6-astra` at high effort, looping until consensus, without overengineering.
- Releases: `..\References\Docs\RELEASING.md`. A tag publishes three ways (#34):
  - CurseForge project **1744024** (https://www.curseforge.com/wow/addons/glassminimap) builds
    from the tag webhook through `.pkgmeta`;
  - the `release` job publishes `check`'s zip as a GitHub Release, with `release.json` and the
    tag's `## vX.Y.Z` section of `CHANGELOG.md` as the notes;
  - the `wago` job uploads the same zip to Wago Addons project **5NRgYe63**
    (https://addons.wago.io/addons/5NRgYe63; `## X-Wago-ID`, the `WAGO_API_TOKEN` secret).
  An alpha tag (`vX.Y.Z-alpha1`) is a pre-release on GitHub and alpha on CurseForge and Wago, and
  falls back to the `## vX.Y.Z` section, then `## Unreleased`. A failed target is published
  again from Actions > Package check > Run workflow (from `main`: `tag`, `publish`).

## Conventions

- Comments explain why, in the siblings' plain style. Name the measured build when a fact was
  measured.
- `GMM.failures` is the one failure record (`API.Fail`, `API.Try`); `/gmm failures` reads it.
- Every setting goes through `GMM.Settings` (or `GMM.Drawer.Set` for the drawer).
- `GlassMiniMapDB` saves only what differs from `DEFAULTS`; `drawer` is always a table.
