--!strict
-- Generates a murder backwards from a story: a victim home alone, a killer with a reason drawn from
-- their real relationship, and the traces the crime leaves. Every case has at least three independent
-- routes to the killer (lift log + note initials, footprints + boots, witness descriptions + alibi lies).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RngModule = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Rng"))
local BuildingGen = require(script.Parent:WaitForChild("BuildingGen"))
local CitizenGen = require(script.Parent:WaitForChild("CitizenGen"))
local Schedule = require(script.Parent:WaitForChild("Schedule"))

type Rng = RngModule.Rng
type World = BuildingGen.World
type Citizen = CitizenGen.Citizen

export type Evidence = {
	id: string,
	label: string,
	text: string,
	roomId: string?, -- where it physically is, if anywhere
	people: { number }?, -- people this evidence puts on the board
}

export type DoorLogEntry = { minute: number, citizenId: number, direction: string }

export type Case = {
	victimId: number,
	killerId: number,
	motive: string, -- "jealousy" | "debt" | "rivalry"
	relationKind: string,
	method: string, -- "blade" | "blunt"
	tod: number, -- time of death, total game minutes (negative = the night before day 1)
	sceneRoom: string,
	sceneFloor: number,
	initials: string,
	doorLog: { DoorLogEntry },
	evidence: { [string]: Evidence },
	evidenceOrder: { string },
}

local MOTIVE_FOR: { [string]: string } = {
	partner = "jealousy",
	friend = "debt",
	roommate = "debt",
	coworker = "rivalry",
}

local CaseGen = {}

function CaseGen.fmtTime(total: number): string
	local m = math.floor(total % 1440)
	return ("%02d:%02d"):format(m // 60, m % 60)
end

local function fullName(c: Citizen): string
	return c.firstName .. " " .. c.lastName
end

function CaseGen.generate(rng: Rng, world: World, citizens: { Citizen }): Case
	local tod = rng:int(-120, 60)

	local function homeAlone(c: Citizen): boolean
		if Schedule.locationAt(c, tod) ~= c.homeRoom then
			return false
		end
		for _, o in citizens do
			if o ~= c and o.homeRoom == c.homeRoom and Schedule.locationAt(o, tod) == o.homeRoom then
				return false
			end
		end
		return true
	end

	local function killerOptions(v: Citizen): { { id: number, kind: string } }
		local out = {}
		for _, r in v.relationships do
			local k = citizens[r.id]
			if MOTIVE_FOR[r.kind] and k.homeRoom ~= v.homeRoom then
				table.insert(out, { id = r.id, kind = r.kind })
			end
		end
		return out
	end

	-- Pick a victim who is home alone at the time of death and has someone with a reason.
	local order = {}
	for i = 1, #citizens do
		order[i] = i
	end
	rng:shuffle(order)
	local victim: Citizen? = nil
	local options = {}
	for pass = 1, 2 do
		for _, i in order do
			local c = citizens[i]
			local opts = killerOptions(c)
			if #opts > 0 and (pass == 2 or homeAlone(c)) then
				victim, options = c, opts
				break
			end
		end
		if victim then
			break
		end
	end
	assert(victim, "no viable victim")
	local v = victim :: Citizen

	local pick = rng:pick(options)
	local k = citizens[pick.id]
	local motive = MOTIVE_FOR[pick.kind]
	local method = rng:pick({ "blade", "blunt" })
	local scene = world.rooms[v.homeRoom]
	local initials = k.firstName:sub(1, 1) .. "." .. k.lastName:sub(1, 1) .. "."

	-- Lift keycard log: the killer up and down, plus neighbours coming home around then.
	local log: { DoorLogEntry } = {
		{ minute = tod - rng:int(8, 18), citizenId = k.id, direction = "up" },
		{ minute = tod + rng:int(6, 14), citizenId = k.id, direction = "down" },
	}
	local decoys = {}
	for _, o in citizens do
		if o ~= v and o ~= k and world.rooms[o.homeRoom].floor == scene.floor then
			table.insert(decoys, o)
		end
	end
	rng:shuffle(decoys)
	for i = 1, math.min(2, #decoys) do
		table.insert(log, { minute = tod + rng:int(-70, 60), citizenId = decoys[i].id, direction = "up" })
	end
	table.sort(log, function(a, b)
		return a.minute < b.minute
	end)

	local evidence: { [string]: Evidence } = {}
	local function add(e: Evidence)
		evidence[e.id] = e
	end

	local lo, hi = math.floor((tod - 40) / 5) * 5, math.ceil((tod + 40) / 5) * 5
	add({
		id = "body",
		label = "The body: " .. fullName(v),
		text = (if method == "blade"
			then "A single stab wound to the abdomen."
			else "Blunt force trauma to the back of the head.")
			.. " No sign of forced entry, so the victim let the killer in. Body temperature and rigor put the time of death between "
			.. CaseGen.fmtTime(lo)
			.. " and "
			.. CaseGen.fmtTime(hi)
			.. ".",
		roomId = scene.id,
	})
	add({
		id = "footprints",
		label = "Shoe prints",
		text = ("Partial prints in spilled coffee by the door, heading out. Shoe size %d."):format(k.shoeSize),
		roomId = scene.id,
	})
	local noteText = if motive == "debt"
		then ("\"Three months. I want the money back by Friday or this gets ugly. - %s\""):format(initials)
		elseif motive == "jealousy"
		then ("\"I saw you with them again. Don't lie to me. We talk tonight. - %s\""):format(initials)
		else ("\"Everyone knows that promotion was mine. Withdraw your name or you'll regret it. - %s\""):format(initials)
	add({
		id = "note",
		label = "Crumpled note",
		text = noteText .. " Found in the victim's coat pocket.",
		roomId = scene.id,
	})
	add({
		id = "weapon",
		label = if method == "blade" then "Kitchen knife" else "Heavy glass ashtray",
		text = "Wiped clean and dumped in the hallway bin by the lift on floor " .. scene.floor .. ". Matches the wound.",
		roomId = scene.id,
	})
	local lines = {}
	local logPeople = {}
	for _, e in log do
		table.insert(lines, ("%s  %s  lift %s, floor %d"):format(CaseGen.fmtTime(e.minute), fullName(citizens[e.citizenId]), e.direction, scene.floor))
		if not table.find(logPeople, e.citizenId) then
			table.insert(logPeople, e.citizenId)
		end
	end
	add({
		id = "doorlog",
		label = "Lift keycard log",
		text = "Keycard swipes for floor " .. scene.floor .. " last night:\n" .. table.concat(lines, "\n"),
		people = logPeople,
	})
	add({
		id = "boots",
		label = "Boots, size " .. k.shoeSize,
		text = ("Scrubbed recently, but there's a coffee stain on the welt. Found in %s's apartment."):format(fullName(k)),
		roomId = k.homeRoom,
		people = { k.id },
	})

	return {
		victimId = v.id,
		killerId = k.id,
		motive = motive,
		relationKind = pick.kind,
		method = method,
		tod = tod,
		sceneRoom = scene.id,
		sceneFloor = scene.floor,
		initials = initials,
		doorLog = log,
		evidence = evidence,
		evidenceOrder = { "body", "footprints", "note", "weapon", "doorlog", "boots" },
	}
end

return CaseGen
