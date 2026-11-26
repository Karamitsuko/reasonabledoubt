--!strict
-- Runs the active case: places the scene, owns the shared case board, handles interviews and the accusation.
-- The board is server data (evidence ids and people ids), so nothing can vanish from it and co-op players share it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RngModule = require(Shared:WaitForChild("Rng"))
local BuildingGen = require(script.Parent:WaitForChild("BuildingGen"))
local CitizenGen = require(script.Parent:WaitForChild("CitizenGen"))
local CitizenSim = require(script.Parent:WaitForChild("CitizenSim"))
local CaseGen = require(script.Parent:WaitForChild("CaseGen"))
local Knowledge = require(script.Parent:WaitForChild("Knowledge"))
local CaseBoard = require(script.Parent:WaitForChild("CaseBoard"))
local Furnish = require(script.Parent:WaitForChild("Furnish"))
local BodyExam = require(script.Parent:WaitForChild("BodyExam"))
local Prints = require(script.Parent:WaitForChild("Prints"))
local Photos = require(script.Parent:WaitForChild("Photos"))

type World = BuildingGen.World
type Citizen = CitizenGen.Citizen
type Case = CaseGen.Case

export type CaseSave = {
	found: { string },
	people: { [string]: { string } }, -- citizen id -> notes
	todKnown: boolean,
	solved: boolean,
	result: string?,
	board: CaseBoard.Board?,
	body: BodyExam.BodyState?,
	prints: Prints.PrintsState?,
	photos: { Photos.Photo }?,
}

local MOTIVES = {
	{ id = "jealousy", label = "Jealousy (a relationship gone wrong)" },
	{ id = "debt", label = "Money (an unpaid debt)" },
	{ id = "rivalry", label = "Rivalry (a job, a promotion)" },
}

local CaseService = {}

local world: World
local citizens: { Citizen }
local sim: CitizenSim.CitizenSim
local furniture: Furnish.Furniture
local case: Case
local state: CaseSave = { found = {}, people = {}, todKnown = false, solved = false, result = nil, board = CaseBoard.new(), body = {}, prints = Prints.new(), photos = {} }
local remotes: Folder
local sceneFolder: Folder
local caseSeed = 0
local receipt: { minute: number, bar: string }? = nil

local function fullName(c: Citizen): string
	return c.firstName .. " " .. c.lastName
end

local function remote(className: string, name: string): any
	local r = Instance.new(className)
	r.Name = name
	r.Parent = remotes
	return r
end

local boardEvent: RemoteEvent
local notifyEvent: RemoteEvent
local openInterview: RemoteEvent
local openAccuse: RemoteEvent

local function notify(text: string)
	notifyEvent:FireAllClients(text)
end

local function board(): CaseBoard.Board
	return state.board :: CaseBoard.Board
end

local function printState(): Prints.PrintsState
	state.prints = state.prints or Prints.new()
	return state.prints :: Prints.PrintsState
end

-- With the print kit or camera out, clicks are for the tool, not for opening drawers.
local function handsFree(player: Player): boolean
	return player:GetAttribute("Tool") == nil
end

local function knowPerson(id: number, note: string?)
	local key = tostring(id)
	local notes = state.people[key]
	local isNew = notes == nil
	if not notes then
		notes = {}
		state.people[key] = notes
		CaseBoard.autoPin(board(), "p:" .. key)
	end
	if note and not table.find(notes, note) then
		table.insert(notes, note)
	end
	return isNew
end

-- Everything the player has learned, as notebook items. Pinned or not, these can go on the board.
type Item = { kind: string, title: string, lines: { string }, photo: number? }

