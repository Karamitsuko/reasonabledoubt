--!strict
-- Field tools you carry everywhere: the fingerprint kit (G) and the camera (C). With a tool out, clicking in
-- the world uses the tool instead of opening things. Photos are kept on this device for the session and
-- shown on their board notes; what each photo shows is worked out and saved by the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("CaseRemotes")
local setTool = remotes:WaitForChild("SetTool") :: RemoteEvent
local dust = remotes:WaitForChild("Dust") :: RemoteFunction
local liftPrint = remotes:WaitForChild("LiftPrint") :: RemoteFunction
local takePhoto = remotes:WaitForChild("TakePhoto") :: RemoteFunction

local INK = Color3.fromRGB(232, 230, 240)
local QUIET = Color3.fromRGB(160, 156, 175)
local PANEL = Color3.fromRGB(14, 13, 20)
local CARD = Color3.fromRGB(26, 24, 34)
local ACCENT = Color3.fromRGB(255, 70, 160)
local CYAN = Color3.fromRGB(0, 210, 255)
local LAVENDER = Color3.fromRGB(190, 170, 255)

-- Photos taken this session: StringValues named by photo number, read by the case board.
local images = Instance.new("Folder")
images.Name = "PhotoImages"
images.Parent = player

local gui = Instance.new("ScreenGui")
gui.Name = "ToolsUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local function corner(parent: Instance, r: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 6)
	c.Parent = parent
end

local function stroke(parent: Instance, color: Color3)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = 1
	s.Transparency = 0.3
	s.Parent = parent
end

local function label(parent: Instance, str: string, size: number, color: Color3, font: Enum.Font?): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Text = str
	t.TextSize = size
	t.TextColor3 = color
	t.Font = font or Enum.Font.Gotham
	t.TextWrapped = true
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.Size = UDim2.new(1, 0, 0, 0)
	t.AutomaticSize = Enum.AutomaticSize.Y
	t.Parent = parent
	return t
end

-- Tool buttons, bottom left
local bar = Instance.new("Frame")
bar.BackgroundTransparency = 1
bar.AnchorPoint = Vector2.new(0, 1)
bar.Position = UDim2.new(0, 15, 1, -15)
bar.Size = UDim2.fromOffset(330, 34)
bar.Parent = gui
local barList = Instance.new("UIListLayout")
barList.FillDirection = Enum.FillDirection.Horizontal
barList.Padding = UDim.new(0, 8)
barList.Parent = bar

local function toolButton(str: string, color: Color3): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(160, 34)
	b.BackgroundColor3 = PANEL
	b.BackgroundTransparency = 0.15
	b.Text = str
	b.TextColor3 = color
	b.TextSize = 13
	b.Font = Enum.Font.GothamBold
	b.Parent = bar
	corner(b)
	stroke(b, color)
	return b
end
local kitButton = toolButton("PRINT KIT  [G]", LAVENDER)
local camButton = toolButton("CAMERA  [C]", CYAN)

local hint = Instance.new("TextLabel")
hint.AnchorPoint = Vector2.new(0.5, 1)
hint.Position = UDim2.new(0.5, 0, 1, -24)
hint.Size = UDim2.fromOffset(0, 30)
hint.AutomaticSize = Enum.AutomaticSize.X
hint.BackgroundColor3 = PANEL
hint.BackgroundTransparency = 0.2
hint.TextColor3 = INK
hint.TextSize = 14
hint.Font = Enum.Font.GothamMedium
hint.Visible = false
hint.Parent = gui
corner(hint)
local hintPad = Instance.new("UIPadding")
hintPad.PaddingLeft = UDim.new(0, 12)
hintPad.PaddingRight = UDim.new(0, 12)
hintPad.Parent = hint

-- Print card: what the powder showed on the last surface
local card = Instance.new("Frame")
card.AnchorPoint = Vector2.new(1, 1)
card.Position = UDim2.new(1, -20, 1, -70)
card.Size = UDim2.fromOffset(340, 0)
card.AutomaticSize = Enum.AutomaticSize.Y
card.BackgroundColor3 = PANEL
card.BackgroundTransparency = 0.05
card.Visible = false
card.Parent = gui
corner(card, 8)
stroke(card, LAVENDER)
local cardPad = Instance.new("UIPadding")
for _, k in { "PaddingLeft", "PaddingRight", "PaddingTop", "PaddingBottom" } do
	(cardPad :: any)[k] = UDim.new(0, 12)
