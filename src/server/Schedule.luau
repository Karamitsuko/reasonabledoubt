--!strict
-- Where a citizen should be at a given game time. Pure lookup, no state:
-- any citizen can be placed correctly the moment a player arrives, so nobody gets "stuck" off schedule.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rng = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Rng"))
local CitizenGen = require(script.Parent:WaitForChild("CitizenGen"))

type Citizen = CitizenGen.Citizen

local DAY = 24 * 60

local function inWindow(m: number, a: number, b: number): boolean
	if a <= b then
		return m >= a and m < b
	end
	return m >= a or m < b
end

local Schedule = {}

-- Returns a room id, or "offsite" for anywhere outside the building.
function Schedule.locationAt(c: Citizen, totalMinutes: number): string
	local day = math.floor(totalMinutes / DAY)
	local m = totalMinutes % DAY

	if inWindow(m, c.sleep, c.wake) then
		return c.homeRoom
	end

	if c.workRoom then
		local wraps = c.shiftStart > c.shiftEnd
		-- After midnight on a wrapping shift, the shift belongs to the previous day.
		local shiftDay = if wraps and m < c.shiftEnd then day - 1 else day
		local workday = not c.daysOff[shiftDay % 7]
		if workday and inWindow(m, c.shiftStart, c.shiftEnd) then
			local lunchWindow = not wraps and c.shiftStart <= 12 * 60 and c.shiftEnd >= 13 * 60
			if lunchWindow and c.lunchSpot and inWindow(m, 12 * 60, 12 * 60 + 45) and Rng.hash01(c.id, day, 1) < c.lunchChance then
				return c.lunchSpot
			end
			return c.workRoom
		end
	end

	if c.eveningSpot and inWindow(m, c.eveningStart, (c.eveningStart + 120) % DAY) then
		if Rng.hash01(c.id, day, 2) < c.eveningChance then
			return c.eveningSpot
		end
	end

	-- Unemployed people and people on days off wander out for part of the afternoon.
	if (not c.workRoom or c.daysOff[day % 7]) and inWindow(m, 13 * 60, 16 * 60) and Rng.hash01(c.id, day, 3) < 0.5 then
		return "offsite"
	end

	return c.homeRoom
end

return Schedule