local function notebook(): { [string]: Item }
	local victim = citizens[case.victimId]
	local items: { [string]: Item } = {}
	local function place(roomId: string, why: string)
		local key = "place:" .. roomId
		local it = items[key]
		if not it then
			local room = world.rooms[roomId]
			it = { kind = "place", title = room.label, lines = { ("Floor %d"):format(room.floor) } }
			items[key] = it
		end
		table.insert(it.lines, why)
	end
	place(case.sceneRoom, "Where " .. fullName(victim) .. " was found.")

	for _, id in case.evidenceOrder do
		if table.find(state.found, id) then
			local e = case.evidence[id]
			items["ev:" .. id] = { kind = "evidence", title = e.label, lines = { e.text } }
		end
	end

	for key, notes in state.people do
		local c = citizens[tonumber(key) :: number]
		local role = if c.id == victim.id then "Victim" else c.job
		local lines = { ("%s, lives in %s"):format(role, world.rooms[c.homeRoom].label) }
		for _, n in notes do
			table.insert(lines, n)
		end
		local onFile = Prints.personLine(printState(), c.id)
		if onFile then
			table.insert(lines, onFile)
		end
		items["p:" .. key] = { kind = "person", title = fullName(c), lines = lines }
		if c.homeRoom ~= case.sceneRoom then
			place(c.homeRoom, "Home of " .. fullName(c) .. ".")
		end
	end

	-- Facts pulled out of the evidence, so they can be pinned and linked on their own.
	local function fact(key: string, title: string, line: string)
		items["fact:" .. key] = { kind = "fact", title = title, lines = { line } }
	end
	BodyExam.facts(state.body or {}, case, receipt, fact)
	Prints.items(printState(), citizens, function(key: string, kind: string, title: string, lines: { string })
		items[key] = { kind = kind, title = title, lines = lines }
	end)
	Photos.items(state.photos or {}, function(key: string, kind: string, title: string, lines: { string }, n: number?)
		items[key] = { kind = kind, title = title, lines = lines, photo = n }
	end)
	if table.find(state.found, "footprints") then
		fact("shoe", "Killer's shoe size", ("Prints at the scene: size %d."):format(citizens[case.killerId].shoeSize))
	end
	if table.find(state.found, "note") then
		fact("initials", "Note signed " .. case.initials, "The threatening note in the victim's pocket is signed " .. case.initials)
	end
	if table.find(state.found, "doorlog") then
		for i, e in case.doorLog do
			fact(
				"log" .. i,
				"Lift swipe " .. CaseGen.fmtTime(e.minute),
				("%s, lift %s, floor %d."):format(fullName(citizens[e.citizenId]), e.direction, case.sceneFloor)
			)
		end
		for _, room in world.roomList do
			if room.kind == "security" then
				place(room.id, "The lift keycard log is kept here.")
			end
		end
	end
	return items
end

local function boardPayload(): any
	local victim = citizens[case.victimId]
	local evidence = {}
	for _, id in case.evidenceOrder do
		if table.find(state.found, id) then
			local e = case.evidence[id]
			table.insert(evidence, { id = id, label = e.label, text = e.text })
		end
	end
	local b = board()
	local notes = {}
	for _, n in b.notes do
		table.insert(notes, n)
	end
	return {
		title = "The " .. world.rooms[case.sceneRoom].label .. " case",
		objective = if state.solved
			then (state.result or "Case closed.")
			else ("Find out who killed %s and why. Then file an accusation at your desk (Detective Office, top floor)."):format(fullName(victim)),
		evidence = evidence,
		items = notebook(),
		notes = notes,
		links = b.links,
		width = CaseBoard.WIDTH,
		height = CaseBoard.HEIGHT,
		solved = state.solved,
	}
end

local function pushBoard()
	boardEvent:FireAllClients(boardPayload())
end

local function discover(id: string, by: Player?)
	if state.solved or table.find(state.found, id) then
		return
	end
	table.insert(state.found, id)
	local e = case.evidence[id]
	CaseBoard.autoPin(board(), "ev:" .. id)
	if e.people then
		for _, pid in e.people do
			knowPerson(pid, nil)
		end
	end
	notify(("New evidence: %s%s"):format(e.label, if by then " (found by " .. by.DisplayName .. ")" else ""))
	pushBoard()
end

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.Parent = parent
	return p
end

local function prompt(target: BasePart, action: string, object: string, onTrigger: (Player) -> ()): ProximityPrompt
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = action
	pp.ObjectText = object
	pp.KeyboardKeyCode = Enum.KeyCode.E
	pp.HoldDuration = 0.4
	pp.MaxActivationDistance = 7
	pp.RequiresLineOfSight = false
	pp.Parent = target
	pp.Triggered:Connect(onTrigger)
	return pp
end

