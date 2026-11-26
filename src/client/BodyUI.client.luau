--!strict
-- Close-up of the body. A copy of the real body sits in a viewport you can turn and zoom. Pick a tool
-- (gloved hands, thermometer, flashlight) and click where you want to use it. The server answers each
-- action; this script only draws the panel and works out which part of the body you clicked.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("CaseRemotes")
local openBody = remotes:WaitForChild("OpenBody") :: RemoteEvent
local bodyAction = remotes:WaitForChild("BodyAction") :: RemoteFunction

local INK = Color3.fromRGB(232, 230, 240)
local QUIET = Color3.fromRGB(160, 156, 175)
local PANEL = Color3.fromRGB(14, 13, 20)
local CARD = Color3.fromRGB(26, 24, 34)
local ACCENT = Color3.fromRGB(255, 70, 160)
local CYAN = Color3.fromRGB(0, 210, 255)
local GREEN = Color3.fromRGB(120, 230, 150)

local TOOLS = {
	{ id = "hands", label = "GLOVED HANDS", key = Enum.KeyCode.One, about = "Go through pockets. Feel how stiff the body is." },
	{ id = "thermometer", label = "THERMOMETER", key = Enum.KeyCode.Two, about = "Probe thermometer. Take the core temperature." },
	{ id = "flashlight", label = "FLASHLIGHT", key = Enum.KeyCode.Three, about = "Look closely at whatever you shine it on." },
}

local REGION_NAME: { [string]: string } = {
	head = "Head",
	torso = "Torso",
	hands = "Hands",
	arms = "Arms",
	legs = "Legs",
	feet = "Feet",
}

local POCKET_NAME: { [string]: string } = {
	coatL = "Left jacket pocket",
	coatR = "Right jacket pocket",
	pantsL = "Left trouser pocket",
	pantsR = "Right trouser pocket",
}

-- GUI -------------------------------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "BodyUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 5 -- over the clock and board; results show in the panel itself
gui.Parent = player:WaitForChild("PlayerGui")

local function corner(parent: Instance, r: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 8)
	c.Parent = parent
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
	t.TextYAlignment = Enum.TextYAlignment.Top
	t.Size = UDim2.new(1, 0, 0, 0)
	t.AutomaticSize = Enum.AutomaticSize.Y
	t.Parent = parent
	return t
end

local function button(parent: Instance, str: string, color: Color3): TextButton
	local b = Instance.new("TextButton")
	b.AutoButtonColor = true
	b.BackgroundColor3 = CARD
	b.Text = str
	b.TextColor3 = color
	b.TextSize = 14
	b.Font = Enum.Font.GothamBold
	b.Size = UDim2.new(1, 0, 0, 36)
	b.Parent = parent
	corner(b, 6)
	return b
end

local root = Instance.new("Frame")
root.Name = "BodyPanel"
root.Size = UDim2.fromScale(1, 1)
root.BackgroundColor3 = Color3.fromRGB(5, 5, 9)
root.BackgroundTransparency = 0.08
root.Visible = false
root.Active = true
root.Parent = gui

local title = label(root, "", 22, INK, Enum.Font.GothamBold)
title.Position = UDim2.fromOffset(24, 18)
title.Size = UDim2.new(1, -400, 0, 0)
local sub = label(root, "Pick a tool on the right, then click on the body. Drag to look around, scroll to zoom.", 13, QUIET)
sub.Position = UDim2.fromOffset(24, 48)
sub.Size = UDim2.new(1, -400, 0, 0)

local vf = Instance.new("ViewportFrame")
vf.Name = "View"
vf.Position = UDim2.fromOffset(20, 76)
vf.Size = UDim2.new(1, -380, 1, -96)
vf.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
vf.Active = true
vf.Parent = root
corner(vf, 10)
local world = Instance.new("WorldModel")
world.Parent = vf
local cam = Instance.new("Camera")
cam.FieldOfView = 40
cam.Parent = vf
vf.CurrentCamera = cam

local hover = Instance.new("TextLabel")
hover.BackgroundColor3 = PANEL
hover.BackgroundTransparency = 0.15
hover.TextColor3 = INK
hover.TextSize = 13
hover.Font = Enum.Font.GothamMedium
hover.AutomaticSize = Enum.AutomaticSize.X
hover.Size = UDim2.fromOffset(0, 24)
hover.Visible = false
hover.ZIndex = 5
hover.Parent = root
corner(hover, 4)
local hoverPad = Instance.new("UIPadding")
hoverPad.PaddingLeft = UDim.new(0, 8)
hoverPad.PaddingRight = UDim.new(0, 8)
hoverPad.Parent = hover

