--!strict
-- Furniture you can search by hand. Drawers slide out, bin lids lift, wardrobe doors swing open; whatever is
-- inside is a real object you can see and pick up. Nothing glows or announces itself: hidden things are found
-- by opening things. Most containers hold everyday junk, so a thorough search is a real search.

local TweenService = game:GetService("TweenService")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RngModule = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Rng"))
local BuildingGen = require(script.Parent:WaitForChild("BuildingGen"))

type Rng = RngModule.Rng
type World = BuildingGen.World
type Room = BuildingGen.Room

export type Container = {
	kind: string, -- "bin" | "drawer" | "wardrobe"
	model: Model,
	holder: Instance, -- items placed here move with the drawer / sit in the bin
	slot: CFrame, -- where the next item goes (world space, at rest)
	isOpen: boolean,
}

export type Furniture = {
	rooms: { [string]: { [string]: Container } }, -- roomId -> name -> container
	hallBins: { [number]: Container }, -- floor -> the bin by the lift
	onItemClicked: ((Player, Model) -> ())?,
}

local Furnish = {}

local REACH = 10
local WOOD = Color3.fromRGB(78, 58, 44)
local DARK_WOOD = Color3.fromRGB(52, 40, 32)
local METAL = Color3.fromRGB(58, 62, 66)

local function ensureGroups()
	pcall(function()
		if not PhysicsService:IsCollisionGroupRegistered("Furniture") then
			PhysicsService:RegisterCollisionGroup("Furniture")
		end
		if not PhysicsService:IsCollisionGroupRegistered("Citizens") then
			PhysicsService:RegisterCollisionGroup("Citizens")
		end
		PhysicsService:CollisionGroupSetCollidable("Furniture", "Citizens", false)
	end)
end

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.WoodPlanks
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CollisionGroup = "Furniture"
	p.Parent = parent
	return p
end

-- A hollow box: bottom, back, two sides and (optionally) a top. `cf` is the centre of the bottom face, front = -Z.
local function shell(parent: Instance, cf: CFrame, w: number, h: number, d: number, t: number, color: Color3, top: boolean, mat: Enum.Material?)
	part(parent, "Bottom", Vector3.new(w, t, d), cf * CFrame.new(0, t / 2, 0), color, mat)
	part(parent, "Back", Vector3.new(w, h, t), cf * CFrame.new(0, h / 2, d / 2 - t / 2), color, mat)
	part(parent, "Left", Vector3.new(t, h, d), cf * CFrame.new(-w / 2 + t / 2, h / 2, 0), color, mat)
	part(parent, "Right", Vector3.new(t, h, d), cf * CFrame.new(w / 2 - t / 2, h / 2, 0), color, mat)
	if top then
		part(parent, "Top", Vector3.new(w, t, d), cf * CFrame.new(0, h - t / 2, 0), color, mat)
	end
end

-- Animate a mover model between its closed and open pivots; clicking any of `handles` toggles it.
local function hinge(c: Container, mover: Model, closed: CFrame, open: CFrame, handles: { BasePart })
	mover.WorldPivot = closed
	local value = Instance.new("CFrameValue")
	value.Value = closed
	value.Changed:Connect(function(v)
		mover:PivotTo(v)
	end)
	value.Parent = mover
	local busy = false
	local function toggle(player: Player)
		if busy or player:GetAttribute("Tool") ~= nil then -- print kit or camera out: the click is for the tool
			return
		end
		busy = true
		c.isOpen = not c.isOpen
		local tween = TweenService:Create(value, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Value = if c.isOpen then open else closed,
		})
		tween:Play()
		tween.Completed:Wait()
		busy = false
	end
	for _, h in handles do
		local cd = Instance.new("ClickDetector")
		cd.MaxActivationDistance = REACH
		cd.Parent = h
		cd.MouseClick:Connect(toggle)
	end
end