local function placeScene()
	sceneFolder = Instance.new("Folder")
	sceneFolder.Name = "CaseScene"
	sceneFolder.Parent = workspace

	local scene = world.rooms[case.sceneRoom]
	local victim = citizens[case.victimId]
	local floorY = scene.center.Y - 3

	-- Body: the victim's own body, lying on the floor, a stylised dark stain beneath.
	local bodyPos = scene.center + Vector3.new(-2, 0, 0)
	table.insert(sim.keepClear, { pos = bodyPos, radius = 4.5 })
	part(sceneFolder, "Stain", Vector3.new(5, 0.05, 3.5), CFrame.new(bodyPos.X, floorY + 0.08, bodyPos.Z), Color3.fromRGB(38, 3, 6), Enum.Material.SmoothPlastic).Reflectance = 0.12
	local rig = CitizenSim.buildRig(victim)
	local bodyAnchor: BasePart
	if rig then
		local hum = rig:FindFirstChildOfClass("Humanoid") :: Humanoid
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		hum.PlatformStand = true
		for _, d in rig:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
			end
		end
		rig.Name = "Body"
		rig:PivotTo(CFrame.new(bodyPos.X, floorY + 0.9, bodyPos.Z) * CFrame.Angles(math.rad(-90), math.rad(35), 0))
		rig.Parent = sceneFolder
		bodyAnchor = (rig.PrimaryPart or rig:FindFirstChild("HumanoidRootPart")) :: BasePart
	else
		bodyAnchor = part(sceneFolder, "Body", Vector3.new(2, 1, 5), CFrame.new(bodyPos.X, floorY + 0.5, bodyPos.Z), victim.shirtColor)
	end
	-- Up close: click the body to examine it with tools (BodyExam). The note is in one of the pockets.
	receipt = BodyExam.setup({
		case = case,
		victim = victim,
		sceneLabel = scene.label,
		seed = caseSeed,
		body = rig or bodyAnchor,
		bodyPos = bodyPos,
		remotes = remotes,
		state = function()
			state.body = state.body or {}
			return state.body :: BodyExam.BodyState
		end,
		isFound = function(id: string)
			return table.find(state.found, id) ~= nil
		end,
		discover = function(id: string, player: Player)
			discover(id, player)
		end,
		noteText = function()
			return case.evidence.note.text
		end,
		changed = pushBoard,
		setTodKnown = function()
			state.todKnown = true
		end,
	})

	-- Shoe prints in spilled coffee, by the door.
	local door = scene.doorInner
	local prints = Instance.new("Model")
	prints.Name = "ShoePrints"
	prints.Parent = sceneFolder
	local first: Part? = nil
	for i = 0, 3 do
		local pos = bodyPos:Lerp(door, 0.35 + i * 0.17)
		local side = if i % 2 == 0 then 0.5 else -0.5
		local pp = part(prints, "Print", Vector3.new(0.6, 0.04, 1.2), CFrame.new(pos.X + side, floorY + 0.08, pos.Z), Color3.fromRGB(40, 26, 16))
		first = first or pp
	end
	part(sceneFolder, "Spill", Vector3.new(2.2, 0.04, 2.2), CFrame.new(bodyPos:Lerp(door, 0.25).X, floorY + 0.07, bodyPos:Lerp(door, 0.25).Z), Color3.fromRGB(55, 34, 20), Enum.Material.Glass)
	-- Looking closely at the prints (clicking them) records them.
	for _, pr in prints:GetChildren() do
		local cd = Instance.new("ClickDetector")
		cd.MaxActivationDistance = 10
		cd.Parent = pr
		cd.MouseClick:Connect(function(player)
			if not handsFree(player) then
				return
			end
			discover("footprints", player)
		end)
	end

	-- The weapon, dumped in the bin by the lift. You only find it if you lift the lid.
	local hallBin = furniture.hallBins[scene.floor]
	local weapon = if case.method == "blade"
		then Furnish.item(hallBin, "Knife", {
			{ size = Vector3.new(0.1, 0.05, 0.9), offset = CFrame.new(0, -0.12, -0.3), color = Color3.fromRGB(170, 172, 178), mat = Enum.Material.Metal },
			{ size = Vector3.new(0.16, 0.12, 0.55), offset = CFrame.new(0, -0.1, 0.4), color = Color3.fromRGB(24, 22, 22), mat = Enum.Material.Plastic },
		})
		else Furnish.item(hallBin, "Ashtray", {
			{ size = Vector3.new(0.9, 0.3, 0.9), offset = CFrame.new(0, -0.05, 0), color = Color3.fromRGB(150, 180, 190), mat = Enum.Material.Glass },
		})
	weapon:SetAttribute("Evidence", "weapon")
	if table.find(state.found, "weapon") then
		weapon:Destroy() -- already bagged in an earlier session
	end

	-- Lift log terminal in the security office.
	for _, room in world.roomList do
		if room.kind == "security" then
			local term = part(
				sceneFolder,
				"LiftLogTerminal",
				Vector3.new(2.4, 1.6, 0.3),
				CFrame.lookAt(room.center + Vector3.new(0, 0.5, room.size.Z / 2 - 1.5), room.center + Vector3.new(0, 0.5, 0)),
				Color3.fromRGB(80, 200, 255),
				Enum.Material.Neon
			)
			local cd = Instance.new("ClickDetector")
			cd.MaxActivationDistance = 10
			cd.Parent = term
			cd.MouseClick:Connect(function(player)
				if not handsFree(player) then
					return
				end
				discover("doorlog", player)
			end)
		elseif room.kind == "detective" then
			local desk = part(
				sceneFolder,
				"CaseDesk",
				Vector3.new(6, 2.6, 3),
				CFrame.new(room.center.X, room.center.Y - 1.7, room.center.Z - 2),
				Color3.fromRGB(70, 46, 32),
				Enum.Material.Wood
			)
			desk.CanCollide = true
			local lampPart = part(sceneFolder, "DeskLamp", Vector3.new(0.6, 0.6, 0.6), desk.CFrame * CFrame.new(2.2, 1.6, 0), Color3.fromRGB(255, 190, 110), Enum.Material.Neon)
			local light = Instance.new("PointLight")
			light.Color = lampPart.Color
			light.Range = 12
			light.Brightness = 1.2
			light.Parent = lampPart
			prompt(desk, "File accusation", "Case desk", function(player)
				if state.solved then
					notify(state.result or "Case closed.")
					return
				end
				local suspects = {}
				for key in state.people do
					local id = tonumber(key) :: number
					if id ~= case.victimId then
						table.insert(suspects, { id = id, name = fullName(citizens[id]) })
					end
				end
				table.sort(suspects, function(a, b)
					return a.name < b.name
				end)
				openAccuse:FireClient(player, { suspects = suspects, motives = MOTIVES })
			end)
		end
	end

	-- The boots, pushed to the back of the killer's wardrobe.
	local wardrobe = furniture.rooms[citizens[case.killerId].homeRoom].wardrobe
	local boots = Furnish.item(wardrobe, "Boots", {
		{ size = Vector3.new(0.5, 0.7, 1.0), offset = CFrame.new(-0.3, 0.2, 0), color = Color3.fromRGB(34, 24, 20), mat = Enum.Material.Leather },
		{ size = Vector3.new(0.5, 0.7, 1.0), offset = CFrame.new(0.3, 0.2, 0.1), color = Color3.fromRGB(34, 24, 20), mat = Enum.Material.Leather },
	})
	boots:SetAttribute("Evidence", "boots")
	if table.find(state.found, "boots") then
		boots:Destroy()
	end

	Prints.setup({
		world = world,
		citizens = citizens,
		case = case,
		seed = caseSeed,
		furniture = furniture,
		weapon = weapon,
		boots = boots,
		remotes = remotes,
		state = printState,
		changed = pushBoard,
	})

	-- Picking things up: evidence goes in a bag and onto the board; junk is just junk.
	furniture.onItemClicked = function(player: Player, item: Model)
		if not handsFree(player) then
			return
		end
		local ev = item:GetAttribute("Evidence")
		if typeof(ev) == "string" then
			item:Destroy()
			discover(ev, player)
			return
		end
		local j = item:GetAttribute("Junk")
		if typeof(j) == "string" then
			notifyEvent:FireClient(player, j)
		end
	end
