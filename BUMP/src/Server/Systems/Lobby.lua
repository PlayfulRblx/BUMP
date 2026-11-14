--!nonstrict
--[[
	The lobby round the arena (2026-11-13). The city itself is AR's neon hub, placed in Studio as
	Workspace.Lobby (the user's own place, reused at their word: "Think we could reuse/restyle a
	lot of the assets from the AR place?"). This builds what BUMP adds on top, in Workspace.LobbyFx:

	- PitWall: an invisible ring round the pit (World.WallRadius, from World.WallBottom up). The
	  plaza can't get in, and a contestant can't jump out onto the plaza; thrown sideways, you hit
	  it and drop into the gap. A glass rail with neon strips shows where it is.
	- The jumbotron, hung over the arena: six screens showing the round live (the game, who's
	  left, the countdown, the winner), from the BumpRound attributes.
	- The show: searchlights, a ring of gold coins, balloons, a blimp, a giant BUMP! sign over
	  the Play store; confetti and fireworks while results and standings are up.
	- The SHOP, LOCKER, REWARDS and LEADERBOARD stores are Stations' (Server/Systems/Stations).
	- The PLAY store's doorway is a live screen (the round's countdown, who's left, the winner);
	  the PRACTICE store's doorway is a portal to the practice yard (World.YardOrigin), and a pad
	  there brings you back. AR's walk-in halls behind both were removed in the place.
	- A catch: anyone who falls into the pit and isn't being judged by a game is put back on
	  the plaza (or in the yard, if they fell off that).
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local RoundInfo = require("@Shared/Rounds/RoundInfo")
local World = require("@Shared/World")
local Neon = require("@GameServer/Lobby/Neon")

local Lobby = {}

local NEON = Neon.Colors
local CYCLE = Neon.Cycle
local SPARKLE = Neon.Sparkle
local JUMBO_Y = 78
local CATCH_Y = -45 -- below this (and not in a game) you're put back

local fx: Folder = nil
local screens = {} -- { TextLabel } on the jumbotron, in face order
local celebration = {} -- ParticleEmitters on while results are up
local fireworkSpots = {} -- Attachments high over the city

local part = Neon.Part
local sign = Neon.Sign

local function ring(radius: number, count: number, each)
	for index = 0, count - 1 do
		local a1 = index / count * math.pi * 2
		local a2 = (index + 1) / count * math.pi * 2
		local p1 = Vector3.new(math.cos(a1) * radius, 0, math.sin(a1) * radius)
		local p2 = Vector3.new(math.cos(a2) * radius, 0, math.sin(a2) * radius)
		each(index, (p1 + p2) / 2, (p2 - p1).Magnitude, CFrame.lookAt((p1 + p2) / 2, p2))
	end
end

-- ═══ the wall and its rail ═══════════════════════════════════════════════════════

local function buildWall()
	local wall = Instance.new("Folder")
	wall.Name = "PitWall"
	wall.Parent = fx
	local height = World.WallTop - World.WallBottom
	ring(World.WallRadius, 40, function(_, _, length, cframe)
		part(wall, Vector3.new(1, height, length + 0.6), cframe + Vector3.new(0, World.WallBottom + height / 2, 0), Color3.new(), Enum.Material.SmoothPlastic, {
			Transparency = 1,
			CanCollide = true,
		})
	end)
	local rail = Instance.new("Folder")
	rail.Name = "Rail"
	rail.Parent = fx
	ring(World.WallRadius - 0.5, 48, function(index, _, length, cframe)
		part(rail, Vector3.new(0.4, 3.6, length), cframe + Vector3.new(0, World.PlazaY + 1.8, 0), Color3.fromRGB(150, 200, 255), Enum.Material.Glass, { Transparency = 0.65 })
		part(rail, Vector3.new(0.7, 0.45, length), cframe + Vector3.new(0, World.PlazaY + 3.8, 0), index % 2 == 0 and NEON.Cyan or NEON.Pink)
		part(rail, Vector3.new(0.7, 0.35, length), cframe + Vector3.new(0, World.PlazaY - 0.4, 0), NEON.Purple)
	end)
end

-- ═══ the jumbotron ═══════════════════════════════════════════════════════════════

local function buildJumbotron()
	local jumbo = Instance.new("Model")
	jumbo.Name = "Jumbotron"
	jumbo.Parent = fx
	local centre = World.Centre + Vector3.new(0, JUMBO_Y, 0)
	for index = 0, 5 do
		local angle = math.rad(60 * index + 30)
		local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local at = centre + out * 20
		local face = CFrame.lookAt(at, at + out)
		local screen = part(jumbo, Vector3.new(23.5, 14, 1), face, Color3.fromRGB(12, 10, 24), Enum.Material.SmoothPlastic)
		local label = sign(screen, "BUMP!", Color3.new(1, 1, 1), Color3.fromRGB(34, 12, 70))
		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new(CYCLE[index % 6 + 1], CYCLE[(index + 2) % 6 + 1])
		gradient.Rotation = 90
		gradient.Parent = label
		table.insert(screens, label)
		part(jumbo, Vector3.new(24, 0.8, 1.4), face + Vector3.new(0, 7.4, 0), CYCLE[index % 6 + 1])
		part(jumbo, Vector3.new(24, 0.8, 1.4), face + Vector3.new(0, -7.4, 0), CYCLE[(index + 3) % 6 + 1])
	end
	part(jumbo, Vector3.new(2, 60, 2), CFrame.new(centre + Vector3.new(0, 37, 0)), Color3.fromRGB(40, 40, 55), Enum.Material.Metal)
	-- a ring of lights round its underside
	for index = 0, 23 do
		local a = math.rad(index * 15)
		local at = centre + Vector3.new(math.cos(a) * 21, -9.5, math.sin(a) * 21)
		part(jumbo, Vector3.new(2.2, 1.2, 5), CFrame.lookAt(at, centre + Vector3.new(0, -9.5, 0)), CYCLE[index % 6 + 1])
	end
	local glow = Instance.new("PointLight")
	glow.Range = 40
	glow.Brightness = 2
	glow.Color = NEON.Purple
	glow.Parent = jumbo:FindFirstChildWhichIsA("BasePart")
end

local function decode(json)
	local ok, list = pcall(HttpService.JSONDecode, HttpService, json or "[]")
	return ok and type(list) == "table" and list or {}
end

-- What each of the three lines says right now (each shows on two opposite screens).
local function screenTexts(round: Instance): { string }
	local phase = round:GetAttribute("Phase") or "Practice"
	local info = RoundInfo.Minigames[round:GetAttribute("Minigame") or ""]
	local title = info and string.upper(info.Title) or "BUMP!"
	local left = math.max(0, math.ceil((round:GetAttribute("EndsAt") or 0) - Workspace:GetServerTimeNow()))
	local game_ = string.format("GAME %d / %d", round:GetAttribute("GameIndex") or 1, round:GetAttribute("GameCount") or 1)
	if phase == "Practice" then
		return { "BUMP!", "WAITING FOR PLAYERS", "PRACTICE IN THE YARD" }
	elseif phase == "Lobby" then
		return { "BUMP!", string.format("STARTING IN %d", left), "GET ON THE PLAZA!" }
	elseif phase == "Changeover" then
		return { title, "NEXT UP!", game_ }
	elseif phase == "Intro" then
		return { title, "GET READY!", game_ }
	elseif phase == "Play" then
		local note = round:GetAttribute("Note")
		local alive = string.format("%d LEFT!", round:GetAttribute("Alive") or 0)
		return { title, alive, (note and note ~= "") and string.upper(note) or game_ }
	elseif phase == "Results" then
		local winners = {}
		for _, row in decode(round:GetAttribute("Results")) do
			if row.Place == 1 then
				table.insert(winners, row.Name)
			end
		end
		return { title, #winners > 0 and ("WINNER: " .. string.upper(table.concat(winners, " & "))) or "RESULTS", game_ }
	elseif phase == "Standings" then
		local top = decode(round:GetAttribute("Standings"))[1]
		return { "FINAL STANDINGS", top and ("CHAMPION: " .. string.upper(top.Name)) or "GG!", "WELL PLAYED!" }
	end
	return { "BUMP!", "", "" }
end

-- ═══ the show ════════════════════════════════════════════════════════════════════

local function buildShow()
	local show = Instance.new("Model")
	show.Name = "Show"
	show.Parent = fx
	local rng = Random.new(7)
	-- searchlights from round the plaza
	for index = 0, 11 do
		local a = math.rad(30 * index + 15)
		local base = Vector3.new(math.cos(a) * 150, World.PlazaY + 2, math.sin(a) * 150)
		local tip = base + Vector3.new(math.cos(a) * rng:NextNumber(-40, 140) + rng:NextNumber(-80, 80), 420, math.sin(a) * rng:NextNumber(-40, 140) + rng:NextNumber(-80, 80))
		local length = (tip - base).Magnitude
		part(show, Vector3.new(length, 5, 5), CFrame.lookAt((base + tip) / 2, tip) * CFrame.Angles(0, math.rad(90), 0), CYCLE[index % 6 + 1], Enum.Material.Neon, {
			Shape = Enum.PartType.Cylinder,
			Transparency = 0.6,
		})
		part(show, Vector3.new(5, 5, 5), CFrame.new(base), Color3.fromRGB(230, 230, 255), Enum.Material.Neon, { Shape = Enum.PartType.Ball })
	end
	-- a ring of gold coins over the plaza
	for index = 0, 35 do
		local a = math.rad(index * 10)
		local radius = 120 + math.sin(index * 0.7) * 6
		local at = Vector3.new(math.cos(a) * radius, 20 + math.sin(index * 0.9) * 5, math.sin(a) * radius)
		part(show, Vector3.new(0.7, 4, 4), CFrame.lookAt(at, Vector3.new(0, at.Y, 0)) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(255, 205, 50), Enum.Material.Neon, {
			Shape = Enum.PartType.Cylinder,
		})
	end
	-- balloons
	for index = 1, 30 do
		local a = rng:NextNumber(0, math.pi * 2)
		local at = Vector3.new(math.cos(a) * rng:NextNumber(110, 200), rng:NextNumber(45, 95), math.sin(a) * rng:NextNumber(110, 200))
		part(show, Vector3.new(4, 4, 4), CFrame.new(at), CYCLE[index % 6 + 1], Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Ball, Reflectance = 0.1 })
		part(show, Vector3.new(0.15, 8, 0.15), CFrame.new(at - Vector3.new(0, 6, 0)), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
	end
	-- a blimp
	local blimpAt = Vector3.new(-150, 150, -160)
	local blimp = part(show, Vector3.new(24, 24, 24), CFrame.lookAt(blimpAt, blimpAt + Vector3.new(1, 0, -0.4)), Color3.fromRGB(240, 240, 255), Enum.Material.SmoothPlastic, {
		Shape = Enum.PartType.Ball,
	})
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, 1, 3)
	mesh.Parent = blimp
	local board = part(show, Vector3.new(30, 9, 0.5), CFrame.lookAt(blimpAt - Vector3.new(0, 2, 0), Vector3.new(0, 148, 0)) * CFrame.new(0, 0, -12.6), Color3.fromRGB(20, 10, 40), Enum.Material.SmoothPlastic)
	sign(board, "WIN GOLD!", NEON.Yellow, nil, Vector2.new(600, 180))
	-- the giant sign over the Play store (east)
	local signAt = Vector3.new(205, 92, 0)
	local giant = part(show, Vector3.new(90, 34, 1), CFrame.lookAt(signAt, Vector3.new(0, 92, 0)), Color3.new(), Enum.Material.SmoothPlastic, { Transparency = 1 })
	local logo = sign(giant, "BUMP!", Color3.new(1, 1, 1), nil, Vector2.new(900, 340))
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, NEON.Yellow),
		ColorSequenceKeypoint.new(0.5, NEON.Pink),
		ColorSequenceKeypoint.new(1, NEON.Cyan),
	})
	gradient.Parent = logo
	local light = Instance.new("SurfaceLight")
	light.Face = Enum.NormalId.Front
	light.Range = 60
	light.Brightness = 3
	light.Color = NEON.Pink
	light.Parent = giant
	-- confetti over the arena and firework spots over the city, for results
	local sky = part(show, Vector3.new(160, 1, 160), CFrame.new(0, 110, 0), Color3.new(), Enum.Material.SmoothPlastic, { Transparency = 1 })
	for _, color in CYCLE do
		local confetti = Instance.new("ParticleEmitter")
		confetti.Enabled = false
		confetti.Rate = 50
		confetti.Lifetime = NumberRange.new(5, 7)
		confetti.Speed = NumberRange.new(2, 6)
		confetti.EmissionDirection = Enum.NormalId.Bottom
		confetti.Acceleration = Vector3.new(0, -10, 0)
		confetti.Drag = 1
		confetti.SpreadAngle = Vector2.new(40, 40)
		confetti.Size = NumberSequence.new(1)
		confetti.Color = ColorSequence.new(color)
		confetti.LightEmission = 0.6
		confetti.Rotation = NumberRange.new(0, 360)
		confetti.RotSpeed = NumberRange.new(-200, 200)
		confetti.Texture = SPARKLE
		confetti.Parent = sky
		table.insert(celebration, confetti)
	end
	for index = 1, 8 do
		local a = rng:NextNumber(0, math.pi * 2)
		local attachment = Instance.new("Attachment")
		attachment.WorldPosition = Vector3.new(math.cos(a) * rng:NextNumber(60, 260), rng:NextNumber(170, 280), math.sin(a) * rng:NextNumber(60, 260))
		attachment.Parent = Workspace.Terrain
		attachment.Name = "LobbyFirework"
		local burst = Instance.new("ParticleEmitter")
		burst.Enabled = false
		burst.Rate = 0
		burst.Lifetime = NumberRange.new(1, 1.6)
		burst.Speed = NumberRange.new(40, 60)
		burst.Drag = 2.5
		burst.Acceleration = Vector3.new(0, -8, 0)
		burst.SpreadAngle = Vector2.new(180, 180)
		burst.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 0) })
		burst.Color = ColorSequence.new(CYCLE[index % 6 + 1])
		burst.LightEmission = 1
		burst.Texture = SPARKLE
		burst.Parent = attachment
		table.insert(fireworkSpots, burst)
	end
