--!strict
-- Server entry point. The first player to join is the host; their save decides the world seed.
-- Characters load only after the world is built.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Rng = require(Shared:WaitForChild("Rng"))

local Server = script.Parent
local BuildingGen = require(Server:WaitForChild("BuildingGen"))
local CitizenGen = require(Server:WaitForChild("CitizenGen"))
local CitizenSim = require(Server:WaitForChild("CitizenSim"))
local Persistence = require(Server:WaitForChild("Persistence"))
local Atmosphere = require(Server:WaitForChild("Atmosphere"))
local CaseService = require(Server:WaitForChild("CaseService"))
local Furnish = require(Server:WaitForChild("Furnish"))

Players.CharacterAutoLoads = false

local hostId: number? = nil
local ready = false
local seed = 0
local gameMinutes = Config.START_MINUTE
local world: BuildingGen.World? = nil
local citizens: { CitizenGen.Citizen } = {}
local sim: CitizenSim.CitizenSim? = nil
local citizenDeltas: { [string]: any } = {}
local lastSave: { ok: boolean, at: number, err: string? }? = nil
local savingDisabled = false -- set from the debug hook so tests never touch the real save

local function snapshot(): Persistence.WorldSave
	return {
		schema = Config.SCHEMA_VERSION,
		seed = seed,
		gameMinutes = gameMinutes,
		savedAt = os.time(),
		citizens = citizenDeltas,
		case = if ready then CaseService.serialize() else nil,
	}
end

local function saveWorld(reason: string): boolean
	if not hostId or not ready or savingDisabled then
		return false
	end
	local ok, err = Persistence.save(hostId, snapshot())
	lastSave = { ok = ok, at = os.time(), err = err }
	print(("[World] Save (%s): %s"):format(reason, if ok then "ok" else tostring(err)))
	return ok
end

local function spawnPlayer(p: Player)
	if p.Parent then
		p:LoadCharacter()
	end
end

local function wireElevators(w: BuildingGen.World)
	for _, d in w.model:GetDescendants() do
		if d:IsA("ProximityPrompt") and d.Parent and d.Parent.Name == "ElevatorPanel" then
			local panel = d.Parent :: BasePart
			local floor = panel:GetAttribute("Floor") :: number
			local target = if d.Name == "Up" then floor + 1 else floor - 1
			d.Triggered:Connect(function(player)
				local char = player.Character
				if char and w.elevators[target] then
					char:PivotTo(CFrame.new(w.elevators[target] + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, math.rad(-90), 0))
				end
			end)
		end
	end
end

local function boot(host: Player)
	hostId = host.UserId
	local ok, data, err = Persistence.load(host.UserId)
	local savedCase = nil
	if ok and data then
		seed = data.seed
		gameMinutes = data.gameMinutes
		citizenDeltas = data.citizens or {}
		savedCase = data.case
		print(("[World] Loaded save: seed %d, minute %.1f"):format(seed, gameMinutes))
	else
		seed = Random.new():NextInteger(1, 2 ^ 31 - 2)
		if not ok then
			warn("[World] Could not load save, starting a new world:", err)
		else
			print("[World] No save found, new world seed", seed)
		end
	end

	Atmosphere.apply()
	Atmosphere.setTime(gameMinutes)
	local t0 = os.clock()
	local w = BuildingGen.generate(Rng.new(seed), workspace)
	world = w
	citizens = CitizenGen.generate(Rng.new(seed + 1), w)
	sim = CitizenSim.new(w, citizens)
	wireElevators(w)
	local furniture = Furnish.furnish(w, Rng.new(seed + 3))
	CaseService.start({ world = w, citizens = citizens, sim = sim :: any, furniture = furniture, seed = seed, saved = savedCase })
	print(("[World] Built in %.2fs: %d rooms, %d citizens"):format(os.clock() - t0, #w.roomList, #citizens))

	ready = true
	ReplicatedStorage:SetAttribute("WorldSeed", seed)
	for _, p in Players:GetPlayers() do
		spawnPlayer(p)
	end
end

local function onPlayerAdded(p: Player)
	p.CharacterAdded:Connect(function(char)
		local hum = char:WaitForChild("Humanoid") :: Humanoid
		hum.Died:Connect(function()
			task.delay(5, spawnPlayer, p)
		end)
	end)
	if not hostId then
		task.spawn(boot, p)
	elseif ready then
		spawnPlayer(p)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in Players:GetPlayers() do
	onPlayerAdded(p)
end

Players.PlayerRemoving:Connect(function(p)
	if p.UserId == hostId then
		saveWorld("host left")
	end
end)

game:BindToClose(function()
	if RunService:IsStudio() then
		task.wait(0.5)
	end
	saveWorld("shutdown")
end)

-- Clock and simulation
task.spawn(function()
	while true do
		local dt = task.wait(Config.SIM_TICK)
		if ready and sim then
			gameMinutes += dt / Config.REAL_SECONDS_PER_GAME_MINUTE
			ReplicatedStorage:SetAttribute("GameMinutes", gameMinutes)
			Atmosphere.setTime(gameMinutes)
			sim:tick(gameMinutes)
		end
	end
end)

-- Autosave
task.spawn(function()
	while true do
		task.wait(Config.AUTOSAVE_INTERVAL)
		saveWorld("autosave")
	end
end)

-- Debug hook for testing from Studio. Server only; never exposed to clients.
local debugFn = Instance.new("BindableFunction")
debugFn.Name = "WorldDebug"
debugFn.OnInvoke = function(cmd: string, arg: any): any
	if cmd == "stats" then
		local s = if sim then sim:stats() else {}
		s.ready = ready
		s.seed = seed
		s.gameMinutes = gameMinutes
		s.citizens = #citizens
		s.lastSave = lastSave
		return s
	elseif cmd == "setMinutes" then
		gameMinutes = tonumber(arg) or gameMinutes
		return gameMinutes
	elseif cmd == "save" then
		return saveWorld("debug")
	elseif cmd == "load" then
		if not hostId then
			return { ok = false, err = "no host" }
		end
		local ok, data, err = Persistence.load(hostId)
		return { ok = ok, err = err, seed = data and data.seed, gameMinutes = data and data.gameMinutes, schema = data and data.schema }
	elseif cmd == "case" then
		return CaseService.debug()
	elseif cmd == "noSave" then
		savingDisabled = true
		return true
	elseif cmd == "hint" then
		return CaseService.debugHint()
	elseif cmd == "resetCase" then
		CaseService.debugReset()
		return CaseService.debug()
	elseif cmd == "discover" then
		CaseService.debugDiscover(tostring(arg))
		return CaseService.debug()
	elseif cmd == "citizen" then
		local c = citizens[tonumber(arg) or 1]
		if not c then
			return nil
		end
		return {
			name = c.firstName .. " " .. c.lastName,
			job = c.job,
			home = world and world.rooms[c.homeRoom].label,
			work = c.workRoom,
			shift = { c.shiftStart, c.shiftEnd },
			wake = c.wake,
			sleep = c.sleep,
			traits = c.traits,
			relationships = #c.relationships,
		}
	end
	return nil
end
debugFn.Parent = ServerStorage
