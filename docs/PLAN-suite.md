# Plan: Glass MiniMap joins the Glass UI suite (#37)

Glass UI is the optional orchestrator of the Glass addons. Its contract is `GlassUI.Suite`, API 1:
GlassUI's `docs/SUITE.md` (the material) and `docs/SUITE-LOOK.md` (the look, the body and the
accent), on its `main` at 75013df. Glass MiniMap is on its roster as "not yet integrated".

This plan follows the answers of Glass UI's session (2026-10-20):
- the material: GUF and GRF's rule;
- the tint: GAB and GlassChat's override model, **revised after the first in-game run** to GUF and
  GRF's rule (§3);
- the body's tint and wash, with no backing;
- no accent.

**Unchanged without Glass UI:** every Glass addon works alone. With no Glass UI, or a Glass UI
without `Suite`, Glass MiniMap keeps its own look. That look differs from today in one way: its
default material becomes Pearl (below).

## What we speak

| Contract | What we do |
|---|---|
| `Suite.Theme(ADDON)` | asked once, at our `ADDON_LOADED`, before any glass is built |
| `Suite.Report(ADDON, state)` | after the build, and again when the tint in effect changes |
| `Suite.Look()`, `GlassUI.Suite.LookChanged` | the `tint` key only; `hover`, `press`, `emptySlots` and `accent` ignored |
| `Suite.Body(tint)` | its `tint`/`classShade` and `wash` on our surfaces; its `backing` skipped (`own.backing = true`) |
| `Suite.Accent` | not used: the zone text's PvP colours carry information, and the north tab and the day/night disc are art |
| `Suite.Open()` | the "Set in Glass UI" button next to the suspended material choice |

Each optional function is feature-detected (`type(rawget(Suite, "X")) == "function"`). Every call
is wrapped in `pcall` (`API.Try`). We never read `GlassUIDB` and never touch `GlassUI.Options`.

## 1. The start sequence (`Suite.lua`, new; `Glass.lua`; `GlassMiniMap.lua`)

- **TOC:** `## OptionalDeps: GlassMiniMapBar, GlassUI`. Glass UI's S.2 (measured on 70450) found
  every `Theme` answer given after `Ready()` when the asker has `OptionalDeps: GlassUI` and asks at
  its own `ADDON_LOADED`.
- **The build moves out of file scope.** `Glass.lua` defines `GMM.BuildGlass(preset)`, which
  returns the instance and stores it in `GMM.Glass`. Seven files capture `local Glass = GMM.Glass`
  at file scope today: Difficulty, Footer, Header, Queue, Ring, Theme and Tracking (Drawer reads it
  at call time). Each now reads `GMM.Glass` when it builds or paints. All of them build at
  `PLAYER_LOGIN` or later, so no file-scope capture is needed. `GMM.MEDIA` stays at file scope.
