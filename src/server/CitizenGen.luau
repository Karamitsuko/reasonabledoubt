--!strict
-- Generates citizen records from a seed: identity, home, job, routine and relationships.
-- Citizens are plain data; bodies only exist near players (see CitizenSim).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Names = require(Shared:WaitForChild("Names"))
local RngModule = require(Shared:WaitForChild("Rng"))
local BuildingGen = require(script.Parent:WaitForChild("BuildingGen"))

type Rng = RngModule.Rng
type World = BuildingGen.World

export type Relationship = { id: number, kind: string }

export type Citizen = {
	id: number,
	firstName: string,
	lastName: string,
	age: number,
	heightCm: number,
	shoeSize: number,
	bloodType: string,
	traits: { string },
	skinTone: Color3,
	shirtColor: Color3,
	pantsColor: Color3,
	homeRoom: string,
	job: string,
	workRoom: string?, -- room id, "offsite", or nil when unemployed
	shiftStart: number, -- minutes after midnight
	shiftEnd: number,
	daysOff: { [number]: boolean }, -- day-of-week index 0..6
	wake: number,
	sleep: number,
	lunchChance: number,
	lunchSpot: string?,
	eveningStart: number,
	eveningChance: number,
	eveningSpot: string?,
	errandSpots: { string },
	relationships: { Relationship },
}

local H = 60

type JobDef = { cap: number, titles: { string }, shifts: { { number } } }
local JOBS: { [string]: JobDef } = {
	diner = { cap = 4, titles = { "cook", "server" }, shifts = { { 7 * H, 15 * H }, { 15 * H, 23 * H } } },
	bar = { cap = 3, titles = { "bartender", "bar back" }, shifts = { { 18 * H, 2 * H } } },
	shop = { cap = 2, titles = { "clerk" }, shifts = { { 8 * H, 16 * H }, { 14 * H, 22 * H } } },
	security = { cap = 2, titles = { "security guard" }, shifts = { { 22 * H, 6 * H }, { 6 * H, 14 * H } } },
	lobby = { cap = 1, titles = { "doorman" }, shifts = { { 8 * H, 18 * H } } },
	office = { cap = 4, titles = { "analyst", "clerk", "manager", "accountant", "receptionist" }, shifts = { { 9 * H, 17 * H } } },
	clinic = { cap = 3, titles = { "nurse", "doctor" }, shifts = { { 20 * H, 4 * H }, { 8 * H, 16 * H } } },
}

local OFFSITE_JOBS = { "dock worker", "taxi driver", "teacher", "mechanic", "programmer", "courier", "line cook", "tram driver" }
local TRAITS = {
	"honest", "nervous", "proud", "greedy", "loyal", "hostile to police",
	"gossip", "private", "friendly", "quick-tempered", "observant", "forgetful",
}
local BLOOD = {
	{ value = "O+", weight = 38 }, { value = "A+", weight = 34 }, { value = "B+", weight = 9 },
	{ value = "AB+", weight = 3 }, { value = "O-", weight = 7 }, { value = "A-", weight = 6 },
	{ value = "B-", weight = 2 }, { value = "AB-", weight = 1 },
}
local SKIN = {
	Color3.fromRGB(255, 224, 196), Color3.fromRGB(234, 192, 160), Color3.fromRGB(204, 152, 112),
	Color3.fromRGB(168, 116, 80), Color3.fromRGB(124, 82, 56), Color3.fromRGB(86, 56, 40),
}
local CLOTHES = {
	Color3.fromRGB(30, 30, 36), Color3.fromRGB(60, 52, 44), Color3.fromRGB(40, 50, 66),
	Color3.fromRGB(80, 30, 40), Color3.fromRGB(46, 62, 52), Color3.fromRGB(110, 100, 88),
	Color3.fromRGB(150, 140, 120), Color3.fromRGB(24, 40, 60), Color3.fromRGB(90, 70, 110),
}

local function isNightShift(s: number): boolean
	return s >= 18 * H or s < 4 * H
end

local CitizenGen = {}

