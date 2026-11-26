--!strict
-- Fingerprints. Every citizen has a print with a classification (pattern, ridge count, delta). Handles of
-- drawers, wardrobes and bins carry the prints of whoever uses them: residents at home, staff at work, and
-- the killer wherever they touched something. The player dusts a surface with the kit, lifts what's there,
-- and the notebook groups lifted prints that match. A print gets a name once that person has given theirs
-- in an interview (the killer never will), or the player works it out from where it was lifted.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RngModule = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Rng"))
local BuildingGen = require(script.Parent:WaitForChild("BuildingGen"))
local CitizenGen = require(script.Parent:WaitForChild("CitizenGen"))
local CaseGen = require(script.Parent:WaitForChild("CaseGen"))
local Furnish = require(script.Parent:WaitForChild("Furnish"))

type World = BuildingGen.World
type Citizen = CitizenGen.Citizen
type Case = CaseGen.Case

export type Lifted = { cid: number, letter: string, from: { string } }
export type PrintsState = {
	lifted: { Lifted },
	taken: { [string]: boolean }, -- citizen id -> gave prints in an interview
}

type Surface = { key: string, label: string, people: { number }, instance: Instance }

local Prints = {}

local PATTERNS = { "Loop", "Whorl", "Arch", "Tented arch", "Double loop" }
local DELTAS = { "a", "b", "c", "d", "e", "f" }
local REACH = 9
local LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

local classes: { [number]: string } = {}
local surfaces: { [string]: Surface } = {}

local function fullName(c: Citizen): string
	return c.firstName .. " " .. c.lastName
end

function Prints.classify(cid: number): string
	return classes[cid] or "?"
end

function Prints.new(): PrintsState
	return { lifted = {}, taken = {} }
end

function Prints.normalize(p: any): PrintsState
	if typeof(p) ~= "table" then
		return Prints.new()
	end
	p.lifted = if typeof(p.lifted) == "table" then p.lifted else {}
	p.taken = if typeof(p.taken) == "table" then p.taken else {}
	return p :: PrintsState
end

