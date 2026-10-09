-- GpsUI (ModuleScript in ReplicatedStorage)
-- Drawing code for the GPS. No game logic here: GpsClient tells it what to show.
--   GpsUI.MapView   - a map of the roads, either heading-up (following the car) or north-up
--   GpsUI.NavScreen - the full Waze-style navigation screen (map + turn banner + speed + ETA)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RoadNetwork = require(ReplicatedStorage:WaitForChild("RoadNetwork"))

local GpsUI = {}

---------------------------------------------------------------- colours (night mode)
local C = {
	background = Color3.fromRGB(26, 36, 48),
	roadCasing = Color3.fromRGB(66, 82, 100),
	roadFill = Color3.fromRGB(100, 118, 138),
	majorCasing = Color3.fromRGB(122, 100, 54),
	majorFill = Color3.fromRGB(204, 170, 92),
	routeCasing = Color3.fromRGB(18, 112, 170),
	routeFill = Color3.fromRGB(51, 204, 255),
	car = Color3.fromRGB(51, 204, 255),
	pin = Color3.fromRGB(255, 88, 96),
	panel = Color3.fromRGB(16, 23, 32),
	text = Color3.fromRGB(255, 255, 255),
	subtext = Color3.fromRGB(170, 186, 204),
	speeding = Color3.fromRGB(235, 64, 64),
	limitRing = Color3.fromRGB(220, 40, 40),
}
GpsUI.Colors = C

local FONT = Enum.Font.GothamBold
local FONT_REGULAR = Enum.Font.GothamMedium

---------------------------------------------------------------- small helpers
local function new(className: string, props: { [string]: any }, children: { Instance }?): any
	local inst = Instance.new(className)
	for k, v in props do
		if k ~= "Parent" then
			(inst :: any)[k] = v
		end
	end
	if children then
		for _, child in children do
			child.Parent = inst
		end
	end
	if props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

local function round(parent: Instance, radius: UDim?)
	new("UICorner", { CornerRadius = radius or UDim.new(0.5, 0), Parent = parent })
end

local function label(parent: Instance, props: { [string]: any }): TextLabel
	local base = {
		BackgroundTransparency = 1,
		TextScaled = true,
		Font = FONT,
		TextColor3 = C.text,
		Text = "",
		Parent = parent,
	}
	for k, v in props do
		base[k] = v
	end
	return new("TextLabel", base)
end

-- A line is a rounded Frame stretched and rotated between two points (in pixels).
local function newLine(parent: Instance, color: Color3, z: number): Frame
	local f = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BorderSizePixel = 0,
		BackgroundColor3 = color,
		ZIndex = z,
		Visible = false,
		Parent = parent,
	})
	round(f)
	return f
end

local function placeLine(f: Frame, x1: number, y1: number, x2: number, y2: number, thick: number, w: number, h: number)
	-- Skip lines that are completely off-screen.
	if math.max(x1, x2) < -thick or math.min(x1, x2) > w + thick or math.max(y1, y2) < -thick or math.min(y1, y2) > h + thick then
		f.Visible = false
		return
	end
	local dx, dy = x2 - x1, y2 - y1
	local len = math.sqrt(dx * dx + dy * dy)
	f.Position = UDim2.fromOffset((x1 + x2) / 2, (y1 + y2) / 2)
	-- Extend by the thickness so the round ends overlap neatly at corners.
	f.Size = UDim2.fromOffset(len + thick, thick)
	f.Rotation = math.deg(math.atan2(dy, dx))
	f.Visible = true
end

---------------------------------------------------------------- MapView
local MapView = {}
MapView.__index = MapView
GpsUI.MapView = MapView

