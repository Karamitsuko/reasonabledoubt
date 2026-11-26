--!strict
-- Runs citizens against the clock with simulation level of detail:
--   Tier 0 (near a player): a real body that walks its route through doors, corridors and the elevator.
--   Everyone else: a record whose location is a schedule lookup.
-- A body that cannot reach a waypoint in time is snapped to it, so citizens never stay stuck.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local BuildingGen = require(script.Parent:WaitForChild("BuildingGen"))
local CitizenGen = require(script.Parent:WaitForChild("CitizenGen"))
local Schedule = require(script.Parent:WaitForChild("Schedule"))

type World = BuildingGen.World
type Citizen = CitizenGen.Citizen

type Waypoint = { pos: Vector3, teleport: boolean? }

type CitizenState = {
	loc: string,
	spot: Vector3,
	rig: Model?,
	spawning: boolean,
	moving: boolean,
	token: number,
	nextIdle: number,
}

local CitizenSim = {}
CitizenSim.__index = CitizenSim

export type CitizenSim = typeof(setmetatable(
	{} :: {
		world: World,
		citizens: { Citizen },
		state: { [number]: CitizenState },
		folder: Folder,
		rigCount: number,
		snaps: number,
		idleRng: Random,
		excluded: { [number]: boolean },
		onRigSpawned: ((Citizen, Model) -> ())?,
		keepClear: { { pos: Vector3, radius: number } },
	},
	CitizenSim
))

local function strHash(s: string): number
	local h = 0
	for i = 1, #s do
		h = (h * 31 + string.byte(s, i)) % 2147483647
	end
	return h
end

function CitizenSim.new(world: World, citizens: { Citizen }): CitizenSim
	local folder = Instance.new("Folder")
	folder.Name = "Citizens"
	folder.Parent = workspace
	local self = setmetatable({
		world = world,
		citizens = citizens,
		state = {},
		folder = folder,
		rigCount = 0,
		snaps = 0,
		idleRng = Random.new(),
		excluded = {},
		onRigSpawned = nil,
		keepClear = {},
	}, CitizenSim)
	return self
end

-- A stable standing spot for this citizen inside a location.
-- Push a standing spot out of any keep-clear zone (a crime scene, for example).
function CitizenSim.clearOf(self: CitizenSim, p: Vector3): Vector3
	for _, z in self.keepClear do
		local d = Vector3.new(p.X - z.pos.X, 0, p.Z - z.pos.Z)
		if math.abs(p.Y - z.pos.Y) < 6 and d.Magnitude < z.radius then
			local dir = if d.Magnitude > 0.01 then d.Unit else Vector3.new(1, 0, 0)
			p = Vector3.new(z.pos.X, p.Y, z.pos.Z) + dir * z.radius
		end
	end
	return p
end

function CitizenSim.spotFor(self: CitizenSim, c: Citizen, loc: string): Vector3
	if loc == "offsite" then
		local r = Random.new(c.id * 7 + 1)
		return self.world.street + Vector3.new(r:NextNumber(-20, 20), 0, r:NextNumber(-1.5, 1.5))
	end
	local room = self.world.rooms[loc]
	local r = Random.new(c.id * 1000 + strHash(loc))
	local hx, hz = room.size.X / 2 - 2.5, room.size.Z / 2 - 2.5
	return self:clearOf(room.center + Vector3.new(r:NextNumber(-hx, hx), 0, r:NextNumber(-hz, hz)))
end

function CitizenSim.pathToCorridor(self: CitizenSim, loc: string, spot: Vector3): (number, { Vector3 })
	if loc == "offsite" then
		local lobby = self.world.rooms[self.world.lobbyId]
		return 0, { spot, self.world.streetDoorOut, self.world.streetDoorIn, lobby.doorInner, lobby.corridor }
	end
	local room = self.world.rooms[loc]
	return room.floor, { spot, room.doorInner, room.corridor }
end

