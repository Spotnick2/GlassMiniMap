# Forever probe: Glass MiniMap

What has to be measured on the live client before v0.1.0 ships, and what was found. Deploy with
`pwsh Tools\deploy.ps1 -Probe`, restart the client, then run `/mmprobe` and the checklist below.
Record the build each result was measured on.

## Probe questions (`/mmprobe`)

| # | Question | Command | Result |
|---|---|---|---|
| P1 | What draws the purple "72" above the bottom-left disc (mockup and stock screenshot)? | `/mmprobe near` | **RestedXP's guide step** (owner, 70374): its step pin on the minimap, an unnamed child of `Minimap`. Not ours; left alone |
| P2 | Are `IngameCalendarDisabled`, `IngameTrackingDisabled`, `MinimapDisabled` active on Forever? | `/mmprobe rules` | **all off** (ids 75, 76, 146; WorldMapDisabled 145 and UserAddonsDisabled 29 off too) |
| P3 | Which tracking entries does a Vanilla-content character get (filterIDs, spellIDs, subTypes)? | `/mmprobe tracking` | **24 types**, below |
| P4 | What is in `AddonCompartmentFrame.registeredAddons` with the usual addons? | `/mmprobe frames` | **6**: DBM, AltStableSync, Gnomesweeper, GuildSpy, Leatrix Maps, Leatrix Plus (icons as file paths, one file ID) |
| P5 | Where does `QueueStatusButton` sit while queued? Its Edit Mode default is `Minimap` CENTER (-68, -68), the launcher disc's spot (225°). | `/mmprobe queue` while queued | **default confirmed** (not queued): parent UIParent, CENTER -> Minimap CENTER (-68, -68), 45×45, hidden. Overlap while queued: #4 |
| P6 | Is Blizzard's mask (`ui-hud-minimap-frame-generic-mask`) a clean 198 px circle the ring fits, in both rotation modes? | look, toggle Rotate Minimap | open |
| P7 | `MinimapContainer` scale and size per Edit Mode scale (the ring is sized once and scales with it). | `/mmprobe frames` at 80% / 120% | at 100%: Minimap 198×198, all scale 1 (effective 0.64, the UI scale); other scales open |

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
- `/mmprobe near` threw on a FontString with a **secret position** (another addon's glass text, a
  unit name): positions can be secret on this client. Fixed in the probe (#7). Its second run threw
  on a frame's **IsVisible** being a secret boolean (a unit aura frame): visibility can be secret
  too. Fixed.
- First look (owner's screenshot): the ring, notch, pills and sun disc render; the coords pill
  hung below the cluster onto the quest tracker's header (moved up into the ring's edge); Glass
  MiniMap Bar's start stopped before collecting the minimap buttons (most likely the same secret
  answers, from `IsProtected`/sizes: Spotnick2/GlassMiniMapBar#26 now skips secrets).
