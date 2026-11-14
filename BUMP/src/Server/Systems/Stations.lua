--!nonstrict
--[[
	The lobby's stores that do something (2026-11-14). AR's city came with SHOP, LOCKER, REWARDS
	and LEADERBOARD storefronts that led nowhere; each now has a job:

	- SHOP and LOCKER: a glowing pad at the doorway with a prompt (F, gamepad D-pad up, or tap)
	  that opens the power-up shop (You "OpenShop"; the shop is also on B anywhere). LOCKER's
	  prompt says "Loadout": choosing what you bring is in the same screen.
	- REWARDS: the daily reward (Progress.ClaimDaily). The prompt's words are each player's own
	  (Client/Systems/StationClient reads their BumpDaily* attributes): what today pays, or how long
	  until the next one.
	- LEADERBOARD: AR's three empty boards show this server's last winners, wins today (bots
	  count: they fill the seats), and the players here by level. Server-only: the place has no
	  API access, so nothing global.

	Prompts carry the tag "BumpStation" and a Station attribute ("Shop", "Locker", "Daily").
]]

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Neon = require("@GameServer/Lobby/Neon")
local PowerUpInfo = require("@Shared/PowerUps/PowerUpInfo")
local Progress = require("@GameServer/Systems/Progress")
local Remotes = require("@Shared/Movement/Remotes")
local RoundInfo = require("@Shared/Rounds/RoundInfo")
local World = require("@Shared/World")

local Stations = {}

local TAG = "BumpStation"
local RECENT = 6 -- winners kept on the board
local ROWS = 6 -- rows on each board
local BOARD_BACK = Color3.fromRGB(14, 10, 30)

local folder: Folder = nil

-- ═══ the prompts ═════════════════════════════════════════════════════════════════

-- The floor under a spot (AR's stores sit on steps and stages of different heights).
local function floorUnder(at: Vector3): Vector3
	local lobby = Workspace:FindFirstChild("Lobby")
	if not lobby then
		return at
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { lobby }
	local hit = Workspace:Raycast(at + Vector3.new(0, 12, 0), Vector3.new(0, -30, 0), params)
	return hit and hit.Position or at
end

-- A glowing pad on the floor with a prompt over it, facing the arena.
local function station(spot: Vector3, name: string, action: string, object: string, color: Color3, onUse: (Player) -> ())
	local at = floorUnder(spot)
	local flat = Vector3.new(at.X, 0, at.Z)
	local facing = flat.Magnitude > 0 and CFrame.lookAt(at, at - flat) or CFrame.new(at)
	local pad = Neon.Part(folder, Vector3.new(0.4, 9, 9), facing * CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0, math.rad(90)), color, Enum.Material.Neon, {
		Shape = Enum.PartType.Cylinder,
		Transparency = 0.35,
	})
	pad.Name = name .. "Pad"
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 14
	light.Brightness = 1.5
	light.Parent = pad
	local glitter = Instance.new("ParticleEmitter")
	glitter.Texture = Neon.Sparkle
	glitter.Rate = 6
	glitter.Lifetime = NumberRange.new(1, 1.6)
	glitter.Speed = NumberRange.new(2, 4)
	glitter.EmissionDirection = Enum.NormalId.Right -- the cylinder's axis, turned upright
	glitter.SpreadAngle = Vector2.new(25, 25)
	glitter.Color = ColorSequence.new(color)
	glitter.LightEmission = 1
	glitter.Size = NumberSequence.new(0.8, 0)
	glitter.Parent = pad

	local anchor = Neon.Part(folder, Vector3.new(1, 1, 1), facing * CFrame.new(0, 3, 0), color, Enum.Material.SmoothPlastic, { Transparency = 1 })
	anchor.Name = name .. "Prompt"
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.KeyboardKeyCode = Enum.KeyCode.F -- E is the shove
	prompt.GamepadKeyCode = Enum.KeyCode.DPadUp -- X is the shove, Y the power-up
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("Station", name)
	CollectionService:AddTag(prompt, TAG)
	prompt.Parent = anchor
	prompt.Triggered:Connect(function(player)
		onUse(player)
		glitter:Emit(20)
	end)
	return anchor