local spot = Instance.new("Frame")
spot.Size = UDim2.fromOffset(110, 110)
spot.AnchorPoint = Vector2.new(0.5, 0.5)
spot.BackgroundColor3 = Color3.fromRGB(255, 248, 220)
spot.BackgroundTransparency = 0.9
spot.Visible = false
spot.ZIndex = 4
spot.Parent = root
corner(spot, 55)

local side = Instance.new("Frame")
side.Position = UDim2.new(1, -344, 0, 20)
side.Size = UDim2.new(0, 324, 1, -40)
side.BackgroundColor3 = PANEL
side.Parent = root
corner(side, 10)
local sidePad = Instance.new("UIPadding")
for _, k in { "PaddingLeft", "PaddingRight", "PaddingTop", "PaddingBottom" } do
	(sidePad :: any)[k] = UDim.new(0, 14)
end
sidePad.Parent = side
local sideList = Instance.new("UIListLayout")
sideList.Padding = UDim.new(0, 8)
sideList.SortOrder = Enum.SortOrder.LayoutOrder
sideList.Parent = side

local toolsTitle = label(side, "TOOLS", 13, ACCENT, Enum.Font.GothamBold)
toolsTitle.LayoutOrder = 1
local toolButtons: { [string]: TextButton } = {}
for i, t in TOOLS do
	local b = button(side, ("%s   [%d]"):format(t.label, i), INK)
	b.LayoutOrder = 1 + i
	toolButtons[t.id] = b
end
local toolAbout = label(side, "", 12, QUIET)
toolAbout.LayoutOrder = 10
local rollButton = button(side, "ROLL THE BODY OVER", CYAN)
rollButton.LayoutOrder = 11
local closeButton = button(side, "CLOSE   [Q]", QUIET)
closeButton.LayoutOrder = 12
local notesTitle = label(side, "WHAT YOU FOUND", 13, ACCENT, Enum.Font.GothamBold)
notesTitle.LayoutOrder = 13

local log = Instance.new("ScrollingFrame")
log.LayoutOrder = 14
log.Size = UDim2.new(1, 0, 1, -330)
log.BackgroundTransparency = 1
log.BorderSizePixel = 0
log.ScrollBarThickness = 4
log.CanvasSize = UDim2.new()
log.AutomaticCanvasSize = Enum.AutomaticSize.Y
log.Parent = side
local logList = Instance.new("UIListLayout")
logList.Padding = UDim.new(0, 8)
logList.SortOrder = Enum.SortOrder.LayoutOrder
logList.Parent = log

-- State -----------------------------------------------------------------------------------------------

local isOpen = false
local tool = "hands"
local source: Instance? = nil -- the real body in the world
local copy: Instance? = nil -- its copy in the viewport
local centre = Vector3.zero
local yaw, pitch, dist = 0.6, 1.0, 9
local logOrder = 0
local busy = false
local savedWalk, savedJump = 16, 50

local function addLog(str: string, color: Color3?): TextLabel
	logOrder += 1
	local t = label(log, str, 13, color or INK)
	t.LayoutOrder = logOrder
	task.defer(function()
		log.CanvasPosition = Vector2.new(0, math.max(0, log.AbsoluteCanvasSize.Y - log.AbsoluteSize.Y))
	end)
	return t
end

local function setTool(id: string)
	tool = id
	for tid, b in toolButtons do
		b.BackgroundColor3 = if tid == id then Color3.fromRGB(70, 20, 50) else CARD
		b.TextColor3 = if tid == id then ACCENT else INK
	end
	for _, t in TOOLS do
		if t.id == id then
			toolAbout.Text = t.about
		end
	end
end

local function call(action: string, a: any?, b: any?): any
	if busy then
		return nil
	end
	busy = true
	local ok, res = pcall(function()
		return bodyAction:InvokeServer(action, a, b)
	end)
	busy = false
	if not ok or typeof(res) ~= "table" then
		addLog("(No answer. Try again.)", QUIET)
		return nil
	end
	return res
end

local close: () -> ()

local function show(res: any)
	if not res then
		return
	end
	addLog(tostring(res.text))
	if res.fact then
		addLog("Added to your notebook.", GREEN)
	end
	if res.close then
		close()
	end
end

local function showPocket(res: any)
	if not res then
		return
	end
	addLog(tostring(res.text), QUIET)
	if typeof(res.items) ~= "table" then
		return
	end
	for _, it in res.items do
		logOrder += 1
		local b = button(log, "Take out: " .. tostring(it.label), CYAN)
		b.Size = UDim2.new(1, -6, 0, 30)
		b.TextSize = 13
		b.LayoutOrder = logOrder
		b.MouseButton1Click:Connect(function()
			local r = call("take", res.slot, it.id)
			if r then
				b:Destroy()
				addLog(tostring(it.label) .. ":", QUIET)
				show(r)
			end
		end)
	end