function CitizenGen.generate(rng: Rng, world: World): { Citizen }
	local apartments, diners, bars, errands = {}, {}, {}, {}
	local jobSlots: { { room: string, kind: string } } = {}
	for _, room in world.roomList do
		if room.kind == "apartment" then
			table.insert(apartments, room.id)
		elseif room.kind == "diner" then
			table.insert(diners, room.id)
		elseif room.kind == "bar" then
			table.insert(bars, room.id)
		end
		if room.kind == "diner" or room.kind == "shop" then
			table.insert(errands, room.id)
		end
		local def = JOBS[room.kind]
		if def then
			for _ = 1, def.cap do
				table.insert(jobSlots, { room = room.id, kind = room.kind })
			end
		end
	end
	rng:shuffle(apartments)
	rng:shuffle(jobSlots)

	local usedNames: { [string]: boolean } = {}
	local citizens: { Citizen } = {}
	for i = 1, Config.CITIZEN_COUNT do
		local first, last
		repeat
			first, last = rng:pick(Names.first), rng:pick(Names.last)
		until not usedNames[first .. last]
		usedNames[first .. last] = true

		local traits = {}
		local pool = table.clone(TRAITS)
		rng:shuffle(pool)
		for t = 1, 3 do
			traits[t] = pool[t]
		end

		local heightCm = rng:int(152, 196)
		local shoe = math.clamp(math.floor(36 + (heightCm - 150) / 46 * 11 + rng:float(-1, 1) + 0.5), 35, 48)

		-- Job
		local job, workRoom, shiftStart, shiftEnd = "unemployed", nil, 0, 0
		local slot = table.remove(jobSlots)
		if slot then
			local def = JOBS[slot.kind]
			job = rng:pick(def.titles)
			workRoom = slot.room
			local shift = rng:pick(def.shifts)
			shiftStart, shiftEnd = shift[1], shift[2]
		elseif rng:chance(0.85) then
			job = rng:pick(OFFSITE_JOBS)
			workRoom = "offsite"
			local start = rng:pick({ 7 * H, 8 * H, 9 * H, 14 * H })
			shiftStart, shiftEnd = start, (start + 8 * H) % (24 * H)
		end

		-- Routine
		local wake, sleep
		if workRoom and isNightShift(shiftStart) then
			sleep = (shiftEnd + rng:int(30, 90)) % (24 * H)
			wake = (sleep + rng:int(7 * H, 8 * H)) % (24 * H)
		elseif workRoom then
			wake = math.max(5 * H, shiftStart - rng:int(45, 100))
			sleep = (23 * H + rng:int(-60, 70)) % (24 * H)
		else
			wake = rng:int(8 * H, 10 * H)
			sleep = rng:int(0, 90)
		end

		local offDay = rng:int(0, 6)
		local daysOff = { [offDay] = true, [(offDay + 1) % 7] = true }

		local eveningStart = if workRoom and isNightShift(shiftStart) then 16 * H else 19 * H + rng:int(0, 60)

		citizens[i] = {
			id = i,
			firstName = first,
			lastName = last,
			age = rng:int(19, 72),
			heightCm = heightCm,
			shoeSize = shoe,
			bloodType = rng:weighted(BLOOD),
			traits = traits,
			skinTone = rng:pick(SKIN),
			shirtColor = rng:pick(CLOTHES),
			pantsColor = rng:pick(CLOTHES),
			homeRoom = apartments[((i - 1) % #apartments) + 1],
			job = job,
			workRoom = workRoom,
			shiftStart = shiftStart,
			shiftEnd = shiftEnd,
			daysOff = daysOff,
			wake = wake,
			sleep = sleep,
			lunchChance = rng:float(0.2, 0.7),
			lunchSpot = if #diners > 0 then diners[1] else nil,
			eveningStart = eveningStart,
			eveningChance = rng:float(0.1, 0.5),
			eveningSpot = nil,
			errandSpots = errands,
			relationships = {},
		}
	end

	-- Relationships: people sharing an apartment, coworkers, and a web of friends
	local function relate(a: Citizen, b: Citizen, kind: string)
		table.insert(a.relationships, { id = b.id, kind = kind })
		table.insert(b.relationships, { id = a.id, kind = kind })
	end
	local byHome: { [string]: { Citizen } } = {}
	local byWork: { [string]: { Citizen } } = {}
	for _, c in citizens do
		byHome[c.homeRoom] = byHome[c.homeRoom] or {}
		table.insert(byHome[c.homeRoom], c)
		if c.workRoom and c.workRoom ~= "offsite" then
			byWork[c.workRoom] = byWork[c.workRoom] or {}
			table.insert(byWork[c.workRoom], c)
		end
	end
	for _, group in byHome do
		for a = 1, #group do
			for b = a + 1, #group do
				relate(group[a], group[b], if #group == 2 and rng:chance(0.6) then "partner" else "roommate")
			end
		end
	end
	for _, group in byWork do
		for a = 1, #group do
			for b = a + 1, #group do
				relate(group[a], group[b], "coworker")
			end
		end
	end
	for _ = 1, math.floor(#citizens * 0.6) do
		local a, b = rng:pick(citizens), rng:pick(citizens)
		if a ~= b then
			relate(a, b, "friend")
		end
	end

	-- Evening plans: the bar, the diner, or a friend's place
	for _, c in citizens do
		local roll = rng:float()
		if roll < 0.4 and #bars > 0 then
			c.eveningSpot = bars[1]
		elseif roll < 0.7 and #diners > 0 then
			c.eveningSpot = diners[1]
		else
			for _, r in c.relationships do
				if r.kind == "friend" then
					c.eveningSpot = citizens[r.id].homeRoom
					break
				end
			end
		end
	end

	return citizens
end

return CitizenGen
