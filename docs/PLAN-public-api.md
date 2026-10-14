# Plan revision: keep Glass MiniMap Bar, give it a public API

**Decision (owner, 2026-10-13):** instead of absorbing Glass MiniMap Bar (PR #6 as first written),
keep both addons. Glass MiniMap Bar stays the one drawer implementation and gains a small public
API; Glass MiniMap is a pure reskin that hands the drawer its bottom-left disc as the launcher
when Glass MiniMap Bar is installed.

Why: one collector codebase (no fork), the AddOns-compartment feature reaches every Glass MiniMap
Bar user, Glass MiniMap carries no HidingBar-derived code (back to MIT like GlassMail), and no
coexistence/import machinery.

## Glass MiniMap Bar (repo Spotnick2/GlassMiniMapBar), v1.1.0

Public API, AltStable's convention (`AltStable.PUBLIC_API_VERSION`, docs/PUBLIC-API.md): the
version is bumped on any incompatible change; adding a function doesn't bump it. Named
`PUBLIC_API_VERSION` because `GlassMiniMapBar.API` is the internal Compat adapter.

```lua
GlassMiniMapBar.PUBLIC_API_VERSION = 1
GlassMiniMapBar.UseLauncher(frame, opts) -> true | false, why
--   The bar opens from `frame` (another addon's button) instead of its own LibDBIcon launcher,
--   which is hidden (lib:Hide: not saved, the player's ring position is kept).
--   Safe before or after Glass MiniMap Bar's PLAYER_LOGIN (applied when the bar is built).
--   opts.setIcon(file|atlas, coords|nil): called whenever the launcher's face changes
--   (last used button, or the arrow toward the bar). Optional.
GlassMiniMapBar.ReleaseLauncher()          -- back to its own launcher
GlassMiniMapBar.LauncherClick(frame, mouse) / LauncherEnter(frame) / LauncherLeave(frame)
--   The consumer's frame calls these from its OnClick / OnEnter / OnLeave (no hooks on
--   someone else's frame). Ignored unless `frame` is the current external launcher.
GlassMiniMapBar.SetGlassTint(r, g, b, a, wash)   -- or SetGlassTint() for the built look
--   Body tint of the bar and the orbs, so the drawer follows the host's theme.
```

New feature: **the AddOns compartment in the bar** (`Compartment.lua`, moved from Glass MiniMap's
PR #6 as reviewed there: `hooksecurefunc(AddonCompartmentFrame, "UpdateDisplay")` + next-frame
reconcile + reconcile on open; click `func(nil, {buttonName}, ourButton)`; duplicates by LibDBIcon
`compartmentData` identity, then an unambiguous exact title). Option `compartment` (default on):
while on, Blizzard's AddOns button is hidden with GlassPanel's SystemHider (deferred, given back in
Edit Mode, waits for combat). Collector gains `AddOwn` / `RemoveOwn`.

Tests: the public API (before/after build, release, setIcon, handlers ignore a stale frame,
SetGlassTint), the compartment (ported test), CHANGELOG v1.1.0, docs/PUBLIC-API.md.

### After review round 1 (Codex gpt-6-astra)

- **Native launcher suppressed for the whole attachment**, not one `lib:Hide`: a
  `hooksecurefunc(nativeLauncher, "Show")` (our own button) hides it again while an external
  launcher is attached; LibDBIcon's `Show`, `Refresh` and login visibility all go through `Show`.
  `ReleaseLauncher` stops that and restores the saved preference (`db.minimap.hide`: hidden stays
  hidden, else `lib:Show`). Takeover is never saved.
- **The host owns the external launcher's look**: the native LibDBIcon button stays a separate
  reference and is the only one `Orb.Skin` touches; `Bar.Launcher()` is "the active anchor".
- Lifecycle: `UseLauncher` before build is pending and applied right after the native launcher
  exists; `ReleaseLauncher` before build cancels it; attaching after build publishes the current
  face (`setIcon`) and relayouts at once.
- `GlassMiniMapBar.OpenOptions()` (exists) is part of the documented contract.
- `SetGlassTint`: remembered before build, applied to orbs made later, no arguments = as built;
  `wash` is a multiplier of the built wash (Glass MiniMap's smoked passes 0.14 / 0.18).
- **Compartment hover callbacks get `(ourButton, entryData)`**: LibDBIcon's
  `onEnterCompartment(self, menu)` reads `menu.text`; Blizzard's TOC wrappers ignore the extra
  argument. Tested with a two-argument callback.
- Duplicate titles: **exact** comparison after stripping colour/texture markup and trimming
  (case-insensitive), identity first. No punctuation folding.
- Replay re-checks `IsProtected`/`IsForbidden` on the target before clicking; documented as
  ordinary addon-button replay, not a way to run protected actions.
- **Pushed back:** `compartment` stays **on by default**. Folding the AddOns list into the bar is
  what the owner asked for; the release notes call the change out and the option turns it off
  (the button comes back). Documented: only one addon should manage `AddonCompartmentFrame`
  (SystemHider undoes any other reparenting while it wants the button hidden).
- "Left alone" in Glass MiniMap means Glass MiniMap itself never touches the AddOns button.

The public API is also what the next addon, GlassMaps (replacing Leatrix Maps), will integrate
through, so it stays small, versioned, and documented in Glass MiniMap Bar's docs/PUBLIC-API.md.

## Glass MiniMap (this repo), v0.1.0 (PR #6 reworked)

- Remove `Drawer\*`, the import/coexistence code, the compartment hider, the drawer options page,
  `/gmm drawer` and `/gmm scan` (Glass MiniMap Bar has `/gmb`), and the orb textures but
  `orb_mask` (hover light).
- `## OptionalDeps: GlassMiniMapBar`. At PLAYER_LOGIN, if `GlassMiniMapBar.PUBLIC_API_VERSION == 1`:
  build the bottom-left disc, `UseLauncher(disc, { setIcon = ... })`, its scripts call the
  Launcher* handlers. No Glass MiniMap Bar, or another API version: no disc; Blizzard's AddOns
  button is left alone.
- `Theme.Refresh` also calls `SetGlassTint` with the theme's tint and wash.
- Options page: a "Drawer options" button (Glass MiniMap Bar's page) when it is installed.
- Licence back to MIT; README says the drawer needs Glass MiniMap Bar (CurseForge optional dependency).

## Order

Glass MiniMap Bar's PR (API + compartment) first, released as v1.1.0; Glass MiniMap's PR #6
depends on it. Live probe results so far (1.60.1.70374): P2 all rules off, P3 24 tracking types,
P4 six compartment entries (DBM, AltStableSync, Gnomesweeper, GuildSpy, Leatrix Maps, Leatrix
Plus), P5 QueueStatusButton CENTER -> Minimap CENTER (-68, -68), hidden when not queued.
