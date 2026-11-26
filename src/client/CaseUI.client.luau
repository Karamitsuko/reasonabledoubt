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
local boardButton = Instance.new("TextButton")
boardButton.AnchorPoint = Vector2.new(0, 0)
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
board.Position = UDim2.fromScale(0.5, 0.52)
board.Size = UDim2.new(0.86, 0, 0.8, 0)
board.BackgroundColor3 = PANEL
board.BackgroundTransparency = 0.04
board.Visible = false
board.Parent = gui
corner(board, 10)
stroke(board, ACCENT, 0.35)
pad(board, 18)
local sizeLimit = Instance.new("UISizeConstraint")
sizeLimit.MaxSize = Vector2.new(1100, 760)
sizeLimit.Parent = board

local header = Instance.new("Frame")
header.BackgroundTransparency = 1
header.Size = UDim2.new(1, 0, 0, 0)
header.AutomaticSize = Enum.AutomaticSize.Y
header.Parent = board
list(header, 4)
local titleLabel = text(header, "No active case", 22, INK, Enum.Font.GothamBold, 1)
local objectiveLabel = text(header, "", 14, QUIET, Enum.Font.Gotham, 2)

local columns = Instance.new("Frame")
columns.BackgroundTransparency = 1
columns.Position = UDim2.new(0, 0, 0, 78)
columns.Size = UDim2.new(1, 0, 1, -78)
columns.Parent = board

local function column(xScale: number, wScale: number, title: string): ScrollingFrame
	local c = Instance.new("Frame")
	c.BackgroundTransparency = 1
	c.Position = UDim2.new(xScale, if xScale > 0 then 10 else 0, 0, 0)
	c.Size = UDim2.new(wScale, -10, 1, 0)
	c.Parent = columns
	local t = text(c, title, 13, ACCENT, Enum.Font.GothamBold)
	t.Size = UDim2.new(1, 0, 0, 18)
	t.AutomaticSize = Enum.AutomaticSize.None
	local s = scroller(c)
	s.Position = UDim2.new(0, 0, 0, 24)
	s.Size = UDim2.new(1, 0, 1, -24)
	list(s, 8)
	return s
end
local evidenceCol = column(0, 0.55, "EVIDENCE")
local peopleCol = column(0.55, 0.45, "PEOPLE")

local currentBoard: any = nil

local function clear(frame: Instance)
	for _, c in frame:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

local function card(parent: Instance, title: string, lines: { string }, order: number, accent: Color3)
	local f = Instance.new("Frame")
	f.BackgroundColor3 = CARD
	f.Size = UDim2.new(1, -6, 0, 0)
	f.AutomaticSize = Enum.AutomaticSize.Y
	f.LayoutOrder = order
	f.Parent = parent
	corner(f)
	stroke(f, accent, 0.65)
	pad(f, 10)
	list(f, 4)
	text(f, title, 16, INK, Enum.Font.GothamBold, 1)
	for i, l in lines do
		text(f, l, 14, if i == 1 then INK else QUIET, Enum.Font.Gotham, i + 1)
	end
end

local function renderBoard(b: any)
	currentBoard = b
	titleLabel.Text = b.title
	objectiveLabel.Text = b.objective
	clear(evidenceCol)
	clear(peopleCol)
	for i, e in b.evidence do
		card(evidenceCol, e.label, { e.text }, i, CYAN)
	end
	if #b.evidence == 0 then
		text(evidenceCol, "Nothing yet. Start at the scene.", 14, QUIET)
	end
	for i, p in b.people do
		local lines = { ("%s  ·  lives in %s"):format(p.role, p.home) }
		for _, n in p.notes do
			table.insert(lines, "• " .. n)
		end
		card(peopleCol, p.name, lines, i, if p.role == "Victim" then ACCENT else Color3.fromRGB(200, 190, 255))
	end
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

local function toggleBoard(force: boolean?)
	board.Visible = if force ~= nil then force else not board.Visible
end
boardButton.Activated:Connect(function()
	toggleBoard()
end)

---------------------------------------------------------------- Shared side panel (interviews, accusation)
local side = Instance.new("Frame")
side.AnchorPoint = Vector2.new(1, 0.5)
side.Position = UDim2.new(1, -16, 0.5, 0)
side.Size = UDim2.new(0, 400, 0.8, 0)
side.BackgroundColor3 = PANEL
side.BackgroundTransparency = 0.04
side.Visible = false
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
