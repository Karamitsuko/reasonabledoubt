--!strict
-- The body, examined up close. Clicking the body opens a close-up panel on the client; the player picks a
-- tool (hands, thermometer, flashlight) and uses it on the part of the body they choose. Nothing is handed
-- over: the temperature has to be taken at the core, the wound has to be found and lit, the pockets have to
-- be gone through one by one. The server owns the truth and answers each action.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RngModule = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Rng"))
local CaseGen = require(script.Parent:WaitForChild("CaseGen"))
local CitizenGen = require(script.Parent:WaitForChild("CitizenGen"))

type Case = CaseGen.Case
type Citizen = CitizenGen.Citizen

-- What the player has established from the body. Saved with the case.
export type BodyState = {
	temp: number?, -- core temperature reading, °C
	tempAt: number?, -- game minute it was taken
	wound: boolean?, -- found and looked at the wound under a light
	hands: boolean?, -- looked at the hands under a light
	receipt: boolean?, -- went through the wallet
}

type PocketItem = { id: string, label: string }

local BodyExam = {}

BodyExam.ROOM_TEMP = 21
BodyExam.COOL_PER_HOUR = 0.8 -- °C lost per hour after death, roughly
local REACH = 14

local POCKETS = {
	coatL = "Left jacket pocket",
	coatR = "Right jacket pocket",
	pantsL = "Left trouser pocket",
	pantsR = "Right trouser pocket",
}

local BARS = { "The Copper Lamp", "Halfmoon Bar", "the Night Kettle diner", "Static Lounge" }

local function fullName(c: Citizen): string
	return c.firstName .. " " .. c.lastName
end

local function nowMinutes(): number
	return tonumber(ReplicatedStorage:GetAttribute("GameMinutes")) or 0
end

-- Deterministic per case: where things sit in the pockets, and the bar receipt.
local function layout(seed: number, case: Case)
	local rng = RngModule.new(seed + 5)
	local slots = { "coatL", "coatR", "pantsL", "pantsR" }
	for i = #slots, 2, -1 do
		local j = rng:int(1, i)
		slots[i], slots[j] = slots[j], slots[i]
	end
	local pockets: { [string]: { PocketItem } } = { coatL = {}, coatR = {}, pantsL = {}, pantsR = {} }
	table.insert(pockets[slots[1]], { id = "note", label = "Folded paper" })
	table.insert(pockets[slots[2]], { id = "wallet", label = "Wallet" })
	table.insert(pockets[slots[3]], { id = "keys", label = "Keys" })
	table.insert(pockets[slots[4]], { id = "coins", label = "Coins and lint" })
	if rng:chance(0.5) then
		table.insert(pockets[slots[rng:int(2, 4)]], { id = "gum", label = "Chewing gum" })
	end
	local receiptMinute = math.floor((case.tod - rng:int(70, 110)) / 5) * 5
	return pockets, receiptMinute, rng:pick(BARS)
end

-- When the death happened, read back from the temperature the player took.
function BodyExam.estimate(bs: BodyState): (number?, number?)
	if not bs.temp or not bs.tempAt or bs.temp <= BodyExam.ROOM_TEMP + 0.3 then
		return nil, nil
	end
	local est = bs.tempAt - (37 - bs.temp) / BodyExam.COOL_PER_HOUR * 60
	return math.floor((est - 40) / 5) * 5, math.ceil((est + 40) / 5) * 5
end

