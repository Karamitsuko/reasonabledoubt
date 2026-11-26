--!strict
-- Neon-noir look: dense haze, purple decay, bloom on neon, cool colour grade, time of day from the game clock.
-- Lighting.Technology (Future) is a place setting and is set once in Studio.

local Lighting = game:GetService("Lighting")

local Atmosphere = {}

local function ensure<T>(className: string, name: string): T
	local existing = Lighting:FindFirstChild(name)
	if existing then
		return existing :: any
	end
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = Lighting
	return inst :: any
end

function Atmosphere.apply()
	Lighting.Ambient = Color3.fromRGB(16, 14, 22)
	Lighting.OutdoorAmbient = Color3.fromRGB(46, 48, 66)
	Lighting.Brightness = 1.4
	Lighting.EnvironmentDiffuseScale = 0.35
	Lighting.EnvironmentSpecularScale = 1
	Lighting.GlobalShadows = true
	Lighting.ExposureCompensation = 0.1

	local atm = ensure("Atmosphere", "NoirAtmosphere") :: Atmosphere
	atm.Density = 0.42
	atm.Offset = 0.15
	atm.Color = Color3.fromRGB(110, 120, 145)
	atm.Decay = Color3.fromRGB(70, 40, 95)
	atm.Glare = 0.15
	atm.Haze = 2.2

	local bloom = ensure("BloomEffect", "NoirBloom") :: BloomEffect
	bloom.Intensity = 0.9
	bloom.Size = 30
	bloom.Threshold = 0.85

	local grade = ensure("ColorCorrectionEffect", "NoirGrade") :: ColorCorrectionEffect
	grade.Contrast = 0.12
	grade.Saturation = -0.12
	grade.Brightness = 0
	grade.TintColor = Color3.fromRGB(225, 232, 255)

	for _, child in Lighting:GetChildren() do
		if child:IsA("Atmosphere") and child.Name ~= "NoirAtmosphere" then
			child:Destroy()
		end
	end
end

function Atmosphere.setTime(totalMinutes: number)
	local hour = (totalMinutes / 60) % 24
	Lighting.ClockTime = hour
	-- Mist thickens late at night and around dawn.
	local atm = Lighting:FindFirstChild("NoirAtmosphere") :: Atmosphere?
	if atm then
		local night = if hour < 6 or hour > 20 then 1 else 0
		atm.Density = 0.36 + 0.12 * night
	end
end

return Atmosphere
