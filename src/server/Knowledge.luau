--!strict
-- What a citizen knows and how they say it. Answers come from the simulation (where they really were,
-- who they really know), filtered by personality. The killer lies, consistently, and nervous killers show it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rng = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Rng"))
local BuildingGen = require(script.Parent:WaitForChild("BuildingGen"))
local CitizenGen = require(script.Parent:WaitForChild("CitizenGen"))
local Schedule = require(script.Parent:WaitForChild("Schedule"))
local CaseGen = require(script.Parent:WaitForChild("CaseGen"))

type World = BuildingGen.World
type Citizen = CitizenGen.Citizen
type Case = CaseGen.Case

export type Answer = {
	text: string,
	note: string?, -- line added to this person's card
	addPeople: { number }?,
}

local Knowledge = {}

local COLOURS = {
	{ "black", Color3.fromRGB(30, 30, 36) },
	{ "dark brown", Color3.fromRGB(60, 52, 44) },
	{ "navy", Color3.fromRGB(40, 50, 66) },
	{ "burgundy", Color3.fromRGB(80, 30, 40) },
	{ "dark green", Color3.fromRGB(46, 62, 52) },
	{ "grey-brown", Color3.fromRGB(110, 100, 88) },
	{ "beige", Color3.fromRGB(150, 140, 120) },
	{ "deep blue", Color3.fromRGB(24, 40, 60) },
	{ "plum", Color3.fromRGB(90, 70, 110) },
}

function Knowledge.colourName(c: Color3): string
	local best, bestD = "dark", math.huge
	for _, entry in COLOURS do
		local col = entry[2] :: Color3
		local d = (col.R - c.R) ^ 2 + (col.G - c.G) ^ 2 + (col.B - c.B) ^ 2
		if d < bestD then
			best, bestD = entry[1] :: string, d
		end
	end
	return best
end

function Knowledge.describe(c: Citizen): string
	local build = if c.heightCm >= 183 then "tall" elseif c.heightCm <= 164 then "short" else "medium height"
	return ("%s, in a %s coat"):format(build, Knowledge.colourName(c.shirtColor))
end

local function name(c: Citizen): string
	return c.firstName .. " " .. c.lastName
end

local function has(c: Citizen, trait: string): boolean
	return table.find(c.traits, trait) ~= nil
end

local function relation(c: Citizen, otherId: number): string?
	for _, r in c.relationships do
		if r.id == otherId then
			return r.kind
		end
	end
	return nil
end

local function placeName(world: World, loc: string): string
	if loc == "offsite" then
		return "out, across town"
	end
	local room = world.rooms[loc]
	if room.kind == "apartment" then
		return "at " .. room.label
	end
	if room.label:sub(1, 4) == "The " then
		return "at " .. room.label
	end
	return "at the " .. room.label
end

local function tell(c: Citizen, salt: number): string
	if has(c, "nervous") then
		return " (They won't meet your eyes.)"
	elseif has(c, "quick-tempered") then
		return " (Their jaw tightens.)"
	elseif Rng.hash01(c.id, salt, 9) < 0.4 then
		return " (A pause, a little too long.)"
	end
	return ""
end

-- Innocent people with a nervous or prickly streak show tells too, so a tell alone never proves guilt.
local function herring(c: Citizen, salt: number): string
	if (has(c, "nervous") or has(c, "quick-tempered")) and Rng.hash01(c.id, salt, 17) < 0.5 then
		return tell(c, salt)
	end
	return ""
end

export type Ctx = { case: Case, world: World, citizens: { Citizen }, todKnown: boolean }

function Knowledge.questions(ctx: Ctx, c: Citizen): { { id: string, text: string } }
	local victim = ctx.citizens[ctx.case.victimId]
	local when = if ctx.todKnown then "around " .. CaseGen.fmtTime(ctx.case.tod) else "late last night"
	return {
		{ id = "alibi", text = "Where were you " .. when .. "?" },
		{ id = "victim", text = "How did you know " .. name(victim) .. "?" },
		{ id = "circle", text = "Who was close to " .. victim.firstName .. "?" },
		{ id = "saw", text = "See or hear anything last night?" },
	}
end

