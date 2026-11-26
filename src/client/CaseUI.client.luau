--!strict
-- Case board (B or the button), interview panel, accusation panel and notification toasts.
-- All case data comes from the server; this script only draws it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("CaseRemotes")
local boardEvent = remotes:WaitForChild("Board") :: RemoteEvent
local notifyEvent = remotes:WaitForChild("Notify") :: RemoteEvent
local openInterview = remotes:WaitForChild("OpenInterview") :: RemoteEvent
local openAccuse = remotes:WaitForChild("OpenAccuse") :: RemoteEvent
local getBoard = remotes:WaitForChild("GetBoard") :: RemoteFunction
local ask = remotes:WaitForChild("Ask") :: RemoteFunction
local accuse = remotes:WaitForChild("Accuse") :: RemoteFunction

local INK = Color3.fromRGB(232, 230, 240)
local QUIET = Color3.fromRGB(160, 156, 175)
local PANEL = Color3.fromRGB(14, 13, 20)
local CARD = Color3.fromRGB(26, 24, 34)
local ACCENT = Color3.fromRGB(255, 70, 160)
local CYAN = Color3.fromRGB(0, 210, 255)

local gui = Instance.new("ScreenGui")
gui.Name = "CaseUI"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

local function corner(parent: Instance, r: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 6)
	c.Parent = parent
end

local function stroke(parent: Instance, color: Color3, transparency: number?)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Transparency = transparency or 0.5
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
end

local function pad(parent: Instance, px: number)
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, px)
	p.PaddingBottom = UDim.new(0, px)
	p.PaddingLeft = UDim.new(0, px)
	p.PaddingRight = UDim.new(0, px)
	p.Parent = parent
end

local function list(parent: Instance, gap: number)
	local l = Instance.new("UIListLayout")
	l.Padding = UDim.new(0, gap)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = parent
	return l
end

local function text(parent: Instance, str: string, size: number, color: Color3, font: Enum.Font?, order: number?): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.new(1, 0, 0, 0)
	t.AutomaticSize = Enum.AutomaticSize.Y
	t.TextWrapped = true
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextYAlignment = Enum.TextYAlignment.Top
	t.Font = font or Enum.Font.Gotham
	t.TextSize = size
	t.TextColor3 = color
	t.Text = str
	t.LayoutOrder = order or 0
	t.Parent = parent
	return t
end

local function button(parent: Instance, str: string, order: number?, accent: Color3?): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, -10, 0, 0)
	b.AutomaticSize = Enum.AutomaticSize.Y
	b.BackgroundColor3 = CARD
	b.AutoButtonColor = true
	b.Font = Enum.Font.GothamMedium
	b.TextSize = 15
	b.TextColor3 = INK
	b.TextWrapped = true
	b.TextXAlignment = Enum.TextXAlignment.Left
	b.Text = str
	b.LayoutOrder = order or 0
	b.Parent = parent
	corner(b)
	stroke(b, accent or CYAN, 0.6)
	pad(b, 10)
	return b
end

local function scroller(parent: Instance): ScrollingFrame
	local s = Instance.new("ScrollingFrame")
	s.BackgroundTransparency = 1
	s.BorderSizePixel = 0
	s.ScrollBarThickness = 4
	s.ScrollBarImageColor3 = ACCENT
	s.AutomaticCanvasSize = Enum.AutomaticSize.Y
	s.CanvasSize = UDim2.new()
	s.Parent = parent
	return s
end

---------------------------------------------------------------- Toasts
local toastHolder = Instance.new("Frame")
toastHolder.BackgroundTransparency = 1
toastHolder.AnchorPoint = Vector2.new(0.5, 0)
toastHolder.Position = UDim2.new(0.5, 0, 0, 64)
toastHolder.Size = UDim2.new(0, 460, 0, 0)
toastHolder.AutomaticSize = Enum.AutomaticSize.Y
toastHolder.ZIndex = 50
toastHolder.Parent = gui
list(toastHolder, 6)

