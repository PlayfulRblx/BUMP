--!nonstrict
--[[
	BUMP, the ball game, on the server.

	A platform of hex tiles in the sky, rings round a centre tile, with one ball fewer than there
	are players. After a grace period it crumbles one cell at a time (the user's idea): random
	cells off the edge, then holes anywhere once enough is gone, faster and faster. Jump onto a ball to ride it; ride into people to knock them about. A rider hit
	once wobbles (the "BumpWobbleUntil" attribute on their character); hit again while wobbling
	and they're knocked off. Someone on foot hit by a ball is thrown the way it was rolling and
	ragdolls. Fall below the platform and you're out. Last one standing
	wins, or everyone still in when the time is up.

	Who drives a ball: a player's own client drives the ball they ride (it owns its physics, see
	Client/Systems/BallRider); the server drives free balls (plain physics) and bots' balls (the
	same BallPhysics the clients use). Hits are judged here from the balls' touches.
]]

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local BallPhysics = require("@Shared/Minigames/BallPhysics")
local Hex = require("@Shared/Minigames/Hex")
local Ragdoll = require("@Shared/Ragdoll")
local Remotes = require("@Shared/Movement/Remotes")
local RoundInfo = require("@Shared/Rounds/RoundInfo")
local Tuning = require("@Shared/Movement/Tuning")
local BumpServer = require("@GameServer/Systems/BumpServer")
local Bots = require("@GameServer/Rounds/Bots")
local HexArena = require("@GameServer/Rounds/HexArena")
local PowerUps = require("@GameServer/Rounds/PowerUps")
local BumpBots = require("@GameServer/Rounds/BumpBots")
local World = require("@Shared/World")

local Ball = Tuning.Of("Ball")
local Pound = Tuning.Of("Pound")
local Hits = Tuning.Of("BumpHits")
local Arena = Tuning.Of("BumpArena")
local Rounds = Tuning.Of("Rounds")

local BumpGame = {}

BumpGame.BallTag = "BumpBall"
BumpGame.RiderAttr = "Rider" -- on a ball: the Id of who rides it, "" for none
BumpGame.WobbleAttr = "BumpWobbleUntil" -- on a character: server time its wobble ends