end

local function ctx(): Knowledge.Ctx
	return { case = case, world = world, citizens = citizens, todKnown = state.todKnown }
end

local function questionsFor(c: Citizen): { { id: string, text: string } }
	local qs = Knowledge.questions(ctx(), c)
	if c.id ~= case.victimId and not printState().taken[tostring(c.id)] then
		table.insert(qs, { id = "prints", text = "Can I take your fingerprints?" })
	end
	return qs
end

local function onRigSpawned(c: Citizen, rig: Model)
	-- Citizens walk through furniture rather than getting stuck on it.
	for _, d in rig:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = "Citizens"
		end
	end
	local root = rig:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local pp = Instance.new("ProximityPrompt")
	pp.Name = "Talk"
	pp.ActionText = "Talk"
	pp.ObjectText = fullName(c)
	pp.KeyboardKeyCode = Enum.KeyCode.F
	pp.MaxActivationDistance = 8
	pp.RequiresLineOfSight = false
	pp.Parent = root
	pp.Triggered:Connect(function(player)
		if state.solved then
			notify("The case is closed.")
			return
		end
		sim:hold(c.id, 30, player)
		openInterview:FireClient(player, {
			citizenId = c.id,
			name = fullName(c),
			job = c.job,
			questions = questionsFor(c),
		})
	end)
