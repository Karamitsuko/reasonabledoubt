--!strict
-- Builds one tower block from a seed: rooms with doors, an elevator, the street, and background skyline.
-- Returns room data the simulation uses for navigation. The world is never saved; it is rebuilt from the seed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local RngModule = require(Shared:WaitForChild("Rng"))

type Rng = RngModule.Rng

export type Room = {
	id: string,
	kind: string,
	label: string,
	floor: number,
	center: Vector3,
	size: Vector3,
	doorInner: Vector3,
	corridor: Vector3,
}

export type World = {
	rooms: { [string]: Room },
	roomList: { Room },
	elevators: { [number]: Vector3 },
	street: Vector3,
	streetDoorOut: Vector3,
	streetDoorIn: Vector3,
	lobbyId: string,
	spawn: CFrame,
	model: Model,
}

local FH = Config.FLOOR_HEIGHT
local X0, X1 = 0, 64
local Z_N, Z_S = 20, -20
local CORR = 4
local DOOR_W, DOOR_H = 5, 8
local T = 1 -- wall thickness

local C = {
	wall = Color3.fromRGB(52, 49, 58),
	interior = Color3.fromRGB(58, 52, 60),
	floor = Color3.fromRGB(40, 38, 42),
	brick = Color3.fromRGB(74, 48, 46),
	corridorFloor = Color3.fromRGB(30, 34, 36),
	trim = Color3.fromRGB(18, 18, 22),
	glass = Color3.fromRGB(60, 90, 110),
	asphalt = Color3.fromRGB(24, 24, 28),
	sidewalk = Color3.fromRGB(62, 62, 66),
	skyline = Color3.fromRGB(20, 20, 26),
}

local LIGHT: { [string]: Color3 } = {
	apartment = Color3.fromRGB(255, 186, 130),
	office = Color3.fromRGB(190, 215, 255),
	diner = Color3.fromRGB(255, 90, 170),
	bar = Color3.fromRGB(150, 80, 255),
	shop = Color3.fromRGB(120, 255, 220),
	lobby = Color3.fromRGB(255, 200, 120),
	security = Color3.fromRGB(120, 180, 255),
	clinic = Color3.fromRGB(200, 255, 240),
	detective = Color3.fromRGB(255, 170, 90),
	corridor = Color3.fromRGB(140, 255, 200),
}

local FLOOR_FINISH: { [string]: { any } } = {
	apartment = { Enum.Material.WoodPlanks, Color3.fromRGB(70, 50, 40) },
	office = { Enum.Material.Fabric, Color3.fromRGB(40, 44, 52) },
	security = { Enum.Material.Fabric, Color3.fromRGB(40, 44, 52) },
	detective = { Enum.Material.WoodPlanks, Color3.fromRGB(56, 38, 30) },
	clinic = { Enum.Material.Marble, Color3.fromRGB(170, 176, 176) },
	diner = { Enum.Material.Marble, Color3.fromRGB(150, 40, 60) },
	bar = { Enum.Material.Marble, Color3.fromRGB(30, 26, 40) },
	shop = { Enum.Material.Marble, Color3.fromRGB(120, 120, 116) },
	lobby = { Enum.Material.Marble, Color3.fromRGB(110, 100, 90) },
}

type Bay = { side: string, x0: number, x1: number, kind: string, label: string }

local function bay(side: string, x0: number, x1: number, kind: string, label: string): Bay
	return { side = side, x0 = x0, x1 = x1, kind = kind, label = label }
end

