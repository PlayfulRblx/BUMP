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
local BotMind = require("@GameServer/Rounds/BotMind")
local World = require("@Shared/World")

local Ball = Tuning.Of("Ball")
local Pound = Tuning.Of("Pound")
local Hits = Tuning.Of("BumpHits")
local Arena = Tuning.Of("BumpArena")
local Rounds = Tuning.Of("Rounds")
local BumpMoves = Tuning.Of("Bump")

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

-- ═══ bots ═════════════════════════════════════════════════════════════════════════

-- The nearest ball someone else rides that's coming at `position` fast: the ball, how far.
local function incoming(participant, position: Vector3, within: number)
	local best, bestDistance = nil, within
	for id, ball in state.riding do
		if id ~= participant.Id and ball.Parent then
			local velocity = flat(ball.AssemblyLinearVelocity)
			local toMe = flat(position - ball.Position)
			local distance = toMe.Magnitude
			if distance < bestDistance and distance > 0.1 and velocity.Magnitude > Hits.Min
				and velocity.Unit:Dot(toMe.Unit) > 0.8 then
				best, bestDistance = ball, distance
			end
		end
	end
	return best, bestDistance
end

-- The nearest other contestant (riding or not) to `position`: participant, distance.
local function nearestOther(participant, position: Vector3)
	local best, bestDistance = nil, math.huge
	for _, other in state.ctx.Alive() do
		if other ~= participant then
			local ball = state.riding[other.Id]
			local root = rootOf(state.ctx.Character(other))
			local at = ball and ball.Parent and ball.Position or root and root.Position
			if at then
				local distance = flat(at - position).Magnitude
				if distance < bestDistance then
					best, bestDistance = other, distance
				end
			end
		end
	end
	return best, bestDistance
end

-- Whether a bot uses its power-up now (a roll of the dice each frame it would make sense).
-- `turbo`: it's a good moment for a Turbo; `wobbling`: it's been hit once already.
local function botPowerUp(participant, position: Vector3, turbo: boolean, wobbling: boolean)
	local power = participant.Power
	local stats = PowerUps.Ready(participant)
	local brain = state.bots[participant.Id]
	if not stats or math.random() > 0.08 or (brain and (brain.calmUntil or 0) > os.clock()) then
		return
	end
	local threat, distance = incoming(participant, position, 16)
	local use = false
	if power.Id == "Shield" then
		use = threat ~= nil or (wobbling and select(2, nearestOther(participant, position)) < 16)
	elseif power.Id == "Turbo" then
		use = turbo
	elseif power.Id == "Shockwave" then
		local _, near = nearestOther(participant, position)
		use = near < stats.Radius * 0.75
	end
	local _ = distance
	if use then
		PowerUps.Use(participant)
	end
end

-- Who a riding bot goes for, by its personality: close ones, ones near an edge or wobbling
-- (finish them off), players (bullies), anyone on foot (run them over); a little stickiness so
-- it doesn't flit between targets, and some chance. Nil if nobody's worth it (a coward waits).
local function chooseTarget(participant, brain, mind, position: Vector3)
	local best, bestScore = nil, -math.huge
	for _, other in state.ctx.Alive() do
		if other ~= participant then
			local model = state.ctx.Character(other)
			local root = rootOf(model)
			local ball = state.riding[other.Id]
			local at = ball and ball.Parent and ball.Position or root and root.Position
			if at and not PowerUps.Shielded(model) then
				local distance = flat(at - position).Magnitude
				if distance < 90 then
					local holeDistance = BotMind.HoleDistance(state.arena, at, 20, 4)
					local edgeness = 1 - math.clamp(holeDistance / 20, 0, 1)
					local wobbling = (model:GetAttribute(BumpGame.WobbleAttr) or 0) > now()
					local score = -distance / 25
						+ mind.EdgeBias * edgeness * 1.5
						+ (wobbling and mind.WobbleBias or 0)
						+ (other.Player and mind.HumanBias or 0)
						+ (ball and 0 or 0.4)
						+ (other == brain.target and 0.6 or 0)
						+ math.random() * mind.Random
					if score > bestScore then
						best, bestScore = other, score
					end
				end
			end
		end
	end
	-- the timid wait for a good chance; everyone hunts once it's down to a few
	local fewLeft = #state.ctx.Alive() <= 3
	if best and not fewLeft and bestScore < 1.2 - mind.Aggro * 2 then
		return nil
	end
	return best
end