- **At our `ADDON_LOADED`**, in this order:
  1. `ensureDefaults()`, with the one-time tint migration (section 3).
  2. `Suite.Decide()`:
     - `G = rawget(_G, "GlassUI")`. The suite counts only if `type(G) == "table"`,
       `type(rawget(G, "Suite")) == "table"`, `rawget(Suite, "API") == 1` exactly, and `Theme`
       and `Report` (read with `rawget`) are both functions. A throwing `__index` can't escape
       (GUF's `Glass.lua:84`).
     - Then `pcall(Suite.Theme, ADDON)`. We follow only if the answer is a table whose
       `rawget(answer, "preset") == "pearl"`. Every payload we read later (`Look`, `Body`,
       `LookChanged`) is read the same way: `rawget`, plain values only.
     - Anything else (absent, junk, a throw, `"not-ready"`, `"not-following"`) means our own
       look. A `"not-ready"` answer is recorded for `/gmm suite`, since it means the load order
       failed.
     - Decided once per session. A Follow toggled later waits for a `/reload`; Glass UI's page
       shows "Reload to apply" itself.
  3. If following and `Look` exists: register for `GlassUI.Suite.LookChanged` (EventRegistry),
     then pull `Suite.Look()` at once. We copy only a valid `tint` name and never keep the table.
     Nothing is replayed to a late registrant. A `Look` that throws counts as no `Look`: our own
     tint, ours to set (Codex's PR review).
  4. Build the glass, choosing the preset:
     - following: `"pearl"`;
     - otherwise: `db.material` (`"pearl"` by default, or `"clean"`).

     Pearl needs LibGlass MINOR ≥ 11. If the winning LibGlass is older, or `New` errors:
     - a followed Pearl reports `reason = "library-too-old"` or `"build-failed"`;
     - the local material falls back to `"clean"` and says so once.

     If clean fails too, it is today's failure, recorded in `GMM.failures`.
  5. `Report`, under pcall:
     - `api = 1`;
     - `built = "pearl"` when following and built, else nil;
     - `reason`;
     - `minor = LibStub("LibGlass-1.0")`'s MINOR at the attempt;
     - `options = GMM.Options.Open`;
     - `look = { tint = <effective> }`;
     - `own = { tint = true | nil, backing = true }`.
- `PLAYER_LOGIN` keeps its fallback: if `GMM.Glass` is still nil (our `ADDON_LOADED` failed),
  build there before the ring. It reuses the decision if one was made, and decides only if none
  was: one answer per session.
- `GMM.Suite` exposes the session's state for the options page, `/gmm suite` and the probe:
  - `Following()`;
  - `Answer()` (preset or reason);
  - `Built()`;
  - `Reason()`.

## 2. The material setting (`material`, new)

- `DEFAULTS.material = "pearl"`. The values are `pearl` and `clean`, saved sparse like every
  key. An empty profile moves to Pearl at its next `/reload`; nobody has saved a material yet.
  Clean is today's look. Classic is left out: its rims and grain were never seen on a ring.
- It applies at reload. `Settings.SetMaterial(name)` saves it and prints "applies after /reload".
- **While following it is suspended, but kept.** Every write path answers "Set in Glass UI"
  instead of writing:
  - `Settings.SetMaterial`;
  - `/gmm material`;
  - the options radio, shown disabled with "Following Glass UI (Pearl)" and a "Set in Glass UI"
    button when `Open` exists.

  `db.material` is untouched, so stopping following brings it back after a reload.
- After a failed build, the options page and `/gmm material` say "own look: <reason>".

## 3. The tint (`theme` → `look.tint`, suspended while following)

**Revised (the owner, 2026-10-20, after `/fp steps mm suite` rev 1 on 70450).** The plan first took
GAB and GlassChat's override model: a "Glass UI (…)" choice first, and a tint of the player's own
overriding the suite's for the minimap. The owner's verdict: the tint should be grayed out like
the others' (GlassPanel, GUF, GRF), with no choice at the addon level to follow Glass UI. So the
tint now follows the material's rule (§2): **suspended but kept**. While following with `Look`,
the suite's tint is the one in effect; ours stays saved and unused, the setters refuse ("set in
Glass UI"), and the page shows our tint grayed out with "Following Glass UI (<Smoked glass>): set
in Glass UI". The bullets below are amended to match.

- **Storage:** `GlassMiniMapDB.look = { tint = name }`.
  - It is sparse and read with `rawget`.
  - `ensureDefaults` never prunes it against `DEFAULTS`: a chosen Clear survives a reload.
  - A junk value is dropped.
- **The one-time move**, in `ensureDefaults` before the prune and before the defaults metatable:
  - a raw, valid `db.theme` moves into `db.look.tint`, unless `look.tint` is already set (a saved
    one wins);
  - `theme` is then deleted, so the move is idempotent with no version stamp;
  - `theme = "clear"` can't be in a saved file, because the old prune removed it.
- **The effective tint:**
  - while following with `Look`: the suite's tint, else `"clear"` (`look.tint` unused);
  - otherwise: `look.tint`, else `"clear"`.
- **One resolution path.** `Theme.Resolve()` returns the effective name, the tint (nil = as built)
  and the wash factor. `Theme.Register` (which paints at once, and runs after startup too: the
  tracking menu's checkboxes, `Tracking.lua:215`), `Theme.Current` (the drawer, the runes) and
  `Theme.Refresh` all use it. `Current` stays safe before `GMM.db` and `GMM.Glass` exist (Ring's
  file-scope `OnChange`, `Ring.lua:175`).
- **`Theme.lua` paints from the effective tint.** While following with `Body`:
  - it takes `Suite.Body(name)` on every refresh (a fresh table) and uses its `tint`, or
    `classShade` times our class colour at the surface's built alpha, and its `wash` factor of our
    `STYLE.wash`;
  - `Body` returning nil (an unknown name) falls back to our own `Theme.PRESETS[name]`.

  Otherwise it uses `Theme.PRESETS` as today. The class colour's retry at `PLAYER_ENTERING_WORLD`
  is unchanged.
  - **Clear, compared:** our Clear is "as built", with no tint. Glass UI's Clear body is
    {0.13, 0.16, 0.22, 0.24}, which is LibGlass's own built tint (`LibGlass.lua:133`), so on our
    unbacked ring the two look the same. Smoked and class are the same numbers too: the difference
    is only that the numbers are Glass UI's, so a later change there reaches us.
- **`LookChanged`** (in or out of combat):
  - copy a valid `tint`, then `Theme.Refresh()`;
  - our surfaces are our own unprotected textures, so it is combat-safe as is;
  - it is idempotent;
  - an unknown tint value clears the cached suite tint, so the effective tint falls back to our
    default (Clear) (SUITE-LOOK.md: "keeps its own default for that key"; GAB's `Look.lua:83`);
  - it then re-reports with fresh tables, since Glass UI's `copyReport` keeps a snapshot
    (`Suite.lua:128`).
- **Setters:**
  - `Settings.SetTheme(name)` writes `look.tint` and re-reports;
  - `Settings.ClearTheme()` removes it (the probe's restore of "none" uses it too);
  - while following with `Look`, both refuse: false, "set in Glass UI";
  - `/gmm theme clear|smoked|class` (while following it prints the tint line).
- **The options radio:** our three tints, our own selected. While following with `Look` they are
  disabled and seen to be (alpha 0.5, gray labels: the radio art has no disabled look, GRF
  measured), as the material's are, with "Following Glass UI (<Smoked glass>): set in Glass UI".
- **Report:** `look.tint` is the effective name; `own = { backing = true }`, with no `own.tint`
  (we never override the suite's tint). Re-reported whenever the effective tint changes.

## 4. Glass MiniMap Bar: one driver

GMMB is its own roster member. It doesn't speak the suite yet: it is at LibGlass r6 and has no
`Suite` code. Today `Drawer.lua` forwards our tint through `SetGlassTint` (`Theme.OnChange`).
- **We keep forwarding unless GMMB says it follows the suite**, through a feature-detected,
  additive `GlassMiniMapBar.FollowsSuite()` that returns true.
  - That function is GMMB's to add in its own issue, along with its suite integration. Its
    session decides it, and this repo never edits it.
  - Until then GMMB's glass wears our effective tint, which while following is the suite's.
- Glass UI's session suggested "forward only when Suite is absent". That would leave GMMB
  untinted until it integrates, so this plan replaces it with the GMMB opt-out above.
  - Under the opt-out, the bar wears our effective tint, which is the suite's while we follow.
- **The wash:** GMMB used to apply the forwarded wash with `SetAlpha` on gradient textures, which
  has no effect on this client (our `Theme.lua:56`). GMMB fixed that in its #36/#38 (v1.1.1), so
  the forwarded wash now applies too.
- **GMMB's side (its PR #41, 2026-10-20):** `FollowsSuite()`, additive on its API version 1,
  settled at its `ADDON_LOADED`, so it's answered before our `Drawer.Start` at `PLAYER_LOGIN`.
  - It's true only while GMMB follows and paints the suite look itself (Theme answered Pearl, and
    Look and Body exist).
  - While it's true, a `SetGlassTint` call from an older Glass MiniMap is accepted but not painted.
  - With the tint suspended while following (§3), the bar and the minimap wear the same suite tint
    either way.
- Glass UI's session agreed (2026-10-20):
  - `FollowsSuite` is read with `rawget` and called under pcall; anything but `true` means "not
    following";
  - GMMB is never listed in our `tenants`: it is a roster member in its own right, and its card
    honestly says "Not yet integrated" until it speaks the API.

## 5. LibGlass r7 → r11

`.pkgmeta` moves to `tag: r11`. What changes from r7:
- r8 and r10 only touch bar fills (we have none);
- r9 adds per-surface rim and region alphas and `Reflect`; it is additive and existing surfaces
  keep their look;
- r11 adds `preset = "pearl"` and the fill repaint fix.

PR #32 (70450, r9, waiting for its in-game check) also touches `.pkgmeta`. Whichever merges second
rebases, and r11 wins.

## 6. Tests (mutation-tested)

- **Suite absent or broken:** no `GlassUI`; `Suite` missing or not a table; `API` 2 or `"1"`;
  `Theme` or `Report` not a function; `Theme` throwing; `Theme` returning junk; `"not-ready"`;
  `"not-following"`. Each builds the local material and never touches `material`, `look` or any
  saved key.
- **Following:** builds Pearl. `material = "clean"` stays saved and untouched. Every material
  write path refuses with "Set in Glass UI".
- **Follow on, reload, off, reload:** the local material and tint are back exactly.
- **An old LibGlass** (MINOR 10) with Pearl asked:
  - followed: it reports `library-too-old` and builds clean;
  - local: it falls back to clean and says so;
  - a newer LibGlass arriving after the build never restyles.
- **`New` throwing:** `build-failed`.
- **The build's timing:** every TOC file loads with `GMM.Glass == nil`, and nothing is built
  before the decision (the harness's `opts.before`, `harness.lua:84`).
- **The guard:** a `GlassUI` whose `Suite` lookup throws, and a `Theme` answer whose `preset`
  lookup throws: both are our own look.
- **Tint:**
  - the migration: an empty profile; a legacy `theme = "smoked"`; legacy and `look.tint` in
    conflict; junk;
  - a chosen Clear surviving a reload;
  - an unknown suite tint: Clear, never ours;
  - the effective value: following (a saved tint of ours unused), not following, `Look`
    absent, and `Look` throwing (our tint kept and settable, a later `LookChanged` ignored);
  - the setters refused while following, and the saved tint kept;
  - `LookChanged`: a fresh table repaints and re-reports; mutating it afterwards changes nothing;
    it is applied in combat (`WoW.combat`) with no protected call;
  - a late registrant pulls `Look()` at once.
- **Body:** the numbers painted for each tint, through `Register` (a surface built late, such as
  the tracking menu's), `Current` and `Refresh` alike, under suite Clear; `classShade` at the built alpha; the class colour
  unreadable, then the retry; the backing never painted; `Body` absent or returning nil falls back
  to our presets.
- **Report:** its fields; no `own.tint`; a re-report on each change of the tint in effect;
  `Report` throwing is harmless.
- **GMMB:** the tint is forwarded without `FollowsSuite`, and not forwarded when it returns true.
- **The options page:** the material and tint radios are disabled and dimmed while following,
  with the tint line; "Set in Glass UI" calls `Open` under pcall and is hidden without `Open`.
- **Stubs:** a fake `GlassUI.Suite` in `tests/wow_stubs.lua`, in the same spirit as the fake GMMB
  API; `EventRegistry` callbacks.

## 7. In game (`/fp steps mm suite` and `suiteoff`, MinimapProbe)

**The existing procedures move first.** MinimapProbe reads and restores `g.db.theme`
(`MinimapProbe.lua:171`, `:383`), which the migration deletes. Its snapshot keeps the **source**:
whether `look.tint` was set and to what, apart from the effective tint. Restoring sets it back
or clears it, so a run never leaves a tint that wasn't there, after a reload too (while following
the setters refuse, and no procedure changes it). Its wash expectations stop being
absolute (`0.18`/`0.14`, `:168`) and become the built `STYLE.wash` times the effective factor.
`test_probe` follows.

- **G.1:** without Glass UI, an empty profile is Pearl (`GMM.Glass.STYLE.wash` is Pearl's), and a
  saved Clean is clean.
- **G.2:** with Glass UI, following: Pearl, and Glass UI's card says "Following (Pearl)" with "its
  own backing".
- **G.3:** change the suite tint live (Clear, Smoked, Class): the ring, pills, discs, north tab and
  drawer repaint; screenshots on bright and dark terrain. With GMMB's PR #41 deployed too, the
  drawer takes the tint from Glass UI, not from us.
- **G.4:** our tint while following: the setters refuse and the saved one is kept; the page shows
  the tint and the material grayed out, with "Set in Glass UI" (a screenshot; suite rev 2).
- **G.5:** follow off, then reload: our own material and tint come back.
- **G.6:** a tint change in combat: no `ADDON_ACTION_BLOCKED`, and `scriptErrors 1` is clean.

The results go in docs/FOREVER-PROBE.md with the build.

## Review

Codex (`gpt-6-astra`, high effort), round 1: no BLOCKER; five SHOULDs and two NITs, all adopted:
- the probe's tint snapshot keeps the override's source, and its wash expectations follow the
  material;
- an unknown suite tint falls back to our default;
- one resolution path for `Register`, `Current` and `Refresh`;
- `rawget` across the namespace and payload reads;
- a re-report after `LookChanged`;
- GMMB's wash limit recorded (NIT);
- the initialisation check instead of a grep (NIT).

Round 2 found all seven resolved and no new defect: **consensus** (2026-10-20).

## Out of scope

The accent; hover/press/emptySlots; GMMB's own suite integration (its repo); Glass UI hosting our
options page.