local function layoutFor(floor: number): { Bay }
	if floor == 0 then
		return {
			bay("S", 0, 32, "lobby", "Lobby"),
			bay("S", 32, 64, "bar", "The Blue Hour"),
			bay("N", 0, 32, "diner", "Night Owl Diner"),
			bay("N", 32, 48, "shop", "Corner Store"),
			bay("N", 48, 64, "security", "Security Office"),
		}
	elseif floor == Config.FLOORS - 1 then
		return {
			bay("S", 0, 16, "detective", "Detective Office"),
			bay("S", 16, 48, "office", "Halvorsen Insurance"),
			bay("S", 48, 64, "clinic", "Night Clinic"),
			bay("N", 0, 32, "office", "Ardent Logistics"),
			bay("N", 32, 64, "office", "Vesper Data"),
		}
	end
	local bays = {}
	local south = { "A", "B", "C", "D" }
	local northL = { "E", "F", "G", "H" }
	for i = 0, 3 do
		table.insert(bays, bay("S", i * 16, i * 16 + 16, "apartment", ("Apt %d%s"):format(floor, south[i + 1])))
		table.insert(bays, bay("N", i * 16, i * 16 + 16, "apartment", ("Apt %d%s"):format(floor, northL[i + 1])))
	end
	return bays
end