function MapView.new(parent: GuiObject)
	local self = setmetatable({}, MapView)
	self.canvas = new("Frame", {
		Name = "Map",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.background,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = 1,
		Parent = parent,
	})
	self.casings, self.fills = {}, {}
	for i, e in RoadNetwork.edges do
		local major = e.limit >= 60
		self.casings[i] = newLine(self.canvas, if major then C.majorCasing else C.roadCasing, 1)
		self.fills[i] = newLine(self.canvas, if major then C.majorFill else C.roadFill, 2)
	end
	self.routeCasings, self.routeFills = {}, {}

	self.pin = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = C.pin,
		BorderSizePixel = 0,
		ZIndex = 6,
		Visible = false,
		Parent = self.canvas,
	})
	round(self.pin)
	self.pinStroke = new("UIStroke", { Color = Color3.new(1, 1, 1), Parent = self.pin })
	local dot = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.4, 0.4),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 7,
		Parent = self.pin,
	})
	round(dot)

	self.car = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = C.car,
		BorderSizePixel = 0,
		ZIndex = 8,
		Visible = false,
		Parent = self.canvas,
	})
	round(self.car)
	self.carStroke = new("UIStroke", { Color = Color3.new(1, 1, 1), Parent = self.car })
	self.chevron = { newLine(self.canvas, Color3.new(1, 1, 1), 9), newLine(self.canvas, Color3.new(1, 1, 1), 9) }
	return self
end

local function routeLine(self, list: { Frame }, i: number, color: Color3, z: number): Frame
	if not list[i] then
		list[i] = newLine(self.canvas, color, z)
	end
	return list[i]
end

-- opts:
--   center: Vector3      world point shown at `anchor`
--   anchor: Vector2      where that point sits on the canvas (0..1)
--   heading: Vector3?    heading-up view if set, north-up if nil
--   studsPerHeight: number  how many studs fit from top to bottom
--   car: { pos: Vector3, heading: Vector3 }?
--   route: { Vector3 }?  points to draw as the route line
--   destination: Vector3?
function MapView:render(opts)
	local size = self.canvas.AbsoluteSize
	local w, h = size.X, size.Y
	if w < 2 or h < 2 then
		return
	end
	local s = h / opts.studsPerHeight
	local ax, ay = opts.anchor.X * w, opts.anchor.Y * h
	local c = opts.center
	local fx, fz, rx, rz = 0, -1, 1, 0
	local headingUp = opts.heading ~= nil
	if headingUp then
		local hv = opts.heading
		local m = math.sqrt(hv.X * hv.X + hv.Z * hv.Z)
		if m > 1e-4 then
			fx, fz = hv.X / m, hv.Z / m
			rx, rz = -fz, fx -- right of "forward" when looking down from above
		end
	end

	local function toScreen(p: Vector3): (number, number)
		local dx, dz = p.X - c.X, p.Z - c.Z
		if headingUp then
			return ax + (dx * rx + dz * rz) * s, ay - (dx * fx + dz * fz) * s
		end
		return ax + dx * s, ay + dz * s
	end

	-- Roads
	local roadPx = math.clamp(RoadNetwork.ROAD_WIDTH * s, 3, h * 0.08)
	local casingPx = roadPx + math.max(2, roadPx * 0.25)
	local nodes = RoadNetwork.nodes
	for i, e in RoadNetwork.edges do
		local x1, y1 = toScreen(nodes[e.a])
		local x2, y2 = toScreen(nodes[e.b])
		placeLine(self.casings[i], x1, y1, x2, y2, casingPx, w, h)
		placeLine(self.fills[i], x1, y1, x2, y2, roadPx, w, h)
	end

	-- Route
	local used = 0
	local route = opts.route
	if route and #route >= 2 then
		local fillPx = math.max(3, roadPx * 0.6)
		local edgePx = fillPx + math.max(2, fillPx * 0.35)
		for i = 1, #route - 1 do
			local x1, y1 = toScreen(route[i])
			local x2, y2 = toScreen(route[i + 1])
			placeLine(routeLine(self, self.routeCasings, i, C.routeCasing, 3), x1, y1, x2, y2, edgePx, w, h)
			placeLine(routeLine(self, self.routeFills, i, C.routeFill, 4), x1, y1, x2, y2, fillPx, w, h)
			used = i
		end
	end
	for i = used + 1, #self.routeFills do
		self.routeFills[i].Visible = false
		self.routeCasings[i].Visible = false
	end

	-- Destination pin
	local markerPx = math.max(10, h * 0.07)
	if opts.destination then
		local x, y = toScreen(opts.destination)
		self.pin.Position = UDim2.fromOffset(x, y)
		self.pin.Size = UDim2.fromOffset(markerPx, markerPx)
		self.pinStroke.Thickness = math.max(1, markerPx * 0.12)
		self.pin.Visible = true
	else
		self.pin.Visible = false
	end

	-- Car marker: a blue circle with a white arrow pointing where the car faces.
	local car = opts.car
	if car then
		local x, y = toScreen(car.pos)
		local r = markerPx * 0.9
		self.car.Position = UDim2.fromOffset(x, y)
		self.car.Size = UDim2.fromOffset(r * 2, r * 2)
		self.carStroke.Thickness = math.max(1, r * 0.14)
		self.car.Visible = true

		-- Direction of the car on screen.
		local hx, hy = 0, -1
		local hv = car.heading
		if hv and hv.Magnitude > 1e-4 then
			local px, py = toScreen(car.pos + hv.Unit * 10)
			local dx, dy = px - x, py - y
			local m = math.sqrt(dx * dx + dy * dy)
			if m > 1e-4 then
				hx, hy = dx / m, dy / m
			end
		end
		local nx, ny = -hy, hx
		local tipX, tipY = x + hx * r * 0.5, y + hy * r * 0.5
		local backX, backY = x - hx * r * 0.25, y - hy * r * 0.25
		local t = math.max(2, r * 0.26)
		placeLine(self.chevron[1], tipX, tipY, backX + nx * r * 0.45, backY + ny * r * 0.45, t, w, h)
		placeLine(self.chevron[2], tipX, tipY, backX - nx * r * 0.45, backY - ny * r * 0.45, t, w, h)
	else
		self.car.Visible = false
		self.chevron[1].Visible = false
		self.chevron[2].Visible = false
	end
