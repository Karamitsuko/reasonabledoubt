--!strict
-- World saves. The city is rebuilt from its seed, so a save only holds the seed, the clock and what changed.
-- Every save carries a schema version and passes through migrations on load, so updates never break old worlds.

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

export type WorldSave = {
	schema: number,
	seed: number,
	gameMinutes: number,
	savedAt: number,
	citizens: { [string]: any }, -- per-citizen deltas, keyed by id as a string
}

-- MIGRATIONS[n] upgrades a save from schema n to n + 1.
local MIGRATIONS: { [number]: (any) -> any } = {}

local Persistence = {}

local store: DataStore? = nil
local function getStore(): DataStore
	if not store then
		store = DataStoreService:GetDataStore(Config.DATASTORE_NAME)
	end
	return store :: DataStore
end

local function key(ownerId: number): string
	return "world_" .. tostring(ownerId)
end

-- Returns ok, save-or-nil, error message.
function Persistence.load(ownerId: number): (boolean, WorldSave?, string?)
	local ok, result = pcall(function()
		return getStore():GetAsync(key(ownerId))
	end)
	if not ok then
		return false, nil, tostring(result)
	end
	if result == nil then
		return true, nil, nil
	end
	local data = result
	while (data.schema or 0) < Config.SCHEMA_VERSION do
		local migrate = MIGRATIONS[data.schema or 0]
		if not migrate then
			return false, nil, ("no migration from schema %s"):format(tostring(data.schema))
		end
		data = migrate(data)
	end
	return true, data :: WorldSave, nil
end

function Persistence.save(ownerId: number, data: WorldSave): (boolean, string?)
	data.schema = Config.SCHEMA_VERSION
	data.savedAt = os.time()
	local lastErr = ""
	for attempt = 1, 3 do
		local ok, err = pcall(function()
			getStore():UpdateAsync(key(ownerId), function()
				return data
			end)
		end)
		if ok then
			return true, nil
		end
		lastErr = tostring(err)
		warn(("[Persistence] Save attempt %d failed: %s"):format(attempt, lastErr))
		task.wait(2 ^ attempt)
	end
	return false, lastErr
end

return Persistence
