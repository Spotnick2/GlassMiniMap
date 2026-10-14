# GlassMiniMap — implementation plan

> **Revised:** the drawer is no longer absorbed. Glass MiniMap Bar stays its own addon and Glass
> MiniMap integrates through its public API: [PLAN-public-api.md](PLAN-public-api.md). Sections 7 and
> the drawer parts of 1 and 9 below are superseded by it.

## Context
A new WoW Forever (Interface 16001) addon that reskins the Blizzard minimap as liquid glass to match the
mockup (`Downloads\Liquid glass Thendal Village minimap.png`):
- a round map inside a glass ring with an "N" notch;
- a zone pill above (tracking magnifier on the left, calendar on the right);
- a day/night sun disc at the top right;
- a coords pill below with − / + zoom buttons;
- the bar-launcher disc at the bottom left.

The bottom-left gold disc in the mockup is GlassMiniMapBar's launcher orb (confirmed by the user's in-game screenshot), so **GlassMiniMapBar is absorbed into GlassMiniMap**:
- its glass bar becomes the single "addon drawer";
- the drawer also lists Blizzard's AddOns-compartment entries, so Blizzard's "AddOns" button goes away;
- there is no extra launcher disc.

**Decisions (user):**
- Merge into one drawer, so GlassMiniMap ships as **GPLv3** (GlassMiniMapBar's HidingBar heritage).
- Themes are **Clear / Smoked / Class colour**, repainted live.
- Releases go to GitHub and to CurseForge project **1744024** (https://www.curseforge.com/wow/addons/glassminimap).

**Ground rules** (`References\PORTING-TBC-TO-FOREVER.md:443-484`): `MinimapCluster` is an Edit Mode system and a taint minefield.
- Never reparent or move `Minimap`/`MinimapCluster`, never `Hide()` Blizzard system frames, and never reassign Blizzard globals or methods.
- Fade stock art (alpha 0, mouse off) the way GlassMail's `Skin.lua` does. For frames that must disappear, use GlassPanel's `API.Suppressor` / `API.SystemHider` (`GlassPanel\Compat.lua:112-283`).
- Position and scale come from Blizzard Edit Mode. All our frames anchor to `Minimap`, so they follow.

**Adversarial review:** Codex `gpt-6-astra` at high effort, 2 rounds, ended in CONSENSUS.
- Round 1 raised 2 BLOCKERs, both now fixed:
  - compartment entries added in bulk at login were missed;
  - with standalone GlassMiniMapBar loaded, compartment-only addons became unreachable.
- Round 1's SHOULDs were folded in below.
- One recommendation was kept against the reviewer's advice: the glass tracking popup stays, because the user asked for it. It must match Blizzard's behaviour, and Blizzard's menu is the fallback.

## Templates to copy (don't reinvent)
| From | What |
|---|---|
| `GlassMail` (newest, released) | TOC shape, `Compat.lua` (`API.Fail`, `RegisterEvents`, `IsSecret`, `MEASURED_ON_BUILD`, runtime dev-copy token), `Options.lua` canvas page, slash/help pattern, `.pkgmeta`, `.github/workflows/package-check.yml` (check and release jobs), `Tools\deploy.ps1`, `Tools\LibGlassPin.ps1`, `tests\{harness,wow_stubs,run.ps1,fetch_external.sh,test_toc,test_methods}.lua`, `.gitignore`/`.gitattributes`, CHANGELOG format, CLAUDE.md sections |
| `GlassPanel\Bar.lua:363-427`, `Settings.lua:10-59` | `GLASS` presets plus `classShade`, a secret-safe `classColor()`, `paintGlass` via `Glass.SetSurfaceTint`, `glassPending` retry on PEW |
| `GlassMiniMapBar\{Collector,Bar,Orb,Options}.lua`, `Media\orb_*`, `Tools\make_orb_textures.py`, its tests | The drawer: collector, bar layout and animation, orb skin, dual-list options |
| `PortalRoulette\UI\Skin.lua:65-116` (`Skin:Disc`), `UI\Wheel\Node.lua:27-155`, `UI\Anim.lua` (`ApproachHover`), `Tools\make_art.py` (`disc_rim`, `node_ring`, `specular`) | Glass discs (sun, launcher), hover glow, and rim art for the big ring |
| `GuildSpy\Minimap.lua` | Compartment entry for GlassMiniMap itself (`GlassMiniMap_OnAddonCompartmentClick`) |
| `References\RELEASING.md`, `LIBGLASS-MIGRATION.md` | Release flow, pkgmeta gotchas |

LibGlass is an external at **r6** with `preset = "clean"`. The ring uses `Glass.Disc(host,"disc")`. Pills use `Glass.Apply(host,"small")` / `Glass.Pill`.

## File layout (`C:\Projects\WoW\GlassMiniMap`)
```
GlassMiniMap.toc        Interface 16001, Title |cff7fd4ffGlass|r MiniMap, Version @project-version@,
                        X-License GPL-3.0, X-Curse-Project-ID 1744024, IconTexture,
                        AddonCompartmentFunc*, SavedVariables GlassMiniMapDB
Libs\                   LibGlass-1.0 (external, gitignored); LibStub, CallbackHandler, LibDataBroker, LibDBIcon (vendored, as GuildSpy)
Compat.lua              from GlassMail + Suppressor/SystemHider from GlassPanel + MouseOverMenu from GlassMiniMapBar
Glass.lua               GlassMiniMap.Glass = LibStub("LibGlass-1.0"):New({ preset = "clean" })
Theme.lua               presets clear/smoked + class; surface registry; Theme.Refresh() repaints every registered g
Blizzard.lua            API.Fade of stock minimap art; mask + rotateMinimap re-apply; compartment SystemHider (gated)
Ring.lua                glass ring behind Minimap, perimeter rim art, N notch, Ring.AddDisc; sun/moon disc
Header.lua              zone pill: tracking button | zone text (PvP colour, click = world map) | calendar button
Footer.lua              coords pill + zoom −/+
Tracking.lua            glass tracking popup (not mocked; matches the screenshot list)
Drawer\Orb.lua          port of GlassMiniMapBar Orb.lua
Drawer\Collector.lua    port of Collector.lua + compartment source
Drawer\Bar.lua          port of Bar.lua; launcher = our bottom-left disc
Options.lua             canvas settings page (radio groups, no dropdowns) + drawer dual list
GlassMiniMap.lua        bootstrap last: DB defaults/repair, events, slash /gmm
Media\                  ring_rim, ring_rim_dark, notch, specular, orb_* (TGA, generated)
Tools\                  deploy.ps1, LibGlassPin.ps1, make_textures.py, MinimapProbe\ (throwaway measuring addon)
tests\                  harness, wow_stubs, test_toc, test_methods, test_theme, test_tracking, test_collector, test_bar, test_db
docs\                   PLAN.md, FOREVER-PROBE.md, mockups\ (the mockup), images\
.pkgmeta  .github\workflows\package-check.yml  CHANGELOG.md  README.md  LICENSE (GPLv3 + third-party)  CLAUDE.md  .gitignore  .gitattributes
```

## Components

### 1. Blizzard minimap: fade, don't fight (`Blizzard.lua`)
- **New alpha-only `API.Fade(region)` helper.** GlassPanel's `Suppressor` calls `Hide()`, so it isn't reused here.
  - Sets alpha 0 and, for frames, `EnableMouse(false)`.
  - Its state lives in our own weak table, never on Blizzard tables.
  - It re-applies from `hooksecurefunc` on `Show`/`SetAlpha`, because ZoomIn/Out fade back in on hover.
- **What gets faded** (full paths, found by parentKey, never by texture path):
  - `MinimapCompassTexture`, `MinimapCompassTextureUnderlay`, `MinimapBackdrop.StaticOverlayTexture`
  - `MinimapCluster.BorderTop`, `.ZoneTextButton`, `.Tracking` **and `.Tracking.Button`** (mouse off on the button itself)
  - `Minimap.ZoomIn` / `ZoomOut` / `ZoomHitArea`, `MinimapCluster.MinimapContainer.PlayerCoords`
  - `GameTimeFrame`, `MinimapCluster.DielFrame`
- **`AddonCompartmentFrame`:** reparented away through GlassPanel's full `API.SystemHider` contract (deferred changes, given back while Edit Mode is open, waits for combat to end, re-checks after layout changes). This runs **only when our drawer is active** (see §7 coexistence).
- **Mask:** call `Minimap:SetMaskTexture(round mask)`. Re-apply it after Blizzard's `rotateMinimap` `CVarCallbackRegistry` callback (`Camelot\Skin.lua:23` resets the mask and compass art), deferred one frame, and on `EDIT_MODE_LAYOUTS_UPDATED`.
- **Leave alone:** `QueueStatusButton` (its own Edit Mode system), `IndicatorFrame` (Blizzard's mail and crafting icons stay as they are in v0.1.0), `InstanceDifficulty`.
- **No `GetMinimapShape`:** LibDBIcon already defaults to ROUND.

### 2. Ring and notch (`Ring.lua`)
- **Parenting and scale:**
  - The ring host is **parented to `MinimapCluster.MinimapContainer`**. Blizzard scales that container, so the ring inherits the Edit Mode scale and LOW strata.
  - Its level is `Minimap:GetFrameLevel() - 1`.
  - It's sized once at `Minimap:GetWidth() + 2*ringWidth` and centred on `Minimap`, and never resized: scale changes arrive through the parent.
  - Every attached control (pills, discs) is parented the same way, so it all scales together.
- **Glass:** `Glass.Disc(host,"disc")`. The opaque, round-masked map draws over its centre, so only a glass ring shows.
- **Rim art:** `g.top` ends up at map level + 9, above the map. Its rim/specular art (PortalRoulette's `disc_rim` generator, regenerated into our `Media\`) must be **perimeter-only, with a clear centre**.
- **N notch:** a small glass tab at 12 o'clock with an "N" FontString. When `rotateMinimap` is on it orbits by `GetPlayerFacing()`, using an OnUpdate that runs only while rotation is on.
- **Mouse:** wheel zoom and ping stay Blizzard's.

### 3. Zone pill (`Header.lua`)
- `Glass.Apply(pill,"small")`, anchored above the ring.
- **Left button (magnifier):** opens the Tracking popup. Right-click falls back to Blizzard's own menu through `MinimapCluster.Tracking.Button:OpenMenu()`.
- **Zone text:** `GetMinimapZoneText()`, coloured by `C_PvP.GetZonePVPInfo()` like Blizzard's mixin. Updates on `ZONE_CHANGED*`. Click toggles the world map.
- **Right button (calendar):** shows the day number and a pending-invite badge (`C_Calendar.GetNumPendingInvites`, `CALENDAR_UPDATE_PENDING_INVITES`). Click calls `ToggleCalendar()`. Hidden if the `IngameCalendarDisabled` game rule is on.
- **Our own frames stay unnamed** so the collector never grabs them.

### 4. Coords pill (`Footer.lua`)
- **Coords:** a 0.2 s ticker, running only while shown, reads `C_Map.GetBestMapForUnit` → `C_Map.GetPlayerMapPosition`. Shows "—" in instances (nil position). The `coordsByTenths` setting gives 1 decimal place, otherwise 0.
- **Zoom:** − / + are `Glass.Pill` buttons calling `Minimap:SetZoom` clamped to `GetZoomLevels()-1`. They enable/disable on `MINIMAP_UPDATE_ZOOM`.

### 5. Discs (no separate module)
- **Helper:** one small `Ring.AddDisc(angle, size)` function in `Ring.lua`.
  - It builds a square sized host, calls `Glass.Disc(host,"disc_small")`, adds a round-masked icon and a hover glow (the `Node.PaintGlow` idea), and registers the surface with Theme.
  - Positions are angles on the ring.
- **Sun/moon disc** (top-right, about 45°):
  - icon from `C_DateAndTime.IsDayTime()` and `DIEL_CYCLE_CHANGED`;
  - tooltip shows game and local time;
  - click toggles the time manager.
- **Launcher disc** (bottom-left, about 225°): the drawer launcher (§7).

### 6. Tracking popup (`Tracking.lua`; not mocked up, so styled after the stock list in your screenshot)
The user asked for a glass tracking dialog. It ships in v0.1.0 only if it matches Blizzard's behaviour fully. Otherwise the magnifier opens Blizzard's own menu (`MinimapCluster.Tracking.Button:OpenMenu()`, `DropdownButton.lua:108`), which is also always the **right-click fallback**.
- **Panel:** a glass `"large"` panel, named `GlassMiniMapTrackingPopup` so it can go in `UISpecialFrames` for Escape. It's parented to UIParent, so no minimap collector sees it.
- **Rows:** "Uncheck All", then one row per tracking type: glass checkbox, name, icon.
- **Behaviour copied from `Blizzard_Minimap\Mainline\Minimap.lua:636-772`:**
  - `info = C_Minimap.GetTrackingInfo(i)`, plus `filter = C_Minimap.GetTrackingFilter(i)` for the `filterID`.
  - Show an entry only if `MinimapConstants.OPTIONAL_FILTERS[filter.filterID]` or `filter.spellID` is set, **except when the `minimapTrackingShowAll` CVar is on**. Show-all skips filtering, drops "Uncheck All" and changes the townsfolk grouping, as Blizzard's does.
  - Hunter entries (subType 1) get a sub-section only when there's more than one. Townsfolk (subType 2) follow the show-all rule.
  - "Uncheck All" calls `ClearAllTracking()`, then re-selects the ALWAYS_ON/CONDITIONAL filters.
  - Toggling goes through `MinimapUtil.SetTrackingFilterByFilterIndex`.
- **Spell-cast tracking:** a click shows the predicted checkbox state at once, then the real state replaces it on the next `MINIMAP_UPDATE_TRACKING`.
- **Refresh** on `MINIMAP_UPDATE_TRACKING`, `SPELLS_CHANGED`, and `CVAR_UPDATE` for `minimapTrackedInfov4` or `minimapTrackingShowAll`.
- **Closing:** outside click (`GLOBAL_MOUSE_DOWN`, registered only while open) or Escape.
- **Hidden** if the `IngameTrackingDisabled` game rule is on.

### 7. Drawer: absorbed GlassMiniMapBar (`Drawer\*`)
- **Ported almost as-is.** Collector (filter, Grab/overrides, LibDBIcon_IconCreated, `lib.objects` replay), Bar (layout, grow/shrink animation, hover/click open, hideDelay, last-used) and the options all come across. Namespaces are renamed and the tests kept.
  - **One small Orb change:** `Orb.build` exposes its tint and wash regions to Theme so they repaint.
- **Launcher changes:**
  - The launcher is no longer a LibDBIcon button. It's our bottom-left glass disc.
  - `Bar.lua`'s anchor (`:98-112`, `launcherSide()`) is parameterised to anchor to that disc.
  - Default direction is auto, so it opens leftward like the screenshot.
- **Compartment source:**
  - **Watch:** `hooksecurefunc(AddonCompartmentFrame, "UpdateDisplay")`. Every path that changes the list ends in it: the bulk `RegisterAddons` at PEW, `RegisterAddon`, and LibDBIcon's `RemoveButtonFromCompartment`.
  - **Reconcile:** on the next frame, re-read `AddonCompartmentFrame.registeredAddons`, adding and removing orbs. Opening the drawer also re-reads it, as a backstop.
  - **Per entry:** an orb with its icon (atlas if `C_Texture.GetAtlasInfo`, else file) and its `funcOnEnter`/`funcOnLeave` (given our orb).
  - **Click:** `addonData.func(nil, { buttonName = mouse }, orb)`. That covers both callers: Blizzard's TOC wrapper reads only `buttonName` (`AddonCompartment.lua:102`), and LibDBIcon forwards the third argument as the anchor frame (`LibDBIcon-1.0.lua:649`). Nothing beyond those two is promised; any other custom entry is called the same way, as best effort.
  - **Dedupe:**
    - If a LibDBIcon object's `compartmentData == entry`, it's the same button; keep the minimap button and drop the compartment copy.
    - Otherwise, fall back to an exact normalised title match only when it's unambiguous.
    - A compartment entry is never dropped just because the matching minimap button is hidden by the user.
    - Rechecked whenever either source changes.
  - Compartment orbs take part in the hidden/order lists like any other entry.
- **Coexistence:** if the standalone `GlassMiniMapBar` is loaded, GlassMiniMap's drawer and launcher disc are off, **`AddonCompartmentFrame` is left untouched** (so compartment-only addons stay reachable), and a one-time note is printed.
- **Saved data and migration:**
  - Drawer settings live in `GlassMiniMapDB.drawer` (openOn, hideDelay, direction, perRow, buttonSize, skin, animate, lastUsed, last, order, hidden).
  - At `PLAYER_LOGIN` (after both addons' SavedVariables have loaded), if `GlassMiniMapBarDB` exists and `drawer` was never imported, copy it once and set `drawer.imported = true`. The note then says to disable GlassMiniMapBar and `/reload`.
  - The README explains that the import needs one session with both addons enabled.

### 8. Theme (`Theme.lua`)
- **Presets:**
  - `clear = { classShade = 0.6 }`
  - `smoked = { tint = {0.05,0.06,0.08,0.62}, grain = 0, wash = 0.14, classShade = 0.3 }`
  - `class`: the clear body tinted by class colour × classShade. If the colour is unreadable it sets a pending flag and retries on PEW.
- Every surface (ring disc, pills, discs, tracking panel, drawer bar, orbs) registers its `g`.
- `Theme.Set(name)` repaints them all live via `Glass.SetSurfaceTint` + grain/wash alphas.
- Saved key: `GlassMiniMapDB.theme` (`"clear"|"smoked"|"class"`, default clear).

### 9. Options, slash and saved data
- **Settings canvas page** (GlassMail pattern; radio groups):
  - Theme;
  - show coords, coords decimals;
  - sun disc;
  - a drawer sub-page with GlassMiniMapBar's controls and dual list.
- **Deferred past v0.1.0:**
  - a live "Stock look" toggle (disable the addon to get the stock minimap back);
  - a clock in the footer;
  - a glass mail disc.
- **Slash:** `/gmm [options|theme clear|smoked|class|drawer|scan|failures|reset|version|help]`.
- **Saved data:** `GlassMiniMapDB` is account-wide. Store only non-defaults, with a metatable fallback to `DEFAULTS` and repair/clamp on load.

## Phases
0. **Scaffold and probe.**
   - Create the folder skeleton from the GlassMail template, the TOC, LibGlass r6 external, and CI.
   - Add `Tools\MinimapProbe` to measure on the live build:
     - what the "72" FontString above the launcher is;
     - the game rules for calendar and tracking;
     - which tracking entries a character gets;
     - `registeredAddons` contents;
     - the effect of the mask re-apply on rotate;
     - QueueStatusButton overlap at its default position (-68,-68), which is the launcher's spot, so the launcher angle may need to move.
   - Record the findings in `docs\FOREVER-PROBE.md`.
1. **Blizzard fade + ring + mask + notch + theme**, with test_theme and test_toc.
2. **Zone pill, coords pill, zoom, sun disc.**
3. **Tracking popup**, with test_tracking (stubbed C_Minimap).
4. **Drawer port + compartment source + launcher disc + coexistence/import**, with the ported test_collector and test_bar.
5. **Options page, slash, README/README.curseforge, CHANGELOG v0.1.0, release.**
   - `git init` and create the GitHub repo `Spotnick2/GlassMiniMap` (confirm with the user first).
   - Connect the CurseForge webhook to project 1744024.
   - Tag `v0.1.0` per `RELEASING.md`.
   - Add a notice to GlassMiniMapBar's README pointing at GlassMiniMap; that's a separate repo, so confirm first.

## Verification
- **Offline:** `pwsh tests\run.ps1` runs `luac -p` on every TOC file and all `tests\test_*.lua`.
  - Strict-globals stubs catch globals the dump doesn't have; `test_methods` checks recorded widget calls against `References\forever-api-1.60.1.70374.md`.
  - Neither proves argument contracts, event behaviour or protection rules. That needs the in-game pass.
  - Unit tests cover:
    - compartment reconcile (bulk add, single add, LibDBIcon removal, `compartmentData` dedupe, click args);
    - the tracking filter and show-all logic against stubbed `C_Minimap`;
    - migration;
    - the coexistence gate.
- **CI:** the `package-check.yml` dry-run packager zip allowlist, the LibGlass pin parity check and the version-token substitution check all pass on push.
- **In game:**
  - Deploy with `pwsh Tools\deploy.ps1`, restart the client (new addon with new textures), `/console scriptErrors 1`.
  - Compare with the mockup in each theme (clear, smoked, class); toggle `rotateMinimap` (mask and art must stay glass, N notch orbits).
  - Move and scale the minimap in Edit Mode (everything follows).
  - Zone change and PvP colour; coords in an instance; zoom limits.
  - Tracking toggles match Blizzard's menu.
  - The drawer collects LibDBIcon buttons plus compartment-only addons with no duplicates.
  - **Taint pass:**
    - open Edit Mode, move and scale the minimap, toggle rotation, close Edit Mode;
    - then use action bars and macros in combat;
    - check for no "blocked/forbidden action" errors (BugSack/scriptErrors) as well as an empty `/gmm failures`.
  - **Compartment:**
    - a TOC-only compartment addon (e.g. Gnomesweeper) appears;
    - a LibDBIcon addon that also shows in the compartment appears once;
    - left and right clicks reach both kinds;
    - removing an entry removes its orb.
  - **Coexistence and migration:**
    - with standalone GlassMiniMapBar enabled, the drawer is off and Blizzard's AddOns button still works;
    - settings import once;
    - after disabling GlassMiniMapBar, the drawer is on.
- **After release:** compare CurseForge's zip with the GitHub zip (`RELEASING.md` §4).

## Implementation notes (v0.1.0 as built)

Where the code differs from the plan above, and why (simpler, same result):
- **Blizzard's mask is kept.** `ui-hud-minimap-frame-generic-mask` is already a round mask at the
  map's 198 px, and Camelot\Skin.lua re-applies it on every `rotateMinimap` change. So there is no
  `SetMaskTexture` and no re-apply hook; the ring is drawn to fit it. Measured in game as probe P6.
- **No vendored LibDataBroker / LibDBIcon.** The launcher is our own disc, so the drawer only
  listens to whatever LibDBIcon the collected addons embed (`LibStub("LibDBIcon-1.0", true)`).
- **`Drawer\Compartment.lua`** holds the compartment source; Collector gained `AddOwn`/`RemoveOwn`.
- **`/gmm reset` dropped** (nothing positional to reset: Edit Mode owns the position).
- **Geometry**: the zone pill's bottom sits on the north tab's tip, 9 px above the ring, so its top
  stays inside MinimapCluster when the cluster is at the screen's top edge.
