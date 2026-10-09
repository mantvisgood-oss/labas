-- RoadBuilder (Script in ServerScriptService)
-- Builds the road network described in ReplicatedStorage.RoadNetwork when the game starts:
-- asphalt, junctions, lane markings, a concrete barrier around the ring road, and a
-- grass ground under the whole map so you can't fall out of the world.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RoadNetwork = require(ReplicatedStorage:WaitForChild("RoadNetwork"))

---------------------------------------------------------------- look
local ASPHALT_COLOR = Color3.fromRGB(58, 60, 64)
local JUNCTION_COLOR = Color3.fromRGB(62, 64, 68)
local LINE_COLOR = Color3.fromRGB(235, 235, 230)
local CENTER_COLOR = Color3.fromRGB(245, 200, 60)
local BARRIER_COLOR = Color3.fromRGB(190, 188, 182)
local GRASS_COLOR = Color3.fromRGB(92, 140, 70)

local DASH_LENGTH = 10
local DASH_GAP = 14
local MAP_MARGIN = 250 -- grass beyond the ring road

---------------------------------------------------------------- heights
-- Everything sits on top of the Baseplate if there is one.
local baseplate = workspace:FindFirstChild("Baseplate")
local groundY = 0
if baseplate and baseplate:IsA("BasePart") then
	groundY = baseplate.Position.Y + baseplate.Size.Y / 2
end
local ROAD_TOP = groundY + 0.08
local JUNCTION_TOP = groundY + 0.05 -- a hair lower than roads, so they never flicker against each other
local MARK_TOP = groundY + 0.11
local GRASS_TOP = groundY - 0.03    -- a hair below the baseplate

local W = RoadNetwork.ROAD_WIDTH
local nodes, edges, adj = RoadNetwork.nodes, RoadNetwork.edges, RoadNetwork.adj

---------------------------------------------------------------- helpers
local old = workspace:FindFirstChild("Roads")
if old then
	old:Destroy()
end
local folder = Instance.new("Folder")
folder.Name = "Roads"

local function makePart(name: string, parent: Instance, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Paint (lane markings): no collision and invisible to raycasts, so the van's
-- suspension and the camera ignore it.
local function makePaint(parent: Instance, size: Vector3, cf: CFrame, color: Color3)
	local p = makePart("Paint", parent, size, cf, color, Enum.Material.SmoothPlastic)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
end

-- How far roads stop short of a junction so they don't overlap each other.
local function junctionTrim(id: number): number
	local dirs = {}
	for _, link in adj[id] do
		table.insert(dirs, (nodes[link.to] - nodes[id]).Unit)
	end
	local trim = W / 2
	for i = 1, #dirs do
		for j = i + 1, #dirs do
			local alpha = math.acos(math.clamp(math.abs(dirs[i]:Dot(dirs[j])), 0, 1)) -- 0..90 degrees
			if alpha > math.rad(5) then
				trim = math.max(trim, (W / 2) / math.tan(alpha / 2))
			end
		end
	end
	return trim
end

local trims = {}
for id in nodes do
	trims[id] = junctionTrim(id)
end

---------------------------------------------------------------- ground
do
	local b = RoadNetwork.bounds
	local minX, maxX = b.minX - MAP_MARGIN, b.maxX + MAP_MARGIN
	local minZ, maxZ = b.minZ - MAP_MARGIN, b.maxZ + MAP_MARGIN
	local ground = Instance.new("Folder")
	ground.Name = "Ground"
	ground.Parent = folder
	local MAX = 2000 -- parts can't be bigger than 2048 studs
	local nx = math.ceil((maxX - minX) / MAX)
	local nz = math.ceil((maxZ - minZ) / MAX)
	local sx, sz = (maxX - minX) / nx, (maxZ - minZ) / nz
	for i = 0, nx - 1 do
		for j = 0, nz - 1 do
			local cx = minX + sx * (i + 0.5)
			local cz = minZ + sz * (j + 0.5)
			makePart("Grass", ground, Vector3.new(sx, 4, sz), CFrame.new(cx, GRASS_TOP - 2, cz), GRASS_COLOR, Enum.Material.Grass)
		end
	end
end

---------------------------------------------------------------- junctions
do
	local junctions = Instance.new("Folder")
	junctions.Name = "Junctions"
	junctions.Parent = folder
	for id, pos in nodes do
		-- A round pad that covers the corners of every road ending here.
		local radius = math.sqrt(trims[id] ^ 2 + (W / 2) ^ 2)
		local pad = makePart(
			"Junction",
			junctions,
			Vector3.new(1, radius * 2, radius * 2),
			CFrame.new(pos.X, JUNCTION_TOP - 0.5, pos.Z) * CFrame.Angles(0, 0, math.pi / 2),
			JUNCTION_COLOR,
			Enum.Material.Asphalt
		)
		pad.Shape = Enum.PartType.Cylinder
	end
end

---------------------------------------------------------------- roads
for _, e in edges do
	local a, b = nodes[e.a], nodes[e.b]
	local dir = (b - a).Unit
	local trimA, trimB = trims[e.a], trims[e.b]
	local len = e.length - trimA - trimB
	if len <= 0 then
		continue
	end

	local street = folder:FindFirstChild(e.name) or Instance.new("Folder")
	street.Name = e.name
	street.Parent = folder

	local startPos = a + dir * trimA
	local mid = startPos + dir * (len / 2)
	-- Facing along the road: LookVector = dir, RightVector = across the road.
	local base = CFrame.lookAt(Vector3.new(mid.X, 0, mid.Z), Vector3.new(mid.X + dir.X, 0, mid.Z + dir.Z))

	makePart(
		"Road",
		street,
		Vector3.new(W, 1, len),
		base + Vector3.new(0, ROAD_TOP - 0.5, 0),
		ASPHALT_COLOR,
		Enum.Material.Asphalt
	)

	local paintCf = base + Vector3.new(0, MARK_TOP - 0.025, 0)
	local markLen = len - 8
	if markLen > 0 then
		-- Solid edge lines.
		for _, side in { -1, 1 } do
			makePaint(street, Vector3.new(0.6, 0.05, markLen), paintCf * CFrame.new(side * (W / 2 - 1.8), 0, 0), LINE_COLOR)
		end
		-- Dashed centre line.
		local step = DASH_LENGTH + DASH_GAP
		local count = math.floor((markLen + DASH_GAP) / step)
		local used = count * step - DASH_GAP
		for i = 0, count - 1 do
			local z = -used / 2 + DASH_LENGTH / 2 + i * step
			makePaint(street, Vector3.new(0.6, 0.05, DASH_LENGTH), paintCf * CFrame.new(0, 0, z), CENTER_COLOR)
		end
	end

	-- Concrete barrier on the outside of the ring road.
	if e.ring then
		local right = base.RightVector
		local side = if right:Dot(mid) > 0 then 1 else -1
		local barrierLen = e.length + W + 3 -- runs into the corners so there are no gaps
		local edgeMid = (a + b) / 2
		local barrierBase = CFrame.lookAt(Vector3.new(edgeMid.X, 0, edgeMid.Z), Vector3.new(edgeMid.X + dir.X, 0, edgeMid.Z + dir.Z))
		makePart(
			"Barrier",
			street,
			Vector3.new(1.5, 3.5, barrierLen),
			barrierBase * CFrame.new(side * (W / 2 + 1.5), ROAD_TOP + 1.75, 0),
			BARRIER_COLOR,
			Enum.Material.Concrete
		)
	end
end

folder.Parent = workspace
print(string.format("[RoadBuilder] Built %d roads and %d junctions.", #edges, #nodes))
