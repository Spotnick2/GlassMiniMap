# Glass MiniMap public API

For other addons that briefly borrow Blizzard's `Minimap` (move it, shrink it, set its alpha) and
want Glass MiniMap to stay put and quiet meanwhile. First consumer: **NodeRadar**'s scan mode
(NodeRadar#91). On 1.60.1.70862 the minimap's mouseover reads only under the real cursor
(`Minimap:UpdateMouseoverAtPoint` is a no-op, Stanzilla/WoWUIBugs#894), so it moves the map under
the resting cursor for a few frames. Code: `Scan.lua`. Issue: #56.

## Stability

- `GlassMiniMap.PUBLIC_API_VERSION` changes on **any incompatible change** (a function's arguments
  or meaning, a removal). Adding a function doesn't change it. Check it before calling:

  ```lua
  local gmm = rawget(_G, "GlassMiniMap")
  if gmm and gmm.PUBLIC_API_VERSION == 1 and type(gmm.ScanBegin) == "function" then ... end
  ```
- Glass MiniMap loaded **without** `PUBLIC_API_VERSION` is a release from before #56 (v1.0.1 and earlier). Its
  ring is anchored to `Minimap` and travels with a borrowed map, so don't borrow the map then.
- `GlassMiniMap.API` and the other fields of `GlassMiniMap` are internal: not this.
- No function here throws, and all are safe at any time, before or after our `PLAYER_LOGIN`, in
  combat or with Edit Mode open. They touch our own tables, timers and frames only: the first
  `ScanBegin` and the last release re-sync our glass behind the LFG eye (its visibility, scale and
  level), which also keeps Blizzard's tip on the eye clamped to the screen, as it always does (#53),
  and show or start fading our scan face (below).

## Version 1

**What it promises:** nothing of Glass MiniMap's is parented or anchored to `Minimap`. Our frames
are children of `MinimapCluster.MinimapContainer`, and the ring sits on the container's centre,
where Blizzard puts the map. A moved, shrunken or invisible map leaves the ring, the pills and the
discs at home. Nothing reads the map's size or position after our build.

The one exception follows Blizzard: our glass disc behind the LFG eye (`QueueStatusButton`) is
centred on the eye, which Blizzard anchors to `Minimap`. That disc is **hidden while any scan is
under way**, even if the eye shows mid-scan (a queue pop), and comes back with the eye at the end.
Blizzard's eye itself still travels with a borrowed map: that one is yours to handle (check it on
every scan frame, not only at the start).

### `GlassMiniMap.ScanBegin(owner) -> acquired`

A borrow starts. Call it before your first change to `Minimap`. `owner` is a non-empty string,
your addon's name.

- Returns `true` when acquired, including before our build (nothing of ours exists yet to travel).
- Returns `false` only for a bad `owner`, or if the function failed inside. There is no transient
  refusal: no combat, Edit Mode or menu gating. The borrower gates those.
- Calling it again for an owner already active returns `true` and restarts that owner's timeout.
  One `ScanEnd` clears it.

### `GlassMiniMap.ScanEnd(owner)`

The borrow ended. Call it once after any `ScanBegin`, whatever happened. It's idempotent: a second
call, one without a `ScanBegin`, or one after the timeout does nothing.

### `GlassMiniMap.ScanStandIn() -> drawn`

Added in 1.2.0, still version 1 (feature-detect it with `type(gmm.ScanStandIn) == "function"`).
`true` when Glass MiniMap draws its own stand-in over the map's spot (the scan face, below) for a
scan begun now. Ask it before each `ScanBegin`, since the answer changes:

- `true` only when the player chose NodeRadar's radar look: `NodeRadar.ScanFace.RadarLook()` returns
  `true` (NodeRadar's `scanRadar` option, off by default; a NodeRadar without `RadarLook`, or none,
  counts as no). Otherwise `false`, and the borrower draws its own stand-in: NodeRadar draws the
  minimap's real ground where it can, its radar face elsewhere (the owner, 2026-11-12);
- latched per borrow: the answer at the first `ScanBegin` holds until the last release, and our
  face follows the same answer, whatever the player toggles meanwhile. The next borrow reads it
  again;
- `false` before our build (`PLAYER_LOGIN`), and if the build failed (`/gmm failures`: `scan face`,
  for example new art before a client restart);
- `false` while a scan that began before our build is still under way: that scan keeps the stand-in
  it chose, and ours starts with the next one.

`true` doesn't promise a face on screen: none shows while Blizzard's toggle hides the map. A
borrower that draws its own stand-in draws it unless this returns `true`:

| Glass MiniMap | Your stand-in |
|---|---|
| not loaded | yours |
| version 1 with `ScanStandIn`, returns `false` | yours |
| version 1 with `ScanStandIn`, returns `true` | none: ours shows |
| version 1 without `ScanStandIn` (1.1.0) | yours (1.1.0 draws none) |

### The timeout

If an owner's `ScanEnd` doesn't come within **1 s** of its last `ScanBegin`, Glass MiniMap ends that
owner's scan itself and records it (`/gmm failures`: `scan:<owner>`).

### While any scan is under way

- The **auto zoom-out** countdown is paused (not restarted), so our `Minimap:SetZoom(0)` never
  lands mid-scan. It resumes with what was left.
- Our glass behind the LFG eye is hidden (above).
- **The scan face** (#59, from 1.2.0), when `ScanStandIn` said `true`, covers the map's spot: a
  dark round radar the map's resting size, with range rings and a sweep turning clockwise once per 1.2 s, in our glass's tint. It shows
  in the first `ScanBegin` call itself, one level above the map (under our ring's rim, the north tab,
  the pills and the discs), mouse off, and takes the fader's alpha. After the last release it stays
  0.4 s over the returned map, then fades over 0.2 s; a `ScanBegin` meanwhile brings it back to
  full, so a run of scans reads as one ping. Only over a visible map: a hidden map (or container)
  removes it at once.
- Nothing else changes. With the ring at home, hover and the fader see only the real cursor.
- A scan under way when our ring is built (before our `PLAYER_LOGIN`) doesn't size it: the ring is
  built at the map's resting size.

Glass MiniMap sets `MinimapContainer`'s alpha (the fader), never `Minimap`'s. Leave the container
alone. Save and restore `Minimap`'s own state. A stand-in of yours outside the container should take
the map's effective alpha at home, read before you move it, or a faded minimap flashes opaque at
each look.

### For your own stand-in

- **The shape.** From 1.2.0 Glass MiniMap declares the global `GetMinimapShape` (returning
  `"ROUND"`, LibDBIcon's convention) at its `PLAYER_LOGIN`, unless another addon declared one first.
  Our map keeps Blizzard's round mask.
- **The stacking.** Everything of ours over the map's edge (the runes and their bloom and fog, the
  north tab, the pills, the discs) is at least two levels above `Minimap`, so a stand-in at
  `MinimapBackdrop`'s strata and level (the map's + 1) draws under it. The ring's glass is under
  the map.