end

local function openShop(player: Player)
	Remotes.You(player, "OpenShop")
end

local function claimDaily(player: Player)
	local gold = Progress.ClaimDaily(player)
	if gold > 0 then
		-- a burst everyone on the plaza sees
		local burst = folder:FindFirstChild("DailyPad")
		local emitter = burst and burst:FindFirstChildOfClass("ParticleEmitter")
		if emitter then
			emitter:Emit(60)
		end
	end
end

-- ═══ the leaderboards ════════════════════════════════════════════════════════════

local boards = {} -- { { Title: TextLabel, Rows: { TextLabel } } }, along the wall
local recent = {} -- { { Game, Name, Seat } }, newest first
local winsToday = {} -- [name] = { Wins, Seat }

local function boardScreen(model: Model, title: string, color: Color3)
	local cframe, size = model:GetBoundingBox()
	local centre = cframe.Position
	local inward = Vector3.new(-centre.X, 0, -centre.Z).Unit
	local at = centre + inward * (math.min(size.X, size.Z) / 2 + 0.25) - Vector3.new(0, 2, 0)
	local width = math.max(size.X, size.Z) * 0.82
	local screen = Neon.Part(folder, Vector3.new(width, size.Y * 0.62, 0.2), CFrame.lookAt(at, at + inward), BOARD_BACK, Enum.Material.SmoothPlastic)
	screen.Name = "LeaderboardScreen"
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.Brightness = 2
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(500, 760)
	gui.Parent = screen
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 10)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = gui
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 24)
	padding.Parent = gui

	local function label(parent: Instance, text: string, height: number, textColor: Color3, order: number): TextLabel
		local l = Instance.new("TextLabel")
		l.Size = UDim2.new(0.9, 0, 0, height)
		l.BackgroundTransparency = 1
		l.Font = Neon.Font
		l.TextScaled = true
		l.TextColor3 = textColor
		l.Text = text
		l.LayoutOrder = order
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 3
		stroke.Color = Neon.Outline
		stroke.Parent = l
		l.Parent = parent
		return l
	end

	-- the title sits on the board's own red header, above the screen
	local header = Neon.Part(folder, Vector3.new(width, size.Y * 0.16, 0.05), CFrame.lookAt(at, at + inward) * CFrame.new(0, size.Y * 0.4, -0.05), BOARD_BACK, Enum.Material.SmoothPlastic, { Transparency = 1 })
	header.Name = "LeaderboardTitle"
	local headerGui = Instance.new("SurfaceGui")
	headerGui.Face = Enum.NormalId.Front
	headerGui.LightInfluence = 0
	headerGui.Brightness = 2
	headerGui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	headerGui.CanvasSize = Vector2.new(500, 200)
	headerGui.Parent = header
	local titleLabel = label(headerGui, title, 150, Color3.new(1, 1, 1), 0)
	titleLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	titleLabel.Position = UDim2.fromScale(0.5, 0.5)
	local stroke = titleLabel:FindFirstChildOfClass("UIStroke")
	stroke.Thickness = 6
	stroke.Color = color:Lerp(Neon.Outline, 0.6)

	local board = { Title = titleLabel, Rows = {} }
	for index = 1, ROWS do
		board.Rows[index] = label(gui, "", 96, Color3.new(1, 1, 1), index)
	end
	table.insert(boards, board)
end

local function show(board, lines)
	if not board then
		return
	end
	for index, row in board.Rows do
		local line = lines[index]
		row.Text = line and line.Text or (index == 1 and "Nobody yet" or "")
		row.TextColor3 = line and line.Color or Color3.fromRGB(150, 150, 170)
	end
end

local function seatColor(seat): Color3
	return RoundInfo.SeatColors[seat] or Color3.new(1, 1, 1)
end

