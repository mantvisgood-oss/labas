-- GpsClient (LocalScript in StarterPlayer > StarterPlayerScripts)
-- Waze-style GPS:
--   * Press M (or tap the Map button) to open the city map, click any road to set a destination.
--   * While you sit in the van, the route shows on the dashboard screen (the "mini TV"):
--     next turn + distance, the blue route line, speed and speed limit, time and distance left.
--   * In third person the same screen also shows in the bottom-right corner, since you
--     can't read the dashboard from outside.
--   * Drive off the route and it recalculates.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local RoadNetwork = require(ReplicatedStorage:WaitForChild("RoadNetwork"))
local GpsUI = require(ReplicatedStorage:WaitForChild("GpsUI"))

---------------------------------------------------------------- settings
local MAP_KEY = Enum.KeyCode.M
local ARRIVE_DISTANCE = 30        -- studs from the destination that count as "arrived"
local OFF_ROUTE_DISTANCE = RoadNetwork.ROAD_WIDTH * 0.9
local SCREEN_PIXELS_PER_STUD = 200 -- sharpness of the dashboard screen
local SCREEN_BRIGHTNESS = 1.6
local THIRD_PERSON_DISTANCE = 5   -- camera this far from your head = third person
local HUD_SIZE = Vector2.new(360, 225)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

---------------------------------------------------------------- navigation state
local destination: Vector3? = nil
local route = nil
local offRouteTime = 0
local lastRecalc = 0
local recalculatingUntil = 0
local arrivedUntil = 0
local smoothHeading = Vector3.new(0, 0, -1)
local smoothZoom = 300

local function setDestination(pos: Vector3?, fromPos: Vector3?, heading: Vector3?)
	if not pos then
		destination, route = nil, nil
		return
	end
	destination = RoadNetwork.project(pos).point
	if fromPos then
		route = RoadNetwork.findRoute(fromPos, destination, heading)
		lastRecalc = os.clock()
	end
end

---------------------------------------------------------------- vehicle detection
local currentSeat: Seat? = nil
local vehicle = { model = nil :: Model?, driveSeat = nil :: VehicleSeat?, screen = nil :: BasePart? }
local lastScreenSearch = 0

local function vehicleModelOf(seat: Instance): Model?
	local top: Model? = nil
	local cur = seat.Parent
	while cur and cur ~= workspace do
		if cur:IsA("Model") then
			top = cur
		end
		cur = cur.Parent
	end
	return top
end

local function updateVehicle(humanoid: Humanoid?)
	local seat = humanoid and humanoid.SeatPart
	if seat ~= currentSeat then
		currentSeat = seat
		vehicle.model, vehicle.driveSeat, vehicle.screen = nil, nil, nil
		if seat then
			local model = vehicleModelOf(seat)
			local driveSeat = model and model:FindFirstChildWhichIsA("VehicleSeat", true)
			if driveSeat then -- only vehicles count, not park benches
				vehicle.model = model
				vehicle.driveSeat = driveSeat
			end
		end
		lastScreenSearch = 0
	end
	-- The screen might be added a moment after we sit down.
	if vehicle.model and not vehicle.screen and os.clock() - lastScreenSearch > 1 then
		lastScreenSearch = os.clock()
		local screen = vehicle.model:FindFirstChild("GPSScreen", true)
		if screen and screen:IsA("BasePart") then
			vehicle.screen = screen
		end
	end
end

---------------------------------------------------------------- dashboard screen
local tvGui = Instance.new("SurfaceGui")
tvGui.Name = "GpsScreen"
tvGui.Face = Enum.NormalId.Front
tvGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
tvGui.PixelsPerStud = SCREEN_PIXELS_PER_STUD
tvGui.LightInfluence = 0
tvGui.Brightness = SCREEN_BRIGHTNESS
tvGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
tvGui.ResetOnSpawn = false
tvGui.Enabled = false
tvGui.Parent = playerGui
local tv = GpsUI.NavScreen.new(tvGui)

---------------------------------------------------------------- on-screen GUI (HUD + big map)
local hudGui = Instance.new("ScreenGui")
hudGui.Name = "GpsHud"
hudGui.ResetOnSpawn = false
hudGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
hudGui.Parent = playerGui