local function toast(msg: string)
	local f = Instance.new("Frame")
	f.BackgroundColor3 = PANEL
	f.BackgroundTransparency = 0.1
	f.Size = UDim2.new(1, 0, 0, 0)
	f.AutomaticSize = Enum.AutomaticSize.Y
	f.Parent = toastHolder
	corner(f)
	stroke(f, ACCENT, 0.3)
	pad(f, 10)
	local t = text(f, msg, 15, INK, Enum.Font.GothamMedium)
	t.TextXAlignment = Enum.TextXAlignment.Center
	task.delay(6, function()
		local info = TweenInfo.new(0.6)
		TweenService:Create(f, info, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(t, info, { TextTransparency = 1 }):Play()
		task.wait(0.7)
		f:Destroy()
	end)
end
notifyEvent.OnClientEvent:Connect(toast)

---------------------------------------------------------------- Case board
-- The player's own board: a cork canvas you pan and zoom, sticky notes you drag, strings you tie between
-- them, notes you write yourself, and a notebook of everything you've learned that isn't pinned yet.
local boardAction = remotes:WaitForChild("BoardAction") :: RemoteFunction

local NOTE_W = 200
local CORK = Color3.fromRGB(62, 47, 36)
local STRING = Color3.fromRGB(205, 38, 52)
local NOTE_INK = Color3.fromRGB(34, 30, 28)
local KIND_COLOUR: { [string]: Color3 } = {
	evidence = Color3.fromRGB(246, 214, 120),
	person = Color3.fromRGB(240, 168, 196),
	place = Color3.fromRGB(156, 202, 238),
	fact = Color3.fromRGB(176, 224, 162),
	custom = Color3.fromRGB(236, 232, 224),
}
local KIND_LABEL: { [string]: string } = {
	evidence = "EVIDENCE",
	person = "PERSON",
	place = "PLACE",
	fact = "FACT",
	custom = "NOTE",
}

local function clear(frame: Instance)
	for _, c in frame:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

local boardButton = Instance.new("TextButton")
boardButton.Position = UDim2.fromOffset(16, 58)
boardButton.Size = UDim2.fromOffset(190, 32)
boardButton.BackgroundColor3 = PANEL
boardButton.BackgroundTransparency = 0.2
boardButton.Font = Enum.Font.GothamBold
boardButton.TextSize = 14
boardButton.TextColor3 = INK
boardButton.Text = "CASE BOARD  [B]"
boardButton.Parent = gui
corner(boardButton)
stroke(boardButton, CYAN, 0.4)

local board = Instance.new("Frame")
board.AnchorPoint = Vector2.new(0.5, 0.5)
board.Position = UDim2.fromScale(0.5, 0.5)
board.Size = UDim2.new(1, -40, 1, -40)
board.BackgroundColor3 = PANEL
board.Visible = false
board.ZIndex = 5
board.Parent = gui
corner(board, 10)
stroke(board, ACCENT, 0.35)

-- Top bar
local topBar = Instance.new("Frame")
topBar.BackgroundTransparency = 1
topBar.Size = UDim2.new(1, -24, 0, 58)
topBar.Position = UDim2.fromOffset(12, 6)
topBar.Parent = board
local titleLabel = text(topBar, "No active case", 20, INK, Enum.Font.GothamBold)
titleLabel.Size = UDim2.new(1, -330, 0, 24)
titleLabel.AutomaticSize = Enum.AutomaticSize.None
titleLabel.Position = UDim2.fromOffset(0, 6)
local objectiveLabel = text(topBar, "", 13, QUIET, Enum.Font.Gotham)
objectiveLabel.Size = UDim2.new(1, -330, 0, 18)
objectiveLabel.AutomaticSize = Enum.AutomaticSize.None
objectiveLabel.Position = UDim2.fromOffset(0, 32)
objectiveLabel.TextTruncate = Enum.TextTruncate.AtEnd

local function barButton(str: string, xFromRight: number, w: number, accent: Color3): TextButton
	local b = Instance.new("TextButton")
	b.AnchorPoint = Vector2.new(1, 0)
	b.Position = UDim2.new(1, -xFromRight, 0, 12)
	b.Size = UDim2.fromOffset(w, 34)
	b.BackgroundColor3 = CARD
	b.Font = Enum.Font.GothamBold
	b.TextSize = 13
	b.TextColor3 = INK
	b.Text = str
	b.Parent = topBar
	corner(b)
	stroke(b, accent, 0.4)
	return b
end
local closeButton = barButton("CLOSE  [B]", 0, 110, QUIET)
local newNoteButton = barButton("+ WRITE NOTE", 120, 130, CYAN)
local centreButton = barButton("RECENTRE", 260, 100, QUIET)

-- Notebook drawer: everything learned that isn't on the board
local drawer = Instance.new("Frame")
drawer.BackgroundColor3 = Color3.fromRGB(20, 19, 27)
drawer.Position = UDim2.fromOffset(12, 70)
drawer.Size = UDim2.new(0, 250, 1, -82)
drawer.Parent = board
corner(drawer, 8)
pad(drawer, 10)
local drawerTitle = text(drawer, "NOTEBOOK", 13, ACCENT, Enum.Font.GothamBold)
drawerTitle.Size = UDim2.new(1, 0, 0, 16)
drawerTitle.AutomaticSize = Enum.AutomaticSize.None
local drawerHint = text(drawer, "Things you've learned that aren't on the board. Click one to pin it.", 12, QUIET)
drawerHint.Position = UDim2.fromOffset(0, 20)
local drawerList = scroller(drawer)
drawerList.Position = UDim2.fromOffset(0, 58)
drawerList.Size = UDim2.new(1, 0, 1, -58)
list(drawerList, 6)

-- Cork viewport
local viewport = Instance.new("Frame")
viewport.BackgroundColor3 = Color3.fromRGB(40, 31, 25)
viewport.Position = UDim2.fromOffset(272, 70)
viewport.Size = UDim2.new(1, -284, 1, -82)
viewport.ClipsDescendants = true
viewport.Parent = board
corner(viewport, 8)

local canvas = Instance.new("Frame")
canvas.BackgroundColor3 = CORK
canvas.BorderSizePixel = 0
canvas.Size = UDim2.fromOffset(2400, 1600)
canvas.Parent = viewport
local canvasScale = Instance.new("UIScale")
canvasScale.Parent = canvas
-- Faint cork grain
for i = 1, 40 do
	local g = Instance.new("Frame")
	g.BorderSizePixel = 0
	g.BackgroundColor3 = if i % 2 == 0 then Color3.fromRGB(74, 56, 42) else Color3.fromRGB(54, 40, 31)
	g.BackgroundTransparency = 0.55
	g.Position = UDim2.fromOffset(((i * 977) % 2300), ((i * 613) % 1550))
	g.Size = UDim2.fromOffset(60 + (i * 37) % 140, 3 + i % 4)
	g.Parent = canvas
end
local linesLayer = Instance.new("Frame")
linesLayer.BackgroundTransparency = 1
linesLayer.Size = UDim2.fromScale(1, 1)
linesLayer.ZIndex = 2
linesLayer.Parent = canvas
local notesLayer = Instance.new("Frame")
notesLayer.BackgroundTransparency = 1
notesLayer.Size = UDim2.fromScale(1, 1)
notesLayer.ZIndex = 3
notesLayer.Parent = canvas

local hint = Instance.new("TextLabel")
hint.AnchorPoint = Vector2.new(0.5, 1)
hint.Position = UDim2.new(0.5, 0, 1, -10)
hint.Size = UDim2.fromOffset(560, 30)
hint.BackgroundColor3 = PANEL
hint.BackgroundTransparency = 0.15
hint.Font = Enum.Font.GothamMedium
hint.TextSize = 13
hint.TextColor3 = INK
hint.ZIndex = 20
hint.Text = "Drag notes to arrange them. Drag the cork to pan, scroll to zoom. STRING ties two notes together."
hint.Parent = viewport
corner(hint)

-- Write-a-note dialog
local writer = Instance.new("Frame")
writer.AnchorPoint = Vector2.new(0.5, 0.5)
writer.Position = UDim2.fromScale(0.5, 0.5)
writer.Size = UDim2.fromOffset(360, 200)
writer.BackgroundColor3 = KIND_COLOUR.custom
writer.Visible = false
writer.ZIndex = 30
writer.Parent = board
corner(writer, 4)
pad(writer, 12)
local writerBox = Instance.new("TextBox")
writerBox.Size = UDim2.new(1, 0, 1, -44)
writerBox.BackgroundTransparency = 1
writerBox.ClearTextOnFocus = false
writerBox.MultiLine = true
writerBox.TextWrapped = true
writerBox.TextXAlignment = Enum.TextXAlignment.Left
writerBox.TextYAlignment = Enum.TextYAlignment.Top
writerBox.Font = Enum.Font.Gotham
writerBox.TextSize = 15
writerBox.TextColor3 = NOTE_INK
writerBox.PlaceholderText = "Write a note: a theory, a question, a lead to follow..."
writerBox.PlaceholderColor3 = Color3.fromRGB(120, 112, 100)
writerBox.Text = ""
writerBox.ZIndex = 31
writerBox.Parent = writer
local function writerButton(str: string, x: number): TextButton
	local b = Instance.new("TextButton")
	b.AnchorPoint = Vector2.new(1, 1)
	b.Position = UDim2.new(1, -x, 1, 0)
	b.Size = UDim2.fromOffset(100, 32)
	b.BackgroundColor3 = NOTE_INK
	b.Font = Enum.Font.GothamBold
	b.TextSize = 13
	b.TextColor3 = INK
	b.Text = str
	b.ZIndex = 31
	b.Parent = writer
	corner(b)
	return b
end
local writerPin = writerButton("PIN IT", 0)
local writerCancel = writerButton("CANCEL", 110)

---------------------------------------------------------------- Board state and rendering
local currentBoard: any = nil
local pan = Vector2.new(0, 0)
local noteFrames: { [string]: TextButton } = {}
local noteSig: { [string]: string } = {}
local notePos: { [string]: Vector2 } = {}
local draggingId: string? = nil
local linkFrom: string? = nil

local function setHint(str: string?)
	hint.Text = str or "Drag notes to arrange them. Drag the cork to pan, scroll to zoom. STRING ties two notes together."
end

local function applyPan()
	local vs = viewport.AbsoluteSize
	local s = canvasScale.Scale
	local w, h = 2400 * s, 1600 * s
	-- Keep at least part of the board on screen
	pan = Vector2.new(math.clamp(pan.X, math.min(0, vs.X - w), 0), math.clamp(pan.Y, math.min(0, vs.Y - h), 0))
	canvas.Position = UDim2.fromOffset(pan.X, pan.Y)
end

-- Canvas coordinates at the middle of what you're looking at.
local function viewCentre(): Vector2
	local vs = viewport.AbsoluteSize
	return (Vector2.new(vs.X / 2, vs.Y / 2) - pan) / canvasScale.Scale
end

local function act(action: string, args: any)
	task.spawn(function()
		local ok, res = pcall(function()
			return boardAction:InvokeServer(action, args)
		end)
		if ok and res and not res.ok and res.err then
			setHint("Couldn't do that: " .. res.err)
			task.delay(3, function()
				setHint(nil)
			end)
		end
	end)
end

local function drawLines()
	clear(linesLayer)
	if not currentBoard then
		return
	end
	for _, l in currentBoard.links do
		local a, b = notePos[l.a], notePos[l.b]
		if a and b then
			local pa = a + Vector2.new(NOTE_W / 2, 8)
			local pb = b + Vector2.new(NOTE_W / 2, 8)
			local d = pb - pa
			local line = Instance.new("Frame")
			line.AnchorPoint = Vector2.new(0.5, 0.5)
			line.BorderSizePixel = 0
			line.BackgroundColor3 = STRING
			line.Position = UDim2.fromOffset((pa.X + pb.X) / 2, (pa.Y + pb.Y) / 2)
			line.Size = UDim2.fromOffset(d.Magnitude, 3)
			line.Rotation = math.deg(math.atan2(d.Y, d.X))
			line.ZIndex = 3
			line.Parent = linesLayer
		end
	end
end

local function highlight()
	for id, f in noteFrames do
		local s = f:FindFirstChild("LinkStroke") :: UIStroke?
		if s then
			s.Enabled = (id == linkFrom)
		end
	end
end

local function overButton(f: GuiObject, pos: Vector2): boolean
	for _, c in f:GetDescendants() do
		if c:IsA("TextButton") then
			local p, s = c.AbsolutePosition, c.AbsoluteSize
			if pos.X >= p.X and pos.X <= p.X + s.X and pos.Y >= p.Y and pos.Y <= p.Y + s.Y then
				return true
			end
		end
	end
	return false
end

local function onNoteClicked(id: string)
	if linkFrom and linkFrom ~= id then
		act("link", { a = linkFrom, b = id })
		linkFrom = nil
		highlight()
		setHint(nil)
	end
end

local function buildNote(note: any, item: any): TextButton
	local kind = if item then item.kind else "custom"
	local f = Instance.new("TextButton")
	f.Name = note.id
	f.Text = ""
	f.AutoButtonColor = false
	f.BackgroundColor3 = KIND_COLOUR[kind] or KIND_COLOUR.custom
	f.Size = UDim2.fromOffset(NOTE_W, 0)
	f.AutomaticSize = Enum.AutomaticSize.Y
	f.ZIndex = 4
	-- A slight, stable tilt so it reads as paper on cork
	local h = 0
	for i = 1, #note.id do
		h += string.byte(note.id, i) * i
	end
	f.Rotation = ((h % 7) - 3) * 0.5
	local shadow = Instance.new("UIStroke")
	shadow.Color = Color3.new(0, 0, 0)
	shadow.Transparency = 0.6
	shadow.Thickness = 1.5
	shadow.Parent = f
	local linkStroke = Instance.new("UIStroke")
	linkStroke.Name = "LinkStroke"
	linkStroke.Color = STRING
	linkStroke.Thickness = 3
	linkStroke.Enabled = false
	linkStroke.Parent = f
	-- Content flows in its own frame so the pin can sit on top, outside the list.
	local content = Instance.new("Frame")
	content.BackgroundTransparency = 1
	content.Size = UDim2.new(1, 0, 0, 0)
	content.AutomaticSize = Enum.AutomaticSize.Y
	content.ZIndex = 5
	content.Parent = f
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, 14)
	p.PaddingBottom = UDim.new(0, 10)
	p.PaddingLeft = UDim.new(0, 10)
	p.PaddingRight = UDim.new(0, 10)
	p.Parent = content
	list(content, 3)

	local pin = Instance.new("Frame")
	pin.AnchorPoint = Vector2.new(0.5, 0.5)
	pin.Position = UDim2.new(0.5, 0, 0, -6)
	pin.Size = UDim2.fromOffset(12, 12)
	pin.BackgroundColor3 = Color3.fromRGB(190, 30, 40)
	pin.ZIndex = 6
	pin.Parent = f
	local pc = Instance.new("UICorner")
	pc.CornerRadius = UDim.new(1, 0)
	pc.Parent = pin

	local headerRow = Instance.new("Frame")
	headerRow.BackgroundTransparency = 1
	headerRow.Size = UDim2.new(1, 0, 0, 18)
	headerRow.LayoutOrder = 1
	headerRow.ZIndex = 5
	headerRow.Parent = content
	local kindLabel = text(headerRow, KIND_LABEL[kind] or "NOTE", 10, Color3.fromRGB(90, 70, 60), Enum.Font.GothamBold)
	kindLabel.ZIndex = 5
	local function smallButton(str: string, x: number, w: number): TextButton
		local b = Instance.new("TextButton")
		b.AnchorPoint = Vector2.new(1, 0)
		b.Position = UDim2.new(1, -x, 0, 0)
		b.Size = UDim2.fromOffset(w, 18)
		b.BackgroundColor3 = NOTE_INK
		b.BackgroundTransparency = 0.82
		b.Font = Enum.Font.GothamBold
		b.TextSize = 10
		b.TextColor3 = NOTE_INK
		b.Text = str
		b.ZIndex = 6
		b.Parent = headerRow
		corner(b, 3)
		return b
	end
	local remove = smallButton("X", 0, 20)
	local tie = smallButton("STRING", 24, 54)
	remove.Activated:Connect(function()
		if linkFrom == note.id then
			linkFrom = nil
			setHint(nil)
		end
		act("unpin", { id = note.id })
	end)
	tie.Activated:Connect(function()
		if linkFrom == note.id then
			linkFrom = nil
			setHint(nil)
		elseif linkFrom then
			onNoteClicked(note.id)
			return
		else
			linkFrom = note.id
			setHint("Click another note to tie a string to it. Tying two notes that are already tied cuts the string. Esc cancels.")
		end
		highlight()
	end)

	local title = if item then item.title else "Note"
	local t = text(content, title, 14, NOTE_INK, Enum.Font.GothamBold, 2)
	t.ZIndex = 5
	local lines = if item then item.lines else { note.text or "" }
	for i, l in lines do
		local lt = text(content, l, 12, NOTE_INK, Enum.Font.Gotham, 2 + i)
		lt.ZIndex = 5
	end
	if note.by and not item then
		local by = text(content, "- " .. note.by, 10, Color3.fromRGB(110, 100, 90), Enum.Font.GothamMedium, 99)
		by.ZIndex = 5
	end

	-- Drag to move; a click without movement completes a string.
	f.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local pos = Vector2.new(input.Position.X, input.Position.Y)
		if overButton(f, pos) then
			return
		end
		draggingId = note.id
		local startMouse = pos
		local startNote = notePos[note.id] or Vector2.new(note.x, note.y)
		local moved = false
		f.ZIndex = 7
		local moveConn, endConn
		moveConn = UserInputService.InputChanged:Connect(function(m)
			if m.UserInputType == Enum.UserInputType.MouseMovement or m.UserInputType == Enum.UserInputType.Touch then
				local delta = (Vector2.new(m.Position.X, m.Position.Y) - startMouse) / canvasScale.Scale
				if delta.Magnitude > 4 then
					moved = true
				end
				local np = startNote + delta
				np = Vector2.new(math.clamp(np.X, 0, 2400 - NOTE_W), math.clamp(np.Y, 0, 1600 - 120))
				notePos[note.id] = np
				f.Position = UDim2.fromOffset(np.X, np.Y)
				drawLines()
			end
		end)
		endConn = UserInputService.InputEnded:Connect(function(e)
			if e.UserInputType == input.UserInputType then
				moveConn:Disconnect()
				endConn:Disconnect()
				draggingId = nil
				f.ZIndex = 4
				if moved then
					local np = notePos[note.id]
					act("move", { id = note.id, x = np.X, y = np.Y })
				else
					onNoteClicked(note.id)
				end
			end
		end)
	end)
	return f
