# Roads + Waze-style GPS

Five scripts. Each file in this folder goes into Roblox Studio at the place named below.
The script names must match exactly.

| File | Where in Studio | Type |
|---|---|---|
| `ReplicatedStorage/RoadNetwork.luau` | ReplicatedStorage → **RoadNetwork** | ModuleScript |
| `ReplicatedStorage/GpsUI.luau` | ReplicatedStorage → **GpsUI** | ModuleScript |
| `ServerScriptService/RoadBuilder.server.luau` | ServerScriptService → **RoadBuilder** | Script |
| `ServerScriptService/GpsScreenSetup.server.luau` | ServerScriptService → **GpsScreenSetup** | Script |
| `StarterPlayerScripts/GpsClient.client.luau` | StarterPlayer → StarterPlayerScripts → **GpsClient** | LocalScript |

## How to install

1. In the Explorer, hover over **ReplicatedStorage**, click **+**, and add a **ModuleScript**.
   Rename it `RoadNetwork`, delete the default text, and paste in the file. Do the same for `GpsUI`.
2. Add the two **Script**s to **ServerScriptService** the same way.
3. Add the **LocalScript** to **StarterPlayer → StarterPlayerScripts**.
4. Move the van onto a road. The streets run along X or Z = ±300, ±900 and ±1500.
   For example, put it at position `300, <height>, 0` to start on Main St.
5. Press Play.

## What you get

**Roads (built when the game starts)**
- A 6 × 6 grid of streets, 3000 studs across: Oak St, Maple St, Main St, Pine St,
  1st/2nd/Central/4th Ave, plus a **Ring Rd** around the outside and a diagonal **Harbor Blvd**.
- Asphalt, round junction pads, white edge lines and a yellow dashed centre line.
- Two closed sections ("road works") so the GPS has to route around them.
- A concrete barrier around the ring road, and grass under the whole map, so you can't
  drive off the edge of the world any more.

**GPS (Waze-style)**
- **M** opens the city map. Click any road to set a destination. Hover a road to see
  its name. **Let's go! [M]** closes the map, and **Clear route** removes the route.
- The **dashboard screen** (the mini TV) shows:
  - the next turn arrow, the distance to it, and "Turn right onto Pine St"
  - the blue route line, on a dark map that turns with the van and zooms out as you speed up
  - your speed in a bubble that turns **red** when you're over the limit, next to the
    speed limit sign (Ring Rd 70, Harbor Blvd 60, other streets 50)
  - the current street name
  - minutes left, distance left and arrival time
- If you go the wrong way, it says **Recalculating...** and finds a new route.
- **You have arrived!** shows at the destination.
- In **third person (V)**, the same screen also appears in the bottom-right corner.
- A **Map [M]** button is there for touch screens.

## Settings to tweak

| What | Where |
|---|---|
| Screen position on the dashboard | `SCREEN_OFFSET` in **GpsScreenSetup** (X = right, Y = up, negative Z = forward) |
| Screen size | `SCREEN_SIZE` in **GpsScreenSetup** |
| Your own screen part | Put a Part named `GPSScreen` in the van, with its front face towards the driver and welded to the van. The script will use it instead. |
| Screen brightness / sharpness | `SCREEN_BRIGHTNESS`, `SCREEN_PIXELS_PER_STUD` in **GpsClient** |
| Map key | `MAP_KEY` in **GpsClient** |
| Road width, street layout, names, closed roads | top of **RoadNetwork** |
| km/h conversion | `METERS_PER_STUD` in **RoadNetwork** (0.28 is the Roblox standard). If the GPS speed doesn't match the van's speedometer, set this to the same value VanClient uses. |