end

function CaseService.start(args: { world: World, citizens: { Citizen }, sim: CitizenSim.CitizenSim, furniture: Furnish.Furniture, seed: number, saved: CaseSave? })
	world = args.world
	furniture = args.furniture
	citizens = args.citizens
	sim = args.sim
	caseSeed = args.seed
	case = CaseGen.generate(RngModule.new(args.seed + 2), world, citizens)
	if args.saved then
		state = args.saved
		if not state.board then
			-- Saves from before the board: pin what was already known.
			state.board = CaseBoard.new()
			for _, id in state.found do
				CaseBoard.autoPin(state.board :: CaseBoard.Board, "ev:" .. id)
			end
			for key in state.people do
				CaseBoard.autoPin(state.board :: CaseBoard.Board, "p:" .. key)
			end
		else
			state.board = CaseBoard.normalize(state.board)
		end
		state.prints = Prints.normalize(state.prints)
		state.photos = if typeof(state.photos) == "table" then state.photos else {}
		if not state.body then
			-- Saves from before the close-up exam: an inspected body keeps what it told you.
			state.body = {}
			if table.find(state.found, "body") then
				local at = case.tod + 8 * 60
				state.body = { wound = true, tempAt = at, temp = math.floor((37 - BodyExam.COOL_PER_HOUR * 8) * 10 + 0.5) / 10 }
			end
		end
	else
		knowPerson(case.victimId, "Found dead at home: " .. world.rooms[case.sceneRoom].label .. ".")
	end
	CaseBoard.autoPin(board(), "place:" .. case.sceneRoom)

	-- The victim is out of the simulation; their body is at the scene.
	sim:exclude(case.victimId)
	sim.onRigSpawned = onRigSpawned

	remotes = Instance.new("Folder")
	remotes.Name = "CaseRemotes"
	remotes.Parent = ReplicatedStorage
	boardEvent = remote("RemoteEvent", "Board")
	notifyEvent = remote("RemoteEvent", "Notify")
	openInterview = remote("RemoteEvent", "OpenInterview")
	openAccuse = remote("RemoteEvent", "OpenAccuse")
	local getBoard = remote("RemoteFunction", "GetBoard") :: RemoteFunction
	local ask = remote("RemoteFunction", "Ask") :: RemoteFunction
	local accuse = remote("RemoteFunction", "Accuse") :: RemoteFunction

	getBoard.OnServerInvoke = function()
		return boardPayload()
	end

	local setTool = remote("RemoteEvent", "SetTool") :: RemoteEvent
	setTool.OnServerEvent:Connect(function(player: Player, tool: any)
		player:SetAttribute("Tool", if tool == "prints" or tool == "camera" then tool else nil)
	end)
	Photos.setup({
		world = world,
		citizens = citizens,
		case = case,
		remotes = remotes,
		photos = function()
			state.photos = state.photos or {}
			return state.photos :: { Photos.Photo }
		end,
		isKnown = function(id: number)
			return state.people[tostring(id)] ~= nil
		end,
		changed = function()
			-- A photo you took goes straight on the board.
			CaseBoard.autoPin(board(), "photo:" .. #(state.photos or {}))
			pushBoard()
		end,
	})

	local boardAction = remote("RemoteFunction", "BoardAction") :: RemoteFunction
	boardAction.OnServerInvoke = function(player: Player, action: any, args: any)
		local changed, err = CaseBoard.apply(board(), player, action, args, function(item: string)
			return notebook()[item] ~= nil
		end)
		if changed then
			pushBoard()
		end
		return { ok = changed, err = err }
	end

	ask.OnServerInvoke = function(player: Player, citizenId: any, qid: any, evidenceId: any)
		local c = citizens[tonumber(citizenId) or 0]
		if not c or typeof(qid) ~= "string" or state.solved then
			return { text = "..." }
		end
		if evidenceId ~= nil and (typeof(evidenceId) ~= "string" or not table.find(state.found, evidenceId)) then
			return { text = "You don't have that." }
		end
		-- Must be standing near them
		local char = player.Character
		local rig = sim:rigFor(c.id)
		if not char or not rig or (char:GetPivot().Position - rig:GetPivot().Position).Magnitude > 14 then
			return { text = "(They've walked off.)" }
		end
		sim:hold(c.id, 30, player)
		if qid == "prints" then
			local text
			if Prints.willGive(case, c) then
				printState().taken[tostring(c.id)] = true
				knowPerson(c.id, "Gave you their fingerprints.")
				text = "Fine. If it helps. (You roll each finger on the card.)"
			else
				knowPerson(c.id, "Refused to give fingerprints.")
				text = if c.id == case.killerId then "No. Not without a warrant." else "I don't think so. I haven't done anything."
			end
			pushBoard()
			return { text = text, questions = questionsFor(c) }
		end
		local a = Knowledge.answer(ctx(), c, qid, evidenceId)
		local changed = knowPerson(c.id, a.note)
		if a.addPeople then
			for _, pid in a.addPeople do
				if knowPerson(pid, nil) then
					notify("New person of interest: " .. fullName(citizens[pid]))
				end
			end
			changed = true
		end
		if changed or a.note then
			pushBoard()
		end
		return { text = a.text, questions = questionsFor(c) }
	end

	accuse.OnServerInvoke = function(player: Player, suspectId: any, motiveId: any)
		if state.solved then
			return { text = state.result }
		end
		local suspect = citizens[tonumber(suspectId) or 0]
		if not suspect or typeof(motiveId) ~= "string" then
			return { text = "Pick a suspect and a motive." }
		end
		local killer = citizens[case.killerId]
		local rightKiller = suspect.id == killer.id
		local rightMotive = motiveId == case.motive
		local score = (if rightKiller then 70 else 0) + (if rightMotive then 30 else 0)
		local motiveWords = ({ jealousy = "jealousy", debt = "an unpaid debt", rivalry = "a work rivalry" })[case.motive]
		local verdict = if rightKiller and rightMotive
			then "Case closed. You got it."
			elseif rightKiller
			then "You named the killer, but the motive didn't hold up."
			else "Wrong person. The real killer walks."
		local truth = ("%s killed %s at about %s, over %s. Score: %d/100."):format(
			fullName(killer),
			fullName(citizens[case.victimId]),
			CaseGen.fmtTime(case.tod),
			motiveWords,
			score
		)
		state.solved = true
		state.result = verdict .. " " .. truth
		notify(player.DisplayName .. " filed an accusation against " .. fullName(suspect) .. ".")
		pushBoard()
		return { text = state.result, correct = rightKiller }
	end

	placeScene()
	task.delay(4, function()
		notify(("Case file: a neighbour hasn't seen %s since last night. Check %s."):format(
			fullName(citizens[case.victimId]),
			world.rooms[case.sceneRoom].label
		))
		pushBoard()
	end)
	Players.PlayerAdded:Connect(function(p)
		task.delay(6, function()
			if p.Parent then
				boardEvent:FireClient(p, boardPayload())
			end
		end)
	end)
end

function CaseService.serialize(): CaseSave
	return state
end

-- Wipe case progress (testing only): the scene stays, the board starts over.
function CaseService.debugReset()
	state = { found = {}, people = {}, todKnown = false, solved = false, result = nil, board = CaseBoard.new(), body = {}, prints = Prints.new(), photos = {} }
	knowPerson(case.victimId, "Found dead at home: " .. world.rooms[case.sceneRoom].label .. ".")
	CaseBoard.autoPin(board(), "place:" .. case.sceneRoom)
	pushBoard()
end

function CaseService.debugDiscover(id: string)
	if case.evidence[id] then
		discover(id, nil)
	end
end

function CaseService.debug(): any
	return {
		victim = fullName(citizens[case.victimId]),
		killer = fullName(citizens[case.killerId]),
		motive = case.motive,
		method = case.method,
		tod = CaseGen.fmtTime(case.tod),
		scene = world.rooms[case.sceneRoom].label,
		killerHome = world.rooms[citizens[case.killerId].homeRoom].label,
		found = state.found,
		solved = state.solved,
	}
end

return CaseService