end

local function renderDrawer(b: any)
	clear(drawerList)
	local pinned = {}
	for _, n in b.notes do
		if n.item then
			pinned[n.item] = true
		end
	end
	local order = { evidence = 1, person = 2, place = 3, fact = 4 }
	local keys = {}
	for key, item in b.items do
		if not pinned[key] then
			table.insert(keys, key)
		end
	end
	table.sort(keys, function(x, y)
		local ix, iy = b.items[x], b.items[y]
		if ix.kind ~= iy.kind then
			return (order[ix.kind] or 9) < (order[iy.kind] or 9)
		end
		return ix.title < iy.title
	end)
	for i, key in keys do
		local item = b.items[key]
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(1, -8, 0, 0)
		btn.AutomaticSize = Enum.AutomaticSize.Y
		btn.BackgroundColor3 = KIND_COLOUR[item.kind] or KIND_COLOUR.custom
		btn.AutoButtonColor = true
		btn.Font = Enum.Font.GothamMedium
		btn.TextSize = 13
		btn.TextColor3 = NOTE_INK
		btn.TextWrapped = true
		btn.TextXAlignment = Enum.TextXAlignment.Left
		btn.Text = ("%s\n%s"):format(KIND_LABEL[item.kind] or "", item.title)
		btn.LayoutOrder = i
		btn.Parent = drawerList
		corner(btn, 4)
		pad(btn, 8)
		btn.Activated:Connect(function()
			local c = viewCentre() + Vector2.new(math.random(-60, 60) - NOTE_W / 2, math.random(-40, 40) - 40)
			act("pin", { item = key, x = c.X, y = c.Y })
		end)
	end
	if #keys == 0 then
		text(drawerList, "Everything you know is on the board.", 12, QUIET)
	end
	drawerTitle.Text = ("NOTEBOOK  (%d)"):format(#keys)
end

local function renderBoard(b: any)
	currentBoard = b
	titleLabel.Text = b.title
	objectiveLabel.Text = b.objective
	local seen = {}
	for _, n in b.notes do
		seen[n.id] = true
		local item = if n.item then b.items[n.item] else nil
		local sig = if item then (item.title .. "|" .. table.concat(item.lines, "|")) else ("custom|" .. tostring(n.text))
		local f = noteFrames[n.id]
		if f and noteSig[n.id] ~= sig then
			f:Destroy()
			f = nil
		end
		if not f then
			f = buildNote(n, item)
			f.Parent = notesLayer
			noteFrames[n.id] = f
			noteSig[n.id] = sig
		end
		if draggingId ~= n.id then
			notePos[n.id] = Vector2.new(n.x, n.y)
			f.Position = UDim2.fromOffset(n.x, n.y)
		end
	end
	for id, f in noteFrames do
		if not seen[id] then
			f:Destroy()
			noteFrames[id] = nil
			noteSig[id] = nil
			notePos[id] = nil
			if linkFrom == id then
				linkFrom = nil
				setHint(nil)
			end
		end
	end
	highlight()
	drawLines()
	renderDrawer(b)
end
boardEvent.OnClientEvent:Connect(renderBoard)
task.spawn(function()
	local ok, b = pcall(function()
		return getBoard:InvokeServer()
	end)
	if ok and b then
		renderBoard(b)
	end
end)

-- Pan by dragging empty cork; zoom with the wheel around the cursor.
local function overAnyNote(pos: Vector2): boolean
	for _, f in noteFrames do
		local p, s = f.AbsolutePosition, f.AbsoluteSize
		if pos.X >= p.X and pos.X <= p.X + s.X and pos.Y >= p.Y and pos.Y <= p.Y + s.Y then
			return true
		end
	end
	return false
end

viewport.InputBegan:Connect(function(input)
	local pos = Vector2.new(input.Position.X, input.Position.Y)
	if input.UserInputType == Enum.UserInputType.MouseWheel then
		local before = canvasScale.Scale
		local after = math.clamp(before * (if input.Position.Z > 0 then 1.1 else 1 / 1.1), 0.4, 1.4)
		local local_ = pos - viewport.AbsolutePosition
		-- keep the point under the cursor fixed
		pan = local_ - (local_ - pan) * (after / before)
		canvasScale.Scale = after
		applyPan()
		return
	end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	if overAnyNote(pos) or writer.Visible then
		return
	end
	if linkFrom then
		linkFrom = nil
		highlight()
		setHint(nil)
	end
	local startMouse, startPan = pos, pan
	local moveConn, endConn
	moveConn = UserInputService.InputChanged:Connect(function(m)
		if m.UserInputType == Enum.UserInputType.MouseMovement or m.UserInputType == Enum.UserInputType.Touch then
			pan = startPan + (Vector2.new(m.Position.X, m.Position.Y) - startMouse)
			applyPan()
		end
	end)
	endConn = UserInputService.InputEnded:Connect(function(e)
		if e.UserInputType == input.UserInputType then
			moveConn:Disconnect()
			endConn:Disconnect()
		end
	end)
end)
viewport:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyPan)