function Furnish.bin(parent: Instance, cf: CFrame, color: Color3?): Container
	local m = Instance.new("Model")
	m.Name = "Bin"
	m.Parent = parent
	local w, h, d, t = 1.6, 1.8, 1.6, 0.12
	local col = color or METAL
	shell(m, cf, w, h, d, t, col, false, Enum.Material.Metal)
	part(m, "Front", Vector3.new(w, h, t), cf * CFrame.new(0, h / 2, -d / 2 + t / 2), col, Enum.Material.Metal)
	-- A half-full bag, so whatever is dumped in sits where you can see it once the lid is up
	part(m, "Bag", Vector3.new(w - t * 2, h * 0.6, d - t * 2), cf * CFrame.new(0, t + h * 0.3, 0), Color3.fromRGB(22, 22, 26), Enum.Material.Plastic)
	local lidModel = Instance.new("Model")
	lidModel.Name = "Lid"
	lidModel.Parent = m
	local hingeCF = cf * CFrame.new(0, h, d / 2)
	local lid = part(lidModel, "LidTop", Vector3.new(w + 0.1, 0.15, d + 0.1), hingeCF * CFrame.new(0, 0.075, -d / 2), col, Enum.Material.Metal)
	local handle = part(lidModel, "LidHandle", Vector3.new(0.5, 0.12, 0.12), hingeCF * CFrame.new(0, 0.18, -d + 0.1), Color3.fromRGB(30, 30, 34), Enum.Material.Metal)
	local c: Container = { kind = "bin", model = m, holder = m, slot = cf * CFrame.new(0, t + h * 0.6 + 0.15, 0), isOpen = false }
	hinge(c, lidModel, hingeCF, hingeCF * CFrame.Angles(math.rad(105), 0, 0), { lid, handle })
	return c
end

-- A chest of drawers. Returns one container per drawer, top first.
function Furnish.drawers(parent: Instance, cf: CFrame, count: number, w: number, h: number, d: number, color: Color3?): { Container }
	local m = Instance.new("Model")
	m.Name = "Drawers"
	m.Parent = parent
	local col = color or WOOD
	local t = 0.15
	shell(m, cf, w, h, d, t, col, true)
	local out = {}
	local dh = (h - t * 2) / count
	for i = 1, count do
		local y = h - t - dh * (i - 0.5)
		local base = cf * CFrame.new(0, y - dh / 2 + 0.05, 0)
		local dm = Instance.new("Model")
		dm.Name = "Drawer" .. i
		dm.Parent = m
		local iw, id = w - t * 2 - 0.08, d - t - 0.1
		local front = part(dm, "Front", Vector3.new(w - 0.06, dh - 0.06, 0.14), cf * CFrame.new(0, y, -d / 2 - 0.02), DARK_WOOD)
		local knob = part(dm, "Knob", Vector3.new(0.5, 0.14, 0.14), cf * CFrame.new(0, y, -d / 2 - 0.16), Color3.fromRGB(180, 160, 110), Enum.Material.Metal)
		part(dm, "DBottom", Vector3.new(iw, 0.06, id), base * CFrame.new(0, 0.03, 0), col)
		part(dm, "DBack", Vector3.new(iw, dh * 0.55, 0.06), base * CFrame.new(0, dh * 0.275, id / 2), col)
		part(dm, "DLeft", Vector3.new(0.06, dh * 0.55, id), base * CFrame.new(-iw / 2, dh * 0.275, 0), col)
		part(dm, "DRight", Vector3.new(0.06, dh * 0.55, id), base * CFrame.new(iw / 2, dh * 0.275, 0), col)
		local c: Container = { kind = "drawer", model = m, holder = dm, slot = base * CFrame.new(0, 0.2, 0), isOpen = false }
		local pivot = cf * CFrame.new(0, y, 0)
		hinge(c, dm, pivot, pivot * CFrame.new(0, 0, -(d * 0.75)), { front, knob })
		table.insert(out, c)
	end
	return out
end

function Furnish.wardrobe(parent: Instance, cf: CFrame): Container
	local m = Instance.new("Model")
	m.Name = "Wardrobe"
	m.Parent = parent
	local w, h, d, t = 3, 6.4, 1.9, 0.15
	shell(m, cf, w, h, d, t, WOOD, true)
	part(m, "Rail", Vector3.new(w - 0.4, 0.1, 0.1), cf * CFrame.new(0, h - 0.7, 0), Color3.fromRGB(150, 150, 155), Enum.Material.Metal)
	local doorModel = Instance.new("Model")
	doorModel.Name = "Door"
	doorModel.Parent = m
	local hingeCF = cf * CFrame.new(-w / 2, 0, -d / 2)
	local door = part(doorModel, "Panel", Vector3.new(w, h, 0.14), hingeCF * CFrame.new(w / 2, h / 2, -0.07), DARK_WOOD)
	local pull = part(doorModel, "Pull", Vector3.new(0.12, 0.8, 0.12), hingeCF * CFrame.new(w - 0.35, h / 2, -0.2), Color3.fromRGB(180, 160, 110), Enum.Material.Metal)
	local c: Container = { kind = "wardrobe", model = m, holder = m, slot = cf * CFrame.new(0.3, t + 0.4, 0), isOpen = false }
	hinge(c, doorModel, hingeCF, hingeCF * CFrame.Angles(0, math.rad(100), 0), { door, pull })
	return c