local hudFrame = Instance.new("Frame")
hudFrame.Name = "MiniGps"
hudFrame.AnchorPoint = Vector2.new(1, 1)
hudFrame.Position = UDim2.new(1, -16, 1, -16)
hudFrame.Size = UDim2.fromOffset(HUD_SIZE.X, HUD_SIZE.Y)
hudFrame.BackgroundColor3 = GpsUI.Colors.panel
hudFrame.BorderSizePixel = 0
hudFrame.ClipsDescendants = true
hudFrame.Visible = false
hudFrame.Parent = hudGui
Instance.new("UICorner", hudFrame).CornerRadius = UDim.new(0, 14)
local hudStroke = Instance.new("UIStroke", hudFrame)
hudStroke.Color = Color3.fromRGB(8, 10, 14)
hudStroke.Thickness = 3
local hud = GpsUI.NavScreen.new(hudFrame)

local mapButton = Instance.new("TextButton")
mapButton.Name = "MapButton"
mapButton.AnchorPoint = Vector2.new(1, 1)
mapButton.Position = UDim2.new(1, -16, 1, -16)
mapButton.Size = UDim2.fromOffset(120, 36)
mapButton.BackgroundColor3 = GpsUI.Colors.panel
mapButton.BackgroundTransparency = 0.1
mapButton.TextColor3 = Color3.new(1, 1, 1)
mapButton.Font = Enum.Font.GothamBold
mapButton.TextSize = 16
mapButton.Text = "Map [M]"
mapButton.Visible = false
mapButton.Parent = hudGui
Instance.new("UICorner", mapButton).CornerRadius = UDim.new(0, 10)

-- Big map ("Where to?")
local mapGui = Instance.new("ScreenGui")
mapGui.Name = "GpsMap"
mapGui.ResetOnSpawn = false
mapGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
mapGui.DisplayOrder = 10
mapGui.Enabled = false
mapGui.Parent = playerGui

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromScale(0.8, 0.86)
panel.BackgroundColor3 = GpsUI.Colors.panel
panel.BorderSizePixel = 0
panel.Parent = mapGui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 16)
local aspect = Instance.new("UIAspectRatioConstraint", panel)
aspect.AspectRatio = 0.92 -- a bit taller than wide: title above, buttons below

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.new(0, 20, 0, 10)
title.Size = UDim2.new(1, -40, 0, 34)
title.Font = Enum.Font.GothamBold
title.TextSize = 24
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.new(1, 1, 1)
title.Text = "Where to?"
title.Parent = panel

local hint = Instance.new("TextLabel")
hint.BackgroundTransparency = 1
hint.Position = UDim2.new(0, 20, 0, 42)
hint.Size = UDim2.new(1, -40, 0, 22)
hint.Font = Enum.Font.GothamMedium
hint.TextSize = 16
hint.TextXAlignment = Enum.TextXAlignment.Left
hint.TextColor3 = GpsUI.Colors.subtext
hint.Text = "Click any road to set your destination"
hint.Parent = panel

local mapHolder = Instance.new("Frame")
mapHolder.Position = UDim2.new(0, 16, 0, 72)
mapHolder.Size = UDim2.new(1, -32, 1, -140)
mapHolder.BackgroundTransparency = 1
mapHolder.ClipsDescendants = true
mapHolder.Active = true
mapHolder.Parent = panel
Instance.new("UICorner", mapHolder).CornerRadius = UDim.new(0, 10)
local bigMap = GpsUI.MapView.new(mapHolder)

local function makeButton(text: string, color: Color3, xScale: number, xOffset: number): TextButton
	local b = Instance.new("TextButton")
	b.AnchorPoint = Vector2.new(xScale, 1)
	b.Position = UDim2.new(xScale, xOffset, 1, -14)
	b.Size = UDim2.fromOffset(160, 42)
	b.BackgroundColor3 = color
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 18
	b.Text = text
	b.Parent = panel
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 10)
	return b
end
local clearButton = makeButton("Clear route", Color3.fromRGB(70, 82, 98), 0, 16)
local goButton = makeButton("Let's go! [M]", Color3.fromRGB(20, 150, 215), 1, -16)
-- A visible Modal button frees the mouse even in first person.
goButton.Modal = true

