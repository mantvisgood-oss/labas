-- RoadNetwork (ModuleScript in ReplicatedStorage)
-- One place that describes every road in the map. RoadBuilder (server) turns it
-- into parts, GpsClient uses it for routing. Everything here is flat (X/Z); Y is ignored.

local RoadNetwork = {}

---------------------------------------------------------------- settings
RoadNetwork.ROAD_WIDTH = 40          -- studs, edge to edge (two lanes)
RoadNetwork.GRID = { -1500, -900, -300, 300, 900, 1500 } -- street positions on X and Z
RoadNetwork.METERS_PER_STUD = 0.28   -- Roblox standard; match the speedometer in VanClient

-- Street names. Columns run north-south (constant X), rows run east-west (constant Z).
-- The outer square is the ring road.
local COLUMN_NAMES = { "Ring Rd", "Oak St", "Maple St", "Main St", "Pine St", "Ring Rd" }
local ROW_NAMES = { "Ring Rd", "1st Ave", "2nd Ave", "Central Ave", "4th Ave", "Ring Rd" }
local LIMITS = { ["Ring Rd"] = 70, ["Harbor Blvd"] = 60 } -- km/h, everything else 50
local DEFAULT_LIMIT = 50

-- Grid segments that are closed ("road works"), so routes are more interesting.
-- Written as {col1,row1, col2,row2} grid indices.
local CLOSED = {
	{ 4, 2, 5, 2 }, -- 1st Ave between Main St and Pine St
	{ 2, 4, 2, 5 }, -- Oak St between Central Ave and 4th Ave
}

---------------------------------------------------------------- types
export type Edge = { a: number, b: number, name: string, limit: number, length: number, ring: boolean }
export type Projection = { edge: number, t: number, point: Vector3, dist: number }
export type Maneuver = { distance: number, kind: string, text: string, street: string }
export type Route = {
	points: { Vector3 },
	cum: { number },          -- distance from start to points[i]
	legStreet: { string },    -- street of leg i (points[i] -> points[i+1])
	legLimit: { number },
	length: number,
	maneuvers: { Maneuver },
	destination: Vector3,
}

---------------------------------------------------------------- build graph
local nodes: { Vector3 } = {}
local edges: { Edge } = {}
local adj: { [number]: { { edge: number, to: number } } } = {}
local nodeAt: { [string]: number } = {}

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function addNode(x: number, z: number): number
	local key = x .. "," .. z
	if nodeAt[key] then
		return nodeAt[key]
	end
	table.insert(nodes, Vector3.new(x, 0, z))
	local id = #nodes
	nodeAt[key] = id
	adj[id] = {}
	return id
end