end

-- Viewport --------------------------------------------------------------------------------------------

local function stripCopy(m: Instance)
	for _, d in m:GetDescendants() do
		if d:IsA("ClickDetector") or d:IsA("ProximityPrompt") or d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
		end
	end
end

local function updateCamera()
	cam.CFrame = CFrame.new(centre) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(-pitch, 0, 0) * CFrame.new(0, 0, dist)
	if tool == "flashlight" then
		vf.Ambient = Color3.fromRGB(105, 104, 112)
		vf.LightColor = Color3.fromRGB(255, 248, 232)
		vf.LightDirection = cam.CFrame.LookVector
	else
		vf.Ambient = Color3.fromRGB(48, 48, 58)
		vf.LightColor = Color3.fromRGB(105, 100, 118)
		vf.LightDirection = Vector3.new(-0.4, -1, -0.3)
	end
end

local function build(): boolean
	world:ClearAllChildren()
	local scene = workspace:FindFirstChild("CaseScene")
	local body = scene and scene:FindFirstChild("Body")
	if not body then
		return false
	end
	local wasArchivable = body.Archivable
	body.Archivable = true
	local c = body:Clone()
	body.Archivable = wasArchivable
	if not c then
		return false
	end
	stripCopy(c)
	local stain = scene:FindFirstChild("Stain") :: BasePart?
	local pivot = if body:IsA("Model") then body:GetPivot() elseif body:IsA("BasePart") then body.CFrame else CFrame.new()
	local floorY = if stain then stain.Position.Y - 0.1 else pivot.Y - 0.9
	local shift = Vector3.new(pivot.X, floorY, pivot.Z)
	if c:IsA("Model") then
		c:PivotTo(pivot - shift)
	elseif c:IsA("BasePart") then
		c.CFrame = pivot - shift
	end
	c.Parent = world
	if stain then
		local s = stain:Clone()
		s.CFrame = stain.CFrame - shift
		s.Reflectance = 0
		s.Parent = world
	end
	local floor = Instance.new("Part")
	floor.Anchored = true
	floor.Size = Vector3.new(16, 0.2, 16)
	floor.CFrame = CFrame.new(0, -0.1, 0)
	floor.Color = Color3.fromRGB(46, 40, 36)
	floor.Material = Enum.Material.WoodPlanks
	floor.CanQuery = false
	floor.Parent = world
	source, copy = body, c
	centre = if c:IsA("Model") then (c:GetBoundingBox()).Position else (c :: BasePart).Position
	return true
end

local function roll()
	local c = copy
	if not c or not c:IsA("Model") then
		return
	end
	-- Turn over about the spine.
	c:PivotTo(c:GetPivot() * CFrame.Angles(0, math.pi, 0))
	addLog("You roll the body over.", QUIET)
end

-- Which part of the body is under the cursor, and which pocket if it's over one.
local function pick(screen: Vector2): (string?, string?, BasePart?)
	local c = copy
	if not c then
		return nil, nil, nil
	end
	-- Mouse positions include the top bar inset; AbsolutePosition does not.
	local rel = screen - GuiService:GetGuiInset() - vf.AbsolutePosition
	local size = vf.AbsoluteSize
	if rel.X < 0 or rel.Y < 0 or rel.X > size.X or rel.Y > size.Y then
		return nil, nil, nil
	end
	local nx, ny = rel.X / size.X * 2 - 1, 1 - rel.Y / size.Y * 2
	local tanY = math.tan(math.rad(cam.FieldOfView) / 2)
	local dir = cam.CFrame:VectorToWorldSpace(Vector3.new(nx * tanY * size.X / size.Y, ny * tanY, -1)).Unit
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { c }
	local hit = world:Raycast(cam.CFrame.Position, dir * 80, params)
	if not hit then
		return nil, nil, nil
	end
	local p = hit.Instance :: BasePart
	local n = p.Name
	if n == "Wound" then
		return "wound", nil, p
	end
	if p.Parent and p.Parent:IsA("Accessory") then
		return "head", nil, p
	end
	local local_ = p.CFrame:PointToObjectSpace(hit.Position)
	local lr = if local_.X < 0 then "L" else "R"
	if n == "Head" then
		return "head", nil, p
	elseif n == "UpperTorso" or n == "Torso" or n == "Body" then
		return "torso", "coat" .. lr, p
	elseif n == "LowerTorso" then
		return "torso", "pants" .. lr, p
	elseif n:find("UpperLeg") then
		return "legs", "pants" .. (if n:find("Left") then "L" else "R"), p
	elseif n:find("Foot") then
		return "feet", nil, p
	elseif n:find("Leg") then
		return "legs", nil, p
	elseif n:find("Hand") or n:find("LowerArm") then
		return "hands", nil, p
	elseif n:find("Arm") then
		return "arms", nil, p
	end
	return "torso", nil, p
