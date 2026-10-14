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
- **Addon drawer** with Glass MiniMap Bar installed: the disc at the bottom left opens its glass
  drawer, with your addons' minimap buttons and Blizzard's AddOns list in one place, in the same
  glass as the minimap.

It's a reskin: Blizzard's minimap keeps working underneath, so **Edit Mode** still moves and scales
it, and everything glass follows.

## Commands

- `/gmm theme clear|smoked|class`: the glass
- `/gmm coords on|off`, `/gmm sun on|off`
- `/gmm options`: Esc > Options > AddOns > Glass MiniMap

## Glass MiniMap Bar

Glass MiniMap Bar is optional and stays its own addon (it works with any minimap). With both
installed, its bar opens from Glass MiniMap's bottom-left disc instead of its own minimap button,
and its settings (`/gmb`) stay yours.

## Licence

MIT, like the embedded LibGlass-1.0. See [LICENSE](LICENSE).
