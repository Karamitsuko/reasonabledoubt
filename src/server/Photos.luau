--!strict
-- The camera. The client takes the shot (and keeps the picture for this session); the server works out what
-- the photo actually shows from the camera's position: who is in frame and not hidden behind a wall, any
-- evidence or traces in view, and where it was taken. Each photo becomes a notebook entry.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BuildingGen = require(script.Parent:WaitForChild("BuildingGen"))
local CitizenGen = require(script.Parent:WaitForChild("CitizenGen"))
local CaseGen = require(script.Parent:WaitForChild("CaseGen"))

type World = BuildingGen.World
type Citizen = CitizenGen.Citizen
type Case = CaseGen.Case

export type Photo = { n: number, at: number, place: string, shows: { string } }

local Photos = {}

local MAX_PHOTOS = 60
local RANGE = 70
local HALF_FOV = math.rad(32)

local function fullName(c: Citizen): string
	return c.firstName .. " " .. c.lastName
end

-- A plain colour name for describing someone you can't name.
local function colourName(c: Color3): string
	local h, s, v = c:ToHSV()
	if v < 0.18 then
		return "black"
	elseif s < 0.15 then
		return if v > 0.8 then "white" elseif v > 0.45 then "grey" else "dark grey"
	end
	local deg = h * 360
	local base = if deg < 15 or deg >= 345
		then "red"
		elseif deg < 40 then "orange"
		elseif deg < 70 then "yellow"
		elseif deg < 160 then "green"
		elseif deg < 200 then "teal"
		elseif deg < 255 then "blue"
		elseif deg < 290 then "purple"
		else "pink"
	return if v < 0.45 then "dark " .. base else base
end

function Photos.placeAt(world: World, pos: Vector3): string
	for _, room in world.roomList do
		local d = pos - room.center
		if math.abs(d.X) <= room.size.X / 2 and math.abs(d.Z) <= room.size.Z / 2 and math.abs(d.Y) <= room.size.Y / 2 + 1 then
			return room.label
		end
	end
	for floor, lift in world.elevators do
		if math.abs(pos.Y - lift.Y) < 4 then
			return ("the corridor, floor %d"):format(floor)
		end
	end
	return "the street"
end

function Photos.items(photos: { Photo }, add: (string, string, string, { string }, number?) -> ())
	for _, p in photos do
		local lines = { ("Taken in %s at %s."):format(p.place, CaseGen.fmtTime(p.at)) }
		table.insert(lines, if #p.shows > 0 then "Shows " .. table.concat(p.shows, "; ") .. "." else "Nothing much in it.")
		add("photo:" .. p.n, "photo", "Photo " .. p.n, lines, p.n)
	end
end

export type Setup = {
	world: World,
	citizens: { Citizen },
	case: Case,
	remotes: Folder,
	photos: () -> { Photo },
	isKnown: (number) -> boolean,
	changed: () -> (),
}

function Photos.setup(s: Setup)
	local world, citizens, case = s.world, s.citizens, s.case
	local remote = Instance.new("RemoteFunction")
	remote.Name = "TakePhoto"
	remote.Parent = s.remotes

	local function visible(player: Player, from: Vector3, look: Vector3, target: Instance, at: Vector3): boolean
		local v = at - from
		if v.Magnitude > RANGE or v.Magnitude < 0.5 or v.Unit:Dot(look) < math.cos(HALF_FOV) then
			return false
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { player.Character :: Instance }
		local hit = workspace:Raycast(from, v, params)
		return hit == nil or hit.Instance:IsDescendantOf(target) or (hit.Position - at).Magnitude < 1.5
	end

	remote.OnServerInvoke = function(player: Player, cf: any): any
		local photos = s.photos()
		if typeof(cf) ~= "CFrame" then
			return nil
		end
		local char = player.Character
		-- The shot has to come from where the player actually is.
		if not char or (char:GetPivot().Position - cf.Position).Magnitude > 30 then
			return nil
		end
		if #photos >= MAX_PHOTOS then
			return { text = "The camera's memory is full." }
		end
		local from, look = cf.Position, cf.LookVector
		local shows: { string } = {}

		local folder = workspace:FindFirstChild("Citizens")
		if folder then
			for _, rig in folder:GetChildren() do
				local id = rig:GetAttribute("CitizenId")
				local head = rig:FindFirstChild("Head") :: BasePart?
				if typeof(id) == "number" and rig:IsA("Model") and head and visible(player, from, look, rig, head.Position) then
					local c = citizens[id]
					if c then
						table.insert(shows, if s.isKnown(id) then fullName(c) else "someone in a " .. colourName(c.shirtColor) .. " shirt")
					end
				end
			end
		end
		local scene = workspace:FindFirstChild("CaseScene")
		if scene then
			local body = scene:FindFirstChild("Body")
			if body and body:IsA("Model") and visible(player, from, look, body, body:GetPivot().Position) then
				table.insert(shows, "the body of " .. fullName(citizens[case.victimId]))
			end
			local prints = scene:FindFirstChild("ShoePrints")
			if prints and prints:IsA("Model") and visible(player, from, look, prints, prints:GetPivot().Position) then
				table.insert(shows, "shoe prints in spilled coffee")
			end
		end
		local furniture = workspace:FindFirstChild("Furniture")
		if furniture then
			for _, d in furniture:GetDescendants() do
				local ev = d:GetAttribute("Evidence")
				if typeof(ev) == "string" and d:IsA("Model") and visible(player, from, look, d, d:GetPivot().Position) then
					table.insert(shows, string.lower(d.Name))
				end
			end
		end

		local photo: Photo = {
			n = #photos + 1,
			at = math.floor(tonumber(ReplicatedStorage:GetAttribute("GameMinutes")) or 0),
			place = Photos.placeAt(world, from),
			shows = shows,
		}
		table.insert(photos, photo)
		s.changed()
		return { n = photo.n, text = ("Photo %d saved to your notebook."):format(photo.n) }
	end
end

return Photos
