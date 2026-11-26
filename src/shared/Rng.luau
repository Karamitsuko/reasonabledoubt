--!strict
-- Seeded random helper. Every generator takes one of these so worlds rebuild identically from a seed.

local Rng = {}
Rng.__index = Rng

export type Rng = typeof(setmetatable({} :: { _r: Random }, Rng))

function Rng.new(seed: number): Rng
	return setmetatable({ _r = Random.new(seed) }, Rng)
end

function Rng.int(self: Rng, a: number, b: number): number
	return self._r:NextInteger(a, b)
end

function Rng.float(self: Rng, a: number?, b: number?): number
	local lo, hi = a or 0, b or 1
	return lo + self._r:NextNumber() * (hi - lo)
end

function Rng.chance(self: Rng, p: number): boolean
	return self._r:NextNumber() < p
end

function Rng.pick<T>(self: Rng, list: { T }): T
	return list[self._r:NextInteger(1, #list)]
end

function Rng.weighted<T>(self: Rng, entries: { { value: T, weight: number } }): T
	local total = 0
	for _, e in entries do
		total += e.weight
	end
	local roll = self._r:NextNumber() * total
	for _, e in entries do
		roll -= e.weight
		if roll <= 0 then
			return e.value
		end
	end
	return entries[#entries].value
end

function Rng.shuffle<T>(self: Rng, list: { T }): { T }
	for i = #list, 2, -1 do
		local j = self._r:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

function Rng.fork(self: Rng): Rng
	return Rng.new(self._r:NextInteger(1, 2 ^ 31 - 1))
end

-- Stable 0..1 roll from integers, for per-day variation without storing state.
function Rng.hash01(a: number, b: number, c: number?): number
	local h = (a * 73856093 + b * 19349663 + (c or 0) * 83492791) % 1000003
	return h / 1000003
end

return Rng