---------------------------------------------------------------- position source
local function getSource(): (Vector3?, Vector3, number)
	-- Returns position, facing direction, and speed in studs/second.
	local seat = vehicle.driveSeat
	if seat then
		local v = seat.AssemblyLinearVelocity
		return seat.Position, seat.CFrame.LookVector, Vector3.new(v.X, 0, v.Z).Magnitude
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local v = root.AssemblyLinearVelocity
		return root.Position, root.CFrame.LookVector, Vector3.new(v.X, 0, v.Z).Magnitude
	end
	return nil, Vector3.new(0, 0, -1), 0
end

local function flatUnit(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	if f.Magnitude < 1e-4 then
		return Vector3.new(0, 0, -1)
	end
	return f.Unit
end

---------------------------------------------------------------- big map open/close
local mapOpen = false
local savedMouseIcon = true

local function bigMapOptions()
	local b = RoadNetwork.bounds
	local size = mapHolder.AbsoluteSize
	local worldW, worldH = b.maxX - b.minX, b.maxZ - b.minZ
	-- Fit the whole city, keeping it square.
	local studsPerHeight = math.max(worldH, worldW * size.Y / math.max(size.X, 1)) * 1.04
	return {
		center = Vector3.new((b.minX + b.maxX) / 2, 0, (b.minZ + b.maxZ) / 2),
		anchor = Vector2.new(0.5, 0.5),
		studsPerHeight = studsPerHeight,
	}
end

local function setMapOpen(open: boolean)
	if open == mapOpen then
		return
	end
	mapOpen = open
	mapGui.Enabled = open
	if open then
		savedMouseIcon = UserInputService.MouseIconEnabled
		-- Keep the mouse free while the map is open, even if another script tries to lock it.
		RunService:BindToRenderStep("GpsMapMouse", Enum.RenderPriority.Last.Value, function()
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
		end)
	else
		RunService:UnbindFromRenderStep("GpsMapMouse")
		UserInputService.MouseIconEnabled = savedMouseIcon
	end
end

mapHolder.InputBegan:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	local world = GpsUI.MapView.screenToWorld(bigMapOptions(), bigMap.canvas, Vector2.new(input.Position.X, input.Position.Y))
	local pos, heading = getSource()
	setDestination(world, pos, heading)
	arrivedUntil = 0
end)

mapHolder.InputChanged:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseMovement then
		return
	end
	local world = GpsUI.MapView.screenToWorld(bigMapOptions(), bigMap.canvas, Vector2.new(input.Position.X, input.Position.Y))
	local edge = RoadNetwork.edges[RoadNetwork.project(world).edge]
	hint.Text = "Click to drive to " .. edge.name
end)
mapHolder.MouseLeave:Connect(function()
	hint.Text = "Click any road to set your destination"
end)

goButton.Activated:Connect(function()
	setMapOpen(false)
end)
clearButton.Activated:Connect(function()
	setDestination(nil)
end)
mapButton.Activated:Connect(function()
	setMapOpen(not mapOpen)
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == MAP_KEY then
		setMapOpen(not mapOpen)
	end
end)

