--!nonstrict
--[[
	The bots' brains in BUMP (moved out of BumpGame, which runs the game and calls these each
	frame for every bot still in). Each bot has a mind dealt by BotMind (Bully, Opportunist, Coward,
	Wildcard, and a skill that sets how far ahead it looks, its aim and its reactions):

	- on foot: dodge a ball rolling at it, walk to a free ball by a path over floor and mount it,
	  or leap at a rider to knock them off and take theirs (the same body hit a player's dive is);
	- riding: survival first (floor all the way to where this roll would stop), then keep away
	  when wobbling, sidestep incoming balls (a bully meets them head on), else hunt a target its
	  personality picks, circling round to the side away from their nearest edge and dashing only
	  with floor past them; power-ups when they make sense.

	BumpGame hands over what the brains need of the running game with BumpBots.Bind(hooks):
	State() (the running game's state), FloorAt, SafeSpot, FreeBalls, Radius, Mount,
	ParticipantById and OnBodyHit.
]]

local Workspace = game:GetService("Workspace")

local BallPhysics = require("@Shared/Minigames/BallPhysics")
local Hex = require("@Shared/Minigames/Hex")
local Ragdoll = require("@Shared/Ragdoll")
local Remotes = require("@Shared/Movement/Remotes")
local Tuning = require("@Shared/Movement/Tuning")
local BotMind = require("@GameServer/Rounds/BotMind")
local PowerUps = require("@GameServer/Rounds/PowerUps")
local World = require("@Shared/World")

local Ball = Tuning.Of("Ball")
local Hits = Tuning.Of("BumpHits")
local Arena = Tuning.Of("BumpArena")
local BumpMoves = Tuning.Of("Bump")

local BumpBots = {}

local ORIGIN = World.ArenaOrigin
local WOBBLE_ATTR = "BumpWobbleUntil" -- BumpGame.WobbleAttr

local hooks = nil
local state = nil -- the running game's, refreshed at each call in
local floorAt, safeSpot, freeBalls, radius, mount, participantById, onBodyHit

function BumpBots.Bind(given)
	hooks = given
	floorAt, safeSpot, freeBalls = given.FloorAt, given.SafeSpot, given.FreeBalls
	radius, mount = given.Radius, given.Mount
	participantById, onBodyHit = given.ParticipantById, given.OnBodyHit
end

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function rootOf(model: Model?): BasePart?
	local root = model and model:FindFirstChild("HumanoidRootPart")
	return root and root:IsA("BasePart") and root or nil
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

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
-- (finish them off), players (bullies), anyone on foot (run them over). BotMind.PickTarget re-weighs
-- it at every decision as people move, with each bot's whims, a reluctance to flit between
-- targets, and giving up on one it can't catch. Nil if nobody's worth it yet (the timid patrol and
-- wait for a chance); everyone hunts once it's down to a few.
local function chooseTarget(participant, brain, mind, position: Vector3)
	local others = {}
	for _, other in state.ctx.Alive() do
		if other ~= participant then
			table.insert(others, other)
		end
	end
	local function where(other)
		local model = state.ctx.Character(other)
		local root = rootOf(model)
		local ball = state.riding[other.Id]
		return model, ball and ball.Parent and ball.Position or root and root.Position, ball
	end
	local best, bestScore = BotMind.PickTarget(brain, mind, others, function(other)
		local model, at, ball = where(other)
		if not at or PowerUps.Shielded(model) then
			return nil
		end
		local distance = flat(at - position).Magnitude
		if distance > 90 then
			return nil
		end
		local holeDistance = BotMind.HoleDistance(state.arena, at, 20, 4)
		local edgeness = 1 - math.clamp(holeDistance / 20, 0, 1)
		local wobbling = (model:GetAttribute(WOBBLE_ATTR) or 0) > now()
		return -distance / 30
			+ mind.EdgeBias * edgeness * 1.5
			+ (wobbling and mind.WobbleBias or 0)
			+ (other.Player and mind.HumanBias or 0)
			+ (ball and 0 or 0.4)
	end, function(other)
		local _, at = where(other)
		return at and flat(at - position).Magnitude or nil
	end)
	local fewLeft = #state.ctx.Alive() <= 3
	if best and not fewLeft and bestScore < 1.6 - mind.Aggro * 2 then
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

-- A bot on foot this frame: dodge balls rolling at it, walk to a free ball over floor and get on,
-- or leap at a rider to take theirs.
function BumpBots.OnFoot(participant, brain, character: Model, dt: number)
	state = hooks.State()
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

	-- nothing to do: keep moving over safe floor near the middle, the next spot picked on arrival
	local goal = brain.wanderGoal
	if not goal or flat(goal - position).Magnitude < 4 or (brain.wanderAt or 0) < os.clock() then
		brain.wanderAt = os.clock() + 4
		brain.wanderGoal = safeSpot(ORIGIN + Hex.Position(math.random(-3, 3), math.random(-3, 3), Arena.Tile))
		humanoid:MoveTo(brain.wanderGoal)
	end
	local _ = dt
end

-- A riding bot this frame: stay on (floor all the way to where this roll would stop), keep clear
-- when wobbling, sidestep incoming balls, otherwise hunt a target picked by its personality and
-- dash at them when lined up with floor past them. Drives its ball with the same BallPhysics a
-- player's client uses.
function BumpBots.Riding(participant, brain, character: Model, ball: BasePart, dt: number)
	state = hooks.State()
	local root = rootOf(character)
	if not root or not ball.Parent then
		return
	end
	local mind = BotMind.Of(participant)
	local physics = brain.physics
	local position = ball.Position
	local planar = flat(ball.AssemblyLinearVelocity)
	local speed = planar.Magnitude
	physics.Wobbling = (character:GetAttribute(WOBBLE_ATTR) or 0) > now()
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
		if toSafe.Magnitude < 0.5 then
			-- the nearest safe spot is right here (the cell is going): head for safe floor inward
			toSafe = flat(safeSpot(ORIGIN) - position)
		end
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
		-- nobody worth it yet: patrol round the arena, never parked (they used to drift to a spot
		-- near the middle and stop: measured, riders still for 3 to 5 s). A loop of points round the
		-- middle at a distance that suits the bot (the careful nearer the middle), each picked as
		-- the last is reached, and the way round turning now and then
		mode = "Patrol"
		local radius = Arena.Tile * (2.5 + (1 - mind.Caution) * 3)
		if not brain.patrolSpot or flat(brain.patrolSpot - position).Magnitude < 8 or (brain.patrolAt or 0) < nowClock then
			brain.patrolTurn = brain.patrolTurn or (math.random() < 0.5 and 1 or -1)
			if math.random() < 0.15 then
				brain.patrolTurn = -brain.patrolTurn
			end
			local fromMiddle = flat(position - ORIGIN)
			local angle = math.atan2(fromMiddle.Z, fromMiddle.X) + brain.patrolTurn * (0.7 + math.random() * 0.6)
			local spot = ORIGIN + Vector3.new(math.cos(angle), 0, math.sin(angle)) * radius * (0.8 + math.random() * 0.4)
			brain.patrolSpot = floorAt(spot) and spot or safeSpot(spot)
			brain.patrolAt = nowClock + 4
		end
		local toSpot = flat(brain.patrolSpot - position)
		input = toSpot.Magnitude > 0.5 and toSpot.Unit * (0.6 + 0.4 * mind.Aggro) or Vector3.zero
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

return BumpBots