end

-- For the overview map: which world point is under a pixel on the canvas.
function MapView.screenToWorld(opts, canvas: GuiObject, screenPos: Vector2): Vector3
	local size = canvas.AbsoluteSize
	local s = size.Y / opts.studsPerHeight
	local px = screenPos.X - canvas.AbsolutePosition.X - opts.anchor.X * size.X
	local py = screenPos.Y - canvas.AbsolutePosition.Y - opts.anchor.Y * size.Y
	return Vector3.new(opts.center.X + px / s, 0, opts.center.Z + py / s)
end

---------------------------------------------------------------- turn arrows
-- Each icon: a list of polylines in a 0..1 box (y goes down), plus an arrow head.
local ICONS = {
	straight = { lines = { { { 0.5, 0.88 }, { 0.5, 0.18 } } }, head = { 0.5, 0.12, 0, -1 } },
	right = { lines = { { { 0.3, 0.88 }, { 0.3, 0.5 }, { 0.8, 0.5 } } }, head = { 0.86, 0.5, 1, 0 } },
	left = { lines = { { { 0.7, 0.88 }, { 0.7, 0.5 }, { 0.2, 0.5 } } }, head = { 0.14, 0.5, -1, 0 } },
	slight_right = { lines = { { { 0.38, 0.88 }, { 0.38, 0.56 }, { 0.72, 0.22 } } }, head = { 0.77, 0.17, 0.707, -0.707 } },
	slight_left = { lines = { { { 0.62, 0.88 }, { 0.62, 0.56 }, { 0.28, 0.22 } } }, head = { 0.23, 0.17, -0.707, -0.707 } },
	uturn = {
		lines = { { { 0.68, 0.88 }, { 0.68, 0.4 }, { 0.5, 0.2 }, { 0.32, 0.4 }, { 0.32, 0.64 } } },
		head = { 0.32, 0.74, 0, 1 },
	},
	arrive = { lines = { { { 0.3, 0.9 }, { 0.3, 0.1 } }, { { 0.3, 0.14 }, { 0.78, 0.3 }, { 0.3, 0.46 } } } },
	search = { lines = { { { 0.62, 0.62 }, { 0.86, 0.86 } }, { { 0.42, 0.14 }, { 0.66, 0.26 }, { 0.7, 0.5 }, { 0.54, 0.68 }, { 0.3, 0.68 }, { 0.16, 0.5 }, { 0.2, 0.26 }, { 0.42, 0.14 } } } },
}