centreButton.Activated:Connect(function()
	canvasScale.Scale = 1
	pan = Vector2.new(0, 0)
	applyPan()
end)

newNoteButton.Activated:Connect(function()
	writer.Visible = true
	writerBox.Text = ""
	writerBox:CaptureFocus()
end)
writerCancel.Activated:Connect(function()
	writer.Visible = false
end)
writerPin.Activated:Connect(function()
	local str = writerBox.Text
	writer.Visible = false
	if #str:gsub("%s", "") > 0 then
		local c = viewCentre() - Vector2.new(NOTE_W / 2, 40)
		act("custom", { text = str, x = c.X, y = c.Y })
	end
end)

local function toggleBoard(force: boolean?)
	board.Visible = if force ~= nil then force else not board.Visible
	if not board.Visible then
		writer.Visible = false
		linkFrom = nil
		highlight()
		setHint(nil)
	else
		applyPan()
	end
end
boardButton.Activated:Connect(function()
	toggleBoard()
end)
closeButton.Activated:Connect(function()
	toggleBoard(false)
end)

---------------------------------------------------------------- Shared side panel (interviews, accusation)
local side = Instance.new("Frame")
side.AnchorPoint = Vector2.new(1, 0.5)
side.Position = UDim2.new(1, -16, 0.5, 0)
side.Size = UDim2.new(0, 400, 0.8, 0)
side.BackgroundColor3 = PANEL
side.BackgroundTransparency = 0.04
side.Visible = false
side.ZIndex = 40
side.Parent = gui
corner(side, 10)
stroke(side, CYAN, 0.35)
pad(side, 14)
local sideScroll = scroller(side)
sideScroll.Size = UDim2.fromScale(1, 1)
list(sideScroll, 8)

