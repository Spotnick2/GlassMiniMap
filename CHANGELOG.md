# Changelog

## Unreleased

- **The sun and moon stand out on bright ground**: the day/night disc (and the instance size's)
  gets a dark well under its glyph, as an addon icon has. Over a desert they used to fade out.
- **The ring stays a closed circle**: the coordinates pill now tucks behind the ring's bottom
  edge instead of cutting into it.

## v0.2.0

Released 2026-10-15.

- **Optional runic mode**, off by default: stationary etched runes beneath a
  sparse moving layer, with glowing/etched styles, sway/orbit motion, exterior
  vapor, glow intensity, and orbit speed. Enable it in the settings dialog to
  reveal its controls. Defaults are Glowing, Sway, Vapor On, and 100% intensity
  and speed. All choices persist and follow clear, smoked, or class-colour glass.
- **New mail shows as an envelope in the zone pill**, by the zone name, with the latest senders on
  hover. Blizzard's mail icon used to float over the zone pill.
- **The instance size shows in the coordinates pill** in dungeons and raids, where there are no
  coordinates: "Dungeon · 5", "Raid · 40", with Blizzard's tooltip. It shows even with Blizzard's
  coordinates turned off. Blizzard's instance flag used to float over the zone pill.
- **Or both as glass discs on the ring**: Options > AddOns > Glass MiniMap, "New mail and the
  instance's size".
- **Smoked glass gets its softer top sheen**, as designed: the game ignored the setting, so smoked
  surfaces drew the clear glass's brighter sheen. Uses LibGlass r7.

## v0.1.1

Released 2026-10-14.

- **The LFG eye moves to the top left of the ring**, mirroring the day and night disc, with a
  glass disc behind it in the minimap's glass. It used to sit on the addon drawer's disc at the
  bottom left while you were queued. If you've placed the eye yourself in Edit Mode, it stays
  where you put it.
- **Coordinates follow Blizzard's own settings**: Options > Interface, "Player Minimap
  Coordinates" and "Coordinates by Tenths", live. Glass MiniMap's two coordinate options and
  `/gmm coords` are gone: if you had turned the coordinates off there, turn off Blizzard's setting
  instead.
- The zone tooltip shows the zone, subzone and territory again.

## v0.1.0

Released 2026-10-14. The first release.

- **The minimap in liquid glass**: a glass ring around the map with a north tab (it follows north
  when the minimap rotates), on LibGlass r6's clean material. Blizzard's own minimap keeps working
  underneath, so Edit Mode still moves and scales it.
- **Three looks**: clear, smoked or class-coloured glass, switched live (`/gmm theme`, or Esc >
  Options > AddOns > Glass MiniMap).
- **Zone pill**: the zone name in Blizzard's PvP colours (click for the world map), the tracking
  magnifier, and today's calendar page with pending invites.
- **Glass tracking menu**: the same entries and rules as Blizzard's menu, in glass. Right-click the
  magnifier for Blizzard's own.
- **Coordinates pill** with zoom − / +, following Blizzard's own "Player Minimap Coordinates" and
  "Coordinates by Tenths" settings.
- **Day and night disc**: a sun or a moon, with server and local time; click for the clock.
- **Addon drawer** with Glass MiniMap Bar 1.1 or later: its glass bar (your addons' minimap buttons
  and Blizzard's AddOns list) opens from the disc at the bottom left of the map and takes on the
  minimap's glass.