-- Notebook facts drawn from the examination.
function BodyExam.facts(bs: BodyState, case: Case, receipt: { minute: number, bar: string }?, fact: (string, string, string) -> ())
	if bs.temp and bs.tempAt then
		local lo, hi = BodyExam.estimate(bs)
		if lo and hi then
			fact(
				"tod",
				"Time of death",
				("Core %.1f°C at %s, room %d°C. Losing about %.1f°C an hour puts death between %s and %s."):format(
					bs.temp,
					CaseGen.fmtTime(bs.tempAt),
					BodyExam.ROOM_TEMP,
					BodyExam.COOL_PER_HOUR,
					CaseGen.fmtTime(lo),
					CaseGen.fmtTime(hi)
				)
			)
		else
			fact("tod", "Time of death", ("Body already at room temperature when checked at %s. Too late to time it from the body."):format(CaseGen.fmtTime(bs.tempAt)))
		end
	end
	if bs.wound then
		fact("method", "Cause of death", if case.method == "blade" then "A single stab wound low in the abdomen." else "A blow to the back of the head.")
	end
	if bs.hands then
		fact(
			"hands",
			"The victim's hands",
			if case.method == "blade"
				then "Shallow cuts across both palms. They saw it coming and grabbed for the blade."
				else "Clean. No torn nails, no bruising. They never saw it coming."
		)
	end
	if bs.receipt and receipt then
		fact("receipt", "Bar receipt " .. CaseGen.fmtTime(receipt.minute), ("From %s, two drinks, paid at %s last night. In the victim's wallet."):format(receipt.bar, CaseGen.fmtTime(receipt.minute)))
	end
end

-- A wound on the body itself, so it exists in the world and in the close-up.
local function addWound(rig: Model, method: string)
	local host = rig:FindFirstChild(if method == "blade" then "LowerTorso" else "Head") :: BasePart?
	if not host then
		return
	end
	local w = Instance.new("Part")
	w.Name = "Wound"
	w.Anchored = true
	w.CanCollide = false
	w.Material = Enum.Material.SmoothPlastic
	w.Color = Color3.fromRGB(70, 6, 10)
	if method == "blade" then
		w.Size = Vector3.new(0.4, 0.1, 0.05)
		w.CFrame = host.CFrame * CFrame.new(0.18, 0.05, -host.Size.Z / 2 - 0.01)
	else
		w.Shape = Enum.PartType.Ball
		w.Size = Vector3.new(0.5, 0.5, 0.5)
		w.CFrame = host.CFrame * CFrame.new(0, 0.2, host.Size.Z * 0.3)
	end
	w.Parent = rig
end

export type Setup = {
	case: Case,
	victim: Citizen,
	sceneLabel: string,
	seed: number,
	body: Instance, -- the rig model, or a stand-in part
	bodyPos: Vector3,
	remotes: Folder,
	state: () -> BodyState,
	isFound: (string) -> boolean,
	discover: (string, Player) -> (),
	noteText: () -> string,
	changed: () -> (),
	setTodKnown: () -> (),
}

