# Forever probe: Glass MiniMap

What has to be measured on the live client before v0.1.0 ships, and what was found. Deploy with
`pwsh Tools\deploy.ps1 -Probe`, restart the client, then run `/mmprobe` and the checklist below.
Record the build each result was measured on.

## Probe questions (`/mmprobe`)

| # | Question | Command | Result |
|---|---|---|---|
| P1 | What draws the purple "72" above the bottom-left disc (mockup and stock screenshot)? | `/mmprobe near` | open |
| P2 | Are `IngameCalendarDisabled`, `IngameTrackingDisabled`, `MinimapDisabled` active on Forever? | `/mmprobe rules` | open |
| P3 | Which tracking entries does a Vanilla-content character get (filterIDs, spellIDs, subTypes)? | `/mmprobe tracking` | open |
| P4 | What is in `AddonCompartmentFrame.registeredAddons` with the usual addons? | `/mmprobe frames` | open |
| P5 | Where does `QueueStatusButton` sit while queued? Its Edit Mode default is `Minimap` CENTER (-68, -68), the launcher disc's spot (225°). | `/mmprobe queue` while queued | open |
| P6 | Is Blizzard's mask (`ui-hud-minimap-frame-generic-mask`) a clean 198 px circle the ring fits, in both rotation modes? | look, toggle Rotate Minimap | open |
| P7 | `MinimapContainer` scale and size per Edit Mode scale (the ring is sized once and scales with it). | `/mmprobe frames` at 80% / 120% | open |

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
- [ ] Coexistence: with Glass MiniMap Bar enabled, the drawer is off, Blizzard's AddOns button
      works, settings import once; after disabling it, the drawer is on with them.

## Measured

(nothing yet)
