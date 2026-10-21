# Glass MiniMap

A liquid-glass minimap for **World of Warcraft: Forever**.

![The look (mockup)](https://raw.githubusercontent.com/Spotnick2/GlassMiniMap/main/docs/mockups/glass-minimap.png)

- **A glass ring** around the map, with a north tab that follows north when the minimap rotates.
- **Clear, smoked or class-coloured glass**, switched live, in Pearl (the default) or Clean.
- **Glass UI's suite**: with Glass UI, the minimap can follow the suite's glass and tint (its "Use
  Glass UI appearance" switch).
- **Optional runic mode:** stationary engraved runes beneath a moving layer,
  with etched/glowing styles, sway/orbit motion, and exterior vapor. Effects
  follow the glass theme; glow intensity and orbit speed are adjustable.
- **Zone pill**: the zone name in Blizzard's PvP colours (click for the world map), a magnifier for
  tracking, and today's calendar page with your pending invites.
- **Glass tracking menu**: the same entries as Blizzard's menu, in glass. Right-click the magnifier
  for Blizzard's own.
- **Coordinates pill** with zoom buttons at its ends, or on the ring as discs (Blizzard's "Player
  Minimap Coordinates" and "Coordinates by Tenths" settings apply).
- **Zooms back out** on its own 5 seconds after you zoomed in and moved the mouse away (0 to 30
  seconds, or never).
- **Who pinged**: when a group member clicks the minimap, their name shows by the ping in their
  class colour (or in chat, or not at all).
- **Fades until hovered**: the minimap rests at 60 % opacity and comes to full under the mouse
  (or not at all, or another opacity).
- **Day and night disc**: a sun or a moon, with the server and local time. Click it for the clock.
- **New-mail disc** at the bottom right of the ring while you have unread mail, with the latest
  senders on hover.
- **Instance disc** on the right of the ring in dungeons and raids: the group size, 5 to 40.
- **Addon drawer** with [Glass MiniMap Bar](https://www.curseforge.com/wow/addons/glass-minimap-bar) installed: the disc at the bottom left opens its glass
  drawer, with your addons' minimap buttons and Blizzard's AddOns list in one place, in the same
  glass as the minimap.

It's a reskin: Blizzard's minimap keeps working underneath, so **Edit Mode** still moves and scales
it, and everything glass follows.

## Commands

- `/gmm theme clear|smoked|class`: the glass's tint (Glass UI's while the minimap follows it)
- `/gmm material pearl|clean`: the glass itself, after a `/reload`
- `/gmm suite`: whether the minimap follows Glass UI
- `/gmm sun on|off`: the day and night disc
- `/gmm options`: Esc > Options > AddOns > Glass MiniMap
- `/gmm runes on|off`: enable or disable runic mode; `/gmm runes` opens settings

Runic mode is off by default. Enable it in the settings dialog to reveal its
controls. Initial choices are Glowing, Sway, Vapor On, 100% glow intensity, and
100% orbit speed. All choices are saved; disabling the mode keeps your choices.

## Glass MiniMap Bar

Glass MiniMap Bar is optional and stays its own addon (it works with any minimap). With both
installed, its bar opens from Glass MiniMap's bottom-left disc instead of its own minimap button,
and its settings (`/gmb`) stay yours.

## Licence

MIT, like the embedded LibGlass-1.0. See [LICENSE](LICENSE).
