# Glass MiniMap

A liquid-glass minimap for **World of Warcraft: Forever**.

![The look (mockup)](https://raw.githubusercontent.com/Spotnick2/GlassMiniMap/main/docs/mockups/glass-minimap.png)

- **A glass ring** around the map, with a north tab that follows north when the minimap rotates.
- **Clear, smoked or class-coloured glass**, switched live.
- **Zone pill**: the zone name in Blizzard's PvP colours (click for the world map), a magnifier for
  tracking, and today's calendar page with your pending invites.
- **Glass tracking menu**: the same entries as Blizzard's menu, in glass. Right-click the magnifier
  for Blizzard's own.
- **Coordinates pill** with zoom buttons.
- **Day and night disc**: a sun or a moon, with the server and local time. Click it for the clock.
- **Addon drawer**: the disc at the bottom left opens a glass drawer with your addons' minimap
  buttons and Blizzard's AddOns list, in one place. Hover or click to open; hide, show and reorder
  buttons in the options.

It's a reskin: Blizzard's minimap keeps working underneath, so **Edit Mode** still moves and scales
it, and everything glass follows.

## Commands

- `/gmm theme clear|smoked|class`: the glass
- `/gmm coords on|off`, `/gmm sun on|off`
- `/gmm drawer`: open the addon drawer
- `/gmm scan`: look for minimap buttons again, and list them
- `/gmm options`: Esc > Options > AddOns > Glass MiniMap

## Coming from Glass MiniMap Bar

Glass MiniMap Bar is now part of Glass MiniMap. Log in once with both enabled: your bar settings
(hidden buttons, order, layout) are copied into the drawer. Then disable Glass MiniMap Bar and
`/reload`. While both are enabled, the drawer stays off so the two don't fight over the buttons.

## Licence

GPLv3 (the drawer's button collector adapts HidingBar's technique). The embedded LibGlass-1.0 is
MIT. See [LICENSE](LICENSE).