function CitizenSim.route(self: CitizenSim, fromLoc: string, fromSpot: Vector3, toLoc: string, toSpot: Vector3): { Waypoint }
	if fromLoc == toLoc then
		return { { pos = toSpot } }
	end
	local fa, pa = self:pathToCorridor(fromLoc, fromSpot)
	local fb, pb = self:pathToCorridor(toLoc, toSpot)
	local pts: { Waypoint } = {}
	for i = 2, #pa do
		table.insert(pts, { pos = pa[i] })
	end
	if fa ~= fb then
		table.insert(pts, { pos = self.world.elevators[fa] })
		table.insert(pts, { pos = self.world.elevators[fb], teleport = true })
	end
	for i = #pb, 1, -1 do
		table.insert(pts, { pos = pb[i] })
	end
	return pts
end

function CitizenSim.locPosition(self: CitizenSim, loc: string): Vector3
	if loc == "offsite" then
		return self.world.street
	end
	return self.world.rooms[loc].center
end

function CitizenSim.buildRig(c: Citizen): Model?
	local desc = Instance.new("HumanoidDescription")
	desc.HeadColor = c.skinTone
	desc.TorsoColor = c.shirtColor
	desc.LeftArmColor = c.shirtColor
	desc.RightArmColor = c.shirtColor
	desc.LeftLegColor = c.pantsColor
	desc.RightLegColor = c.pantsColor
	desc.HeightScale = math.clamp(c.heightCm / 175, 0.9, 1.1)
	local ok, result = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok then
		warn("[CitizenSim] Could not build a body:", result)
		return nil
	end
	return result :: Model
end

function CitizenSim.spawnRig(self: CitizenSim, c: Citizen, st: CitizenState)
	st.spawning = true
	self.rigCount += 1
	task.spawn(function()
		local rig = CitizenSim.buildRig(c)
		st.spawning = false
		if not rig then
			self.rigCount -= 1
			return
		end
		rig.Name = ("Citizen_%d"):format(c.id)
		rig:SetAttribute("CitizenId", c.id)
		rig:SetAttribute("FullName", c.firstName .. " " .. c.lastName)
		rig:SetAttribute("Job", c.job)
		local hum = rig:FindFirstChildOfClass("Humanoid") :: Humanoid
		hum.DisplayName = c.firstName .. " " .. c.lastName
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
		hum.NameDisplayDistance = 18
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		hum.WalkSpeed = Config.WALK_SPEED
		rig:PivotTo(CFrame.new(st.spot) * CFrame.Angles(0, math.rad((c.id * 47) % 360), 0))
		rig.Parent = self.folder
		local root = rig.PrimaryPart
		if root then
			pcall(function()
				root:SetNetworkOwner(nil)
			end)
		end
		st.rig = rig
		if self.onRigSpawned then
			self.onRigSpawned(c, rig)
		end
	end)
end

-- Take a citizen out of the simulation (for example, a murder victim).
function CitizenSim.exclude(self: CitizenSim, id: number)
	self.excluded[id] = true
	local st = self.state[id]
	if st then
		self:despawnRig(st)
	end
end

function CitizenSim.rigFor(self: CitizenSim, id: number): Model?
	local st = self.state[id]
	return st and st.rig
end

-- Stop a citizen where they stand for a while (being interviewed), turned toward the player.
function CitizenSim.hold(self: CitizenSim, id: number, seconds: number, facing: Player?)
	local st = self.state[id]
	if not st or not st.rig then
		return
	end
	st.token += 1
	st.moving = false
	st.nextIdle = os.clock() + seconds
	local rig = st.rig :: Model
	local hum = rig:FindFirstChildOfClass("Humanoid")
	local root = rig.PrimaryPart
	if hum and root then
		hum:MoveTo(root.Position)
		local char = facing and facing.Character
		if char then
			local target = char:GetPivot().Position
			root.CFrame = CFrame.lookAt(root.Position, Vector3.new(target.X, root.Position.Y, target.Z))
		end
	end
end

function CitizenSim.despawnRig(self: CitizenSim, st: CitizenState)
	st.token += 1
	st.moving = false
	if st.rig then
		st.rig:Destroy()
		st.rig = nil
		self.rigCount -= 1
	end