local function drawIcon(box: Frame, pool: { Frame }, kind: string)
	local size = box.AbsoluteSize
	local w, h = size.X, size.Y
	local icon = ICONS[kind]
	local used = 0
	local function line(x1, y1, x2, y2, t)
		used += 1
		if not pool[used] then
			pool[used] = newLine(box, C.text, box.ZIndex + 1)
		end
		placeLine(pool[used], x1 * w, y1 * h, x2 * w, y2 * h, t, w, h)
	end
	if icon then
		local t = math.max(2, w * 0.11)
		for _, poly in icon.lines do
			for i = 1, #poly - 1 do
				line(poly[i][1], poly[i][2], poly[i + 1][1], poly[i + 1][2], t)
			end
		end
		if icon.head then
			local x, y, dx, dy = table.unpack(icon.head)
			local nx, ny = -dy, dx
			local l = 0.22
			line(x, y, x - dx * l + nx * l, y - dy * l + ny * l, t)
			line(x, y, x - dx * l - nx * l, y - dy * l - ny * l, t)
		end
	end
	for i = used + 1, #pool do
		pool[i].Visible = false
	end
end

---------------------------------------------------------------- NavScreen
local NavScreen = {}
NavScreen.__index = NavScreen
GpsUI.NavScreen = NavScreen

