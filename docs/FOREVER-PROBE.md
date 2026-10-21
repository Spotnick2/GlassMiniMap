# Forever probe: Glass MiniMap

What has to be measured on the live client before v0.1.0 ships, and what was found. Deploy with
`pwsh Tools\deploy.ps1 -Probe` (it deploys `..\ForeverProbe` first), `/reload`, then run `/fp mm`
and the procedures below. Record the build each result was measured on.

## Probe questions (`/fp mm`)

| # | Question | Command | Result |
|---|---|---|---|
| P1 | What draws the purple "72" above the bottom-left disc (mockup and stock screenshot)? | `/fp mm near` | **RestedXP's guide step** (owner, 70374): its step pin on the minimap, an unnamed child of `Minimap`. Not ours; left alone |
| P2 | Are `IngameCalendarDisabled`, `IngameTrackingDisabled`, `MinimapDisabled` active on Forever? | `/fp mm rules` | **all off** (ids 75, 76, 146; WorldMapDisabled 145 and UserAddonsDisabled 29 off too) |
| P3 | Which tracking entries does a Vanilla-content character get (filterIDs, spellIDs, subTypes)? | `/fp mm tracking` | **24 types**, below |
| P4 | What is in `AddonCompartmentFrame.registeredAddons` with the usual addons? | `/fp mm frames` | **6**: DBM, AltStableSync, Gnomesweeper, GuildSpy, Leatrix Maps, Leatrix Plus (icons as file paths, one file ID) |
| P5 | Where does `QueueStatusButton` sit while queued? Its Edit Mode default is `Minimap` CENTER (-68, -68), the launcher disc's spot (225°). | `/fp mm queue` while queued | **default confirmed** (not queued): parent UIParent, CENTER -> Minimap CENTER (-68, -68), 45×45, hidden. Overlap while queued: **confirmed** (owner's screenshot, Thunder Bluff): the eye covered the drawer disc. The eye is mirrored to the top left, (-68, +68), with a glass backing; the drawer disc stays bottom left (#4; tried: drawer at 135°, the open drawer crossed the map; at 255°, owner preferred the mirror) |
| P6 | Is Blizzard's mask (`ui-hud-minimap-frame-generic-mask`) a clean 198 px circle the ring fits, in both rotation modes? | look, toggle Rotate Minimap | open |
| P7 | `MinimapContainer` scale and size per Edit Mode scale (the ring is sized once and scales with it). | `/fp mm frames` at 80% / 120% | at 100%: Minimap 198×198, all scale 1 (effective 0.64, the UI scale); other scales open |

## Guided procedures (`/fp steps mm <name>`)

MinimapProbe is a ForeverProbe module (`..\ForeverProbe\docs\GUIDE.md`): its lines go to the `/fp`
console and `MinimapProbeDB.log`, never to chat. A procedure is a panel of buttons, one step at a
time; every outcome, check and screenshot is saved, and a session reads `MinimapProbe.lua` and
`ForeverProbe.lua` (`steps.records`) after the owner's `/reload`. Screenshots are listed and then
deleted with `pwsh ..\ForeverProbe\Tools\screenshots.ps1 -Module MinimapProbe` (`-Remove`), never
another module's.

| Procedure | Checks | Status |
|---|---|---|
| `wash` (#22) | clear then smoked: the wash's gradient peak 0.18 / 0.14 on the ring and the zoom buttons; zoomed fully out, the minus button dimmed (LibGlass's `disabledAlpha`) in both; the owner judges the sheen | **passed** (70374): peaks 0.18 / 0.14, minus dimmed 0.25 in both. The sheen change is too small to judge by eye (owner skipped the question); measured on the shots instead, below |
| `mail` (#19) | after new mail and its senders: the disc shows with `HasNewMail()`, Blizzard's icon faded; a shot in each theme; the tooltip held for a delayed shot | **passed** (70374): disc shown, Blizzard's icon alpha 0, readable in all three themes (owner), tooltip lists the sender (owner) |
| `suite` (#37) | with Glass UI following: Pearl built; our own tint refused while following and kept; the options page shot (tint and material grayed out, "Set in Glass UI"); the suite's tint (`/glassui look tint smoked`, class, clear) on every surface with the wash that goes with it, a shot each; a tint change in combat; the owner judges the repaint | rev 1 **passed** (70450, 7 checks): Pearl built, the suite's smoked / class / clear at their washes (ring peaks 0.078 / 0.100 / 0.100), repainted live with the drawer's bar (owner), and in combat with no error (owner). Rev 1 also had our own tint override the suite's; the owner's verdict was to gray it out like GlassPanel's. Rev 2 **passed** (70450, 7 checks): our tint refused while following ("set in Glass UI") and the saved smoked kept; the page grayed out with the tint line and Set in Glass UI (owner, shot); the suite's smoked / class / clear at their washes; repainted live with the drawer's bar, and in combat with no error (owner) |
| `suiteoff` (#37) | after turning Follow off (or disabling Glass UI) and `/reload`: our own material and tint, exactly as before | **passed** (70450): Pearl (ours, the default) and our saved smoked back at its wash (0.078); the owner confirmed both on the page |
| `edges` (#39, #40) | the coords pill under the ring (frame levels) and the sun's dark well shown; shots on bright ground (clear, smoked) and dark; the owner judges the sun's contrast against the drawer's disc, the closed rim over the pill, the coordinates' crispness, the well on dark ground | **partly** (70450, Durotar): ring level 2, pill 1, the well shown (PASS); the sun as easy to see as the drawer's disc, and the well reads as glass on dark ground (owner). **Unsure:** the closed rim ("with the smoke animation active, it doesn't; without it, seems under the ring") and the coordinates' crispness ("could be better"). On the shots, runic mode's exterior vapor (`Ring.lua`, level Minimap + 2, 18 px past the ring) and its bloom (+1) now draw over the pill's top and its text, which sit at levels 1 and 3: #42 |
| `edges` rev 2 (#42) | with the runic ring and its vapor on: the pill still under the ring, its text and zoom buttons over the runes and vapor (frame levels, the text on its lifted frame), the sun's well; shots bright (clear, smoked) and dark; the owner judges the text's crispness over the vapor, the closed rim, and whether the vapor's tint on the pill's top still calls for #42's option 2 | **passed, superseded** (70450, Durotar, following Glass UI's tint): text and zoom 7 over the runes and vapor 6 (PASS); the text crisp over the vapor on bright and dark ground, the zoom buttons too (owner). But the text "not centered under the minimap" (it was centered left of the buttons); the rim unsure ("if I zoom, the pill is over the circle": where tucked, the pill's own rim frame, level 11, drew over the ring's glass, 2); and the vapor's tint on the pill still bothered (option 2). The owner's mockup settled it: rev 3 |
| `edges` rev 3 (#42) | the pill hung under the ring by the zone pill's gap (9), drawn over the runes and vapor with its zoom buttons, the text on it; the sun's well; then the zoom buttons as discs on the ring (`zoom = "ring"`); shots bright (in the pill, on the ring) and dark; the owner judges the gap and centering, the closed rim with the vapor behind the pill, the quest tracker's room, the ring discs against the mockup's A | **passed** (70450, Razor Hill, following Glass UI's tint; 2 checks): the pill 9 under the ring and the zone pill 9 over it, the pill at 7 and the zoom at 9 over the runes and vapor at 6, the well shown (PASS); the gap and centering, the closed rim with the vapor behind the pill, the quest tracker's room, all fine on bright and dark ground (owner). The ring discs: placed and shown (PASS), they hover, but "zoom no" (the map was at its closest zoom, 5, where + does nothing: `zoomring` tells) and "they don't fade after a while like the stock ones": now they do |
| `zoomring` (#42) | the zoom discs on the ring with the map's zoom at the middle: faded with the mouse away (alpha 0, a shot), the owner judges the fade in and out; - then + clicked, each changing the zoom (what's under the mouse logged; `/fp mm focus` if a click does nothing) | **passed** (70450, Razor Hill; 3 of 4 checks): on the ring and shown; faded to alpha 0 with the mouse away (the shot: no discs); the fade in and out right (owner); - clicked, zoom 2 to 1 with our - disc under the mouse. The + step FAILed on a second click of - 1.7 s later (zoom 0, our - disc under the mouse): the clicks reach our discs, so the earlier "zoom no" was + at the closest zoom, where it does nothing |
| `instance` (#21) | in a dungeon or raid, once loading has finished: the disc shows the shown Blizzard flag's size, the flag faded; the tooltip shot; outside, no disc | **passed** (70374), Ragefire Chasm: "5" from Blizzard's Default flag (alpha 0), tooltip matched (owner); outside, no disc. **Pills placement (#27, rev 3): passed**, below |

`wash`, `mail` and `suite` change the tint and zoom: they save both first (`MinimapProbeDB.restore`,
never overwritten while one is outstanding; the tint by its source, the player's own or none, #37)
and put them back at the end. After a Stop or a relog,
`/fp mm restore` does it. `/fp mm glass` and `/fp mm discs` read the same state on demand.

Run on 1.60.1.70374, 2026-10-15 (`wash`, `mail` on one character; `instance` on another). No
blocked or forbidden actions in ForeverProbe's log.
- **The smoked sheen, measured on the shots:** down the zone pill (left of the zone name), the
  brightness falls 36 grey levels from top to bottom in clear and 29 in smoked. That ratio, 0.8,
  is the designed 0.14 / 0.18 (0.78). Smoked's darker body (about 13 levels darker on the pill)
  is what the eye sees; the softer sheen alone is too subtle to tell by eye at this size.
- **Tooltips weren't in the delayed shots.** The owner saw both tooltips (the mail sender; the
  instance's type and size), but neither 3 s shot shows one. The later runs' shots do (below), so
  screenshots taken this way can include tooltips; why these two missed them (they hovered the ring
  discs, the later runs the pills) remains unmeasured.
- The instance disc's "5" is small at 90°, but readable.

The pills placement (#27), `instance` at rev 3, on 1.60.1.70374, 2026-10-15, Ragefire Chasm:
- Inside: the coords pill reads "Dungeon · 5" in gold, well inside the pill; no disc; the flag
  faded. "Raid · 40" is shorter, so it fits too (no raid access to see it).
- The tooltip on the pill: Blizzard's "Dungeon / 5 Player", in the delayed shot this time.
- Unread mail at the time: the envelope sat in the zone pill beside "Ragefire Chasm", the name
  still whole.
- Outside: the pill back to coordinates (52.1, 49.4) in their colour.

`mail` at rev 3, pills placement, same day, Cleft of Shadow: **passed**. The envelope shown
(`HasNewMail()` true), no disc, Blizzard's icon alpha 0, one sender readable; the envelope easy to
read in clear, smoked and class (owner, and the shots); its tooltip, "Unread mail from:" and the
sender, caught in the delayed shot, above the zone pill.

Not seen yet: a long zone name beside the envelope, the switch to "On the ring" in game.

## In-game checklist

- [ ] Each theme (clear, smoked, class) next to the mockup; `/gmm theme <name>` repaints live.
- [ ] Rotate Minimap on and off: stock compass art stays hidden, the north tab orbits, the mask is round.
- [ ] Edit Mode: move and scale the minimap; the ring, pills and discs follow.
- [ ] Zone change and PvP colour; coordinates in an instance (dash); zoom limits, wheel and buttons agree.
- [ ] Tracking: every toggle matches Blizzard's menu (right-click on the magnifier); Uncheck All;
      a spell tracking (Find Herbs) toggled.
- [ ] Drawer: LibDBIcon buttons plus compartment-only addons (Gnomesweeper), no duplicates;
      left and right clicks reach both kinds; an addon removing its compartment entry.
- [ ] **Taint pass:** open Edit Mode, move and scale the minimap, toggle rotation, close Edit
      Mode; then action bars and macros in combat. No "blocked/forbidden action" errors
      (BugSack / scriptErrors), and `/gmm failures` empty.
- [ ] With Glass MiniMap Bar 1.1: the bar opens from the bottom-left disc (hover and click), its own
      minimap button stays hidden, the disc shows the last button used, the bar follows each theme;
      `/reload` and Edit Mode keep it so. Without it: no disc, Blizzard's AddOns button untouched.

## Issue #8: runic mode

Owner-approved defaults: **off**, with **Glowing / Sway / Vapor On / 100% glow
intensity / 100% orbit speed** when first enabled. The existing glass theme
remains independent (clear by default). Mode and all choices now persist.

Open `/gmm options` (or `/gmm runes`). Enable **Runic mode** to reveal style,
motion, vapor, intensity, and speed controls. Disabling hides these controls,
stops all rune/vapor animation, and retains the saved choices for next time.
Theme selection uses the existing Clear/Smoked/Class controls on the same page.
The development preview window has been replaced by these shipping settings.

- Stationary base: 28 etched glyphs, always visible while runic mode is on.
- Moving overlay: 16 sparse glyphs, without dots or bounding circles.
- Glowing style adds a glyph halo and irregular rim bloom that travels with
  the moving overlay. Etched style retains crisp strokes without additive light.
- Sway: +4 degrees over two seconds, then -4 over two seconds, eased at both
  ends. Explicit return replaced BOUNCE after the owner reported a visible reset.
- Orbit: one turn in 30 seconds at 100% speed. Range 25-200%; 50% takes 60
  seconds and 200% takes 15. The native speed multiplier changes pace in place
  without stopping the orbit or resetting its angle.
- Glow intensity: 0-100%, independent of the stationary engraving and vapor.
- Vapor: independent, soft wisps outside the ring, up to 18 UI pixels out,
  drifting once every 80 seconds.
- Effects use the current theme tint's hue, normalized for emitted light, with
  the theme's wash controlling strength. Clear is neutral white; smoked and
  class glass follow their material presets. Missing class tint falls back to white.
- All animation is native; rune effects add no per-frame Lua or ticker.
- Disabled mode builds no rune frames or textures. Enabling builds the effects
  separately from core startup; render errors are recorded without blocking
  the minimap, and saved choices remain usable even when rendering fails.
- Failed enables show an unavailable message in chat and in the settings pane.
  Later settings/visibility updates retry using the existing frames, textures,
  and animations, including partial builds. No mode toggle is required.
- Intensity and speed use the sliders' five-percent steps for commands and saved
  settings too; for example, speed 33 is normalized and reported as 35%.

Textures changed during development: restart the client after deployment.
Subsequent Lua-only updates need `/reload`. Commands remain available through
`/gmm help`, including `/gmm runes status` for playback diagnostics.

### Visual evidence and remaining live checks

Owner confirmed motion and changing animation progress. The reference video
(2026-10-14 18-12-52) showed travelling bright patches rather than uniform rim
light; bloom now uses uneven sectors. Owner requested a stationary etched base
and fewer bright moving glyphs, then selected the defaults above from the preview.
The square pattern previously seen inside the map persisted with the addon off.
These owner visual passes were on 2026-10-14; the client build was not captured.
They are visual feedback rather than build-stamped probe results. Record the
build from `/gmm version` for the remaining live checks below.

- [ ] Fresh settings: runic mode off; enabling gives the approved defaults.
- [ ] Settings controls appear/disappear with mode; all choices survive reload.
- [ ] Disable/re-enable retains choices; off/hidden state stops all animations.
- [ ] Both styles and motions work with all themes, with vapor on and off.
- [ ] Zero glow leaves stationary engraving; orbit speed leaves sway/vapor alone.
- [ ] Dragging orbit speed changes pace smoothly with no visible reset.
- [ ] Moving glyphs and bloom remain aligned; sway returns without a jump.
- [ ] No light or vapor leaks onto the map centre or obscures control interactions.
- [ ] Edit Mode 80%, 100%, 120% and rotating minimap keep layout and motion correct.
- [ ] Settings layout fits at the owner's UI scale; sliders and buttons update live.
- [ ] `/gmm failures` empty, no blocked actions after Edit Mode and during combat.

## Measured

1.60.1.70374 (owner's run, 2026-10-13), Glass MiniMap's first deploy:
- `MinimapContainer` is 253×253 (Camelot\Skin.lua sizes it to the frame atlas), not the XML's
  215×226; the cluster 273×279.5. Our frames anchor to `Minimap` (198×198), so nothing depends on it.
- The clock (`TimeManagerClockButton`) hidden (the player's setting); the mail indicator
  (`IndicatorFrame`) shown, 20×15; the instance difficulty at level 11.
- `AddonCompartmentFrame` is MEDIUM strata, level 2.
- Tracking (P3), index: name (filterID or spell, subType, in OPTIONAL_FILTERS):
  1 Find Herbs (spell 2383, -1); 2 Auctioneer (1, 2, yes); 3 Banker (2, 2, yes); 4 Banker
  (4194304, 2); 5 Barber (262144, 2); 6 Battlemaster (4, 2, yes); 7 Flight Master (8, -1, yes);
  8 Food & Drink (16, 2); 9 Innkeeper (32, 2, yes); 10 Item Upgrade (524288, 2); 11 Mailbox
  (64, 2, yes); 12 Class Trainer (8388608, 2, yes); 13 Profession Trainers (128, 2, yes);
  14 Reagents (256, 2); 15 Repair (512, 2, yes); 16 Stable Master (2048, 2, yes);
  17 Transmogrifier (4096, 2); 18 Low-Level Quests (1024, -1, yes); 19 Account Completed Quests
  (2097152, -1, false); 20 Points of Interest (8192, -1); 21 Target (16384, -1); 22 Focus Target
  (32768, -1); 23 Track Quest POIs (65536, -1); 24 Track Digsites (131072, -1).
  The glass menu lists the same 13 as Blizzard's (12 optional + Find Herbs).
- `/fp mm near` threw on a FontString with a **secret position** (another addon's glass text, a
  unit name): positions can be secret on this client. Fixed in the probe (#7). Its second run threw
  on a frame's **IsVisible** being a secret boolean (a unit aura frame): visibility can be secret
  too. Fixed.
- First look (owner's screenshot): the ring, notch, pills and sun disc render; the coords pill
  hung below the cluster onto the quest tracker's header (moved up into the ring's edge); Glass
  MiniMap Bar's start stopped before collecting the minimap buttons (most likely the same secret
  answers, from `IsProtected`/sizes: Spotnick2/GlassMiniMapBar#26 now skips secrets).
