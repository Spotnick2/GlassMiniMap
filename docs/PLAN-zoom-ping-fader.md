# Plan: auto zoom-out, who pinged, the fader (#13, #14, #15)

> **#14 dropped (2026-10-22, measured on 70450).** `MINIMAP_PING` is out of an addon's reach on
> this client. `RegisterEvent` refuses it as an unknown event. Blizzard's own minimap takes it
> with `RegisterEventCallback`, and that is protected for addons (`ADDON_ACTION_FORBIDDEN`). Its
> documentation also flags it `SecretPayloads`. So §2 below is history, and `Ping.lua` was
> removed before the merge. The converted API dump drops the `CallbackEvent` flag, which is
> how the plan and its review missed it.

Three features, each a setting **on by default** (the owner, 2026-10-21), and one probe
procedure that also closes what #2 still has open. Client 1.60.1.70450, Lua 5.1.

## 0. Shared: hover (`Hover.lua`)

All three need "is the mouse over the minimap", and the ring zoom discs already poll it
(`Footer.lua`, `fadeTick`, #42). One module owns it:

- One unnamed frame, one `OnUpdate`, throttled to 0.05 s. Never hooks Blizzard's frames.
- **Over** when the mouse is over any of these:
  - **the ring, as a circle:** the cursor within the ring's outer radius of its centre
    (`GetCursorPosition` / the host's effective scale against `host:GetCenter()`). The host
    is a square, and its corners must not count (Codex, round 1). The ring zoom discs'
    fade today uses the square; it moves to the circle with the rest;
  - our pills, the north tab, our discs (sun, drawer, mail, instance, the zoom buttons, the
    queue backing), each by `IsMouseOver`, **only while it is visible**: a hidden piece
    never counts. The zoom discs at alpha 0 are still visible, so they still count, which
    keeps "hover their spot to bring them back";
  - our tracking popup (`GlassMiniMapTrackingPopup`) while it is shown.
- **Held** at full opacity: no fading while any of these is true:
  - the tracking popup is shown;
  - Edit Mode is active (`EditModeManagerFrame:IsEditModeActive()`, read with `rawget` and
    `pcall`, as `Queue.lua` does);
  - the drawer's bar is open. Glass MiniMap Bar's public API has no "is open", so this one
    is out of reach: while the mouse is on the bar, the minimap may fade. Noted for GMMB's
    session as a possible API addition, not built here.
- It exposes `Hover.Over()`, `Hover.Held()`, `Hover.Idle()` (seconds since the mouse left)
  and `Hover.OnChange(fn)`.
- The ring zoom discs' fade moves onto it, with the same behaviour as today.

## 1. Auto zoom-out (#13)

- **Setting:** `autoZoomOut` = a delay in seconds, `0` = off. **Default 5** (SexyMap's
  default). Range 0 to 30, step 1, as a slider.
- **What starts the countdown:** `MINIMAP_UPDATE_ZOOM` (no payload, 70450 dump) with
  `Minimap:GetZoom() > 0`. That covers our − / +, the mouse wheel, and any other path. At
  zoom 0 the countdown stops.
- **The countdown runs only while the mouse is away** (`Hover.Idle()`). Zooming in to read
  something and keeping the mouse there never yanks the map out. A new zoom restarts it.
- **When it ends:** `Minimap:SetZoom(0)`, then `Footer.UpdateZoomButtons()`. Our own
  `SetZoom(0)` fires `MINIMAP_UPDATE_ZOOM` too, at zoom 0, so it starts nothing (no guard
  flag needed: zoom 0 stops the countdown).
- **Indoors and outdoors** keep separate zoom levels (the `minimapZoom` and
  `minimapInsideZoom` CVars). Whatever the event reports is what we act on.
- **Implementation:** a timestamp on the Hover tick, not `C_Timer` chains. `deadline =
  now + delay`, and reset while hovered.
- Nothing protected: `Minimap:SetZoom` is a plain widget method; `Footer.Zoom` already
  calls it.
- **Tests:** the countdown after a zoom in; a restart on a new zoom; held while hovered,
  resumed after; off at 0; the wheel path (the event alone); our own zoom-out starts no
  new countdown; `SetZoom` in combat (no protected call).

## 2. Who pinged (#14)

- **Event:** `MINIMAP_PING -> unitTarget, y, x` (70450 dump: **y before x**).
- **Order of checks:** each value goes through `API.Plain` before anything compares it.
  1. The unit token: secret, nil or not a string means nothing is shown. That check comes
     **before** `UnitIsUnit`.
  2. The x and y: plain numbers, or nothing is shown.
  3. `UnitIsUnit(unit, "player")` under `pcall`, its result through `API.Plain`: true means
     it's our own ping, and nothing is shown.
  4. `UnitName(unit)` and `UnitClass(unit)` under `pcall` and `API.Plain`. Another player's
     may be secret on this client; a secret or unreadable name shows nothing.
- **Throttle:** the event fires once per alias ("party1", "target", "focus"...). The same
  unit (`UnitIsUnit`, guarded as above) at the same x, y within one second is the same ping.
  The throttle entry is recorded **only after** a label or a chat line was shown.
- **Class colour:** `API.ClassColor(unit)` gains its unit argument (default `"player"`, so
  today's callers keep it), with the same secret checks. An unreadable class shows the name
  in white.
- **Setting:** `pingName` = `"map"` (default) | `"chat"` | `"off"`.
- **"map":**
  - A small glass pill (`Glass.Apply(f, "small")`, `Theme.Register`): the name in its
    class colour (`API.ClassColor`), the theme's tint.
  - **Placed by the ping:** `GetPingPosition` returns the offset from the map's centre
    divided by the map's width (measured: the porting guide, NodeRadar #28). So the offset
    is `GetPingPosition() * Minimap:GetWidth()`, in the map's own units, and the pill sits
    just above it, clamped inside the map's circle. It's followed while shown (an
    `OnUpdate` only while visible, at most 4 s), since the ping is anchored in the world and
    moves as the player does.
  - It shows 3 s, then an Alpha animation fades it over 1 s. A new ping replaces it.
  - Parented to our container, level `AboveMap(6)` like the discs. Unnamed, mouse off.
- **"chat":** one line in the default chat frame, the name in class colour: `Ping: <name>`.
  This is the setting's purpose (not probe output).
- **Tests:**
  - the event order (y, x);
  - the throttle across aliases;
  - our own ping skipped;
  - a secret name or unit: no label and no error; a secret class only: the name in white;
  - the placement clamped;
  - the fade animation played;
  - chat mode, off mode;
  - a ping during combat.

## 3. The fader (#15)

- **Settings:** `fader` on (default) | off; `faderOpacity` = the opacity while the mouse is
  away, **default 60 %** (range 20 to 100, step 5). Full on hover. Fade 0.25 s, after the
  mouse has been away 1 s (the zoom discs' timing).
- **What fades:** the whole minimap as one piece:
  - **Option A, recommended:** `MinimapCluster.MinimapContainer:SetAlpha(a)`. One call fades
    the map, our glass pieces parented there and other addons' minimap pins alike. **One
    exception:** the queue eye's glass backing is a `UIParent` child (`Queue.lua:105`). It
    takes the same alpha by hand. Blizzard's eye itself (`QueueStatusButton`) is left alone.
    - Edit Mode's selection overlay belongs to the cluster, not the container, so it stays
      readable. The fader is held anyway while Edit Mode is open.
    - `SetAlpha` on a Blizzard frame is not in the UI contract's list (reparent, move,
      hide, resize, reassign). Blizzard never sets or reads the container's, the cluster's
      or the map's alpha (`wow-ui-source`, `forever`: Blizzard_Minimap and Blizzard_EditMode,
      confirmed by Codex). Edit Mode only scales the container.
    - **Not yet proven:** that the container isn't protected, and that changing its alpha
      in combat taints nothing. The probe measures `IsProtected()` and changes the alpha in
      combat (§5) before this ships as a default.
    - The contract gains a line: our one Blizzard alpha is the container's, from the fader
      only, restored to 1 when the fader is off.
  - **Option B:** fade only our frames, leaving the map fully opaque. That doesn't match the
    issue ("the minimap and its glass at a lower opacity").
  - The probe checks A for taint (an Edit Mode pass and combat with the fader on).
- **Composition with the ring zoom discs:** their own fade (0 when idle) multiplies with the
  container's alpha by inheritance, so nothing composes by hand.
- **Off:** the container's alpha back to 1. While the fader is on, `SetAlpha` runs only when
  the target changes (the tick compares).
- **Tests:**
  - the idle opacity after the delay;
  - full on hover over the map, a pill and a disc;
  - held while the tracking popup or Edit Mode is open;
  - off restores 1;
  - the opacity setting applied live;
  - in combat, no protected call.

## 4. The options page

These are three more groups on a page that already overflows. The page moves into a scroll
frame (`UIPanelScrollFrameTemplate`, the recipe's `GlassUnitFrames\Options.lua`) before the new
groups go in. **Every control moves to the scroll child**, which is sized to its content. Today the
controls, the runic group included, are parented and anchored to `panel` (`Options.lua:104, 161`),
so each `heading`, `checkbox`, `radios` and slider takes the scroll child as its parent.

A new section, **"Behaviour"**:
- "Zoom back out after N s (0: never)", a slider;
- "Who pinged": On the map / In chat / Off, as radios;
- "Fade the minimap until hovered", a checkbox, plus "Opacity while away", a slider.

Every setting goes through `GMM.Settings`, saved only when it differs from `DEFAULTS`, with junk
pruned at load. The generic `Settings.Set` takes booleans only, so each new setting gets its own
validated setter:
- `SetAutoZoomOut(seconds)`: whole numbers 0 to 30;
- `SetPingName(where)`: `map`, `chat` or `off`;
- `SetFader(on)`;
- `SetFaderOpacity(percent)`: 20 to 100, step 5.

Each refuses anything else and leaves the setting as it was.

## 5. Probe: `extras` and `checklist`

The owner runs them. Results come from SavedVariables, and screenshots are deleted once
recorded.

**`/fp steps mm extras`** (#13, #14, #15):
1. SAVE: tint, zoom, zoom placement, plus the three new settings.
2. **Fader:** the mouse away 2 s, then Check: the container's alpha is 0.6, the queue
   backing's too, and the container's `IsProtected()` is logged. With a shot.
   - Hover the map: full (asked). Hover a corner of the ring's square, outside the circle:
     not full (asked).
   - Open the tracking menu, move away: still full (check).
3. **Auto zoom-out:** zoom in twice with the wheel, then take the mouse away.
   - Within 5 s the zoom is 0. A `wait` step, checked.
   - Zoom in and keep the mouse on the map 8 s: still zoomed (check). Leave: zoomed out.
   - Optional: zoomed in, walk into a building and out. Log each `MINIMAP_UPDATE_ZOOM` with
     the zoom, to see when this client fires it on the indoor and outdoor switch.
4. **Ping:**
   - The probe pings the map itself (`Minimap:PingLocation(40, 25)`): our own ping, so no
     label (check), and the event's payload logged.
   - The probe shows the label for the player's name at that position (a test hook), with a
     shot. Asked: next to the ping, readable, fading?
   - **A real ping from a second player**, in a group. It's skippable in a run, but it's
     required to sign the feature off: #14 stays open until it passes. The check: the
     label's text is that player's name, and nothing errored.
5. **Taint, with the fader on** (`/console scriptErrors 1` first):
   - Edit Mode: open, move and scale the minimap, close;
   - **a fight with the mouse moving on and off the minimap**, so the container's alpha
     changes in combat;
   - `/gmm failures` empty, and no blocked or forbidden action (asked).
6. RESTORE.

**`/fp steps mm checklist`**, what #2 still has open:
- **P6:** Rotate Minimap on, a shot; off, a shot. The mask is round and fits the ring, and
  the north tab orbits.
- **P7:** Edit Mode minimap scale 80 % and 120 %. At each, `frames` logs the container's and
  the map's size and scale, with a shot: the ring, pills and discs follow.
- **Tracking:** toggle Find Herbs in our menu and confirm in Blizzard's (right-click on the
  magnifier); Uncheck All.
- **Drawer:** a LibDBIcon button and a compartment-only addon (Gnomesweeper) both in the bar,
  no duplicates, left and right clicks reach both.
- **Taint pass:** Edit Mode move, scale, rotate, close; then a fight with action bars and
  macros. No blocked or forbidden action, and `/gmm failures` empty.

The items #2 lists that procedures already cover:
- the themes (`wash`, `suite`);
- the zone and coordinates in an instance (`instance`);
- the zoom limits (`zoomring`);
- Glass MiniMap Bar (`suite`, `edges`).

The runic list belongs to #8, shipped and owner-tested.

## 6. Out of scope

- Show on hover, per piece (#16). The Hover module is its base.
- An "is open" for the drawer: a question for Glass MiniMap Bar's session if it matters in
  game.