function NavScreen.new(parent: GuiObject)
	local self = setmetatable({}, NavScreen)
	local root = new("Frame", {
		Name = "Nav",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.background,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = parent,
	})
	self.root = root
	self.map = MapView.new(root)

	-- Top banner: next turn
	local banner = new("Frame", {
		Name = "Banner",
		Size = UDim2.fromScale(1, 0.24),
		BackgroundColor3 = C.panel,
		BorderSizePixel = 0,
		ZIndex = 10,
		Parent = root,
	})
	self.iconBox = new("Frame", {
		Name = "Icon",
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		Size = UDim2.fromScale(0.8, 0.8),
		Position = UDim2.fromScale(0.025, 0.1),
		BackgroundTransparency = 1,
		ZIndex = 11,
		Parent = banner,
	})
	self.iconPool = {}
	self.distance = label(banner, {
		Position = UDim2.fromScale(0.18, 0.06),
		Size = UDim2.fromScale(0.79, 0.52),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 11,
	})
	self.instruction = label(banner, {
		Position = UDim2.fromScale(0.18, 0.58),
		Size = UDim2.fromScale(0.79, 0.34),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.subtext,
		Font = FONT_REGULAR,
		ZIndex = 11,
	})

	-- Bottom bar: time and distance left
	local bar = new("Frame", {
		Name = "Bottom",
		Position = UDim2.fromScale(0, 0.85),
		Size = UDim2.fromScale(1, 0.15),
		BackgroundColor3 = C.panel,
		BorderSizePixel = 0,
		ZIndex = 10,
		Parent = root,
	})
	self.eta = label(bar, {
		Position = UDim2.fromScale(0.04, 0.14),
		Size = UDim2.fromScale(0.34, 0.72),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 11,
	})
	self.info = label(bar, {
		Position = UDim2.fromScale(0.4, 0.2),
		Size = UDim2.fromScale(0.56, 0.6),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = C.subtext,
		Font = FONT_REGULAR,
		ZIndex = 11,
	})
	self.bar = bar

	-- Speed bubble + speed limit sign (bottom left)
	self.speedBubble = new("Frame", {
		Name = "Speed",
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		Size = UDim2.fromScale(0.18, 0.18),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0.025, 0.82),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 10,
		Parent = root,
	})
	round(self.speedBubble)
	self.speed = label(self.speedBubble, {
		Position = UDim2.fromScale(0.15, 0.14),
		Size = UDim2.fromScale(0.7, 0.5),
		TextColor3 = C.panel,
		ZIndex = 11,
	})
	self.speedUnit = label(self.speedBubble, {
		Position = UDim2.fromScale(0.25, 0.62),
		Size = UDim2.fromScale(0.5, 0.2),
		TextColor3 = C.panel,
		Font = FONT_REGULAR,
		Text = "km/h",
		ZIndex = 11,
	})

	self.limitSign = new("Frame", {
		Name = "Limit",
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		Size = UDim2.fromScale(0.13, 0.13),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0.15, 0.82),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 10,
		Parent = root,
	})
	round(self.limitSign)
	self.limitStroke = new("UIStroke", { Color = C.limitRing, Parent = self.limitSign })
	self.limit = label(self.limitSign, {
		Position = UDim2.fromScale(0.2, 0.22),
		Size = UDim2.fromScale(0.6, 0.56),
		TextColor3 = Color3.new(0, 0, 0),
		ZIndex = 11,
	})

	-- Current street (bottom middle)
	self.streetPill = new("Frame", {
		Name = "Street",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.6, 0.81),
		Size = UDim2.fromScale(0.44, 0.09),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		ZIndex = 10,
		Parent = root,
	})
	round(self.streetPill)
	self.street = label(self.streetPill, {
		Position = UDim2.fromScale(0.06, 0.15),
		Size = UDim2.fromScale(0.88, 0.7),
		Font = FONT_REGULAR,
		ZIndex = 11,
	})

	self.lastIcon = nil
	self.lastIconSize = Vector2.zero
	return self
end

function NavScreen:setVisible(visible: boolean)
	self.root.Visible = visible
end

-- state:
--   map: options for MapView:render
--   icon: string?  ("right", "left", "straight", "slight_left", "slight_right", "uturn", "arrive", "search")
--   distance: string, instruction: string
--   eta: string?, info: string?   (bottom bar hidden when eta is nil)
--   speed: number, speeding: boolean, limit: number?
--   street: string?
function NavScreen:update(state)
	self.map:render(state.map)

	local iconSize = self.iconBox.AbsoluteSize
	if state.icon ~= self.lastIcon or iconSize ~= self.lastIconSize then
		self.lastIcon, self.lastIconSize = state.icon, iconSize
		drawIcon(self.iconBox, self.iconPool, state.icon or "")
	end
	self.distance.Text = state.distance or ""
	self.instruction.Text = state.instruction or ""

	self.bar.Visible = state.eta ~= nil
	self.eta.Text = state.eta or ""
	self.info.Text = state.info or ""

	self.speed.Text = tostring(math.floor(state.speed + 0.5))
	local speeding = state.speeding
	self.speedBubble.BackgroundColor3 = if speeding then C.speeding else Color3.new(1, 1, 1)
	self.speed.TextColor3 = if speeding then C.text else C.panel
	self.speedUnit.TextColor3 = self.speed.TextColor3

	self.limitSign.Visible = state.limit ~= nil
	if state.limit then
		self.limit.Text = tostring(state.limit)
		self.limitStroke.Thickness = math.max(2, self.limitSign.AbsoluteSize.X * 0.11)
	end

	self.streetPill.Visible = state.street ~= nil
	self.street.Text = state.street or ""
end

return GpsUI