end

-- ═══ practice pads ═══════════════════════════════════════════════════════════════

local function pad(at: Vector3, color: Color3, text: string, go: () -> CFrame)
	local ring_ = part(fx, Vector3.new(0.6, 12, 12), CFrame.new(at) * CFrame.Angles(0, 0, math.rad(90)), color, Enum.Material.Neon, { Shape = Enum.PartType.Cylinder })
	part(fx, Vector3.new(0.7, 9, 9), CFrame.new(at + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(25, 25, 40), Enum.Material.SmoothPlastic, {
		Shape = Enum.PartType.Cylinder,
	})
	local trigger = part(fx, Vector3.new(10, 6, 10), CFrame.new(at + Vector3.new(0, 3, 0)), Color3.new(), Enum.Material.SmoothPlastic, { Transparency = 1, CanTouch = true })
	trigger.Name = "PadTrigger"
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(220, 60)
	gui.StudsOffset = Vector3.new(0, 6, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 120
	gui.Parent = ring_
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = FONT
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = color
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(20, 10, 40)
	stroke.Parent = label
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = SPARKLE
	sparks.Rate = 20
	sparks.Speed = NumberRange.new(8, 14)
	sparks.Lifetime = NumberRange.new(0.6, 1)
	sparks.Color = ColorSequence.new(color)
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new(1.1, 0)
	sparks.SpreadAngle = Vector2.new(10, 10)
	sparks.EmissionDirection = Enum.NormalId.Right
	sparks.Parent = ring_
	local last = {}
	trigger.Touched:Connect(function(other)
		local character = other.Parent
		local player = character and Players:GetPlayerFromCharacter(character)
		if not player or os.clock() - (last[player] or 0) < 1.5 then
			return
		end
		last[player] = os.clock()
		character:PivotTo(go())
	end)
end

local function yardSpot(): CFrame
	local at = World.YardOrigin + Vector3.new(math.random(-6, 6), 4, math.random(-6, 6))
	return CFrame.lookAt(at, at + Vector3.new(0, 0, -1))
end

-- ═══ the store doorways ═════════════════════════════════════════════════════════

local doorLabel: TextLabel = nil

-- A doorway filled with a screen (solid: nobody walks into the empty space behind).
local function doorScreen(door, text: string, top: Color3, bottom: Color3, background: Color3): TextLabel
	local screen = part(fx, Vector3.new(door.Size.X, door.Size.Y, 0.6), door.CFrame, Color3.fromRGB(12, 10, 24), Enum.Material.SmoothPlastic, { CanCollide = true })
	screen.Name = "DoorScreen"
	local label = sign(screen, text, Color3.new(1, 1, 1), background, Vector2.new(900, 420))
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(top, bottom)
	gradient.Rotation = 90
	gradient.Parent = label
	local light = Instance.new("SurfaceLight")
	light.Face = Enum.NormalId.Front
	light.Range = 24
	light.Brightness = 2
	light.Color = top
	light.Parent = screen
	return label
end

-- A glowing doorway you walk into to go somewhere.
local function portal(door, color: Color3, go: () -> CFrame)
	local sheet = part(fx, Vector3.new(door.Size.X, door.Size.Y, 0.4), door.CFrame, color, Enum.Material.Neon, { Transparency = 0.45, CanTouch = true })
	sheet.Name = "Portal"
	local swirl = Instance.new("ParticleEmitter")
	swirl.Texture = SPARKLE
	swirl.Rate = 40
	swirl.Speed = NumberRange.new(2, 5)
	swirl.Lifetime = NumberRange.new(0.8, 1.4)
	swirl.Color = ColorSequence.new(color)
	swirl.LightEmission = 1
	swirl.Size = NumberSequence.new(1.4, 0)
	swirl.SpreadAngle = Vector2.new(60, 60)
	swirl.EmissionDirection = Enum.NormalId.Front
	swirl.Parent = sheet
	local light = Instance.new("SurfaceLight")
	light.Face = Enum.NormalId.Front
	light.Range = 30
	light.Brightness = 3
	light.Color = color
	light.Parent = sheet
	local last = {}
	sheet.Touched:Connect(function(other)
		local character = other.Parent
		local player = character and Players:GetPlayerFromCharacter(character)
		if not player or os.clock() - (last[player] or 0) < 1.5 then
			return
		end
		last[player] = os.clock()
		character:PivotTo(go())
	end)
end

-- ═══ catching falls ══════════════════════════════════════════════════════════════

local function catchFalls()
	-- a game judges its own falls first (out below the arena's FallDepth, well above CATCH_Y,
	-- and moved to the plaza), so anyone this low is a stray
	while true do
		task.wait(0.3)
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			-- (not someone just knocked out, whose camera is watching them fall: KnockoutCam)
			if root and root.Position.Y < CATCH_Y and not character:GetAttribute(RoundInfo.KnockoutHoldAttr) then
				local inYard = (Vector3.new(root.Position.X, 0, root.Position.Z) - World.YardOrigin).Magnitude < 400
				root.AssemblyLinearVelocity = Vector3.zero
				character:PivotTo(inYard and yardSpot() or World.LobbySpot())
			end
		end
	end
end

function Lobby.start()
	local old = Workspace:FindFirstChild("LobbyFx")
	if old then
		old:Destroy()
	end
	fx = Instance.new("Folder")
	fx.Name = "LobbyFx"
	fx.Parent = Workspace
	buildWall()
	buildJumbotron()
	buildShow()
	-- PLAY's doorway shows the round live; REWARDS hands out the daily reward (Stations)
	doorLabel = doorScreen(World.PlayDoor, "BUMP!", NEON.Green, NEON.Cyan, Color3.fromRGB(20, 40, 30))
	doorScreen(World.RewardsDoor, "DAILY\nREWARD", NEON.Yellow, NEON.Orange, Color3.fromRGB(60, 30, 10))
	portal(World.PracticeDoor, NEON.Green, yardSpot)
	pad(World.YardOrigin + Vector3.new(14, 0.3, -14), NEON.Cyan, "BACK TO LOBBY", World.LobbySpot)

	local round = ReplicatedStorage:WaitForChild(RoundInfo.Folder)
	task.spawn(catchFalls)
	task.spawn(function()
		local rng = Random.new()
		while true do
			task.wait(0.25)
			local texts = screenTexts(round)
			if doorLabel then
				local line = texts[1] .. "\n" .. texts[2]
				if doorLabel.Text ~= line then
					doorLabel.Text = line
				end
			end
			for index, label in screens do
				local text = texts[(index - 1) % 3 + 1]
				if label.Text ~= text then
					label.Text = text
				end
			end
			local phase = round:GetAttribute("Phase")
			local party = phase == "Results" or phase == "Standings"
			for _, confetti in celebration do
				confetti.Enabled = party
			end
			if party and rng:NextNumber() < 0.5 then
				fireworkSpots[rng:NextInteger(1, #fireworkSpots)]:Emit(70)
			end
		end
	end)
end

return Lobby