---------------------------------------------------------------- per-frame update
local function formatEta(seconds: number): (string, string)
	local minutes = math.max(1, math.ceil(seconds / 60))
	local eta = if minutes < 60 then minutes .. " min" else string.format("%d h %02d", minutes // 60, minutes % 60)
	return eta, os.date("%H:%M", os.time() + math.floor(seconds)) :: string
end

local function buildState(pos: Vector3, heading: Vector3, speedStuds: number, dt: number)
	local now = os.clock()
	local kmh = speedStuds * RoadNetwork.METERS_PER_STUD * 3.6
	local street, limit, roadDist = RoadNetwork.streetAt(pos)

	local state = {
		speed = kmh,
		speeding = limit ~= nil and kmh > limit + 2,
		limit = limit,
		street = street,
		icon = "search",
		distance = "Where to?",
		instruction = "Press M to choose a destination",
	}

	local routeDraw = nil
	if route and destination then
		local progress, off, leg, intoLeg = RoadNetwork.trackProgress(route, pos)

		-- Off the route? Recalculate (but not every frame).
		if off > OFF_ROUTE_DISTANCE then
			offRouteTime += dt
		else
			offRouteTime = 0
		end
		if offRouteTime > 0.6 and now - lastRecalc > 1.5 then
			route = RoadNetwork.findRoute(pos, destination, heading)
			lastRecalc = now
			offRouteTime = 0
			if roadDist <= RoadNetwork.ROAD_WIDTH then
				recalculatingUntil = now + 1.5
			end
			progress, off, leg, intoLeg = RoadNetwork.trackProgress(route, pos)
		end

		local remaining = route.length - progress
		if remaining < ARRIVE_DISTANCE and off < OFF_ROUTE_DISTANCE then
			destination, route = nil, nil
			arrivedUntil = now + 5
		else
			-- Next instruction ahead of us.
			local nextStep = route.maneuvers[#route.maneuvers]
			for _, m in route.maneuvers do
				if m.distance > progress + 2 then
					nextStep = m
					break
				end
			end
			state.icon = nextStep.kind
			state.distance = RoadNetwork.formatDistance(nextStep.distance - progress)
			state.instruction = nextStep.text
			if roadDist > RoadNetwork.ROAD_WIDTH then
				state.icon = "search"
				state.distance = "Drive to a road"
				state.instruction = "Route starts on the nearest road"
			elseif now < recalculatingUntil then
				state.instruction = "Recalculating..."
			end

			local eta, clock = formatEta(RoadNetwork.timeRemaining(route, leg, intoLeg))
			state.eta = eta
			state.info = RoadNetwork.formatDistance(remaining) .. "  ·  " .. clock

			-- Only draw the part of the route still ahead.
			local P = route.points
			local here = P[leg]:Lerp(P[leg + 1], if route.cum[leg + 1] > route.cum[leg]
				then intoLeg / (route.cum[leg + 1] - route.cum[leg])
				else 0)
			routeDraw = { here }
			for i = leg + 1, #P do
				table.insert(routeDraw, P[i])
			end
		end
	end

	if not route and now < arrivedUntil then
		state.icon = "arrive"
		state.distance = "You have arrived!"
		state.instruction = "Press M to choose a new destination"
	end

	-- Waze-style camera: zoom out as you go faster, map turns with the car.
	local targetZoom = math.clamp(260 + speedStuds * 4.5, 260, 620)
	smoothZoom += (targetZoom - smoothZoom) * math.min(1, dt * 2)
	state.map = {
		center = pos,
		anchor = Vector2.new(0.5, 0.66),
		heading = smoothHeading,
		studsPerHeight = smoothZoom,
		car = { pos = pos, heading = smoothHeading },
		route = routeDraw,
		destination = destination,
	}
	return state
end

local function isThirdPerson(): boolean
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	local camera = workspace.CurrentCamera
	if not head or not camera then
		return false
	end
	return (camera.CFrame.Position - (head :: BasePart).Position).Magnitude > THIRD_PERSON_DISTANCE
end

RunService.RenderStepped:Connect(function(dt)
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	updateVehicle(humanoid)

	local inVehicle = vehicle.model ~= nil
	local pos, heading, speedStuds = getSource()
	if not pos then
		tvGui.Enabled, hudFrame.Visible, mapButton.Visible = false, false, false
		return
	end

	-- Smooth the heading so the map doesn't shake with the suspension.
	smoothHeading = flatUnit(smoothHeading:Lerp(flatUnit(heading), math.min(1, dt * 6)))

	local showTv = inVehicle and vehicle.screen ~= nil
	local showHud = inVehicle and not mapOpen and (vehicle.screen == nil or isThirdPerson())

	tvGui.Adornee = vehicle.screen
	tvGui.Enabled = showTv
	hudFrame.Visible = showHud
	mapButton.Visible = inVehicle and not mapOpen
	-- Sit above the mini screen when it's showing.
	mapButton.Position = if showHud then UDim2.new(1, -16, 1, -24 - HUD_SIZE.Y) else UDim2.new(1, -16, 1, -16)

	if showTv or showHud or mapOpen then
		local state = buildState(pos, heading, speedStuds, dt)
		if showTv then
			tv:update(state)
		end
		if showHud then
			hud:update(state)
		end
		if mapOpen then
			local opts = bigMapOptions()
			opts.car = { pos = pos, heading = heading }
			opts.route = route and route.points
			opts.destination = destination
			bigMap:render(opts)
			title.Text = if route then "Route: " .. RoadNetwork.formatDistance(route.length) else "Where to?"
		end
	end
end)