end
cardPad.Parent = card
local cardList = Instance.new("UIListLayout")
cardList.Padding = UDim.new(0, 6)
cardList.SortOrder = Enum.SortOrder.LayoutOrder
cardList.Parent = card

-- Camera viewfinder
local finder = Instance.new("Frame")
finder.Size = UDim2.fromScale(1, 1)
finder.BackgroundTransparency = 1
finder.Visible = false
finder.Parent = gui
local function bracket(ax: number, ay: number)
	for _, horiz in { true, false } do
		local f = Instance.new("Frame")
		f.BackgroundColor3 = Color3.new(1, 1, 1)
		f.BackgroundTransparency = 0.2
		f.BorderSizePixel = 0
		f.AnchorPoint = Vector2.new(ax, ay)
		f.Position = UDim2.new(ax, if ax == 0 then 60 else -60, ay, if ay == 0 then 60 else -60)
		f.Size = if horiz then UDim2.fromOffset(46, 3) else UDim2.fromOffset(3, 46)
		f.Parent = finder
	end
end
bracket(0, 0)
bracket(1, 0)
bracket(0, 1)
bracket(1, 1)
local reticle = Instance.new("Frame")
reticle.AnchorPoint = Vector2.new(0.5, 0.5)
reticle.Position = UDim2.fromScale(0.5, 0.5)
reticle.Size = UDim2.fromOffset(18, 18)
reticle.BackgroundTransparency = 1
reticle.Parent = finder
stroke(reticle, Color3.new(1, 1, 1))
corner(reticle, 9)
local flash = Instance.new("Frame")
flash.Size = UDim2.fromScale(1, 1)
flash.BackgroundColor3 = Color3.new(1, 1, 1)
flash.BackgroundTransparency = 1
flash.ZIndex = 10
flash.Parent = gui

-- Polaroid preview after a shot
local preview = Instance.new("Frame")
preview.AnchorPoint = Vector2.new(1, 1)
preview.Position = UDim2.new(1, -20, 1, -70)
preview.Size = UDim2.fromOffset(250, 190)
preview.BackgroundColor3 = Color3.fromRGB(240, 238, 232)
preview.Rotation = 3
preview.Visible = false
preview.Parent = gui
local previewImage = Instance.new("ImageLabel")
previewImage.Position = UDim2.fromOffset(10, 10)
previewImage.Size = UDim2.new(1, -20, 0, 136)
previewImage.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
previewImage.ScaleType = Enum.ScaleType.Crop
previewImage.Parent = preview
local previewText = Instance.new("TextLabel")
previewText.Position = UDim2.new(0, 10, 1, -40)
previewText.Size = UDim2.new(1, -20, 0, 34)
previewText.BackgroundTransparency = 1
previewText.TextColor3 = Color3.fromRGB(40, 36, 34)
previewText.TextSize = 13
previewText.Font = Enum.Font.GothamMedium
previewText.TextWrapped = true
previewText.Parent = preview

-- State -----------------------------------------------------------------------------------------------

local tool: string? = nil
local busy = false

local function setActive(t: string?)
	tool = t
	setTool:FireServer(t)
	kitButton.BackgroundColor3 = if t == "prints" then Color3.fromRGB(45, 36, 70) else PANEL
	camButton.BackgroundColor3 = if t == "camera" then Color3.fromRGB(10, 50, 64) else PANEL
	finder.Visible = t == "camera"
	if t == "prints" then
		hint.Text = "Print kit out: click a handle, lid or object to dust it.   [G] put away"
	elseif t == "camera" then
		hint.Text = "Camera out: click to take a photo.   [C] put away"
	end
	hint.Visible = t ~= nil
	if t ~= "prints" then
		card.Visible = false
	end
end

local function clearCard()
	for _, ch in card:GetChildren() do
		if ch:IsA("GuiObject") then
			ch:Destroy()
		end
	end
end