local function refresh()
	local lines = {}
	for index, win in recent do
		lines[index] = { Text = string.format("%s  %s", win.Game, win.Name), Color = seatColor(win.Seat) }
	end
	show(boards[1], lines)

	local ranked = {}
	for name, entry in winsToday do
		table.insert(ranked, { Name = name, Wins = entry.Wins, Seat = entry.Seat })
	end
	table.sort(ranked, function(a, b)
		return a.Wins > b.Wins or (a.Wins == b.Wins and a.Name < b.Name)
	end)
	lines = {}
	for index, entry in ranked do
		lines[index] = { Text = string.format("%d. %s  %d", index, entry.Name, entry.Wins), Color = seatColor(entry.Seat) }
	end
	show(boards[2], lines)

	local here = {}
	for _, player in Players:GetPlayers() do
		table.insert(here, { Name = player.DisplayName, Level = player:GetAttribute(PowerUpInfo.LevelAttr) or 1, Xp = player:GetAttribute(PowerUpInfo.XpAttr) or 0 })
	end
	table.sort(here, function(a, b)
		return a.Xp > b.Xp
	end)
	lines = {}
	for index, entry in here do
		lines[index] = { Text = string.format("Lv %d  %s", entry.Level, entry.Name), Color = Neon.Colors.Cyan }
	end
	show(boards[3], lines)
end

local function onResults(round: Folder)
	local ok, results = pcall(HttpService.JSONDecode, HttpService, round:GetAttribute("Results") or "[]")
	if not ok or type(results) ~= "table" or #results == 0 then
		return
	end
	local info = RoundInfo.Minigames[round:GetAttribute("Minigame")]
	local title = info and info.Title or "?"
	for _, result in results do
		if result.Place == 1 then
			table.insert(recent, 1, { Game = title, Name = result.Name, Seat = result.Seat })
			local entry = winsToday[result.Name] or { Wins = 0, Seat = result.Seat }
			entry.Wins += 1
			entry.Seat = result.Seat
			winsToday[result.Name] = entry
		end
	end
	while #recent > RECENT do
		table.remove(recent)
	end
	refresh()
end

local function buildBoards()
	local holder = Workspace:FindFirstChild("Lobby")
	holder = holder and holder:FindFirstChild("MainBuildings")
	holder = holder and holder:FindFirstChild("LEADERBOARDS")
	holder = holder and holder:FindFirstChild("Interactable")
	if not holder then
		warn("[Stations] no LEADERBOARDS boards in Workspace.Lobby; skipping the leaderboards")
		return
	end
	local models = {}
	for _, child in holder:GetChildren() do
		if child:IsA("Model") then
			table.insert(models, child)
		end
	end
	-- left to right as you face them from the plaza
	table.sort(models, function(a, b)
		return a:GetPivot().Position.X < b:GetPivot().Position.X
	end)
	local titles = { { "LAST WINNERS", Neon.Colors.Yellow }, { "WINS TODAY", Neon.Colors.Pink }, { "PLAYERS HERE", Neon.Colors.Cyan } }
	for index, model in models do
		local title = titles[index]
		if title then
			boardScreen(model, title[1], title[2])
		end
	end
end

function Stations.start()
	local old = Workspace:FindFirstChild("LobbyStations")
	if old then
		old:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = "LobbyStations"
	folder.Parent = Workspace

	station(World.ShopSpot, "Shop", "Open Shop", "Power-ups", Neon.Colors.Green, openShop)
	station(World.LockerSpot, "Locker", "Loadout", "Choose your power-up", Neon.Colors.Purple, openShop)
	station(World.RewardsSpot, "Daily", "Claim", "Daily Reward", Neon.Colors.Yellow, claimDaily)

	buildBoards()
	refresh()
	local round = ReplicatedStorage:WaitForChild(RoundInfo.Folder)
	round:GetAttributeChangedSignal("Results"):Connect(function()
		onResults(round)
	end)
	Players.PlayerAdded:Connect(function(player)
		player:GetAttributeChangedSignal(PowerUpInfo.XpAttr):Connect(refresh)
		refresh()
	end)
	for _, player in Players:GetPlayers() do
		player:GetAttributeChangedSignal(PowerUpInfo.XpAttr):Connect(refresh)
	end
	Players.PlayerRemoving:Connect(function()
		task.defer(refresh)
	end)
end

return Stations