end

local function bed(parent: Instance, cf: CFrame)
	local m = Instance.new("Model")
	m.Name = "Bed"
	m.Parent = parent
	part(m, "Frame", Vector3.new(4.6, 1.2, 6.8), cf * CFrame.new(0, 0.6, 0), DARK_WOOD)
	part(m, "Mattress", Vector3.new(4.3, 0.6, 6.5), cf * CFrame.new(0, 1.5, 0), Color3.fromRGB(196, 190, 182), Enum.Material.Fabric)
	part(m, "Blanket", Vector3.new(4.4, 0.25, 4.2), cf * CFrame.new(0, 1.85, -1.1), Color3.fromRGB(70, 60, 92), Enum.Material.Fabric)
	part(m, "Pillow", Vector3.new(3, 0.45, 1.1), cf * CFrame.new(0, 2, 2.4), Color3.fromRGB(220, 214, 206), Enum.Material.Fabric)
	part(m, "Headboard", Vector3.new(4.6, 3, 0.3), cf * CFrame.new(0, 1.5, 3.25), DARK_WOOD)
end

---------------------------------------------------------------- Items
-- Small objects that sit in containers. Clicking one hands it to `onItemClicked`.
local JUNK: { { name: string, size: Vector3, color: Color3, mat: Enum.Material, text: string } } = {
	{ name = "Receipts", size = Vector3.new(0.6, 0.05, 0.9), color = Color3.fromRGB(230, 226, 214), mat = Enum.Material.SmoothPlastic, text = "Old receipts. Groceries, a dry cleaner, nothing that matters." },
	{ name = "Keys", size = Vector3.new(0.4, 0.08, 0.25), color = Color3.fromRGB(190, 180, 120), mat = Enum.Material.Metal, text = "A spare key on a plastic tag. It doesn't say what for." },
	{ name = "Menu", size = Vector3.new(0.8, 0.04, 1.1), color = Color3.fromRGB(200, 60, 50), mat = Enum.Material.SmoothPlastic, text = "A takeaway menu from the Night Owl Diner." },
	{ name = "Socks", size = Vector3.new(0.7, 0.2, 0.5), color = Color3.fromRGB(70, 70, 80), mat = Enum.Material.Fabric, text = "Socks. Unmatched." },
	{ name = "Bottle", size = Vector3.new(0.35, 1, 0.35), color = Color3.fromRGB(40, 90, 60), mat = Enum.Material.Glass, text = "An empty bottle." },
	{ name = "Letters", size = Vector3.new(0.7, 0.12, 1), color = Color3.fromRGB(236, 230, 210), mat = Enum.Material.SmoothPlastic, text = "Bills and a postcard from somewhere sunny. Nothing about last night." },
	{ name = "Charger", size = Vector3.new(0.5, 0.1, 0.5), color = Color3.fromRGB(30, 30, 30), mat = Enum.Material.Plastic, text = "A tangled phone charger." },
	{ name = "Batteries", size = Vector3.new(0.5, 0.2, 0.3), color = Color3.fromRGB(60, 120, 200), mat = Enum.Material.Plastic, text = "A pack of batteries, half used." },
	{ name = "Wrappers", size = Vector3.new(0.7, 0.15, 0.6), color = Color3.fromRGB(200, 170, 60), mat = Enum.Material.Plastic, text = "Food wrappers." },
}

local furniture: Furniture? = nil