local function closeSide()
	side.Visible = false
	clear(sideScroll)
end

---------------------------------------------------------------- Interviews
local interviewing: any = nil

local function renderInterview(answer: string?)
	local iv = interviewing
	clear(sideScroll)
	text(sideScroll, iv.name, 20, INK, Enum.Font.GothamBold, 1)
	text(sideScroll, iv.job, 13, QUIET, Enum.Font.Gotham, 2)
	if answer then
		local quote = text(sideScroll, "\"" .. answer .. "\"", 16, INK, Enum.Font.GothamMedium, 3)
		quote.TextColor3 = Color3.fromRGB(255, 220, 190)
	end
	local order = 10
	for _, q in iv.questions do
		order += 1
		local b = button(sideScroll, q.text, order)
		b.Activated:Connect(function()
			b.Text = "..."
			local res = ask:InvokeServer(iv.citizenId, q.id, nil)
			if interviewing == iv then
				if res.questions then
					iv.questions = res.questions
				end
				renderInterview(res.text)
			end
		end)
	end
	if currentBoard and #currentBoard.evidence > 0 then
		order += 1
		text(sideScroll, "SHOW EVIDENCE", 12, ACCENT, Enum.Font.GothamBold, order)
		for _, e in currentBoard.evidence do
			order += 1
			local b = button(sideScroll, "Show: " .. e.label, order, ACCENT)
			b.Activated:Connect(function()
				b.Text = "..."
				local res = ask:InvokeServer(iv.citizenId, "evidence", e.id)
				if interviewing == iv then
					renderInterview(res.text)
				end
			end)
		end
	end
	order += 1
	local leave = button(sideScroll, "Leave", order, QUIET)
	leave.Activated:Connect(function()
		interviewing = nil
		closeSide()
	end)