local ORIGIN = World.ArenaOrigin -- the lobby's pit
-- slate tops on thin coloured outlines (cyan in the middle through blue and purple to pink
-- at the rim): light enough that players stand out on it (the user: "less emphasis on the neon
-- arena. It's hard for the players to see eachother")
local RING_COLORS = { [0] = Color3.fromRGB(84, 88, 112) }
local RING_EDGES = {
	[0] = Color3.fromRGB(60, 226, 255),
	Color3.fromRGB(60, 226, 255),
	Color3.fromRGB(81, 150, 255),
	Color3.fromRGB(81, 150, 255),
	Color3.fromRGB(150, 100, 255),
	Color3.fromRGB(150, 100, 255),
	Color3.fromRGB(255, 81, 200),
	Color3.fromRGB(255, 81, 200),
}

local turbo, shockwave, rescue -- power-up effects, defined further down
local fellWhy -- why someone fell, for the log (below)
local ballImpact -- a ball-on-ball hit, felt (below)

local state = nil -- the running game: { ctx, arena (HexArena), folder, balls = {}, riding = { [id] = ball }, bots = { [id] = brain } }

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function rootOf(model: Model?): BasePart?
	local root = model and model:FindFirstChild("HumanoidRootPart")
	return root and root:IsA("BasePart") and root or nil
end

local function participantById(id: string)
	if not state then
		return nil
	end
	for _, participant in state.ctx.Seats do
		if participant.Id == id then
			return participant
		end
	end
	return nil
end

local function participantOfModel(model: Model)
	local id = model and model:GetAttribute(RoundInfo.IdAttr)
	if not id then
		local player = Players:GetPlayerFromCharacter(model)
		id = player and tostring(player.UserId)
	end
	return id and participantById(id) or nil
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- ═══ the arena (Server/Rounds/HexArena) ════════════════════════════════════════

local function standSpot(): CFrame
	return state.arena:StandSpot()
end

-- ═══ the floor, cell by cell ═════════════════════════════════════════════════════

local function cellAt(position: Vector3)
	return state.arena:CellAt(position)
end

-- Whether there is floor that will stay at this point (a warning cell counts as gone).
local function floorAt(position: Vector3): boolean
	return state.arena:FloorAt(position)
end

local function isEdge(cell): boolean
	return state.arena:IsEdge(cell)
end

local function solidCells()
	return state.arena:SolidCells()
end

-- The next cell to go: a random one off the edge, or once enough is gone, a hole anywhere,
-- more likely where people are.
local function pickCell()
	local solid = solidCells()
	if #solid <= Arena.KeepCells then
		return nil
	end
	local gone = 1 - #solid / state.arena.cellCount
	if gone < Arena.HolesAfter then
		local edge = {}
		for _, cell in solid do
			if isEdge(cell) then
				table.insert(edge, cell)
			end
		end
		return edge[math.random(1, math.max(#edge, 1))] or solid[math.random(1, #solid)]
	end
	local spots = {}
	for _, participant in state.ctx.Alive() do
		local root = rootOf(state.ctx.Character(participant))
		if root then
			table.insert(spots, root.Position)
		end
	end
	local weights, total = {}, 0
	for index, cell in solid do
		local centre = cell.model:GetPivot().Position
		local weight = 1
		for _, spot in spots do
			if flat(spot - centre).Magnitude < 20 then
				weight += 3
			end
		end
		weights[index] = weight
		total += weight
	end
	local roll = math.random() * total
	for index, cell in solid do
		roll -= weights[index]
		if roll <= 0 then
			return cell
		end
	end
	return solid[#solid]
end

local function dropCell(cell)
	state.arena:DropCell(cell, Arena.Warn)
end

local function safeSpot(from: Vector3): Vector3
	return state.arena:SafeSpot(from)
end

-- ═══ balls ════════════════════════════════════════════════════════════════════════

local function radius(): number
	return Ball.Size / 2
end

-- Each ball's number, for keying a pair of balls (GetDebugId is plugin-only).
local ballNumbers = setmetatable({}, { __mode = "k" })
local nextBallNumber = 0

local function makeBall(position: Vector3): BasePart
	local ball = Instance.new("Part")
	nextBallNumber += 1
	ballNumbers[ball] = nextBallNumber
	ball.Name = "Ball"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.one * Ball.Size
	ball.Material = Enum.Material.SmoothPlastic
	ball.Color = Color3.fromRGB(250, 250, 250)
	ball.CustomPhysicalProperties = PhysicalProperties.new(0.6, 0.3, 0.55, 1, 1)
	ball.Position = position
	ball:SetAttribute(BumpGame.RiderAttr, "")
	-- a stripe so it reads as rolling
	local stripe = Instance.new("Decal")
	stripe.Texture = "rbxasset://textures/SpawnLocation.png"
	stripe.Transparency = 0.6
	stripe.Face = Enum.NormalId.Front
	stripe.Parent = ball
	ball.Parent = state.folder
	ball:SetNetworkOwner(nil)
	CollectionService:AddTag(ball, BumpGame.BallTag)
	table.insert(state.balls, ball)
	ball.Touched:Connect(function(other)
		BumpGame.OnTouch(ball, other)
	end)
	return ball
end

local function riderOf(ball: BasePart)
	local id = ball:GetAttribute(BumpGame.RiderAttr)
	return id and id ~= "" and participantById(id) or nil
end

local function freeBalls()
	local list = {}
	for _, ball in state.balls do
		if ball.Parent and not riderOf(ball) then
			table.insert(list, ball)
		end
	end
	return list
end

local function setRiding(model: Model, riding: boolean)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			if riding then
				if part:GetAttribute("BumpRideSolid") == nil then
					part:SetAttribute("BumpRideSolid", part.CanCollide)
				end
				part.CanCollide = false
				part.Massless = true
			elseif part:GetAttribute("BumpRideSolid") ~= nil then
				part.CanCollide = part:GetAttribute("BumpRideSolid")
				part:SetAttribute("BumpRideSolid", nil)
				part.Massless = false
			end
		end
	end
end

-- Puts a participant on a ball. Players' clients take over from here (BallRider); a bot is
-- held on top by the server.
local function mount(participant, ball: BasePart)
	local character = state.ctx.Character(participant)
	if not character or riderOf(ball) or state.riding[participant.Id] then
		return false
	end
	ball:SetAttribute(BumpGame.RiderAttr, participant.Id)
	ball.Color = Bots.SeatColor(participant.Seat)
	state.riding[participant.Id] = ball
	character:SetAttribute(BumpGame.WobbleAttr, 0)
	if participant.Player then
		ball:SetNetworkOwner(participant.Player)
	else
		local root = rootOf(character)
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		setRiding(character, true)
		humanoid.PlatformStand = true
		local attachment = Instance.new("Attachment")
		attachment.Name = "BumpRide"
		attachment.Parent = root
		local hold = Instance.new("AlignPosition")
		hold.Name = "BumpRideHold"
		hold.Mode = Enum.PositionAlignmentMode.OneAttachment
		hold.Attachment0 = attachment
		hold.RigidityEnabled = true
		hold.Parent = root
		local upright = Instance.new("AlignOrientation")
		upright.Name = "BumpRideUpright"
		upright.Mode = Enum.OrientationAlignmentMode.OneAttachment
		upright.Attachment0 = attachment
		upright.RigidityEnabled = true
		upright.Parent = root
		state.bots[participant.Id].physics = BallPhysics.NewState()
		character:SetAttribute(Remotes.MoveAttr, "Ride")
	end
	return true
end

local function unmount(participant)
	local ball = state.riding[participant.Id]
	if not ball then
		return
	end
	state.riding[participant.Id] = nil
	if ball.Parent then
		ball:SetAttribute(BumpGame.RiderAttr, "")
		ball.Color = Color3.fromRGB(250, 250, 250)
		ball:SetNetworkOwner(nil)
	end
	local character = state.ctx.Character(participant)
	if character and participant.Bot then
		local root = rootOf(character)
		for _, name in { "BumpRide", "BumpRideHold", "BumpRideUpright" } do
			local thing = root and root:FindFirstChild(name)
			if thing then
				thing:Destroy()
			end
		end
		setRiding(character, false)
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.PlatformStand = false
		end
		character:SetAttribute(Remotes.MoveAttr, "Run")
	end
end

-- Who last hit someone and when: if they fall soon after, they were knocked off, and the one
-- who did it is named ("ELIMINATED BY X", RoundServer's Eliminate).
-- `how` says with what ("ram", "runover", "dive", "shove", "pound", "shockwave"), for the card.
local HOW = { Dive = "dive", Bump = "shove", Pound = "pound" }
local function blame(victim, attacker, how: string?)
	victim.LastHitAt = os.clock()
	victim.LastHitBy = attacker ~= victim and attacker or nil
	victim.LastHitHow = how
end

-- Knocked flat and thrown: off a ball, or hit on foot.
local function knock(participant, velocity: Vector3)
	local character = state.ctx.Character(participant)
	if not character then
		return
	end
	participant.LastHitAt = os.clock()
	unmount(participant)
	character:SetAttribute(Ragdoll.Attribute, true)
	character:SetAttribute(Remotes.MoveAttr, "Knocked")
	BumpServer.Throw(character, velocity)
	if participant.Bot then
		local root = rootOf(character)
		if root then
			root.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * 8
		end
	end
	local mine = os.clock()
	participant.KnockedAt = mine
	task.delay(Hits.Ragdoll, function()
		if participant.KnockedAt == mine and character.Parent then
			character:SetAttribute(Ragdoll.Attribute, false)
			character:SetAttribute(Remotes.MoveAttr, "Run")
		end
	end)
end

-- A ball's velocity just before this touch. A touch is reported after physics has already
-- bounced the two apart, so the velocities then are separating ones; the last frame's are the
-- ones that met (kept every Heartbeat in Run).
local lastVelocity = setmetatable({}, { __mode = "k" })

local function ballVelocity(ball: BasePart): Vector3
	return lastVelocity[ball] or ball.AssemblyLinearVelocity
end

local pairCooldown = {}

-- `knockOff` throws a rider straight off (a dive) instead of wobbling them first.
local function hitRider(victimBall: BasePart, attackerBall: BasePart, direction: Vector3, closing: number, knockOff: boolean?, by, how: string?)
	local victim = riderOf(victimBall)
	local push = direction * (Hits.Push + closing * Hits.PushShare)
	if not victim then
		-- a free ball just gets pushed
		victimBall.AssemblyLinearVelocity += push
		return
	end
	local character = state.ctx.Character(victim)
	if not character then
		return
	end
	blame(victim, by or riderOf(attackerBall), how or "ram")
	if PowerUps.Shielded(character) then
		-- a Shield power-up: the bubble takes it
		Remotes.Fx("Bump", { Position = (victimBall.Position + attackerBall.Position) / 2 })
		return false
	end
	local wobbling = (character:GetAttribute(BumpGame.WobbleAttr) or 0) > now()
	state.folder:SetAttribute("Hits", (state.folder:GetAttribute("Hits") or 0) + 1)
	if wobbling or knockOff then
		state.folder:SetAttribute("KnockedOff", (state.folder:GetAttribute("KnockedOff") or 0) + 1)
		print(string.format("[Bump] %s knocked off their ball (%s)", victim.Name, knockOff and "dive" or "second hit"))
		-- off you go, the way you were hit
		knock(victim, push * 1.2 + Vector3.new(0, Hits.FootLift, 0))
		victimBall.AssemblyLinearVelocity += push
		Remotes.Fx("Bump", { Position = (victimBall.Position + attackerBall.Position) / 2 })
		return true
	else
		character:SetAttribute(BumpGame.WobbleAttr, now() + Hits.Wobble)
		if victim.Player then
			Remotes.You(victim.Player, "BallHit", { Impulse = push })
		else
			victimBall.AssemblyLinearVelocity += push
		end
	end
	Remotes.Fx("Bump", { Position = (victimBall.Position + attackerBall.Position) / 2 })
	return false
end

-- A ball hitting a ball, felt (the user: ramming someone had no "feel good feeling behind the
-- impact"): everyone sees a hit sized by how hard it was (Fx "BallHit": BumpFx's flash, ring,
-- sparks, word and thump; BallRider's freeze and camera punch for the riders involved), and the
-- hitter's ball carries on through at Hits.Follow of its speed instead of bouncing back off.
-- `hitterVelocity` nil for a head-on hit (both bounce).
function ballImpact(hitter: BasePart, hit: BasePart, direction: Vector3, closing: number, knockedOff: boolean?, hitterVelocity: Vector3?)
	local strength = math.clamp((closing - Hits.Min) / math.max(Hits.Hard - Hits.Min, 1), 0, 1)
	local follow = hitterVelocity and flat(hitterVelocity) * Hits.Follow or nil
	local pause = Hits.Pause + Hits.PauseHard * strength
	Remotes.Fx("BallHit", {
		Position = (hitter.Position + hit.Position) / 2,
		Normal = direction,
		Strength = strength,
		Hitter = hitter,
		Hit = hit,
		Off = knockedOff == true,
		Follow = follow,
		Pause = pause,
	})
	-- a ball the server drives (a bot's) carries on here; a player's own client does it (BallRider)
	if follow and not hitter:GetNetworkOwner() then
		task.delay(pause, function()
			if hitter.Parent then
				hitter.AssemblyLinearVelocity = Vector3.new(follow.X, hitter.AssemblyLinearVelocity.Y, follow.Z)
			end
		end)
	end
end

function BumpGame.OnTouch(ball: BasePart, other: BasePart)
	if not state or not ball.Parent then
		return
	end
	if CollectionService:HasTag(other, BumpGame.BallTag) then
		-- each pair once: the touch fires on both balls
		local mine, theirs = ballNumbers[ball] or 0, ballNumbers[other] or 0
		if mine > theirs then
			return
		end
		local key = mine .. ":" .. theirs
		if (pairCooldown[key] or 0) > os.clock() then
			return
		end
		local n = flat(other.Position - ball.Position)
		if n.Magnitude < 0.01 then
			return
		end
		n = n.Unit
		local va, vb = ballVelocity(ball), ballVelocity(other)
		local closing = (va - vb):Dot(n)
		if closing < Hits.Min then
			return
		end
		pairCooldown[key] = os.clock() + Hits.Debounce
		local aToward, bToward = va:Dot(n), vb:Dot(-n)
		-- the faster one into the hit is the attacker; head on and fast, both are hit
		if aToward > Hits.Min * 0.6 and bToward > Hits.Min * 0.6 then
			local offA = hitRider(other, ball, n, closing * 0.6)
			local offB = hitRider(ball, other, -n, closing * 0.6)
			ballImpact(ball, other, n, closing, offA or offB, nil)
		elseif aToward >= bToward then
			local off = hitRider(other, ball, n, closing)
			ballImpact(ball, other, n, closing, off, va)
		else
			local off = hitRider(ball, other, -n, closing)
			ballImpact(other, ball, -n, closing, off, vb)
		end
		return
	end
	-- someone on foot
	local model = other:FindFirstAncestorOfClass("Model")
	if not model or not CollectionService:HasTag(model, Remotes.BodyTag) then
		return
	end
	local victim = participantOfModel(model)
	if not victim or victim.Out or state.riding[victim.Id] or riderOf(ball) == victim then
		return
	end
	local velocity = flat(ballVelocity(ball))
	if velocity.Magnitude < Hits.FootMin or (victim.HitAt or 0) > os.clock() or PowerUps.Shielded(model) then
		return
	end
	victim.HitAt = os.clock() + 0.6
	blame(victim, riderOf(ball), "runover")
	state.folder:SetAttribute("Runover", (state.folder:GetAttribute("Runover") or 0) + 1)
	knock(victim, velocity.Unit * Hits.FootPush + Vector3.new(0, Hits.FootLift, 0))
	Remotes.Fx("Bump", { Position = other.Position })
end

-- Someone on foot hit a rider with a move (BumpServer's body hits): it hits their ball, as a
-- ball would. A dive knocks them straight off; a shove or a ground pound's shock wobbles them.
local BODY_HIT_SPEED = { Dive = 45, Bump = 22, Pound = 30 }

local function onBodyHit(attacker: Model?, target: Model, kind: string, throw: Vector3, reach: number): boolean
	if not state then
		return false
	end
	local victim = participantOfModel(target)
	local attackerRoot = rootOf(attacker)
	if not victim or victim.Out or not attackerRoot then
		return false
	end
	local ball = state.riding[victim.Id]
	if ball and ball.Parent then
		-- riding: measured to their ball, which is what a diver actually reaches
		local surface = (ball.Position - attackerRoot.Position).Magnitude - radius()
		if surface > reach then
			return true -- out of reach: dealt with, nothing happens
		end
		local direction = flat(ball.Position - attackerRoot.Position)
		direction = direction.Magnitude > 0.1 and direction.Unit or Vector3.new(0, 0, 1)
		print(string.format("[Bump] %s on %s's ball", kind, victim.Name))
		-- a dive knocks a rider straight off (the user: diving into a player on a ball should
		-- knock them off); a shove or a pound's shock wobbles them like a ball hit
		local off = hitRider(ball, attackerRoot, direction, BODY_HIT_SPEED[kind] or 22, kind == "Dive", attacker and participantOfModel(attacker) or nil, HOW[kind])
		-- a dive that knocks them off lands you on their ball: you've stolen it (the user: "When
		-- knocking a player off a ball with my jump dive, I should automatically be placed ontop
		-- of the ball - essentially stealing it from them"). It keeps rolling with the hit.
		if off and kind == "Dive" then
			local thief = participantOfModel(attacker)
			if thief and not thief.Out and not state.riding[thief.Id] and mount(thief, ball) then
				print(string.format("[Bump] %s stole %s's ball", thief.Name, victim.Name))
				state.folder:SetAttribute("Steals", (state.folder:GetAttribute("Steals") or 0) + 1)
			end
		end
		return true
	end
	-- on foot in the game (a bot or a player): thrown and knocked flat
	local victimRoot = rootOf(target)
	if not victimRoot or (victimRoot.Position - attackerRoot.Position).Magnitude > reach or PowerUps.Shielded(target) then
		return true
	end
	blame(victim, attacker and participantOfModel(attacker) or nil, HOW[kind])
	if kind == "Bump" then
		-- a shove staggers them back on their feet; dives and pounds knock them flat
		BumpServer.Shove(target, throw)
	else
		knock(victim, throw)
	end
	Remotes.Fx("Bump", { Position = (victimRoot.Position + attackerRoot.Position) / 2, Kind = kind })
	return true
end

-- A ground pound landing on the platform: a ripple goes out through the tiles (every client
-- draws it, BumpFx), and every rider whose ball it reaches is hit as by a ball.
local lastPound = {}

-- A ripple out through the tiles from `position` (every client draws it, BumpFx): riders whose
-- ball it reaches are hit as by a ball. A Shockwave power-up's (`throwOnFoot`) also throws
-- whoever is on foot in reach.
local function ripple(source, position: Vector3, reach: number, sourcePart: BasePart, throwOnFoot: boolean)
	local how = throwOnFoot and "shockwave" or "pound"
	Remotes.Fx("Ripple", { Position = position, Radius = reach, Speed = Pound.RippleSpeed, Height = Pound.RippleHeight })
	for id, ball in state.riding do
		local victim = participantById(id)
		if victim and victim ~= source and ball.Parent then
			local offset = flat(ball.Position - position)
			local onTheFloor = ball.Position.Y - ORIGIN.Y < radius() + 3
			if offset.Magnitude <= reach and onTheFloor then
				task.delay(offset.Magnitude / Pound.RippleSpeed, function()
					if state and state.riding[id] == ball then
						local direction = offset.Magnitude > 0.1 and offset.Unit or Vector3.new(0, 0, 1)
						print(string.format("[Bump] ripple reached %s", victim.Name))
						hitRider(ball, sourcePart, direction, 16, nil, source, how)
					end
				end)
			end
		end
	end
	if not throwOnFoot then
		return
	end
	for _, victim in state.ctx.Alive() do
		local character = state.ctx.Character(victim)
		local victimRoot = rootOf(character)
		if victim ~= source and victimRoot and not state.riding[victim.Id] then
			local offset = flat(victimRoot.Position - position)
			if offset.Magnitude <= reach and math.abs(victimRoot.Position.Y - position.Y) < 10 then
				task.delay(offset.Magnitude / Pound.RippleSpeed, function()
					if state and not victim.Out and not state.riding[victim.Id] and not PowerUps.Shielded(character) then
						local away = offset.Magnitude > 0.1 and offset.Unit or Vector3.new(0, 0, 1)
						blame(victim, source, how)
						knock(victim, away * Hits.FootPush * 0.6 + Vector3.new(0, Hits.FootLift, 0))
					end
				end)
			end
		end
	end
end

local function onPound(player: Player, position)
	if not state or typeof(position) ~= "Vector3" then
		return
	end
	local participant = participantById(tostring(player.UserId))
	local root = rootOf(player.Character)
	if not participant or participant.Out or not root or state.riding[participant.Id] then
		return
	end
	if (root.Position - position).Magnitude > 8 or (lastPound[player] or 0) > os.clock() then
		return
	end
	-- on the platform, near its top
	if math.abs(position.Y - ORIGIN.Y) > 8 or not cellAt(position) then
		return
	end
	lastPound[player] = os.clock() + 0.5
	ripple(participant, position, Pound.RippleRadius, root, false)
end

-- ═══ client requests ══════════════════════════════════════════════════════════════

local function onMount(player: Player, ball)
	if not state or typeof(ball) ~= "Instance" or not CollectionService:HasTag(ball, BumpGame.BallTag) then
		return
	end
	local participant = participantById(tostring(player.UserId))
	local character = player.Character
	local root = rootOf(character)
	if not participant or participant.Out or not root or Ragdoll.IsDown(character) then
		return
	end
	-- close to the top of the ball (with slack for latency)
	local top = ball.Position + Vector3.new(0, radius(), 0)
	if (root.Position - top).Magnitude > Ball.MountReach + 6 then
		return
	end
	mount(participant, ball)
end

local function onDismount(player: Player)
	if not state then
		return
	end
	local participant = participantById(tostring(player.UserId))
	if participant then
		unmount(participant)
	end
end

-- ═══ bots (Server/Rounds/BumpBots) ════════════════════════════════════════════════

BumpBots.Bind({
	State = function()
		return state
	end,
	FloorAt = function(position)
		return floorAt(position)
	end,
	SafeSpot = function(from)
		return safeSpot(from)
	end,
	FreeBalls = function()
		return freeBalls()
	end,
	Radius = function()
		return radius()
	end,
	Mount = function(participant, ball)
		return mount(participant, ball)
	end,
	ParticipantById = function(id)
		return participantById(id)
	end,
	OnBodyHit = function(...)
		return onBodyHit(...)
	end,
})

-- ═══ power-ups (Server/Rounds/PowerUps) ═══════════════════════════════════════════

-- Turbo on a ball: a full dash. A player's own client drives their ball, so it's told to.
function turbo(participant, stats): boolean
	local ball = state and state.riding[participant.Id]
	if not ball or not ball.Parent then
		return false -- on foot: a speed boost (PowerUps does it)
	end
	if participant.Player then
		Remotes.You(participant.Player, "Turbo", { Scale = stats.Dash })
		return true
	end
	local brain = state.bots[participant.Id]
	if not brain or not brain.physics then
		return false
	end
	local targetRoot = brain.target and rootOf(state.ctx.Character(brain.target))
	local direction = targetRoot and flat(targetRoot.Position - ball.Position) or Vector3.zero
	local planar = BallPhysics.Boost(brain.physics, flat(ball.AssemblyLinearVelocity), direction, stats.Dash)
	ball.AssemblyLinearVelocity = Vector3.new(planar.X, ball.AssemblyLinearVelocity.Y, planar.Z)
	brain.dashUntil = os.clock() + 0.45
	return true
end

function shockwave(participant, at: Vector3, reach: number)
	if not state then
		return
	end
	local root = rootOf(state.ctx.Character(participant))
	ripple(participant, Vector3.new(at.X, ORIGIN.Y, at.Z), reach, root, true)
end

-- Second Chance: back onto floor that will stay, dropped in from a little above.
function rescue(participant)
	if not state then
		return
	end
	unmount(participant)
	local character = state.ctx.Character(participant)
	local root = rootOf(character)
	if not character or not root then
		return
	end
	local spot = safeSpot(ORIGIN) + Vector3.new(0, 8, 0)
	participant.KnockedAt = nil
	character:SetAttribute(Ragdoll.Attribute, false)
	character:SetAttribute(Remotes.MoveAttr, "Fall")
	root.AssemblyLinearVelocity = Vector3.zero
	character:PivotTo(CFrame.new(spot) * character:GetPivot().Rotation)
	if participant.Player then
		Remotes.You(participant.Player, "Rescue", { Position = spot })
	end
end

-- ═══ the game ═════════════════════════════════════════════════════════════════════

function BumpGame.Init()
	BumpServer.OnAct("Mount", onMount)
	BumpServer.OnAct("Pound", onPound)
	BumpServer.OnAct("Dismount", onDismount)
end

function BumpGame.Setup(ctx)
	local arena = HexArena.new({ Origin = ORIGIN, Rings = Arena.Rings, Tile = Arena.Tile, Colors = RING_COLORS, Edges = RING_EDGES })
	state = { ctx = ctx, arena = arena, folder = arena.folder, balls = {}, riding = {}, bots = {} }
	BumpServer.SetBodyHitHandler(onBodyHit)
	PowerUps.SetGame({ Turbo = turbo, Shockwave = shockwave, Rescue = rescue })
	-- the arena plays itself in on every client before anyone goes on it (RoundServer waits this)
	return HexArena.ShowSeconds(Arena.Rings)
end

-- Once the arena has landed: everyone onto it, and the balls.
function BumpGame.Place(ctx)
	local alive = ctx.Alive()
	-- everyone round the second ring in from the edge, facing in
	local spots = Hex.Spread(math.max(Arena.Rings - 2, 1), #alive, Arena.Tile)
	for index, participant in alive do
		local spot = ORIGIN + spots[index] + Vector3.new(0, 4, 0)
		local cframe = CFrame.lookAt(spot, Vector3.new(ORIGIN.X, spot.Y, ORIGIN.Z))
		if participant.Bot then
			local model = ctx.SpawnBot(participant, cframe)
			model:SetAttribute(Ragdoll.Attribute, false)
			model:SetAttribute(Remotes.MoveAttr, "Run")
			-- a calm start: no power-ups or dashes for the first few seconds of play (bunched up at
			-- the start, they used to wipe out half the field in the first three)
			state.bots[participant.Id] = { calmUntil = os.clock() + Rounds.Intro + 2.5 + math.random() * 3 }
		else
			local character = ctx.Character(participant)
			if character then
				character:SetAttribute(Ragdoll.Attribute, false)
				character:PivotTo(cframe)
			end
		end
	end
	-- one ball fewer than players, round the middle
	for _, point in Hex.Spread(math.min(2, Arena.Rings), math.max(#alive - 1, 1), Arena.Tile) do
		makeBall(ORIGIN + point + Vector3.new(0, radius() + 0.5, 0))
	end
end

function BumpGame.OnEliminated(ctx, participant)
	if not state then
		return
	end
	unmount(participant)
	local character = ctx.Character(participant)
	if participant.Bot then
		if participant.Model then
			participant.Model:Destroy()
			participant.Model = nil
		end
	elseif character then
		-- a player's body keeps falling while their knockout camera watches it (KnockoutCam), then
		-- goes to the stand
		local stand = standSpot()
		task.delay(RoundInfo.KnockoutHold, function()
			if character.Parent then
				character:SetAttribute(Ragdoll.Attribute, false)
				character:PivotTo(stand)
			end
		end)
	end
	-- keep one ball fewer than players: pop a free one
	local spare = freeBalls()
	local riders = 0
	for _ in state.riding do
		riders += 1
	end
	if #spare + riders > math.max(#ctx.Alive() - 1, 1) and spare[1] then
		local ball = spare[1]
		Remotes.Fx("Bump", { Position = ball.Position })
		table.remove(state.balls, table.find(state.balls, ball))
		ball:Destroy()
	end
end

-- Why someone fell: knocked off (hit in the last few seconds; and by whom, if anyone) or on
-- their own. Returns (reason, by participant or nil, how or nil), as ctx.Eliminate takes them.
function fellWhy(participant)
	if os.clock() - (participant.LastHitAt or -100) < 4 then
		return "knocked off", participant.LastHitBy, participant.LastHitHow
	end
	return "fell alone", nil, nil
end

function BumpGame.Run(ctx)
	local startedAt = now()
	ctx.SetClock(Arena.TimeLimit)
	local nextDrop = startedAt + Arena.Grace
	local floor = ORIGIN.Y - Arena.FallDepth
	local last = os.clock()
	while true do
		local dt = math.min(RunService.Heartbeat:Wait(), 0.1)
		local clock = os.clock()
		dt = math.min(clock - last, 0.1)
		last = clock
		local alive = ctx.Alive()
		if #alive <= 1 or now() - startedAt >= Arena.TimeLimit then
			break
		end
		-- the floor crumbles a cell at a time, faster and faster
		if now() >= nextDrop then
			local cell = pickCell()
			if cell then
				dropCell(cell)
			end
			local ramp = math.clamp((now() - startedAt - Arena.Grace) / Arena.DropRamp, 0, 1)
			nextDrop = now() + Arena.DropStart + (Arena.DropEnd - Arena.DropStart) * ramp
			-- the music follows how much floor is gone and how many are out
			local solid = #solidCells()
			local floorGone = 1 - (solid - Arena.KeepCells) / math.max(state.arena.cellCount - Arena.KeepCells, 1)
			local total = #ctx.Seats
			local out = total > 1 and (total - #ctx.Alive()) / (total - 1) or 0
			ctx.SetIntensity(math.max(floorGone, out * 0.85, ramp * 0.6))
		end
		for _, participant in alive do
			local character = ctx.Character(participant)
			local root = rootOf(character)
			if not character or not character.Parent or not root then
				ctx.Eliminate(participant, "no body")
			elseif root.Position.Y < floor then
				if not PowerUps.TryRescue(participant) then
					ctx.Eliminate(participant, fellWhy(participant))
				end
			elseif participant.Bot then
				local brain = state.bots[participant.Id]
				local ball = state.riding[participant.Id]
				if ball then
					if ball.Parent then
						BumpBots.Riding(participant, brain, character, ball, dt)
					else
						unmount(participant)
					end
				else
					BumpBots.OnFoot(participant, brain, character, dt)
				end
			end
		end
		for _, ball in state.balls do
			if ball.Parent then
				lastVelocity[ball] = ball.AssemblyLinearVelocity
				-- a rider whose ball has dropped off the arena has fallen with it. Judged by the
				-- ball: a player's own body can stop updating on the server as it falls (seen
				-- 2026-11-13: frozen at y -35 while their client fell past -500), so waiting for
				-- the body knocked them out late and a Second Chance never caught them
				local rider = riderOf(ball)
				if rider and not rider.Out and ball.Position.Y < floor then
					unmount(rider)
					if not PowerUps.TryRescue(rider) then
						ctx.Eliminate(rider, fellWhy(rider))
					end
				end
			end
		end
		-- balls that fell: gone, and a fresh one at the middle if there are too few
		for index = #state.balls, 1, -1 do
			local ball = state.balls[index]
			if not ball.Parent or ball.Position.Y < floor - 20 then
				local rider = riderOf(ball)
				if rider then
					unmount(rider)
				end
				table.remove(state.balls, index)
				if ball.Parent then
					ball:Destroy()
				end
				if #state.balls < math.max(#ctx.Alive() - 1, 1) then
					makeBall(ORIGIN + Vector3.new(0, radius() + 6, 0))
				end
			end
		end
	end
end

function BumpGame.Cleanup(ctx)
	if not state then
		return
	end
	for _, participant in ctx.Seats do
		unmount(participant)
		local character = ctx.Character(participant)
		if character then
			character:SetAttribute(Ragdoll.Attribute, false)
			character:SetAttribute(BumpGame.WobbleAttr, 0)
		end
	end
	BumpServer.SetBodyHitHandler(nil)
	state.arena:Destroy()
	state = nil
	table.clear(pairCooldown)
end

return BumpGame
