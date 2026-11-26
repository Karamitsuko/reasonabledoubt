--!strict
-- Tunable constants shared by server and client.

local Config = {
	SCHEMA_VERSION = 1,

	-- Time: 1 game minute = 2 real seconds, so a game day is 48 real minutes.
	REAL_SECONDS_PER_GAME_MINUTE = 2,
	START_MINUTE = 7 * 60 + 30,
	SIM_TICK = 0.5,

	-- World
	FLOORS = 5,
	FLOOR_HEIGHT = 12,
	CITIZEN_COUNT = 50,

	-- Simulation level of detail
	TIER0_RADIUS = 80, -- studs from a player at which citizens get a body
	MAX_RIGS = 40,
	WALK_SPEED = 9,
	WAYPOINT_TIMEOUT = 10, -- seconds before a stuck citizen is snapped to its waypoint

	-- Persistence
	DATASTORE_NAME = "ReasonableDoubt_Worlds_v1",
	AUTOSAVE_INTERVAL = 120,
}

return Config