local function part(
	parent: Instance,
	name: string,
	minV: Vector3,
	maxV: Vector3,
	color: Color3,
	material: Enum.Material?,
	transparency: number?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = maxV - minV
	p.CFrame = CFrame.new((minV + maxV) / 2)
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Transparency = transparency or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Wall running along X at depth z, from x0 to x1, with an optional door centred at doorX.
local function wallX(parent: Instance, x0: number, x1: number, z: number, y0: number, doorX: number?, color: Color3)
	local h = FH - 1
	local z0, z1 = z - T / 2, z + T / 2
	if doorX then
		local d0, d1 = doorX - DOOR_W / 2, doorX + DOOR_W / 2
		if d0 > x0 then
			part(parent, "Wall", Vector3.new(x0, y0, z0), Vector3.new(d0, y0 + h, z1), color)
		end
		if x1 > d1 then
			part(parent, "Wall", Vector3.new(d1, y0, z0), Vector3.new(x1, y0 + h, z1), color)
		end
		part(parent, "Lintel", Vector3.new(d0, y0 + DOOR_H, z0), Vector3.new(d1, y0 + h, z1), color)
	else
		part(parent, "Wall", Vector3.new(x0, y0, z0), Vector3.new(x1, y0 + h, z1), color)
	end
end

-- Exterior wall with a window band; an optional street door gap.
local function facadeX(parent: Instance, x0: number, x1: number, z: number, y0: number, doorX: number?)
	local h = FH - 1
	local z0, z1 = z - T / 2, z + T / 2
	if doorX then
		local d0, d1 = doorX - DOOR_W / 2, doorX + DOOR_W / 2
		facadeX(parent, x0, d0, z, y0, nil)
		facadeX(parent, d1, x1, z, y0, nil)
		part(parent, "Lintel", Vector3.new(d0, y0 + DOOR_H, z0), Vector3.new(d1, y0 + h, z1), C.wall)
		return
	end
	if x1 - x0 < 0.5 then
		return
	end
	part(parent, "Facade", Vector3.new(x0, y0, z0), Vector3.new(x1, y0 + 3, z1), C.brick, Enum.Material.Brick)
	local glass = part(parent, "Window", Vector3.new(x0, y0 + 3, z0), Vector3.new(x1, y0 + 8, z1), C.glass, Enum.Material.Glass, 0.55)
	glass.CastShadow = false
	part(parent, "Facade", Vector3.new(x0, y0 + 8, z0), Vector3.new(x1, y0 + h, z1), C.brick, Enum.Material.Brick)
end

local function wallZ(parent: Instance, z0: number, z1: number, x: number, y0: number, color: Color3)
	part(parent, "Wall", Vector3.new(x - T / 2, y0, z0), Vector3.new(x + T / 2, y0 + FH - 1, z1), color)
end

local function lamp(parent: Instance, pos: Vector3, color: Color3, range: number, brightness: number)
	local fixture = part(
		parent,
		"Lamp",
		pos - Vector3.new(1, 0.1, 1),
		pos + Vector3.new(1, 0.1, 1),
		color,
		Enum.Material.Neon
	)
	fixture.CastShadow = false
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Parent = fixture
end

-- A sign board whose lettered face points along `normal`.
local function sign(parent: Instance, text: string, center: Vector3, w: number, h: number, normal: Vector3, color: Color3)
	local board = part(parent, "Sign", center - Vector3.new(0.05, 0.05, 0.05), center + Vector3.new(0.05, 0.05, 0.05), C.trim)
	board.Size = Vector3.new(w, h, 0.1)
	board.CFrame = CFrame.lookAt(center, center + normal)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.Brightness = 2.5
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = color
	label.Parent = gui
	local glow = Instance.new("PointLight")
	glow.Color = color
	glow.Range = 14
	glow.Brightness = 1.5
	glow.Parent = board
end

local BuildingGen = {}

function BuildingGen.generate(rng: Rng, parent: Instance): World
	local model = Instance.new("Model")
	model.Name = "District"

	local rooms: { [string]: Room } = {}
	local roomList: { Room } = {}
	local elevators: { [number]: Vector3 } = {}
	local lobbyId = ""

	local building = Instance.new("Model")
	building.Name = "KestrelArms"
	building.Parent = model

	for floor = 0, Config.FLOORS - 1 do
		local y0 = floor * FH
		local f = Instance.new("Model")
		f.Name = ("Floor%d"):format(floor)
		f.Parent = building

		-- Slab and corridor runner
		part(f, "Slab", Vector3.new(X0, y0 - 1, Z_S), Vector3.new(X1, y0, Z_N), C.floor, Enum.Material.Concrete)
		part(f, "Runner", Vector3.new(X0, y0, -CORR), Vector3.new(X1, y0 + 0.05, CORR), C.corridorFloor, Enum.Material.Fabric)
		part(f, "ElevatorSlab", Vector3.new(-8, y0 - 1, -CORR), Vector3.new(X0, y0, CORR), C.trim, Enum.Material.DiamondPlate)

		-- End walls; the west one opens onto the elevator
		wallZ(f, Z_S, -CORR, X0, y0, C.wall)
		wallZ(f, CORR, Z_N, X0, y0, C.wall)
		wallZ(f, Z_S, Z_N, X1, y0, C.wall)

		-- Elevator box with prompts
		wallZ(f, -CORR, CORR, -8, y0, C.trim)
		part(f, "Wall", Vector3.new(-8, y0, -CORR - T / 2), Vector3.new(X0, y0 + FH - 1, -CORR + T / 2), C.trim)
		part(f, "Wall", Vector3.new(-8, y0, CORR - T / 2), Vector3.new(X0, y0 + FH - 1, CORR + T / 2), C.trim)
		local panel = part(f, "ElevatorPanel", Vector3.new(-7.4, y0 + 3.5, -1), Vector3.new(-7.2, y0 + 5.5, 1), LIGHT.lobby, Enum.Material.Neon)
		panel:SetAttribute("Floor", floor)
		if floor < Config.FLOORS - 1 then
			local up = Instance.new("ProximityPrompt")
			up.Name = "Up"
			up.ActionText = "Up a floor"
			up.ObjectText = "Elevator"
			up.KeyboardKeyCode = Enum.KeyCode.E
			up.MaxActivationDistance = 8
			up.Parent = panel
		end
		if floor > 0 then
			local down = Instance.new("ProximityPrompt")
			down.Name = "Down"
			down.ActionText = "Down a floor"
			down.ObjectText = "Elevator"
			down.KeyboardKeyCode = Enum.KeyCode.Q
			down.MaxActivationDistance = 8
			down.UIOffset = Vector2.new(0, 60)
			down.Parent = panel
		end
		elevators[floor] = Vector3.new(-4, y0 + 3, 0)
		lamp(f, Vector3.new(-4, y0 + FH - 1.2, 0), LIGHT.lobby, 10, 0.8)

		-- Corridor lights, slightly sickly
		for x = 8, 56, 16 do
			lamp(f, Vector3.new(x, y0 + FH - 1.2, 0), LIGHT.corridor, 14, 0.6)
		end

		for _, b in layoutFor(floor) do
			local north = b.side == "N"
			local zIn = north and CORR or -CORR
			local zOut = north and Z_N or Z_S
			local zMin, zMax = math.min(zIn, zOut), math.max(zIn, zOut)
			local doorX = if b.x1 - b.x0 > 16 then b.x0 + 8 else (b.x0 + b.x1) / 2
			local streetDoor: number? = nil
			if floor == 0 and b.kind == "lobby" then
				streetDoor = 16
			end

			wallX(f, b.x0, b.x1, zIn, y0, doorX, C.interior)
			facadeX(f, b.x0, b.x1, zOut, y0, streetDoor)
			if b.x1 < X1 then
				wallZ(f, zMin, zMax, b.x1, y0, C.interior)
			end

			local id = ("F%d_%s_%d"):format(floor, b.side, b.x0)
			local yc = y0 + 3
			local room: Room = {
				id = id,
				kind = b.kind,
				label = b.label,
				floor = floor,
				center = Vector3.new((b.x0 + b.x1) / 2, yc, (zMin + zMax) / 2),
				size = Vector3.new(b.x1 - b.x0, FH - 1, zMax - zMin),
				doorInner = Vector3.new(doorX, yc, if north then CORR + 2.5 else -CORR - 2.5),
				corridor = Vector3.new(doorX, yc, 0),
			}
			rooms[id] = room
			table.insert(roomList, room)
			if b.kind == "lobby" then
				lobbyId = id
			end

			-- Room volume marker for later systems (trigger zones, crime scenes)
			local zone = part(f, "Zone_" .. id, Vector3.new(b.x0 + 0.5, y0, zMin + 0.5), Vector3.new(b.x1 - 0.5, y0 + FH - 1, zMax - 0.5), C.trim, nil, 1)
			zone.CanCollide = false
			zone.CanQuery = false
			zone.CanTouch = false
			zone.CastShadow = false
			zone:SetAttribute("RoomId", id)
			zone:SetAttribute("Label", b.label)

			-- Floor finish by room type
			local finish = FLOOR_FINISH[b.kind] or { Enum.Material.WoodPlanks, Color3.fromRGB(70, 50, 40) }
			part(f, "Floor", Vector3.new(b.x0 + 0.5, y0, zMin + 0.5), Vector3.new(b.x1 - 0.5, y0 + 0.05, zMax - 0.5), finish[2], finish[1])

			-- Door plate, lettered face toward the corridor
			local plateZ = if north then CORR - 0.6 else -CORR + 0.6
			sign(
				f,
				b.label,
				Vector3.new(doorX + 4.5, y0 + 6.4, plateZ),
				3,
				0.8,
				Vector3.new(0, 0, if north then -1 else 1),
				LIGHT[b.kind] or LIGHT.corridor
			)

			-- Light, dimmer in homes, a second lamp in big rooms
			local lc = LIGHT[b.kind] or LIGHT.apartment
			local bright = if b.kind == "apartment" then 0.7 else 1.1
			lamp(f, Vector3.new(room.center.X, y0 + FH - 1.2, room.center.Z), lc, 18, bright)
			if b.x1 - b.x0 > 16 then
				lamp(f, Vector3.new(room.center.X + 8, y0 + FH - 1.2, room.center.Z), lc, 16, bright * 0.8)
			end

			-- A touch of variety: some apartments are dark (nobody home, or a broken bulb)
			if b.kind == "apartment" and rng:chance(0.2) then
				for _, d in f:GetChildren() do
					if d:IsA("BasePart") and d.Name == "Lamp" and (d.Position - Vector3.new(room.center.X, y0 + FH - 1.2, room.center.Z)).Magnitude < 0.5 then
						local l = d:FindFirstChildOfClass("PointLight")
						if l then
							l.Brightness = 0.15
						end
					end
				end
			end
		end
	end

	-- Roof and sign
	local roofY = Config.FLOORS * FH
	part(building, "Roof", Vector3.new(-8, roofY - 1, Z_S), Vector3.new(X1, roofY, Z_N), C.trim)
	sign(building, "KESTREL ARMS", Vector3.new(32, roofY + 3, Z_S - 0.5), 36, 5, Vector3.new(0, 0, -1), Color3.fromRGB(255, 70, 160))
	sign(building, "THE BLUE HOUR", Vector3.new(48, 9.5, Z_S - 0.9), 16, 2, Vector3.new(0, 0, -1), Color3.fromRGB(90, 140, 255))
	local strip = part(building, "NeonStrip", Vector3.new(X1 + 0.1, 2, Z_S - 0.6), Vector3.new(X1 + 0.6, roofY, Z_S - 0.1), Color3.fromRGB(0, 220, 255), Enum.Material.Neon)
	strip.CastShadow = false

	-- Street
	local street = Instance.new("Model")
	street.Name = "Street"
	street.Parent = model
	part(street, "Road", Vector3.new(-120, -2, -90), Vector3.new(190, -0.4, 70), C.asphalt, Enum.Material.Asphalt)
	part(street, "Sidewalk", Vector3.new(-120, -1, -28), Vector3.new(190, 0, Z_S), C.sidewalk, Enum.Material.Concrete)
	part(street, "SidewalkFar", Vector3.new(-120, -1, -70), Vector3.new(190, 0, -62), C.sidewalk, Enum.Material.Concrete)
	for x = -40, 110, 30 do
		part(street, "Pole", Vector3.new(x - 0.3, 0, -27), Vector3.new(x + 0.3, 14, -26.4), C.trim, Enum.Material.Metal)
		lamp(street, Vector3.new(x, 13.6, -25.4), Color3.fromRGB(255, 165, 80), 26, 1.4)
	end

	-- Skyline: dark towers with lit window strips, south across the road and around
	local skyline = Instance.new("Model")
	skyline.Name = "Skyline"
	skyline.Parent = model
	local spots = {}
	for x = -110, 170, 36 do
		table.insert(spots, Vector3.new(x, 0, -100))
		table.insert(spots, Vector3.new(x, 0, 90))
	end
	for z = -60, 60, 40 do
		table.insert(spots, Vector3.new(-140, 0, z))
		table.insert(spots, Vector3.new(210, 0, z))
	end
	local accents = {
		Color3.fromRGB(255, 70, 160),
		Color3.fromRGB(0, 220, 255),
		Color3.fromRGB(255, 180, 90),
		Color3.fromRGB(150, 90, 255),
	}
	for _, s in spots do
		local w, d, h = rng:int(22, 32), rng:int(22, 32), rng:int(50, 160)
		local tower = part(skyline, "Tower", s - Vector3.new(w / 2, 0, d / 2), s + Vector3.new(w / 2, h, d / 2), C.skyline, Enum.Material.Concrete)
		tower.CastShadow = false
		for _ = 1, rng:int(1, 3) do
			local col = rng:pick(accents)
			local sx = s.X + rng:float(-w / 2 + 2, w / 2 - 2)
			local top = rng:float(h * 0.4, h * 0.95)
			local face = if s.Z < 0 then s.Z + d / 2 + 0.2 else s.Z - d / 2 - 0.2
			local stripPart = part(skyline, "Lights", Vector3.new(sx - 0.4, 6, face - 0.2), Vector3.new(sx + 0.4, top, face + 0.2), col, Enum.Material.Neon)
			stripPart.CastShadow = false
		end
	end

	-- Spawn on the sidewalk outside the lobby
	local spawnPart = Instance.new("SpawnLocation")
	spawnPart.Name = "StreetSpawn"
	spawnPart.Anchored = true
	spawnPart.Size = Vector3.new(6, 1, 6)
	spawnPart.CFrame = CFrame.new(10, -0.45, -24.5) * CFrame.Angles(0, math.pi, 0) -- face the building
	spawnPart.Transparency = 1
	spawnPart.CanCollide = false
	spawnPart.Neutral = true
	spawnPart.Duration = 0
	local decal = spawnPart:FindFirstChildOfClass("Decal")
	if decal then
		decal:Destroy()
	end
	spawnPart.Parent = model

	model.Parent = parent

	return {
		rooms = rooms,
		roomList = roomList,
		elevators = elevators,
		street = Vector3.new(16, 3, -25),
		streetDoorOut = Vector3.new(16, 3, Z_S - 2.5),
		streetDoorIn = Vector3.new(16, 3, Z_S + 2.5),
		lobbyId = lobbyId,
		spawn = CFrame.new(10, 3, -24.5),
		model = model,
	}
end

return BuildingGen
