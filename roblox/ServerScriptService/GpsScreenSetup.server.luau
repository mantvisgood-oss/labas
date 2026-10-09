-- GpsScreenSetup (Script in ServerScriptService)
-- Puts a small screen (the "mini TV") on the dashboard of every vehicle that has a
-- VehicleSeat. GpsClient draws the GPS onto it for whoever is sitting in that vehicle.
--
-- Want it somewhere else? Either tweak SCREEN_OFFSET below, or put your own Part named
-- "GPSScreen" inside the van model (front face towards the driver, welded to the van).
-- If one already exists, this script leaves it alone.

---------------------------------------------------------------- settings
-- Position of the screen relative to the driver's seat, in studs:
--   X = to the right (towards the middle of the dashboard)
--   Y = up
--   Z = backwards, so a negative number is in front of the driver
local SCREEN_OFFSET = Vector3.new(2.3, 2.3, -3.6)
local SCREEN_SIZE = Vector2.new(2.6, 1.6) -- width, height in studs
-- Where the screen looks at, relative to the seat (roughly the driver's eyes).
local EYE_OFFSET = Vector3.new(0, 3.2, 0.3)

---------------------------------------------------------------- setup
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

local function addScreen(seat: VehicleSeat)
	local model = vehicleModelOf(seat)
	if not model or model:FindFirstChild("GPSScreen", true) then
		return
	end

	local seatCf = seat.CFrame
	local pos = seatCf:PointToWorldSpace(SCREEN_OFFSET)
	local eye = seatCf:PointToWorldSpace(EYE_OFFSET)

	local screen = Instance.new("Part")
	screen.Name = "GPSScreen"
	screen.Size = Vector3.new(SCREEN_SIZE.X, SCREEN_SIZE.Y, 0.15)
	-- Front face points at the driver's eyes.
	screen.CFrame = CFrame.lookAt(pos, eye, seatCf.UpVector)
	screen.Color = Color3.fromRGB(12, 14, 18)
	screen.Material = Enum.Material.SmoothPlastic
	screen.CanCollide = false
	screen.CanQuery = false -- doors/seats are clicked with a raycast; don't block it
	screen.CanTouch = false
	screen.Massless = true -- doesn't change how the van drives
	screen.CastShadow = false
	screen.Anchored = false

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = seat
	weld.Part1 = screen
	weld.Parent = screen

	screen.Parent = model
end

local function check(inst: Instance)
	if inst:IsA("VehicleSeat") then
		-- Wait a moment so the rest of the vehicle has loaded in.
		task.defer(addScreen, inst)
	end
end

for _, inst in workspace:GetDescendants() do
	check(inst)
end
workspace.DescendantAdded:Connect(check)