local function addEdge(a: number, b: number, name: string, ring: boolean)
	local e: Edge = {
		a = a,
		b = b,
		name = name,
		limit = LIMITS[name] or DEFAULT_LIMIT,
		length = (nodes[a] - nodes[b]).Magnitude,
		ring = ring,
	}
	table.insert(edges, e)
	table.insert(adj[a], { edge = #edges, to = b })
	table.insert(adj[b], { edge = #edges, to = a })
end

local function isClosed(c1: number, r1: number, c2: number, r2: number): boolean
	for _, c in CLOSED do
		if (c[1] == c1 and c[2] == r1 and c[3] == c2 and c[4] == r2)
			or (c[1] == c2 and c[2] == r2 and c[3] == c1 and c[4] == r1) then
			return true
		end
	end
	return false
end

do
	local G = RoadNetwork.GRID
	local n = #G
	for c = 1, n do
		for r = 1, n do
			addNode(G[c], G[r])
		end
	end
	for c = 1, n do
		for r = 1, n do
			local here = nodeAt[G[c] .. "," .. G[r]]
			if c < n and not isClosed(c, r, c + 1, r) then
				local ring = (r == 1 or r == n)
				addEdge(here, nodeAt[G[c + 1] .. "," .. G[r]], ROW_NAMES[r], ring)
			end
			if r < n and not isClosed(c, r, c, r + 1) then
				local ring = (c == 1 or c == n)
				addEdge(here, nodeAt[G[c] .. "," .. G[r + 1]], COLUMN_NAMES[c], ring)
			end
		end
	end
	-- Diagonal boulevard from the south-west corner to the north-east corner.
	for i = 1, n - 1 do
		local a = nodeAt[G[i] .. "," .. G[n - i + 1]]
		local b = nodeAt[G[i + 1] .. "," .. G[n - i]]
		addEdge(a, b, "Harbor Blvd", false)
	end
end

RoadNetwork.nodes = nodes
RoadNetwork.edges = edges
RoadNetwork.adj = adj

-- World-space bounds of the network (for the overview map).
do
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, p in nodes do
		minX, maxX = math.min(minX, p.X), math.max(maxX, p.X)
		minZ, maxZ = math.min(minZ, p.Z), math.max(maxZ, p.Z)
	end
	local w = RoadNetwork.ROAD_WIDTH
	RoadNetwork.bounds = { minX = minX - w, maxX = maxX + w, minZ = minZ - w, maxZ = maxZ + w }
end

---------------------------------------------------------------- geometry helpers
local function projectOnSegment(p: Vector3, a: Vector3, b: Vector3): (number, Vector3, number)
	local ab = b - a
	local lenSq = ab.X * ab.X + ab.Z * ab.Z
	local t = 0
	if lenSq > 0 then
		t = math.clamp(((p.X - a.X) * ab.X + (p.Z - a.Z) * ab.Z) / lenSq, 0, 1)
	end
	local q = Vector3.new(a.X + ab.X * t, 0, a.Z + ab.Z * t)
	local dx, dz = p.X - q.X, p.Z - q.Z
	return t, q, math.sqrt(dx * dx + dz * dz)
end

-- Nearest point on any road to a world position.
function RoadNetwork.project(pos: Vector3): Projection
	local best: Projection = { edge = 1, t = 0, point = nodes[edges[1].a], dist = math.huge }
	for i, e in edges do
		local t, q, d = projectOnSegment(pos, nodes[e.a], nodes[e.b])
		if d < best.dist then
			best = { edge = i, t = t, point = q, dist = d }
		end
	end
	return best
end

-- Which street is closest to this position (for the "current street" label).
function RoadNetwork.streetAt(pos: Vector3): (string?, number?, number)
	local p = RoadNetwork.project(pos)
	local e = edges[p.edge]
	if p.dist > RoadNetwork.ROAD_WIDTH then
		return nil, nil, p.dist
	end
	return e.name, e.limit, p.dist
end

local function edgeBetween(a: number, b: number): Edge?
	for _, link in adj[a] do
		if link.to == b then
			return edges[link.edge]
		end
	end
	return nil
end

---------------------------------------------------------------- maneuvers
local function classify(d1: Vector3, d2: Vector3): (string, string)
	local l1 = math.sqrt(d1.X * d1.X + d1.Z * d1.Z)
	local l2 = math.sqrt(d2.X * d2.X + d2.Z * d2.Z)
	local dot = (d1.X * d2.X + d1.Z * d2.Z) / (l1 * l2)
	local angle = math.deg(math.acos(math.clamp(dot, -1, 1)))
	-- In Roblox X is east and Z is south, so a positive cross means a right turn.
	local cross = d1.X * d2.Z - d1.Z * d2.X
	local side = if cross > 0 then "right" else "left"
	if angle < 25 then
		return "straight", "Continue"
	elseif angle < 65 then
		return "slight_" .. side, "Keep " .. side
	elseif angle < 155 then
		return side, "Turn " .. side
	else
		return "uturn", "Make a U-turn"
	end
end

local function buildRoute(points: { Vector3 }, legStreet: { string }, legLimit: { number }, destination: Vector3): Route
	-- Drop zero-length legs (happens when the start or end is exactly on a junction).
	local P, S, L = { points[1] }, {}, {}
	for i = 2, #points do
		if (points[i] - P[#P]).Magnitude > 0.5 then
			table.insert(P, points[i])
			table.insert(S, legStreet[i - 1])
			table.insert(L, legLimit[i - 1])
		end
	end
	if #P == 1 then -- start and end are the same spot
		table.insert(P, P[1])
		table.insert(S, legStreet[1] or "")
		table.insert(L, legLimit[1] or DEFAULT_LIMIT)
	end

	local cum = { 0 }
	for i = 2, #P do
		cum[i] = cum[i - 1] + (P[i] - P[i - 1]).Magnitude
	end

	local maneuvers: { Maneuver } = {}
	for i = 2, #P - 1 do
		local kind, verb = classify(P[i] - P[i - 1], P[i + 1] - P[i])
		local street = S[i]
		if kind == "straight" then
			if street ~= S[i - 1] then
				table.insert(maneuvers, { distance = cum[i], kind = kind, text = "Continue onto " .. street, street = street })
			end
		else
			local text = if kind == "uturn" then verb else verb .. " onto " .. street
			table.insert(maneuvers, { distance = cum[i], kind = kind, text = text, street = street })
		end
	end
	table.insert(maneuvers, {
		distance = cum[#P],
		kind = "arrive",
		text = "Arrive at destination",
		street = S[#S],
	})

	return {
		points = P,
		cum = cum,
		legStreet = S,
		legLimit = L,
		length = cum[#P],
		maneuvers = maneuvers,
		destination = destination,
	}
end

---------------------------------------------------------------- routing
local UTURN_PENALTY = 300 -- studs; makes the GPS prefer routes that don't turn you around

-- Shortest route along the roads. `heading` (optional) is the direction the car faces,
-- used to avoid routes that start with a U-turn.
function RoadNetwork.findRoute(fromPos: Vector3, toPos: Vector3, heading: Vector3?): Route
	local s = RoadNetwork.project(fromPos)
	local d = RoadNetwork.project(toPos)
	local se, de = edges[s.edge], edges[d.edge]
	local sA, sB = nodes[se.a], nodes[se.b]

	local function penalty(target: Vector3): number
		if not heading or heading.Magnitude < 1e-3 then
			return 0
		end
		local dir = target - s.point
		if dir.X * heading.X + dir.Z * heading.Z < 0 then
			return UTURN_PENALTY
		end
		return 0
	end

	-- Same road: drive straight there (unless that means turning around and a loop is shorter,
	-- which we don't bother with on a map this size).
	if s.edge == d.edge then
		return buildRoute({ s.point, d.point }, { se.name }, { se.limit }, d.point)
	end

	-- Dijkstra over junctions (the network is tiny, so a simple O(n^2) version is plenty).
	local dist: { [number]: number } = {}
	local prev: { [number]: number } = {}
	local done: { [number]: boolean } = {}
	for id in nodes do
		dist[id] = math.huge
	end
	dist[se.a] = math.min(dist[se.a], s.t * se.length + penalty(sA))
	dist[se.b] = math.min(dist[se.b], (1 - s.t) * se.length + penalty(sB))

	while true do
		local u, best = nil, math.huge
		for id, dv in dist do
			if not done[id] and dv < best then
				u, best = id, dv
			end
		end
		if not u then
			break
		end
		done[u] = true
		for _, link in adj[u] do
			local nd = best + edges[link.edge].length
			if nd < dist[link.to] then
				dist[link.to] = nd
				prev[link.to] = u
			end
		end
	end

	local viaA = dist[de.a] + d.t * de.length
	local viaB = dist[de.b] + (1 - d.t) * de.length
	local last = if viaA <= viaB then de.a else de.b

	local chain = {}
	local cur: number? = last
	while cur do
		table.insert(chain, 1, cur)
		cur = prev[cur]
	end

	local points, streets, limits = { s.point }, { se.name }, { se.limit }
	for i, id in chain do
		table.insert(points, nodes[id])
		if i < #chain then
			local e = edgeBetween(id, chain[i + 1]) :: Edge
			table.insert(streets, e.name)
			table.insert(limits, e.limit)
		end
	end
	table.insert(points, d.point)
	table.insert(streets, de.name)
	table.insert(limits, de.limit)

	return buildRoute(points, streets, limits, d.point)
end

---------------------------------------------------------------- following a route
-- Where along the route the car is. Returns distance travelled along the route,
-- how far the car is from the route line, the leg index, and how far into that leg.
function RoadNetwork.trackProgress(route: Route, pos: Vector3): (number, number, number, number)
	local bestD, bestProgress, bestLeg, bestInto = math.huge, 0, 1, 0
	local P = route.points
	for i = 1, #P - 1 do
		local t, _, d = projectOnSegment(pos, P[i], P[i + 1])
		local legLen = route.cum[i + 1] - route.cum[i]
		-- Small bias towards later legs so junctions don't flicker back.
		if d < bestD - 0.01 or (math.abs(d - bestD) <= 0.01 and i > bestLeg) then
			bestD, bestProgress, bestLeg, bestInto = d, route.cum[i] + t * legLen, i, t * legLen
		end
	end
	return bestProgress, bestD, bestLeg, bestInto
end

-- Seconds left, assuming the car drives at about 80% of each road's speed limit.
function RoadNetwork.timeRemaining(route: Route, leg: number, intoLeg: number): number
	local mps = RoadNetwork.METERS_PER_STUD
	local total = 0
	for i = leg, #route.points - 1 do
		local len = route.cum[i + 1] - route.cum[i]
		if i == leg then
			len -= intoLeg
		end
		local speed = route.legLimit[i] * 0.8 / 3.6 -- m/s
		total += math.max(len, 0) * mps / speed
	end
	return total
end

function RoadNetwork.formatDistance(studs: number): string
	local m = studs * RoadNetwork.METERS_PER_STUD
	if m >= 1000 then
		return string.format("%.1f km", m / 1000)
	elseif m >= 100 then
		return string.format("%d m", math.floor(m / 10 + 0.5) * 10)
	end
	return string.format("%d m", math.max(0, math.floor(m / 5 + 0.5) * 5))
end

return RoadNetwork
