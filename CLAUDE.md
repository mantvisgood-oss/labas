# Project: Roblox delivery van game

Goal: build a Roblox game (with AI help) that can earn money. The core so far is a
delivery van that players drive, with packages loaded from shelves in the trunk.

The game itself lives in a Roblox Studio place file on the user's computer (not in
this repo). Work so far was done in a Cowork chat that controlled Roblox Studio directly.
The place has NOT been published; save it with File → Save to File.

## Done so far

- **Van**: re-imported at 1.35× scale. Trunk inside is ~9.5 wide × 15 long × 10 tall studs
  (room for 3 players).
- **Driving**: physical wheels replaced with a spring suspension + tyre grip model (no jiggle).
  ~69 km/h in 4 s, top speed ~75 km/h. Steering sharper at low speed, calmer at high speed
  (~36°/s at full speed, no sliding). S brakes hard, then reverses. Parking brake holds
  the van when no input. Wheels spin, steer and move with the suspension.
- **Arms (first person)**: player's own avatar arms, half thickness, 80% length; hold the
  steering wheel and grab doors. Tune `ARM_WIDTH` / `ARM_LENGTH` at the top of `VanClient`.
- **Getting in/out**: jumping out is blocked while that seat's door is shut (hint:
  "Open the door to get out"). With the door open, Space exits and lands you beside the door.
- **Shelves**: metal rack on the trunk's right wall, 3 bays: LARGE, MEDIUM, SMALL, each with a
  yellow sign and a front lip, plus an invisible marker for where a package goes later.
- **Speedometer**: lit gauge above the steering wheel, needle 0–120 and digital km/h readout.
- **Seated view**: in either front seat the camera follows the character (not the seat) and is
  lifted ~1.5 studs (eyes ~1.75 m) so the road is visible. Tune `SEATED_VIEW` in `VanClient`
  (middle number = height, currently 0.30).
- **Camera toggle**: V (or right stick on controller) switches first/third person. Third person
  while driving stays ≥30 studs back; on foot it's the normal camera (from 10 studs). Label
  "[V] First person / Third person" bottom-left. Door/seat clicking only works in first
  person (uses the centre dot). Change key with `CAMERA_KEY` in `VanClient`.

## Roads + GPS (written in a cloud session, code in `roblox/`)

- Cloud sessions can't control Roblox Studio, so the scripts live in `roblox/` and the user
  pastes them into Studio. See `roblox/README.md` for where each script goes.
- `RoadNetwork` (shared module): 6×6 street grid (±300/±900/±1500), Ring Rd, diagonal
  Harbor Blvd, 2 closed segments, speed limits, Dijkstra routing, turn instructions,
  progress tracking, ETA. Tested in plain Luau with a Vector3 shim.
- `RoadBuilder`: builds asphalt, junction pads, markings, a ring barrier and grass ground at
  runtime.
- `GpsScreenSetup`: welds a `GPSScreen` part to each vehicle's VehicleSeat (offset is a guess
  and may need tuning).
- `GpsClient` + `GpsUI`: Waze-style nav on the dashboard SurfaceGui, a HUD copy in third
  person, and the M big map where you click to set a destination.
- These have NOT been playtested in Studio yet. Ask the user how it looks.

## Known issues / next steps

- Package system not built yet (the shelf markers are placeholders for it).
- Next ideas: depot + delivery houses as GPS destinations, money, upgrades shop.