end

local function hoverText(region: string, slot: string?): string
	if region == "wound" then
		return if tool == "flashlight" then "A wound" else "Something dark"
	end
	if tool == "hands" and slot then
		return POCKET_NAME[slot]
	end
	return REGION_NAME[region] or region
end

local function use(region: string, slot: string?, p: BasePart?)
	if tool == "hands" then
		if slot then
			showPocket(call("pocket", slot))
		else
			show(call("touch"))
		end
	elseif tool == "thermometer" then
		-- The stab wound sits on the torso; the head wound does not.
		local core = region == "torso" or (region == "wound" and p ~= nil and p.Shape ~= Enum.PartType.Ball)
		if core then
			show(call("temp"))
		else
			addLog("That won't give a core reading. Try the torso.", QUIET)
		end
	elseif tool == "flashlight" then
		if region == "wound" then
			show(call("wound"))
		else
			show(call("look", region))
		end
	end
end

-- Open / close ----------------------------------------------------------------------------------------

close = function()
	if not isOpen then
		return
	end
	isOpen = false
	root.Visible = false
	hover.Visible = false
	spot.Visible = false
	world:ClearAllChildren()
	copy, source = nil, nil
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.WalkSpeed = savedWalk
		hum.JumpPower = savedJump
	end
end

openBody.OnClientEvent:Connect(function(data: any)
	if isOpen then
		return
	end
	if not build() then
		return
	end
	isOpen = true
	title.Text = "Close-up: " .. tostring(data and data.name or "the body")
	for _, ch in log:GetChildren() do
		if ch:IsA("GuiObject") then
			ch:Destroy()
		end
	end
	addLog("You crouch beside the body and pull on gloves.", QUIET)
	yaw, pitch, dist = 0.6, 1.0, 9
	setTool(tool)
	root.Visible = true
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then
		savedWalk, savedJump = hum.WalkSpeed, hum.JumpPower
		hum.WalkSpeed = 0
		hum.JumpPower = 0
	end
end)

for id, b in toolButtons do
	b.MouseButton1Click:Connect(function()
		setTool(id)
	end)
end
rollButton.MouseButton1Click:Connect(roll)
closeButton.MouseButton1Click:Connect(function()
	close()
end)

-- Input -----------------------------------------------------------------------------------------------

local pressAt: Vector2? = nil
local dragged = false

vf.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		pressAt = Vector2.new(input.Position.X, input.Position.Y)
		dragged = false
	end
end)

vf.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseWheel then
		dist = math.clamp(dist - input.Position.Z * 0.8, 2.5, 14)
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if not isOpen or not pressAt then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
		if not dragged and (Vector2.new(input.Position.X, input.Position.Y) - (pressAt :: Vector2)).Magnitude > 5 then
			dragged = true
		end
		if dragged then
			yaw -= input.Delta.X * 0.01
			pitch = math.clamp(pitch + input.Delta.Y * 0.01, 0.25, 1.5)
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	local at = pressAt
	pressAt = nil
	if not isOpen or not at or dragged then
		return
	end
	local region, slot, p = pick(UserInputService:GetMouseLocation())
	if region then
		use(region, slot, p)
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if not isOpen or processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.Q then
		close()
		return
	end
	for _, t in TOOLS do
		if input.KeyCode == t.key then
			setTool(t.id)
		end
	end
end)

local lastCheck = 0
RunService.RenderStepped:Connect(function()
	if not isOpen then
		return
	end
	updateCamera()
	local m = UserInputService:GetMouseLocation()
	local region, slot = pick(m)
	if region and not dragged then
		hover.Text = hoverText(region, slot)
		hover.Position = UDim2.fromOffset(m.X + 16, m.Y + 12)
		hover.Visible = true
	else
		hover.Visible = false
	end
	local r = m - GuiService:GetGuiInset() - vf.AbsolutePosition
	local inView = r.X >= 0 and r.Y >= 0 and r.X <= vf.AbsoluteSize.X and r.Y <= vf.AbsoluteSize.Y
	spot.Visible = tool == "flashlight" and inView
	spot.Position = UDim2.fromOffset(m.X, m.Y)
	-- Walk away (or get moved) and the close-up ends.
	if os.clock() - lastCheck > 0.5 then
		lastCheck = os.clock()
		local char = player.Character
		local src = source
		if not char or not src or not src.Parent then
			close()
		elseif src:IsA("Model") and (char:GetPivot().Position - src:GetPivot().Position).Magnitude > 16 then
			close()
		end
	end
end)
