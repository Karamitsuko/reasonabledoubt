--!strict
-- The player's own case board: sticky notes placed where the player wants them, strings between them,
-- custom notes they write. What the player has learned lives in the notebook (items); the board is only
-- what they chose to pin. Server data, so it saves and co-op partners share it.

local TextService = game:GetService("TextService")

export type Note = {
	id: string,
	item: string?, -- notebook item this note shows; nil for a custom note
	text: string?, -- custom note text (already filtered)
	x: number,
	y: number,
	by: string?, -- display name of whoever placed it
}

export type Link = { a: string, b: string }

export type Board = {
	notes: { [string]: Note },
	links: { Link },
	nextId: number,
	dismissed: { [string]: boolean }, -- items the player took off the board; never auto-pinned again
}

local CaseBoard = {}

CaseBoard.WIDTH = 2400
CaseBoard.HEIGHT = 1600
local MAX_NOTES = 200
local MAX_LINKS = 400
local MAX_TEXT = 200

function CaseBoard.new(): Board
	return { notes = {}, links = {}, nextId = 1, dismissed = {} }
end

-- Fill in fields an older save may lack.
function CaseBoard.normalize(b: any): Board
	if typeof(b) ~= "table" then
		return CaseBoard.new()
	end
	b.notes = if typeof(b.notes) == "table" then b.notes else {}
	b.links = if typeof(b.links) == "table" then b.links else {}
	b.nextId = tonumber(b.nextId) or 1
	b.dismissed = if typeof(b.dismissed) == "table" then b.dismissed else {}
	return b :: Board
end

local function clampPos(x: any, y: any): (number, number)
	local nx = math.clamp(tonumber(x) or 0, 0, CaseBoard.WIDTH - 200)
	local ny = math.clamp(tonumber(y) or 0, 0, CaseBoard.HEIGHT - 120)
	return math.floor(nx), math.floor(ny)
end

local function count(t: { [string]: any }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

function CaseBoard.noteFor(b: Board, item: string): Note?
	for _, n in b.notes do
		if n.item == item then
			return n
		end
	end
	return nil
end

local function add(b: Board, item: string?, text: string?, x: number, y: number, by: string?): Note?
	if count(b.notes) >= MAX_NOTES then
		return nil
	end
	local id = "n" .. b.nextId
	b.nextId += 1
	local note: Note = { id = id, item = item, text = text, x = x, y = y, by = by }
	b.notes[id] = note
	return note
end

-- New discoveries land on the board in a loose grid near the top-left, below what's already there.
function CaseBoard.autoPin(b: Board, item: string)
	if b.dismissed[item] or CaseBoard.noteFor(b, item) then
		return
	end
	local n = count(b.notes)
	local col, row = n % 6, n // 6
	add(b, item, nil, 60 + col * 240 + (row % 2) * 30, 60 + row * 210, nil)
end

local function removeLinksOf(b: Board, noteId: string)
	for i = #b.links, 1, -1 do
		local l = b.links[i]
		if l.a == noteId or l.b == noteId then
			table.remove(b.links, i)
		end
	end
end

local function filter(text: string, player: Player): string?
	local ok, result = pcall(function()
		local f = TextService:FilterStringAsync(text, player.UserId)
		return f:GetNonChatStringForBroadcastAsync()
	end)
	return if ok then result else nil
end

-- Applies one board action from a player. `knows(item)` says whether that item is in the notebook.
-- Returns true when the board changed.
function CaseBoard.apply(b: Board, player: Player, action: any, args: any, knows: (string) -> boolean): (boolean, string?)
	if typeof(action) ~= "string" or typeof(args) ~= "table" then
		return false, "bad request"
	end
	if action == "pin" then
		local item = args.item
		if typeof(item) ~= "string" or not knows(item) then
			return false, "unknown item"
		end
		if CaseBoard.noteFor(b, item) then
			return false, "already pinned"
		end
		local x, y = clampPos(args.x, args.y)
		b.dismissed[item] = nil
		return add(b, item, nil, x, y, player.DisplayName) ~= nil, nil
	elseif action == "move" then
		local note = b.notes[tostring(args.id)]
		if not note then
			return false, "no such note"
		end
		note.x, note.y = clampPos(args.x, args.y)
		return true, nil
	elseif action == "unpin" then
		local note = b.notes[tostring(args.id)]
		if not note then
			return false, "no such note"
		end
		b.notes[note.id] = nil
		removeLinksOf(b, note.id)
		if note.item then
			b.dismissed[note.item] = true
		end
		return true, nil
	elseif action == "custom" then
		local text = args.text
		if typeof(text) ~= "string" then
			return false, "no text"
		end
		text = text:sub(1, MAX_TEXT):gsub("^%s+", ""):gsub("%s+$", "")
		if #text == 0 then
			return false, "no text"
		end
		local clean = filter(text, player)
		if not clean then
			return false, "couldn't check that text, try again"
		end
		local x, y = clampPos(args.x, args.y)
		return add(b, nil, clean, x, y, player.DisplayName) ~= nil, nil
	elseif action == "edit" then
		local note = b.notes[tostring(args.id)]
		if not note or note.item or typeof(args.text) ~= "string" then
			return false, "can't edit that note"
		end
		local clean = filter(args.text:sub(1, MAX_TEXT), player)
		if not clean then
			return false, "couldn't check that text, try again"
		end
		note.text = clean
		return true, nil
	elseif action == "link" then
		local a, c = tostring(args.a), tostring(args.b)
		if a == c or not b.notes[a] or not b.notes[c] then
			return false, "pick two notes"
		end
		-- Toggle: linking two already-linked notes cuts the string.
		for i, l in b.links do
			if (l.a == a and l.b == c) or (l.a == c and l.b == a) then
				table.remove(b.links, i)
				return true, nil
			end
		end
		if #b.links >= MAX_LINKS then
			return false, "too many strings"
		end
		table.insert(b.links, { a = a, b = c })
		return true, nil
	end
	return false, "unknown action"
end

return CaseBoard
