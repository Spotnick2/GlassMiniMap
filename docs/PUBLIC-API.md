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
- Neither function throws, and both are safe at any time, before or after our `PLAYER_LOGIN`, in
  combat or with Edit Mode open. They touch our own tables, timers and frames only: the first
  `ScanBegin` and the last release re-sync our glass behind the LFG eye (its visibility, scale and
  level), which also keeps Blizzard's tip on the eye clamped to the screen, as it always does (#53).

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

### The timeout

If an owner's `ScanEnd` doesn't come within **1 s** of its last `ScanBegin`, Glass MiniMap ends that
owner's scan itself and records it (`/gmm failures`: `scan:<owner>`).

### While any scan is under way

- The **auto zoom-out** countdown is paused (not restarted), so our `Minimap:SetZoom(0)` never
  lands mid-scan. It resumes with what was left.
- Our glass behind the LFG eye is hidden (above).
- Nothing else changes. With the ring at home, hover and the fader see only the real cursor.
- A scan under way when our ring is built (before our `PLAYER_LOGIN`) doesn't size it: the ring is
  built at the map's resting size.

Glass MiniMap sets `MinimapContainer`'s alpha (the fader), never `Minimap`'s. Leave the container
alone. Save and restore `Minimap`'s own state.