-- A bot on foot leaps at a rider to knock them off and take the ball, as a player's dive does.
local function botDive(participant, brain, character: Model, target, ball: BasePart)
	local root = rootOf(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local targetModel = state.ctx.Character(target)
	if not root or not humanoid or not targetModel then
		return
	end
	brain.diveAt = os.clock()
	local direction = flat(ball.Position - root.Position)
	direction = direction.Magnitude > 0.1 and direction.Unit or Vector3.new(0, 0, 1)
	humanoid.Jump = true
	character:SetAttribute(Remotes.MoveAttr, "Dive")
	root.AssemblyLinearVelocity = direction * 52 + Vector3.new(0, 30, 0)
	task.delay(0.28, function()
		if not state or participant.Out or state.riding[participant.Id] or not character.Parent then
			return
		end
		if character:GetAttribute(Remotes.MoveAttr) == "Dive" then
			character:SetAttribute(Remotes.MoveAttr, "Run")
		end
		local throw = direction * BumpMoves.DivePush + Vector3.new(0, BumpMoves.DiveLift, 0)
		onBodyHit(character, targetModel, "Dive", throw, BumpMoves.BodyReach + 3)
	end)
end

local function botOnFoot(participant, brain, character: Model, dt: number)
	local root = rootOf(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or Ragdoll.IsDown(character) then
		return
	end
	local mind = BotMind.Of(participant)
	local position = root.Position
	local grounded = humanoid.FloorMaterial ~= Enum.Material.Air

	-- a ball rolling at me: jump out of its way, to the side with floor
	local threat = incoming(participant, position, 22)
	if threat and BotMind.Think(brain, mind) and math.random() < mind.Dodge then
		local along = flat(threat.AssemblyLinearVelocity).Unit
		local side = Vector3.new(-along.Z, 0, along.X)
		if not floorAt(position + side * 10) then
			side = -side
		end
		humanoid:MoveTo(position + side * 12)
		if grounded then
			humanoid.Jump = true
		end
		brain.dodgeUntil = os.clock() + 0.5
	end
	botPowerUp(participant, position, false, false)
	if (brain.dodgeUntil or 0) > os.clock() then
		return
	end

	-- a free ball I can get to over floor
	local best, bestDistance = nil, math.huge
	for _, ball in freeBalls() do
		local offset = flat(ball.Position - position)
		if offset.Magnitude < bestDistance and BotMind.PathClear(state.arena, position, offset, offset.Magnitude, 4) then
			best, bestDistance = ball, offset.Magnitude
		end
	end
	if best then
		humanoid:MoveTo(best.Position)
		if bestDistance < 12 and grounded then
			humanoid.Jump = true
		end
		if flat(best.Position - position).Magnitude < radius() + 2.6 then
			mount(participant, best)
		end
		botPowerUp(participant, position, bestDistance > 20, false)
		return
	end

	-- none free: go after a rider and leap at them to take theirs
	local victim, victimBall, victimDistance = nil, nil, 34
	for id, ball in state.riding do
		local other = participantById(id)
		if other and other ~= participant and ball.Parent then
			local distance = flat(ball.Position - position).Magnitude
			if distance < victimDistance and BotMind.PathClear(state.arena, position, ball.Position - position, distance, 4) then
				victim, victimBall, victimDistance = other, ball, distance
			end
		end
	end
	if victim then
		-- meet it where it's going, from the side if I can
		local lead = victimBall.Position + flat(victimBall.AssemblyLinearVelocity) * 0.3
		humanoid:MoveTo(floorAt(lead) and lead or victimBall.Position)
		local ready = os.clock() - (brain.diveAt or -10) > 2.6 - mind.Skill
		if ready and grounded and victimDistance < 9 + mind.Skill * 3 and BotMind.Think(brain, mind)
			and math.random() < mind.Steal then
			botDive(participant, brain, character, victim, victimBall)
		end
		return
	end

	-- nothing to do: keep to safe floor near the middle
	if (brain.wanderAt or 0) < os.clock() then
		brain.wanderAt = os.clock() + 1.5
		humanoid:MoveTo(safeSpot(ORIGIN + Hex.Position(math.random(-2, 2), math.random(-2, 2), Arena.Tile)))
	end
	local _ = dt
end

local function botRiding(participant, brain, character: Model, ball: BasePart, dt: number)
	local root = rootOf(character)
	if not root or not ball.Parent then
		return
	end
	local mind = BotMind.Of(participant)
	local physics = brain.physics
	local position = ball.Position
	local planar = flat(ball.AssemblyLinearVelocity)
	local speed = planar.Magnitude
	physics.Wobbling = (character:GetAttribute(BumpGame.WobbleAttr) or 0) > now()
	local nowClock = os.clock()

	-- decisions, at the speed this bot thinks
	if BotMind.Think(brain, mind) then
		brain.target = chooseTarget(participant, brain, mind, position)
		local threat = incoming(participant, position, 22)
		brain.threat = threat
		brain.dodging = threat ~= nil and math.random() < mind.Dodge * (0.5 + mind.Skill * 0.5)
		-- a wildcard sometimes fakes a charge and pulls out
		brain.feint = mind.Feints and math.random() < 0.15
	end

	local input = Vector3.zero
	local mode = "Idle"
	local targetModel = brain.target and state.ctx.Character(brain.target)
	local targetBall = brain.target and state.riding[brain.target.Id]
	local targetRoot = rootOf(targetModel)
	local targetAt = targetBall and targetBall.Parent and targetBall.Position or targetRoot and targetRoot.Position
	local toTarget = targetAt and flat(targetAt - position) or Vector3.zero

	-- 1. stay alive: is there floor all the way to where this roll would stop?
	local stopping = speed * speed / (2 * Ball.SkrrtDecel) + speed * mind.Reaction * 0.5 + radius()
	local lookAhead = stopping * (0.75 + 0.5 * mind.Skill)
	local heading = speed > 2 and planar.Unit or nil
	local danger = not floorAt(position) or (heading and not BotMind.PathClear(state.arena, position, heading, lookAhead, 3))
	local holeDistance, holeDirection = BotMind.HoleDistance(state.arena, position, 12, 3)
	if danger then
		mode = "Recover"
		local toSafe = flat(safeSpot(position) - position)
		toSafe = toSafe.Magnitude > 0.5 and toSafe.Unit or (heading and -heading or Vector3.zero)
		if heading and speed > 6 and heading:Dot(toSafe) < 0.3 then
			input = -heading -- pull back hard: a skrrt
		else
			input = toSafe
		end
	elseif physics.Wobbling then
		-- one more hit and I'm off: get away from everyone, toward the middle
		mode = "Wary"
		local other, distance = nearestOther(participant, position)
		local otherRoot = other and rootOf(state.ctx.Character(other))
		local away = otherRoot and distance < 24 and flat(position - otherRoot.Position).Unit or Vector3.zero
		local inward = flat(safeSpot(ORIGIN) - position)
		inward = inward.Magnitude > 0.5 and inward.Unit or Vector3.zero
		input = away + inward * 0.6
	elseif brain.threat and brain.threat.Parent and brain.dodging then
		local along = flat(brain.threat.AssemblyLinearVelocity)
		along = along.Magnitude > 0.1 and along.Unit or Vector3.new(1, 0, 0)
		if mind.Counter and speed > Ball.MaxSpeed * 0.5 then
			-- a bully meets it head on
			mode = "Counter"
			input = -along
		else
			mode = "Dodge"
			local side = Vector3.new(-along.Z, 0, along.X)
			if not BotMind.PathClear(state.arena, position, side, 12, 4) then
				side = -side
			end
			input = side
		end
	elseif targetAt then
		mode = "Hunt"
		local distance = toTarget.Magnitude
		-- come at them from the side away from their nearest edge, so the hit sends them off it
		local theirHole, theirHoleDirection = BotMind.HoleDistance(state.arena, targetAt, 30, 4)
		local out = theirHoleDirection or flat(targetAt - ORIGIN)
		out = out.Magnitude > 0.1 and out.Unit or Vector3.new(1, 0, 0)
		local fromThem = flat(position - targetAt)
		local onInside = fromThem.Magnitude > 0.1 and fromThem.Unit:Dot(-out) > 0.55
		local stage = targetAt - out * 16
		if (brain.backoffUntil or 0) > nowClock then
			input = -toTarget.Unit
		elseif distance < 9 and speed < 10 then
			-- pressed up against them with no speed: back away, then come again
			brain.backoffUntil = nowClock + 0.45 + math.random() * 0.4
			input = -toTarget.Unit
		elseif theirHole < 30 and not onInside and distance < 45 and floorAt(stage) then
			-- circle round to the inside, keeping clear of them on the way
			mode = "Stage"
			local toStage = flat(stage - position)
			input = toStage.Magnitude > 0.5 and toStage.Unit or Vector3.zero
			if distance < 12 then
				input += fromThem.Unit * 0.9
			end
		else
			-- go at them, a little ahead of where they're going
			local theirVelocity = targetBall and flat(targetBall.AssemblyLinearVelocity) or flat(targetRoot.AssemblyLinearVelocity)
			local lead = theirVelocity * math.clamp(distance / math.max(speed, 18), 0, 0.8) * mind.Skill
			local aim = flat(targetAt + lead - position)
			input = aim.Magnitude > 0.1 and BotMind.Wobble(aim.Unit, mind) or Vector3.zero
		end
	else
		-- waiting for a chance: drift round near the middle, never still
		if not brain.idleSpot or (brain.idleAt or 0) < nowClock then
			brain.idleAt = nowClock + 1.2 + math.random() * 1.5
			brain.idleSpot = safeSpot(ORIGIN + Hex.Position(math.random(-2, 2), math.random(-2, 2), Arena.Tile))
		end
		local toSpot = flat(brain.idleSpot - position)
		input = toSpot.Magnitude > 3 and toSpot.Unit or Vector3.zero
	end
	-- a margin from the edge, more for the careful (not while recovering or making the hit)
	if mode ~= "Recover" and mode ~= "Hunt" and holeDirection and holeDistance < 9 then
		input -= holeDirection * mind.Caution * (1 - holeDistance / 9) * 1.5
	end
	if input.Magnitude > 1 then
		input = input.Unit
	end

	-- the dash: charged when lined up on a target with floor all the way past them
	if physics.Charging then
		local abort = mode == "Recover" or mode == "Dodge" or (brain.feint and physics.Charge > 0.4)
		if abort then
			physics.Charging = false
			physics.Charge = 0
			brain.feint = false
		elseif physics.Charge >= (brain.chargeTo or 0.8) then
			local dashed = BallPhysics.Release(physics, planar, BotMind.Wobble(toTarget, mind), nowClock)
			if dashed then
				planar = dashed
				brain.dashUntil = nowClock + 0.45 -- the launch pose, as a player's
			end
		end
	elseif mode == "Hunt" and targetAt then
		local distance = toTarget.Magnitude
		local lined = distance > 9 and distance < 36 and (speed < 6 or planar.Unit:Dot(toTarget.Unit) > 0.85)
		-- my own ball has to stay on: floor past them by what a dash would carry
		local safe = BotMind.PathClear(state.arena, position, toTarget, math.min(distance + 14, 46), 4)
		if lined and safe and (brain.chargeAt or 0) < nowClock and (brain.calmUntil or 0) < nowClock then
			brain.chargeAt = nowClock + 0.35
			if math.random() < 0.25 + mind.Aggro * 0.4 then
				if PowerUps.Ready(participant, "Turbo") and math.random() < 0.5 then
					PowerUps.Use(participant)
				elseif BallPhysics.BeginCharge(physics, nowClock) then
					brain.chargeTo = 0.5 + mind.Skill * 0.5 * math.random() + mind.Aggro * 0.15
				end
			end
		end
	end

	planar = BallPhysics.Step(physics, planar, input, dt)
	ball.AssemblyLinearVelocity = Vector3.new(planar.X, ball.AssemblyLinearVelocity.Y, planar.Z)
	ball.AssemblyAngularVelocity = BallPhysics.Spin(planar, radius())

	-- held on top, facing the way it rolls
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local height = radius() + (humanoid and humanoid.HipHeight or 2) + root.Size.Y / 2
	local hold = root:FindFirstChild("BumpRideHold")
	local upright = root:FindFirstChild("BumpRideUpright")
	if hold then
		hold.Position = position + Vector3.new(0, height, 0)
	end
	local look = planar.Magnitude > 2 and planar.Unit or (toTarget.Magnitude > 0.1 and toTarget.Unit or Vector3.new(0, 0, -1))
	if upright then
		-- lean into the roll and bank into turns, as a player's rider does (BallRider)
		local before = brain.lastLook or look
		brain.lastLook = look
		local turn = math.atan2(before:Cross(look).Y, before:Dot(look)) / math.max(dt, 1 / 240)
		local bankTarget = math.clamp(turn * planar.Magnitude * 0.006, -math.rad(22), math.rad(22))
		brain.bank = (brain.bank or 0) + (bankTarget - (brain.bank or 0)) * math.min(1, 6 * dt)
		local lean = math.clamp(planar.Magnitude / Ball.MaxSpeed, 0, 1.4) * math.rad(physics.Skrrt and -18 or 10)
		upright.CFrame = CFrame.lookAt(Vector3.zero, look) * CFrame.Angles(-lean, 0, brain.bank)
	end
	local move = physics.Charging and "RideCharge"
		or nowClock < (brain.dashUntil or 0) and "RideDash"
		or physics.Skrrt and "RideSkrrt"
		or physics.Wobbling and "RideWobble"
		or "Ride"
	if character:GetAttribute(Remotes.MoveAttr) ~= move then
		character:SetAttribute(Remotes.MoveAttr, move)
	end
	brain.mode = mode
	botPowerUp(participant, position, false, physics.Wobbling)
end

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
						botRiding(participant, brain, character, ball, dt)
					else
						unmount(participant)
					end
				else
					botOnFoot(participant, brain, character, dt)
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
