--!strict
-- Hunches for a stuck detective, and a measure of how thorough the case file is.
-- The game stays quiet while the player is learning things. Only after a long stretch with nothing new in
-- the notebook does a hunch arrive, pointing at the next unexplored lead in general terms (where to look,
-- not what's there). Hunches are logged in the notebook and counted in the final report.

local Hints = {}

Hints.STUCK_SECONDS = 8 * 60 -- real time without anything new before a hunch
Hints.CHECK_EVERY = 20

export type Progress = {
	found: { string },
	bodyExamined: boolean, -- took the temperature or found the wound
	printsLifted: number,
	people: number,
	given: { [string]: boolean }, -- hunches already given, by id
}

local LEADS: { { id: string, ready: (Progress) -> boolean, text: string } } = {
	{
		id = "body",
		ready = function(p)
			return not table.find(p.found, "body")
		end,
		text = "You haven't looked at the body properly yet. Get close and examine it.",
	},
	{
		id = "exam",
		ready = function(p)
			return not p.bodyExamined
		end,
		text = "The body can tell you when it happened and how. A thermometer and a light would help.",
	},
	{
		id = "pockets",
		ready = function(p)
			return not table.find(p.found, "note")
		end,
		text = "People carry things. Did anyone go through the victim's pockets?",
	},
	{
		id = "floor",
		ready = function(p)
			return not table.find(p.found, "footprints")
		end,
		text = "Look down. The floor of the scene might show which way the killer left.",
	},
	{
		id = "weapon",
		ready = function(p)
			return not table.find(p.found, "weapon")
		end,
		text = "Whoever did this didn't want to be caught holding the weapon. Where's the nearest place to dump something on the way out?",
	},
	{
		id = "records",
		ready = function(p)
			return not table.find(p.found, "doorlog")
		end,
		text = "The building keeps records of who comes and goes. Somebody in security would know where.",
	},
	{
		id = "prints",
		ready = function(p)
			return p.printsLifted == 0
		end,
		text = "The killer touched things in the apartment. Your print kit (G) works on handles and lids.",
	},
	{
		id = "people",
		ready = function(p)
			return p.people < 4
		end,
		text = "Ask around. The people closest to the victim know who else was in their life.",
	},
	{
		id = "boots",
		ready = function(p)
			return table.find(p.found, "footprints") ~= nil and not table.find(p.found, "boots")
		end,
		text = "Shoe prints mean shoes. Someone still has that pair somewhere at home.",
	},
}

-- The next lead the player hasn't followed and hasn't had a hunch about.
function Hints.next(p: Progress): (string?, string?)
	for _, lead in LEADS do
		if not p.given[lead.id] and lead.ready(p) then
			return lead.id, lead.text
		end
	end
	return nil, nil
end

export type FileCounts = {
	people: number,
	places: number,
	evidence: number,
	facts: number,
	prints: number,
	photos: number,
	notes: number,
	strings: number,
}

-- How complete the case file is, as a rank and a one-line summary.
function Hints.thoroughness(c: FileCounts, hunches: number): (string, string)
	local points = c.people * 2 + c.places * 2 + c.evidence * 3 + c.facts + c.prints * 2 + c.photos + c.strings + math.min(c.notes, 30) // 3
	local rank = if points >= 70 then "Meticulous" elseif points >= 45 then "Thorough" elseif points >= 25 then "Solid" else "Quick"
	local function n(count: number, one: string, many: string): string
		return ("%d %s"):format(count, if count == 1 then one else many)
	end
	local summary = ("Case file: %s, %s, %s, %s, %s, %s, %s on the board. Thoroughness: %s. Hunches used: %d."):format(
		n(c.people, "person", "people"),
		n(c.places, "place", "places"),
		n(c.evidence, "piece of evidence", "pieces of evidence"),
		n(c.facts, "fact", "facts"),
		n(c.prints, "print", "prints"),
		n(c.photos, "photo", "photos"),
		n(c.strings, "string", "strings"),
		rank,
		hunches
	)
	return rank, summary
end

return Hints