local function showDust(res: any)
	clearCard()
	card.Visible = true
	local title = label(card, tostring(res.text), 14, INK, Enum.Font.GothamBold)
	title.LayoutOrder = 1
	if typeof(res.prints) ~= "table" then
		return
	end
	for i, pr in res.prints do
		local row = Instance.new("Frame")
		row.BackgroundColor3 = CARD
		row.Size = UDim2.new(1, 0, 0, 44)
		row.LayoutOrder = 1 + i
		row.Parent = card
		corner(row, 5)
		local t = label(row, ("Print %d: %s"):format(i, tostring(pr.cls)), 12, INK)
		t.Position = UDim2.fromOffset(10, 6)
		t.Size = UDim2.new(1, -100, 0, 0)
		local b = Instance.new("TextButton")
		b.AnchorPoint = Vector2.new(1, 0.5)
		b.Position = UDim2.new(1, -8, 0.5, 0)
		b.Size = UDim2.fromOffset(74, 28)
		b.BackgroundColor3 = if pr.lifted then CARD else Color3.fromRGB(60, 46, 100)
		b.TextColor3 = if pr.lifted then QUIET else INK
		b.Text = if pr.lifted then "LIFTED" else "LIFT"
		b.Font = Enum.Font.GothamBold
		b.TextSize = 12
		b.AutoButtonColor = not pr.lifted
		b.Parent = row
		corner(b, 4)
		if not pr.lifted then
			b.MouseButton1Click:Connect(function()
				if busy then
					return
				end
				busy = true
				local ok, r = pcall(function()
					return liftPrint:InvokeServer(res.key, pr.n)
				end)
				busy = false
				if ok and r then
					b.Text = "LIFTED"
					b.TextColor3 = QUIET
					b.BackgroundColor3 = CARD
					local note = label(card, tostring(r.text), 12, LAVENDER)
					note.LayoutOrder = 50 + i
				end
			end)
		end
	end
end

local function aimRay(): (Vector3, Vector3)
	local cam = workspace.CurrentCamera
	local m = UserInputService:GetMouseLocation()
	local ray = cam:ViewportPointToRay(m.X, m.Y)
	return ray.Origin, ray.Direction
end

local function dustAtMouse()
	local origin, dir = aimRay()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character :: Instance }
	local hit = workspace:Raycast(origin, dir * 60, params)
	if not hit then
		return
	end
	busy = true
	local ok, res = pcall(function()
		return dust:InvokeServer(hit.Instance)
	end)
	busy = false
	if ok and res then
		showDust(res)
	end
end

local function shoot()
	busy = true
	local cam = workspace.CurrentCamera
	local cf = cam.CFrame
	finder.Visible = false
	hint.Visible = false
	task.wait()
	local imageId: string? = nil
	pcall(function()
		local CaptureService = game:GetService("CaptureService")
		CaptureService:CaptureScreenshot(function(id: string)
			imageId = id
		end)
	end)
	task.wait(0.05)
	finder.Visible = tool == "camera"
	hint.Visible = tool ~= nil
	flash.BackgroundTransparency = 0.2
	TweenService:Create(flash, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
	local ok, res = pcall(function()
		return takePhoto:InvokeServer(cf)
	end)
	busy = false
	if not ok or not res then
		return
	end
	local n = res.n
	previewText.Text = tostring(res.text)
	previewImage.Image = ""
	preview.Visible = true
	-- The screenshot arrives on its own schedule; attach it when it does.
	task.spawn(function()
		local t0 = os.clock()
		while not imageId and os.clock() - t0 < 3 do
			task.wait(0.1)
		end
		if imageId then
			previewImage.Image = imageId
			if n then
				local v = Instance.new("StringValue")
				v.Name = tostring(n)
				v.Value = imageId
				v.Parent = images
			end
		end
	end)
	local shown = previewText.Text
	task.delay(3.5, function()
		if previewText.Text == shown then
			preview.Visible = false
		end
	end)
end

kitButton.MouseButton1Click:Connect(function()
	setActive(if tool == "prints" then nil else "prints")
end)
camButton.MouseButton1Click:Connect(function()
	setActive(if tool == "camera" then nil else "camera")
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.G then
		setActive(if tool == "prints" then nil else "prints")
	elseif input.KeyCode == Enum.KeyCode.C then
		setActive(if tool == "camera" then nil else "camera")
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 and tool and not busy then
		if tool == "prints" then
			dustAtMouse()
		else
			shoot()
		end
	end
end)

-- Respawning drops the tool.
player.CharacterAdded:Connect(function()
	if tool then
		setActive(nil)
	end
end)