function Knowledge.answer(ctx: Ctx, c: Citizen, qid: string, evidenceId: string?): Answer
	local case, world, citizens = ctx.case, ctx.world, ctx.citizens
	local victim = citizens[case.victimId]
	local killer = citizens[case.killerId]
	local isKiller = c.id == killer.id
	local tod = case.tod
	local t = CaseGen.fmtTime(tod)

	if c.id == victim.id then
		return { text = "..." }
	end

	if qid == "alibi" then
		local loc = Schedule.locationAt(c, tod)
		if isKiller then
			local claim = if loc == "offsite" then "out, across town" else placeName(world, loc)
			return { text = ("I was %s. All night. Ask anyone.%s"):format(claim, tell(c, 1)), note = "Claims they were " .. claim .. "." }
		end
		if Schedule.isAsleep(c, tod) and loc == c.homeRoom then
			return { text = "Home. Asleep, like a normal person." .. herring(c, 1), note = "Says they were home asleep." }
		end
		local where = placeName(world, loc)
		return { text = ("I was %s."):format(where) .. herring(c, 1), note = "Says they were " .. where .. "." }
	elseif qid == "victim" then
		local kind = relation(c, victim.id)
		if not kind then
			return { text = ("%s? I knew the face. We nodded in the lift. That's it."):format(victim.firstName), note = "Barely knew the victim." }
		end
		local lines: { [string]: string } = {
			partner = "We were together. Are they... what happened?",
			roommate = "We share the place. Shared. God.",
			coworker = "We worked together. Same floor, same deadlines.",
			friend = "We were friends. Drinks, favours, the usual.",
		}
		local text = (lines[kind] or "We knew each other.") .. herring(c, 2)
		if isKiller and kind == "friend" then
			text = "We were friends. Not so close lately." .. tell(c, 2)
		elseif isKiller and kind == "coworker" then
			text = "We worked together. Strictly professional." .. tell(c, 2)
		elseif isKiller and kind == "partner" then
			text = "We were seeing each other. It was fine. Everything was fine." .. tell(c, 2)
		end
		return { text = text, note = ("Was the victim's %s."):format(kind) }
	elseif qid == "circle" then
		if not relation(c, victim.id) and not has(c, "gossip") then
			return { text = "I wouldn't know who they ran with." }
		end
		if isKiller then
			return { text = "No idea. They kept to themselves." .. tell(c, 3) }
		end
		local names, ids = {}, {}
		for _, r in victim.relationships do
			if r.id ~= c.id and #names < 4 then
				table.insert(names, ("%s (%s)"):format(name(citizens[r.id]), r.kind))
				table.insert(ids, r.id)
			end
		end
		if #names == 0 then
			return { text = "Honestly? Nobody I can think of." }
		end
		return { text = "Let me think. " .. table.concat(names, ", ") .. ".", addPeople = ids }
	elseif qid == "saw" then
		if isKiller then
			return { text = "Nothing. I wasn't around." .. tell(c, 4) }
		end
		local loc = Schedule.locationAt(c, tod)
		local asleep = Schedule.isAsleep(c, tod)
		-- Living with the killer
		if c.homeRoom == killer.homeRoom and loc == c.homeRoom and not asleep then
			return {
				text = ("%s went out around %s. Came back maybe twenty minutes later, washed up, went to bed."):format(
					killer.firstName,
					CaseGen.fmtTime(tod - 15)
				),
				note = ("Says %s went out around %s."):format(name(killer), CaseGen.fmtTime(tod - 15)),
				addPeople = { killer.id },
			}
		end
		if loc ~= "offsite" then
			local room = world.rooms[loc]
			if room.floor == case.sceneFloor then
				if asleep then
					return { text = ("I was asleep. Something woke me around %s. A thud, then the lift."):format(t), note = "Heard a thud around " .. t .. "." }
				end
				return {
					text = ("Around %s I heard a door, then someone hurried to the lift. %s. Didn't see the face."):format(t, Knowledge.describe(killer)),
					note = "Saw someone leave: " .. Knowledge.describe(killer) .. ".",
				}
			end
			if room.floor == 0 and not asleep then
				return {
					text = ("Just after %s someone came down in the lift and walked straight out. %s."):format(t, Knowledge.describe(killer)),
					note = "Saw someone leave the building: " .. Knowledge.describe(killer) .. ".",
				}
			end
		end
		return { text = "Nothing. I wasn't anywhere near." }
	elseif qid == "evidence" and evidenceId then
		local ev = case.evidence[evidenceId]
		if not ev then
			return { text = "What's that supposed to be?" }
		end
		if evidenceId == "footprints" then
			if isKiller then
				if has(c, "honest") then
					return { text = ("%d. Same as mine, if that's what you're asking. Plenty of people wear a %d."):format(killer.shoeSize, killer.shoeSize) .. tell(c, 5), note = "Admits shoe size " .. killer.shoeSize .. "." }
				end
				local claimed = killer.shoeSize - 2
				return { text = ("I'm a %d. Not mine."):format(claimed) .. tell(c, 5), note = ("Claims shoe size %d."):format(claimed) }
			end
			return { text = ("I'm a %d. So, no."):format(c.shoeSize) .. herring(c, 5), note = ("Shoe size %d."):format(c.shoeSize) }
		elseif evidenceId == "note" then
			if isKiller then
				return { text = "Never seen it before." .. tell(c, 6), note = "Denies knowing the note." }
			end
			if relation(c, victim.id) or has(c, "gossip") then
				return {
					text = ("%s... that could be %s. They and %s had history."):format(case.initials, name(killer), victim.firstName),
					note = ("Thinks the note is from %s."):format(name(killer)),
					addPeople = { killer.id },
				}
			end
			return { text = "Initials don't mean anything to me." }
		elseif evidenceId == "doorlog" then
			local inLog = false
			for _, e in case.doorLog do
				if e.citizenId == c.id then
					inLog = true
				end
			end
			if isKiller then
				return { text = "Then the machine's wrong. I told you where I was." .. tell(c, 7), note = "Denies the lift log." }
			elseif inLog then
				return { text = "Sure, I came home around then. Straight to bed.", note = "Confirms their lift swipe." }
			end
			return { text = "I'm not on there, am I?" }
		elseif evidenceId == "boots" then
			if isKiller then
				return { text = "You've been in my apartment? They're boots. I clean my boots." .. tell(c, 8), note = "Defensive about the boots." }
			end
			return { text = "Not mine." }
		elseif evidenceId == "weapon" or evidenceId == "body" then
			if isKiller and has(c, "nervous") then
				return { text = "That's... I don't want to see that." .. tell(c, 9) }
			end
			return { text = "That's horrible. I don't know anything about it." }
		end
		return { text = "Can't help you with that." }
	end
	return { text = "..." }
end

return Knowledge
