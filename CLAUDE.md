# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Glass MiniMap is a **liquid-glass minimap for World of Warcraft: Forever 1.60.1** (Interface
`16001`), written in **Lua 5.1**. It has a single owner (Spotnick) and uses the same stack and
conventions as the sibling Forever addons: `..\GlassMail` (the template for tooling, tests, CI),
`..\GlassPanel` (the clear/smoked/class glass, SystemHider), `..\GlassMiniMapBar` (the drawer,
absorbed here) and `..\PortalRoulette` (glass discs). When this file doesn't cover something,
check how those handle it before you invent a new idiom.

**The look** is `docs/mockups/glass-minimap.png`: a round map in a glass ring with a north tab, a
zone pill above (tracking magnifier, zone name, calendar), a day/night disc top right, the drawer's
launcher disc bottom left, a coordinates pill with zoom below. The reviewed plan (Codex
`gpt-6-astra`, two rounds, consensus) is [docs/PLAN.md](docs/PLAN.md); measured client facts go
in [docs/FOREVER-PROBE.md](docs/FOREVER-PROBE.md).

**Status: v0.1.0 written, not yet run in game.** Offline tests are green; the probe
(`Tools\MinimapProbe`) and the in-game checklist in docs/FOREVER-PROBE.md come next.

## The UI contract (non-negotiable)

**Reskin Blizzard's minimap; never replace or move it.** `MinimapCluster` is an Edit Mode system
and a taint minefield (`..\References\PORTING-TBC-TO-FOREVER.md`, "Edit Mode systems").
- Never reparent, move, `Hide()` or resize `Minimap` / `MinimapCluster`. Edit Mode positions and
  scales them; our frames are children of `MinimapCluster.MinimapContainer` (the frame Edit Mode
  scales) and follow.
- Stock pieces we replace are **faded** (`API.Fade`: alpha 0, mouse off, re-faded from
  `hooksecurefunc` on Show/SetShown/SetAlpha). State in our own weak tables, never a field on
  their frames. The list is `Blizzard.FADED`.
- The only frame that goes entirely is `AddonCompartmentFrame`, through GlassPanel's
  `API.SystemHider` (reparent to a hidden frame, deferred, given back while Edit Mode is open,
  waits for combat), and **only while our drawer is active**.
- Never reassign a Blizzard global or method. `hooksecurefunc` and our own frames only.
- The map's mask stays Blizzard's (round, re-applied by `Camelot\Skin.lua` on `rotateMinimap`).
- Our own frames stay **unnamed** (minimap-button collectors grab named square children of
  `Minimap`), except `GlassMiniMapTrackingPopup` (UIParent child, for `UISpecialFrames`).

## Layout

| File | What |
|---|---|
| `Compat.lua` | `API.*`: failures, events, version, `Fade`, `SystemHider`, `W` (widget methods), `MouseOverMenu`, `GameRule`, `ClassColor`, Settings registration |
| `Glass.lua` | our LibGlass instance (`preset = "clean"`), `GMM.MEDIA` |
| `Theme.lua` | clear / smoked / class; every surface registers (`Theme.Register(g, kind)`), `Theme.Refresh()` repaints live |
| `Blizzard.lua` | fades stock art, hides the compartment (gated), opens Blizzard's tracking menu |
| `Ring.lua` | the ring (one `Glass.Disc` behind the map), the north tab, `Ring.AddDisc`, the day/night disc |
| `Header.lua` | zone pill: magnifier, zone name (PvP colours), calendar |
| `Footer.lua` | coordinates pill, zoom − / + |
| `Tracking.lua` | the glass tracking menu, a copy of Blizzard's menu logic (`Minimap.lua:636-772`) |
| `Drawer\Orb.lua`, `Collector.lua`, `Bar.lua` | Glass MiniMap Bar, absorbed (GPLv3, from HidingBar); `Bar.lua` holds the drawer settings, import, launcher disc |
| `Drawer\Compartment.lua` | Blizzard's AddOns compartment entries as drawer buttons |
| `Options.lua` | Esc > Options > AddOns > Glass MiniMap, sub-page "Addon drawer" |
| `GlassMiniMap.lua` | bootstrap, `GlassMiniMapDB`, `GMM.Settings`, `/gmm` |
| `Tools\make_art.py` | generates every texture in `Media\` (uses ..\LibGlass\Tools primitives) |
| `Tools\MinimapProbe\` | throwaway measuring addon (`/mmprobe`) |

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

- `..\References\PORTING-TBC-TO-FOREVER.md`: Edit Mode systems, options-page recipe, packaging.
- `..\References\forever-api-1.60.1.70374.md`: does an API exist?
- `..\References\RELEASING.md`, `..\References\LIBGLASS-MIGRATION.md`.
- `..\LibGlass\docs\GLASS-MATERIAL.md`: the material, discs, region fields.

## Toolchain and commands

Lua 5.1 at `C:\Program Files (x86)\Lua\5.1\` (`lua.exe`, `luac.exe`). No build step.

```powershell
pwsh tests\run.ps1                                                   # luac -p on the TOC files + probe, then every tests\test_*.lua (needs ..\LibGlass or $env:LIBGLASS)
& 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_boot.lua      # one test, from the repo root
pwsh Tools\deploy.ps1 -Probe                                         # copy the addon (+ MinimapProbe) into AddOns
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
the Forever minimap cluster, `C_Minimap` tracking, the compartment, a fake LibDBIcon),
`tests\harness.lua` (`check`, `eq`, `near`, `loadAddon`), `test_methods.lua` (every method called
exists on this client). **Mutation-test every new test.** Offline tests can't cover taint,
rendering or the live client's data: that's the probe and the in-game checklist.

## Workflow and releasing

- Issue → branch off `main` → PR. Never commit to `main`; commit or push only when asked.
  `luac -p` clean and tests green before committing.
- **The owner merges and closes PRs and launches reviews.**
- **Plans** get an adversarial review before coding: Codex via the `codex-consult` skill,
  `gpt-6-astra` at high effort, looping until consensus, without overengineering.
- Releases: `..\References\RELEASING.md`. CurseForge project **1744024**
  (https://www.curseforge.com/wow/addons/glassminimap) builds from the tag webhook through
  `.pkgmeta`; the `release` job publishes a GitHub Release from the tag's `## vX.Y.Z` section of
  `CHANGELOG.md`.

## Conventions

- Comments explain why, in the siblings' plain style. Name the measured build when a fact was
  measured.
- `GMM.failures` is the one failure record (`API.Fail`, `API.Try`); `/gmm failures` reads it.
- Every setting goes through `GMM.Settings` (or `GMM.Drawer.Set` for the drawer).
- `GlassMiniMapDB` saves only what differs from `DEFAULTS`; `drawer` is always a table.