local function letterFor(i: number): string
	if i <= #LETTERS then
		return LETTERS:sub(i, i)
	end
	return LETTERS:sub((i - 1) % #LETTERS + 1, (i - 1) % #LETTERS + 1) .. tostring((i - 1) // #LETTERS + 1)
end

-- Notebook entries: one per distinct person whose print was lifted.
function Prints.items(ps: PrintsState, citizens: { Citizen }, add: (string, string, string, { string }) -> ())
	for _, l in ps.lifted do
		local who = if ps.taken[tostring(l.cid)] then citizens[l.cid] else nil
		local lines = { Prints.classify(l.cid) }
		table.insert(lines, "Lifted from: " .. table.concat(l.from, "; ") .. ".")
		if who then
			table.insert(lines, "Matches the prints " .. fullName(who) .. " gave you.")
		end
		add("print:" .. l.letter, "print", if who then ("Print %s: %s"):format(l.letter, fullName(who)) else "Print " .. l.letter, lines)
	end
end

-- The line a person's notebook entry gets once they've given their prints.
function Prints.personLine(ps: PrintsState, cid: number): string?
	if ps.taken[tostring(cid)] then
		return "Prints on file: " .. Prints.classify(cid) .. "."
	end
	return nil
end

-- Whether this citizen will let you take their prints. The killer never does; a few innocents refuse too.
function Prints.willGive(case: Case, c: Citizen): boolean
	if c.id == case.killerId then
		return false
	end
	return (c.id * 7919) % 5 ~= 0
end

local function tag(inst: Instance, key: string, label: string, people: { number })
	inst:SetAttribute("PrintSurface", key)
	local existing = surfaces[key]
	if existing then
		for _, p in people do
			if not table.find(existing.people, p) then
				table.insert(existing.people, p)
			end
		end
		return
	end
	local unique = {}
	for _, p in people do
		if not table.find(unique, p) then
			table.insert(unique, p)
		end
	end
	surfaces[key] = { key = key, label = label, people = unique, instance = inst }
end

local NICE = { drawer1 = "Top drawer", drawer2 = "Middle drawer", drawer3 = "Bottom drawer", wardrobe = "Wardrobe door", bin = "Bin lid" }

export type Setup = {
	world: World,
	citizens: { Citizen },
	case: Case,
	seed: number,
	furniture: Furnish.Furniture,
	weapon: Instance?,
	boots: Instance?,
	remotes: Folder,
	state: () -> PrintsState,
	changed: () -> (),
}

function Prints.setup(s: Setup)
	local world, citizens, case = s.world, s.citizens, s.case

	-- Unique classification per citizen
	local rng = RngModule.new(s.seed + 7)
	local used: { [string]: boolean } = {}
	for _, c in citizens do
		local cls: string
		repeat
			cls = ("%s, %d ridges, delta %s"):format(rng:pick(PATTERNS), rng:int(8, 24), rng:pick(DELTAS))
		until not used[cls]
		used[cls] = true
		classes[c.id] = cls
	end

	-- Who uses each room
	local users: { [string]: { number } } = {}
	for _, c in citizens do
		for _, r in { c.homeRoom, c.workRoom } do
			if r and world.rooms[r] then
				users[r] = users[r] or {}
				table.insert(users[r], c.id)
			end
		end
	end
	local killer = citizens[case.killerId]
	for roomId, set in s.furniture.rooms do
		local room = world.rooms[roomId]
		for name, c in set do
			local people = table.clone(users[roomId] or {})
			if room.kind == "apartment" then
				-- At home, only residents touch the drawers (and the victim's are their own).
				people = {}
				for _, cid in users[roomId] or {} do
					if citizens[cid].homeRoom == roomId then
						table.insert(people, cid)
					end
				end
			end
			-- The killer went through the victim's top drawer.
			if roomId == case.sceneRoom and name == "drawer1" then
				table.insert(people, killer.id)
			end
			local inst = if c.kind == "drawer" then c.holder else c.model
			tag(inst, roomId .. ":" .. name, ("%s, %s"):format(NICE[name] or name, room.label), people)
		end
	end
	for floor, bin in s.furniture.hallBins do
		local people: { number } = {}
		if floor == case.sceneFloor then
			table.insert(people, killer.id) -- lifted the lid to dump the weapon
		end
		-- A neighbour or two from the floor uses it too
		local n = 0
		for _, c in citizens do
			local home = world.rooms[c.homeRoom]
			if home and home.floor == floor and c.id ~= case.victimId and n < 2 and (c.id + floor) % 3 == 0 then
				table.insert(people, c.id)
				n += 1
			end
		end
		tag(bin.model, "hall:" .. floor, ("Bin lid by the lift, floor %d"):format(floor), people)
	end
	if s.weapon then
		tag(s.weapon, "weapon", "The weapon", {}) -- wiped clean
	end
	if s.boots then
		tag(s.boots, "boots", "The boots", { killer.id })
	end

	local function surfaceOf(inst: Instance?): Surface?
		local i = inst
		while i and i ~= workspace do
			local key = i:GetAttribute("PrintSurface")
			if typeof(key) == "string" then
				return surfaces[key]
			end
			i = i.Parent
		end
		return nil
	end

	local function posOf(inst: Instance): Vector3?
		if inst:IsA("BasePart") then
			return inst.Position
		elseif inst:IsA("Model") then
			return inst:GetPivot().Position
		end
		return nil
	end

	local dust = Instance.new("RemoteFunction")
	dust.Name = "Dust"
	dust.Parent = s.remotes
	dust.OnServerInvoke = function(player: Player, inst: any): any
		if typeof(inst) ~= "Instance" then
			return { text = "Nothing there to dust." }
		end
		local char = player.Character
		local at = posOf(inst)
		if not char or not at or (char:GetPivot().Position - at).Magnitude > REACH then
			return { text = "Get closer." }
		end
		local surf = surfaceOf(inst)
		if not surf then
			return { text = "The powder doesn't take. No usable prints here." }
		end
		local ps = s.state()
		local out = {}
		for i, cid in surf.people do
			local lifted = false
			for _, l in ps.lifted do
				if l.cid == cid and table.find(l.from, surf.label) then
					lifted = true
				end
			end
			table.insert(out, { n = i, cls = classes[cid], lifted = lifted })
		end
		if #out == 0 then
			return { text = surf.label .. ": " .. (if surf.key == "weapon" then "wiped clean. Not a single print." else "smudges, nothing you could lift."), key = surf.key }
		end
		return { text = surf.label .. (": %d print%s."):format(#out, if #out == 1 then "" else "s"), prints = out, key = surf.key }
	end

	local lift = Instance.new("RemoteFunction")
	lift.Name = "LiftPrint"
	lift.Parent = s.remotes
	lift.OnServerInvoke = function(player: Player, key: any, n: any): any
		local surf = surfaces[tostring(key)]
		local cid = surf and surf.people[tonumber(n) or 0]
		if not surf or not cid then
			return { text = "Nothing to lift." }
		end
		local char = player.Character
		local at = posOf(surf.instance)
		if not char or not at or (char:GetPivot().Position - at).Magnitude > REACH + 4 then
			return { text = "Get closer." }
		end
		local ps = s.state()
		for _, l in ps.lifted do
			if l.cid == cid then
				if not table.find(l.from, surf.label) then
					table.insert(l.from, surf.label)
					s.changed()
					return { text = ("Lifted. It matches Print %s."):format(l.letter), letter = l.letter }
				end
				return { text = "Already lifted.", letter = l.letter }
			end
		end
		if #ps.lifted >= 60 then
			return { text = "Your print cards are full." }
		end
		local letter = letterFor(#ps.lifted + 1)
		table.insert(ps.lifted, { cid = cid, letter = letter, from = { surf.label } })
		s.changed()
		return { text = ("Lifted as Print %s. It's in your notebook."):format(letter), letter = letter, new = true }
	end
end

return Prints