function Furnish.item(c: Container, name: string, parts: { { size: Vector3, offset: CFrame, color: Color3, mat: Enum.Material } }): Model
	local m = Instance.new("Model")
	m.Name = name
	-- Spread items out a little so several fit
	local n = 0
	for _, ch in c.holder:GetChildren() do
		if ch:GetAttribute("Item") then
			n += 1
		end
	end
	local at = c.slot * CFrame.new(((n % 3) - 1) * 0.45, 0, ((n // 3) % 2 - 0.5) * 0.4)
	local first: BasePart? = nil
	for _, spec in parts do
		local p = part(m, name, spec.size, at * spec.offset, spec.color, spec.mat)
		p.CanCollide = false
		first = first or p
	end
	m.PrimaryPart = first
	m:SetAttribute("Item", name)
	m.Parent = c.holder
	local cd = Instance.new("ClickDetector")
	cd.MaxActivationDistance = REACH
	cd.Parent = m
	cd.MouseClick:Connect(function(player)
		if furniture and furniture.onItemClicked and m.Parent then
			furniture.onItemClicked(player, m)
		end
	end)
	return m
end

local function junk(c: Container, rng: Rng)
	local j = rng:pick(JUNK)
	if c.kind == "drawer" and j.size.Y > 0.4 then
		j = JUNK[1] -- tall things don't fit in a drawer
	end
	local m = Furnish.item(c, j.name, { { size = j.size, offset = CFrame.new(0, j.size.Y / 2 - 0.15, 0), color = j.color, mat = j.mat } })
	m:SetAttribute("Junk", j.text)
end

---------------------------------------------------------------- Layout
-- Builds furniture into every apartment and office, plus a lidded bin by the lift on each floor.
function Furnish.furnish(world: World, rng: Rng): Furniture
	ensureGroups()
	local folder = Instance.new("Folder")
	folder.Name = "Furniture"
	folder.Parent = workspace
	local f: Furniture = { rooms = {}, hallBins = {}, onItemClicked = nil }
	furniture = f

	for _, room in world.roomList do
		local floorY = room.center.Y - 3
		local north = room.center.Z > 0
		local s = if north then 1 else -1 -- +s points from the corridor toward the outer wall
		local x0, x1 = room.center.X - room.size.X / 2, room.center.X + room.size.X / 2
		local zIn = room.center.Z - s * room.size.Z / 2
		local zOut = room.center.Z + s * room.size.Z / 2
		-- A CFrame on the floor at (x, z) whose front (-Z) faces `face`
		local function at(x: number, z: number, face: Vector3): CFrame
			local p = Vector3.new(x, floorY + 0.05, z)
			return CFrame.lookAt(p, p + face)
		end
		local set: { [string]: Container } = {}
		f.rooms[room.id] = set
		local rf = Instance.new("Folder")
		rf.Name = room.id
		rf.Parent = folder

		if room.kind == "apartment" then
			bed(rf, at(x1 - 3.4, zOut - s * 3.7, Vector3.new(0, 0, -s)))
			local dr = Furnish.drawers(rf, at(x0 + 1.1, room.center.Z + s * 1.5, Vector3.new(1, 0, 0)), 3, 3.2, 3, 1.7)
			set.drawer1, set.drawer2, set.drawer3 = dr[1], dr[2], dr[3]
			set.wardrobe = Furnish.wardrobe(rf, at(x0 + 2.2, zIn + s * 1.3, Vector3.new(0, 0, -s)) * CFrame.Angles(0, math.pi, 0))
			set.bin = Furnish.bin(rf, at(x1 - 1.4, zIn + s * 1.2, Vector3.new(0, 0, -s)) * CFrame.Angles(0, math.pi, 0), Color3.fromRGB(150, 150, 146))
		elseif room.kind == "office" or room.kind == "clinic" or room.kind == "security" or room.kind == "detective" then
			local dr = Furnish.drawers(rf, at(x0 + 1.1, zOut - s * 2.5, Vector3.new(1, 0, 0)), 3, 2, 4.2, 2.2, METAL)
			set.drawer1, set.drawer2, set.drawer3 = dr[1], dr[2], dr[3]
			set.bin = Furnish.bin(rf, at(x1 - 1.4, zIn + s * 1.2, Vector3.new(0, 0, -s)) * CFrame.Angles(0, math.pi, 0))
		end

		-- Everyday clutter so that searching means searching
		local names = {}
		for name in set do
			table.insert(names, name)
		end
		table.sort(names) -- same clutter every time the world is rebuilt
		for _, name in names do
			if rng:chance(0.55) then
				junk(set[name], rng)
			end
			if rng:chance(0.2) then
				junk(set[name], rng)
			end
		end
	end

	-- A lidded bin by the lift on every floor
	local floors = {}
	for floor in world.elevators do
		table.insert(floors, floor)
	end
	table.sort(floors)
	for _, floor in floors do
		local floorY = world.elevators[floor].Y - 3
		f.hallBins[floor] = Furnish.bin(folder, CFrame.lookAt(Vector3.new(1.5, floorY + 0.05, 2.8), Vector3.new(1.5, floorY + 0.05, 0)))
		if rng:chance(0.6) then
			junk(f.hallBins[floor], rng)
		end
	end
	return f
end

return Furnish
