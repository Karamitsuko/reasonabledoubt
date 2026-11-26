--!strict
-- Small noir clock in the top-left corner, driven by the server's game clock.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "ClockHud"
gui.ResetOnSpawn = false

local frame = Instance.new("Frame")
frame.Position = UDim2.fromOffset(16, 16)
frame.Size = UDim2.fromOffset(190, 34)
frame.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
frame.BackgroundTransparency = 0.35
frame.BorderSizePixel = 0
frame.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 6)
corner.Parent = frame

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(255, 70, 160)
stroke.Transparency = 0.4
stroke.Parent = frame

local label = Instance.new("TextLabel")
label.Size = UDim2.fromScale(1, 1)
label.BackgroundTransparency = 1
label.Font = Enum.Font.GothamMedium
label.TextSize = 16
label.TextColor3 = Color3.fromRGB(230, 230, 240)
label.Text = "..."
label.Parent = frame

local function update()
	local total = ReplicatedStorage:GetAttribute("GameMinutes")
	if typeof(total) ~= "number" then
		return
	end
	local day = math.floor(total / 1440) + 1
	local m = math.floor(total % 1440)
	label.Text = ("DAY %d   %02d:%02d"):format(day, m // 60, m % 60)
end

ReplicatedStorage:GetAttributeChangedSignal("GameMinutes"):Connect(update)
update()
gui.Parent = player:WaitForChild("PlayerGui")