end

openInterview.OnClientEvent:Connect(function(data)
	interviewing = data
	side.Visible = true
	renderInterview(nil)
end)

---------------------------------------------------------------- Accusation
openAccuse.OnClientEvent:Connect(function(data)
	interviewing = nil
	side.Visible = true
	clear(sideScroll)
	text(sideScroll, "File an accusation", 20, INK, Enum.Font.GothamBold, 1)
	text(sideScroll, "Name the killer and the motive. You only get one shot.", 13, QUIET, Enum.Font.Gotham, 2)
	local chosenSuspect: number? = nil
	local chosenMotive: string? = nil
	local suspectButtons: { [number]: TextButton } = {}
	local motiveButtons: { [string]: TextButton } = {}
	local order = 3
	text(sideScroll, "SUSPECT", 12, ACCENT, Enum.Font.GothamBold, order)
	if #data.suspects == 0 then
		order += 1
		text(sideScroll, "Nobody on your board yet. Investigate first.", 14, QUIET, Enum.Font.Gotham, order)
	end
	for _, s in data.suspects do
		order += 1
		local b = button(sideScroll, s.name, order)
		suspectButtons[s.id] = b
		b.Activated:Connect(function()
			chosenSuspect = s.id
			for id, other in suspectButtons do
				other.BackgroundColor3 = if id == s.id then Color3.fromRGB(60, 30, 60) else CARD
			end
		end)
	end
	order += 1
	text(sideScroll, "MOTIVE", 12, ACCENT, Enum.Font.GothamBold, order)
	for _, m in data.motives do
		order += 1
		local b = button(sideScroll, m.label, order)
		motiveButtons[m.id] = b
		b.Activated:Connect(function()
			chosenMotive = m.id
			for id, other in motiveButtons do
				other.BackgroundColor3 = if id == m.id then Color3.fromRGB(60, 30, 60) else CARD
			end
		end)
	end
	order += 1
	local result = text(sideScroll, "", 15, INK, Enum.Font.GothamMedium, order + 2)
	local submit = button(sideScroll, "Submit accusation", order, ACCENT)
	submit.Font = Enum.Font.GothamBold
	submit.Activated:Connect(function()
		if not chosenSuspect or not chosenMotive then
			result.Text = "Pick a suspect and a motive."
			return
		end
		submit.Text = "Filing..."
		local res = accuse:InvokeServer(chosenSuspect, chosenMotive)
		result.Text = res.text or ""
		submit.Text = "Filed"
		submit.Active = false
	end)
	local leave = button(sideScroll, "Close", order + 3, QUIET)
	leave.Activated:Connect(closeSide)
end)

---------------------------------------------------------------- Input
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.B then
		toggleBoard()
	elseif input.KeyCode == Enum.KeyCode.Escape then
		toggleBoard(false)
		interviewing = nil
		closeSide()
	end
end)