end

function CitizenSim.walk(self: CitizenSim, st: CitizenState, waypoints: { Waypoint })
	st.token += 1
	local token = st.token
	st.moving = true
	task.spawn(function()
		for _, wp in waypoints do
			local rig = st.rig
			if st.token ~= token or not rig then
				return
			end
			local hum = rig:FindFirstChildOfClass("Humanoid")
			if not hum then
				return
			end
			if wp.teleport then
				task.wait(1.5) -- waiting for the lift
				if st.token ~= token then
					return
				end
				rig:PivotTo(CFrame.new(wp.pos))
			else
				local done = false
				local conn = hum.MoveToFinished:Connect(function()
					done = true
				end)
				hum:MoveTo(wp.pos)
				local t0 = os.clock()
				while not done and st.token == token and os.clock() - t0 < Config.WAYPOINT_TIMEOUT do
					task.wait(0.1)
				end
				conn:Disconnect()
				if st.token ~= token then
					return
				end
				local root = rig.PrimaryPart
				if root and (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(wp.pos.X, 0, wp.pos.Z)).Magnitude > 4 then
					self.snaps += 1
					rig:PivotTo(CFrame.new(wp.pos))
				end
			end
		end
		if st.token == token then
			st.moving = false
		end
	end)
end

function CitizenSim.tick(self: CitizenSim, totalMinutes: number)
	local playerPositions = {}
	for _, p in Players:GetPlayers() do
		local char = p.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			table.insert(playerPositions, root.Position)
		end
	end
	local function near(pos: Vector3): boolean
		for _, pp in playerPositions do
			if (pp - pos).Magnitude <= Config.TIER0_RADIUS then
				return true
			end
		end
		return false
	end

	for _, c in self.citizens do
		if self.excluded[c.id] then
			continue
		end
		local loc = Schedule.locationAt(c, totalMinutes)
		local st = self.state[c.id]
		if not st then
			st = { loc = loc, spot = self:spotFor(c, loc), rig = nil, spawning = false, moving = false, token = 0, nextIdle = 0 }
			self.state[c.id] = st
		elseif st.loc ~= loc then
			local fromLoc, fromSpot = st.loc, st.spot
			st.loc = loc
			st.spot = self:spotFor(c, loc)
			if st.rig then
				self:walk(st, self:route(fromLoc, fromSpot, loc, st.spot))
			end
		end

		local isNear = loc ~= "offsite" and near(self:locPosition(loc))
		if isNear and not st.rig and not st.spawning and self.rigCount < Config.MAX_RIGS then
			self:spawnRig(c, st)
		elseif st.rig and not st.moving then
			local rigNear = st.rig.PrimaryPart ~= nil and near((st.rig.PrimaryPart :: BasePart).Position)
			if loc == "offsite" or (not isNear and not rigNear) then
				self:despawnRig(st)
			end
		end

		-- Idle life: awake people shift around the room every so often instead of standing frozen.
		if st.rig and not st.moving and loc ~= "offsite" and os.clock() >= st.nextIdle then
			st.nextIdle = os.clock() + self.idleRng:NextNumber(5, 16)
			if not Schedule.isAsleep(c, totalMinutes) then
				local room = self.world.rooms[loc]
				local hx, hz = room.size.X / 2 - 2.5, room.size.Z / 2 - 2.5
				st.spot = self:clearOf(room.center + Vector3.new(self.idleRng:NextNumber(-hx, hx), 0, self.idleRng:NextNumber(-hz, hz)))
				self:walk(st, { { pos = st.spot } })
			end
		end
	end
end

function CitizenSim.stats(self: CitizenSim): { [string]: any }
	local byLoc: { [string]: number } = {}
	local moving = 0
	for _, st in self.state do
		local label = if st.loc == "offsite" then "offsite" else self.world.rooms[st.loc].label
		byLoc[label] = (byLoc[label] or 0) + 1
		if st.moving then
			moving += 1
		end
	end
	return { rigs = self.rigCount, moving = moving, snaps = self.snaps, byLocation = byLoc }
end

return CitizenSim