-- Returns the bar receipt details so the notebook can show the fact.
function BodyExam.setup(s: Setup): { minute: number, bar: string }
	local case, victim = s.case, s.victim
	local pockets, receiptMinute, bar = layout(s.seed, case)
	if s.body:IsA("Model") then
		addWound(s.body, case.method)
	end

	local openBody = Instance.new("RemoteEvent")
	openBody.Name = "OpenBody"
	openBody.Parent = s.remotes
	local bodyAction = Instance.new("RemoteFunction")
	bodyAction.Name = "BodyAction"
	bodyAction.Parent = s.remotes

	local cd = Instance.new("ClickDetector")
	cd.MaxActivationDistance = 10
	cd.Parent = s.body
	cd.MouseClick:Connect(function(player)
		if player:GetAttribute("Tool") ~= nil then
			return
		end
		s.discover("body", player)
		openBody:FireClient(player, { name = fullName(victim), method = case.method })
	end)

	local function near(player: Player): boolean
		local char = player.Character
		return char ~= nil and (char:GetPivot().Position - s.bodyPos).Magnitude <= REACH
	end

	local function hoursDead(): number
		return math.max(0, (nowMinutes() - case.tod) / 60)
	end

	local LOOK: { [string]: string } = {
		head = if case.method == "blade" then "No marks on the face. Eyes half open, staring at nothing." else "The face is unmarked. Whatever happened, it came from behind.",
		arms = "Sleeves pushed up. No needle marks, no bruises.",
		legs = "Nothing on the legs.",
		feet = "House slippers. They were home for the night and not expecting to go out.",
		torso = if case.method == "blade"
			then "The shirt is stiff with dried blood, low on the front."
			else "The shirt is clean. No blood on the front at all.",
	}

	bodyAction.OnServerInvoke = function(player: Player, action: any, a: any, b: any): any
		if typeof(action) ~= "string" then
			return { text = "?" }
		end
		if not near(player) then
			return { text = "You need to be next to the body.", close = true }
		end
		local bs = s.state()
		if action == "temp" then
			if bs.temp then
				return { text = ("You already took it: %.1f°C at %s."):format(bs.temp, CaseGen.fmtTime(bs.tempAt or 0)) }
			end
			local now = nowMinutes()
			bs.temp = math.floor(math.max(BodyExam.ROOM_TEMP, 37 - BodyExam.COOL_PER_HOUR * hoursDead()) * 10 + 0.5) / 10
			bs.tempAt = math.floor(now)
			if BodyExam.estimate(bs) then
				s.setTodKnown()
			end
			s.changed()
			return {
				text = ("Core temperature %.1f°C at %s. The room is %d°C. A body loses roughly %.1f°C an hour."):format(
					bs.temp :: number,
					CaseGen.fmtTime(bs.tempAt :: number),
					BodyExam.ROOM_TEMP,
					BodyExam.COOL_PER_HOUR
				),
				fact = true,
			}
		elseif action == "wound" then
			local first = not bs.wound
			bs.wound = true
			if first then
				s.changed()
			end
			return {
				text = if case.method == "blade"
					then "A single narrow stab wound, low in the abdomen. One blow, a kitchen-sized blade."
					else "The back of the skull is caved in. Something heavy and blunt, swung hard, once.",
				fact = first,
			}
		elseif action == "touch" then
			local h = hoursDead()
			return {
				text = if h < 2
					then "Still limp, and faintly warm."
					elseif h < 14 then "Stiff through the jaw and arms. Rigor has set in properly."
					elseif h < 30 then "Rigid all over."
					else "Loose again. Rigor has come and gone.",
			}
		elseif action == "look" then
			if a == "hands" then
				local first = not bs.hands
				bs.hands = true
				if first then
					s.changed()
				end
				return {
					text = if case.method == "blade"
						then "Shallow cuts across both palms. They grabbed for the blade."
						else "Clean hands. No torn nails, no bruised knuckles. No struggle.",
					fact = first,
				}
			end
			return { text = LOOK[tostring(a)] or "Nothing there." }
		elseif action == "pocket" then
			local slot = tostring(a)
			local items = pockets[slot]
			if not items then
				return { text = "Nothing there." }
			end
			local out = {}
			for _, it in items do
				if not (it.id == "note" and s.isFound("note")) then
					table.insert(out, it)
				end
			end
			return { text = POCKETS[slot] .. (if #out == 0 then ": empty." else ":"), items = out, slot = slot }
		elseif action == "take" then
			local slot, id = tostring(a), tostring(b)
			local items = pockets[slot]
			local has = false
			for _, it in items or {} do
				has = has or it.id == id
			end
			if not has then
				return { text = "That isn't there." }
			end
			if id == "note" then
				s.discover("note", player)
				return { text = s.noteText(), taken = true }
			elseif id == "wallet" then
				local first = not bs.receipt
				bs.receipt = true
				if first then
					s.changed()
				end
				return {
					text = ("ID card for %s. Forty in cash. A bar receipt from %s, two drinks, paid at %s last night."):format(
						fullName(victim),
						bar,
						CaseGen.fmtTime(receiptMinute)
					),
					fact = first,
				}
			elseif id == "keys" then
				return { text = "Door keys on a ring with a plastic tag: " .. s.sceneLabel .. "." }
			elseif id == "gum" then
				return { text = "Half a pack of mint gum." }
			end
			return { text = "A few coins and pocket lint." }
		end
		return { text = "?" }
	end

	return { minute = receiptMinute, bar = bar }
end

return BodyExam
