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

## Known issues / next steps

- Map is only a flat baseplate; driving long enough goes off the edge and falls out of the
  world. Next big step: build the map (roads, depot, delivery houses).
- Package system not built yet (the shelf markers are placeholders for it).
