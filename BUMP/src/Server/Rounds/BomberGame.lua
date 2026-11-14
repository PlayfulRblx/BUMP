--!nonstrict
--[[
	BOMBER BLOXIANS, on the server: pass the enormous ticking bomb.

	A smaller hex platform in the sky (the shared HexArena). One player is handed a bomb, held
	over their head. Its fuse is a random length nobody is shown; the bomb ticks, and the ticks
	quicken as the fuse burns down (the "TickEvery" attribute on the bomb, which every client
	plays). Touch anyone to pass it on (a dive or a shove passes it from further, BumpServer's
	body hits); whoever just got it can't pass it for a moment. The holder runs faster
	(RoundInfo.SpeedAttr) and holds it overhead (RoundInfo.CarryingAttr, the carry pose).

	When the fuse runs out the holder pops (a red flash, then gone: RoundInfo.PopAttr, drawn by
	Client/Systems/PopFx) and is out; the blast throws and flattens anyone
	close, the floor round it falls away (a crater) and the edge crumbles a bit more. Then, after
	a breath, a new bomb goes to someone still in. Fall off and you're out too. Last one standing
	wins.

	The user's choices (2026-11-13): hidden fuse with ticking that speeds up; crater plus blast;
	the holder is faster; touch anyone to pass.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Hex = require("@Shared/Minigames/Hex")
local Ragdoll = require("@Shared/Ragdoll")
local Remotes = require("@Shared/Movement/Remotes")
local RoundInfo = require("@Shared/Rounds/RoundInfo")
local Tuning = require("@Shared/Movement/Tuning")
local BumpServer = require("@GameServer/Systems/BumpServer")
local HexArena = require("@GameServer/Rounds/HexArena")
local PowerUps = require("@GameServer/Rounds/PowerUps")
local BotMind = require("@GameServer/Rounds/BotMind")
local World = require("@Shared/World")

local Bomber = Tuning.Of("Bomber")
local Rounds = Tuning.Of("Rounds")
local Hits = Tuning.Of("BumpHits")
local Pound = Tuning.Of("Pound")

local BomberGame = {}

BomberGame.BombTag = "BumpBomb"

local ORIGIN = World.ArenaOrigin -- the lobby's pit
-- dark tops on neon outlines, hot colours: yellow in the middle through orange to red at the rim
local RING_COLORS = { [0] = Color3.fromRGB(92, 84, 100) }
local RING_EDGES = {
	[0] = Color3.fromRGB(255, 231, 90),
	Color3.fromRGB(255, 200, 69),
	Color3.fromRGB(255, 160, 60),
	Color3.fromRGB(255, 119, 60),
	Color3.fromRGB(255, 81, 90),
	Color3.fromRGB(255, 60, 140),
}
local BOMB_SIZE = 5.5
local BOMB_HEIGHT = 4.7 -- the bomb's centre above the root: resting in the carry pose's hands
local BOT_SPEED = 24 -- Bots.lua's walking speed
local SAFETY_LIMIT = 300 -- seconds; the game never shows a clock, but it can't run forever
local POP_HIDDEN = 0.6 -- seconds a popped holder's body waits, hidden, before it goes to the stand

-- the running game: { ctx, arena, folder, bots = { [id] = brain }, blown = { [id] = true },
-- bomb = { holder, part, lit, fuse, immuneUntil } or nil }
local state = nil
local shockwave, rescue -- power-up effects, defined further down

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

local function participantOfModel(model: Model)
	if not state or not model then
		return nil
	end
	local id = model:GetAttribute(RoundInfo.IdAttr)
	if not id then
		local player = Players:GetPlayerFromCharacter(model)
		id = player and tostring(player.UserId)
	end
	for _, participant in state.ctx.Seats do
		if participant.Id == id then
			return participant
		end
	end
	return nil
end

-- ═══ knocked about ════════════════════════════════════════════════════════════════

-- Thrown and, if `flatten`, knocked flat for a moment.
-- Thrown (and flattened, if `flatten`) by `by` (a participant, or nil): if they fall soon after,
-- `by` is named as who eliminated them.
local function knock(participant, velocity: Vector3, flatten: boolean, by, how: string?)
	local character = state.ctx.Character(participant)
	if not character then
		return
	end
	participant.LastHitAt = os.clock()
	participant.LastHitBy = by ~= participant and by or nil
	participant.LastHitHow = how -- "pass", "blast", "dive", "shove", "shockwave": for the card
	if flatten then
		character:SetAttribute(Ragdoll.Attribute, true)
		character:SetAttribute(Remotes.MoveAttr, "Knocked")
		local mine = os.clock()
		participant.KnockedAt = mine
		task.delay(Hits.Ragdoll, function()
			if participant.KnockedAt == mine and character.Parent then
				character:SetAttribute(Ragdoll.Attribute, false)
				character:SetAttribute(Remotes.MoveAttr, "Run")
			end
		end)
	end
	BumpServer.Throw(character, velocity)
end

-- ═══ the bomb ═════════════════════════════════════════════════════════════════════

local function setHolderLook(participant, holding: boolean)
	local character = state.ctx.Character(participant)
	if not character then
		return
	end
	character:SetAttribute(RoundInfo.CarryingAttr, holding or nil)
	character:SetAttribute(RoundInfo.SpeedAttr, holding and Bomber.HolderSpeed or nil)
	if participant.Bot then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = BOT_SPEED * (holding and Bomber.HolderSpeed or 1)
		end
	end
end

local function makeBombPart(): BasePart
	local part = Instance.new("Part")
	part.Name = "Bomb"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.one * BOMB_SIZE
	part.Color = Color3.fromRGB(32, 32, 40)
	part.Material = Enum.Material.SmoothPlastic
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	-- a cap and a short fuse on top; the spark is the client's (BumpFx)
	local cap = Instance.new("Part")
	cap.Name = "Cap"
	cap.Shape = Enum.PartType.Cylinder
	cap.Size = Vector3.new(0.8, 1.8, 1.8)
	cap.Color = Color3.fromRGB(90, 90, 100)
	cap.Material = Enum.Material.Metal
	cap.CanCollide = false
	cap.CanTouch = false
	cap.CanQuery = false
	cap.Massless = true
	cap.CFrame = part.CFrame * CFrame.new(0, BOMB_SIZE / 2, 0) * CFrame.Angles(0, 0, math.rad(90))
	cap.Parent = part
	local capWeld = Instance.new("WeldConstraint")
	capWeld.Part0 = part
	capWeld.Part1 = cap
	capWeld.Parent = cap
	local spark = Instance.new("Attachment")
	spark.Name = "Spark"
	spark.Position = Vector3.new(0, BOMB_SIZE / 2 + 0.9, 0)
	spark.Parent = part
	part:SetAttribute("TickEvery", Bomber.TickSlow)
	return part
end

-- Puts the bomb over `participant`'s head.
local function holdBomb(participant)
	local bomb = state.bomb
	local character = state.ctx.Character(participant)
	local root = rootOf(character)
	if not root then
		return false
	end
	if bomb.holder then
		setHolderLook(bomb.holder, false)
	end
	bomb.holder = participant
	local part = bomb.part
	local weld = part:FindFirstChild("HoldWeld")
	if weld then
		weld:Destroy()
	end
	part.CFrame = root.CFrame * CFrame.new(0, BOMB_HEIGHT, 0)
	weld = Instance.new("Weld")
	weld.Name = "HoldWeld"
	weld.Part0 = root
	weld.Part1 = part
	weld.C0 = CFrame.new(0, BOMB_HEIGHT, 0)
	weld.Parent = part
	if not part.Parent then
		part.Parent = state.folder
		CollectionService:AddTag(part, BomberGame.BombTag)
	end
	part:SetAttribute("Holder", participant.Id)
	setHolderLook(participant, true)
	state.ctx.SetNote(participant.Name .. " has the bomb!")
	return true
end

local function giveBomb()
	local alive = state.ctx.Alive()
	if #alive < 2 then
		return
	end
	local participant = alive[math.random(#alive)]
	state.bomb = {
		holder = nil,
		part = makeBombPart(),
		lit = now(),
		fuse = Bomber.FuseMin + math.random() * (Bomber.FuseMax - Bomber.FuseMin),
		immuneUntil = now() + Bomber.PassImmunity,
	}
	if not holdBomb(participant) then
		state.bomb.part:Destroy()
		state.bomb = nil
		return
	end
	print(string.format("[Bomber] bomb to %s, fuse %.1f s", participant.Name, state.bomb.fuse))
	Remotes.Fx("BombGiven", { Holder = participant.Id })
end

local function pass(to, from, push: Vector3)
	local bomb = state.bomb
	holdBomb(to)
	bomb.from = from -- if it goes off on them, this is who did it
	bomb.immuneUntil = now() + Bomber.PassImmunity
	state.folder:SetAttribute("Passes", (state.folder:GetAttribute("Passes") or 0) + 1)
	local toRoot = rootOf(state.ctx.Character(to))
	print(string.format("[Bomber] %s passed to %s", from.Name, to.Name))
	knock(to, push, false, from, "pass")
	if toRoot then
		Remotes.Fx("BombPass", { Position = toRoot.Position + Vector3.new(0, 2, 0) })
	end
end

local function removeBomb()
	local bomb = state.bomb
	if not bomb then
		return
	end
	if bomb.holder then
		setHolderLook(bomb.holder, false)
	end
	bomb.part:Destroy()
	state.bomb = nil
end

-- The fuse ran out: blow the holder up and out, throw everyone close, bite the floor.
local function explode()
	local bomb = state.bomb
	local holder = bomb.holder
	local passer = bomb.from
	local position = bomb.part.Position
	removeBomb()
	print(string.format("[Bomber] BOOM on %s at %s", holder.Name, tostring(position)))
	state.folder:SetAttribute("Blasts", (state.folder:GetAttribute("Blasts") or 0) + 1)
	Remotes.Fx("Boom", { Position = position, Radius = Bomber.BlastRadius })
	-- everyone close is thrown away from it and knocked flat
	for _, participant in state.ctx.Alive() do
		if participant ~= holder and not PowerUps.Shielded(state.ctx.Character(participant)) then
			local root = rootOf(state.ctx.Character(participant))
			if root then
				local offset = flat(root.Position - position)
				local distance = offset.Magnitude
				if distance <= Bomber.BlastRadius then
					local away = distance > 0.1 and offset.Unit or Vector3.new(1, 0, 0)
					local strength = 1 - 0.5 * distance / Bomber.BlastRadius
					knock(participant, away * Bomber.BlastPush * strength + Vector3.new(0, Bomber.BlastLift * strength, 0), true, holder, "blast")
				end
			end
		end
	end
	-- the holder goes up with it (OnEliminated throws them)
	state.blown[holder.Id] = position
	state.ctx.Eliminate(holder, "blew up", passer, passer and "bomb" or nil)
	-- a crater where it went off, and the edge crumbles a little more
	local dropped = state.arena:Crater(position, Bomber.CraterRadius, Bomber.CraterWarn)
	local bite = 0
	for _ = 1, Bomber.EdgeBite do
		local edge = {}
		for _, cell in state.arena:SolidCells() do
			if state.arena:IsEdge(cell) then
				table.insert(edge, cell)
			end
		end
		if #edge <= Bomber.KeepCells then
			break
		end
		local cell = edge[math.random(#edge)]
		state.arena:DropCell(cell, Bomber.CraterWarn + 0.6 + math.random() * 1.2)
		bite += 1
	end
	print(string.format("[Bomber] crater %d cells, edge %d, %d left", dropped, bite, #state.arena:SolidCells()))
end

-- ═══ passing by touch, and by a dive or a shove ══════════════════════════════════

local function touching(a: BasePart, b: BasePart, reach: number): boolean
	local offset = b.Position - a.Position
	return flat(offset).Magnitude <= reach and math.abs(offset.Y) <= 5
end

local function checkTouchPass()
	local bomb = state.bomb
	if not bomb or not bomb.holder or now() < bomb.immuneUntil then
		return
	end
	local holder = bomb.holder
	local mine = rootOf(state.ctx.Character(holder))
	if not mine then
		return
	end
	for _, other in state.ctx.Alive() do
		if other ~= holder then
			local theirs = rootOf(state.ctx.Character(other))
			if theirs and touching(mine, theirs, Bomber.PassReach) and not PowerUps.Shielded(state.ctx.Character(other)) then
				local away = flat(theirs.Position - mine.Position)
				away = away.Magnitude > 0.1 and away.Unit or Vector3.new(0, 0, 1)
				pass(other, holder, away * Bomber.PassPush + Vector3.new(0, 10, 0))
				return
			end
		end
	end
end

-- BumpServer's body hits while this game runs: the holder's dive or shove passes the bomb from
-- further than a touch; anyone else's just shoves (no flattening, so the chase keeps going).
local function onBodyHit(attacker: Model?, target: Model, kind: string, throw: Vector3, reach: number): boolean
	if not state then
		return false
	end
	local from, to = participantOfModel(attacker), participantOfModel(target)
	local mine, theirs = rootOf(attacker), rootOf(target)
	if not from or not to or from.Out or to.Out or not mine or not theirs then
		return false
	end
	if (theirs.Position - mine.Position).Magnitude > reach or PowerUps.Shielded(target) then
		return true -- out of reach, or a Shield power-up's bubble: nothing happens
	end
	local bomb = state.bomb
	if bomb and bomb.holder == from and now() >= bomb.immuneUntil then
		pass(to, from, flat(throw).Unit * Bomber.PassPush * 1.4 + Vector3.new(0, 14, 0))
		return true
	end
	if kind == "Bump" then
		to.LastHitAt = os.clock()
		to.LastHitBy = from
		to.LastHitHow = "shove"
		BumpServer.Shove(target, throw * 0.7)
	else
		knock(to, throw * 0.7, false, from, "dive")
	end
	Remotes.Fx("Bump", { Position = (mine.Position + theirs.Position) / 2, Kind = kind })
	return true
end

-- ═══ bots ═════════════════════════════════════════════════════════════════════════

-- A point to walk to that's floor all the way (checked at a few points along the line).
local function clearPath(from: Vector3, to: Vector3): boolean
	for step = 1, 4 do
		if not state.arena:FloorAt(from:Lerp(to, step / 4)) then
			return false
		end
	end
	return true
end

-- How close the bomb sounds to going off, 0 to 1, from how fast it ticks (everyone can hear it).
local function urgency(): number
	local bomb = state.bomb
	local tick = bomb and bomb.part and bomb.part:GetAttribute("TickEvery")
	if type(tick) ~= "number" then
		return 0
	end
	return math.clamp((Bomber.TickSlow - tick) / math.max(Bomber.TickSlow - Bomber.TickFast, 0.01), 0, 1)
end

-- A leap at someone close: the holder's way of passing from further than a touch (Bomber's own
-- body-hit rule passes the bomb on a holder's dive).
local function botLeap(participant, brain, root: BasePart, humanoid: Humanoid, target)
	local targetModel = state.ctx.Character(target)
	local theirs = rootOf(targetModel)
	if not theirs then
		return
	end
	brain.leapAt = os.clock()
	local direction = flat(theirs.Position - root.Position)
	direction = direction.Magnitude > 0.1 and direction.Unit or Vector3.new(0, 0, 1)
	humanoid.Jump = true
	local character = state.ctx.Character(participant)
	character:SetAttribute(Remotes.MoveAttr, "Dive")
	root.AssemblyLinearVelocity = direction * 48 + Vector3.new(0, 24, 0)
	task.delay(0.25, function()
		if not state or participant.Out or not character.Parent then
			return
		end
		if character:GetAttribute(Remotes.MoveAttr) == "Dive" then
			character:SetAttribute(Remotes.MoveAttr, "Run")
		end
		onBodyHit(character, targetModel, "Dive", direction * 40 + Vector3.new(0, 16, 0), Bomber.PassReach + 5)
	end)
end

local function botHolding(participant, brain, root: BasePart, humanoid: Humanoid)
	local mind = BotMind.Of(participant)
	if now() < state.bomb.immuneUntil then
		-- just got it: a beat of panic before the chase (shorter for the sharp ones)
		if now() < state.bomb.immuneUntil - Bomber.PassImmunity + mind.Reaction * 2 then
			return
		end
	end
	local hurry = urgency()
	-- who to give it to, by personality: close, cornered against an edge, players for a bully
	if BotMind.Think(brain, mind) or not brain.target or brain.target.Out then
		local best, bestScore = nil, -math.huge
		for _, other in state.ctx.Alive() do
			local model = other ~= participant and state.ctx.Character(other)
			local theirs = model and rootOf(model)
			if theirs and not PowerUps.Shielded(model) then
				local distance = flat(theirs.Position - root.Position).Magnitude
				local holeDistance = BotMind.HoleDistance(state.arena, theirs.Position, 16, 4)
				local score = -distance / 20
					+ (1 - holeDistance / 16) * 1.2 * mind.EdgeBias
					+ (other.Player and mind.HumanBias or 0)
					+ (other == brain.target and 0.5 or 0)
					+ math.random() * mind.Random
				if score > bestScore then
					best, bestScore = other, score
				end
			end
		end
		brain.target = best
	end
	local target = brain.target
	local theirs = target and rootOf(state.ctx.Character(target))
	if not theirs then
		return
	end
	local distance = flat(theirs.Position - root.Position).Magnitude
	-- head for where they're going, over floor
	local lead = math.clamp(distance / 40, 0, 0.6) * mind.Skill
	local goal = theirs.Position + flat(theirs.AssemblyLinearVelocity) * lead
	if not clearPath(root.Position, goal) then
		goal = theirs.Position
		if not clearPath(root.Position, goal) then
			goal = state.arena:SafeSpot(root.Position:Lerp(goal, 0.5))
		end
	end
	humanoid:MoveTo(goal)
	-- close enough: leap at them (sooner and keener as the fuse runs out)
	local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
	local reach = 6 + mind.Skill * 3 + hurry * 3
	if grounded and distance < reach and distance > 3 and now() >= state.bomb.immuneUntil
		and os.clock() - (brain.leapAt or -10) > 1.4 - mind.Skill * 0.6
		and clearPath(root.Position, theirs.Position) and math.random() < 0.05 + hurry * 0.1 + mind.Aggro * 0.05 then
		botLeap(participant, brain, root, humanoid, target)
	end
end

local function botFleeing(participant, brain, root: BasePart, humanoid: Humanoid)
	local mind = BotMind.Of(participant)
	local bomb = state.bomb
	local holderRoot = bomb and bomb.holder and rootOf(state.ctx.Character(bomb.holder))
	local position = root.Position
	local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
	-- standing on floor that's going (a crater's warning): off it now, whatever else
	if not state.arena:FloorAt(position) then
		humanoid:MoveTo(state.arena:SafeSpot(position))
		return
	end
	-- the holder bearing down, close: a juke to the side, with a hop
	if holderRoot and (brain.jukeUntil or 0) < os.clock() then
		local fromHolder = flat(position - holderRoot.Position)
		local closing = flat(holderRoot.AssemblyLinearVelocity):Dot(fromHolder.Magnitude > 0.1 and fromHolder.Unit or Vector3.zero)
		if fromHolder.Magnitude < 9 and closing > 8 and math.random() < 0.08 * mind.Dodge * (0.5 + mind.Skill) then
			local side = Vector3.new(-fromHolder.Z, 0, fromHolder.X).Unit
			if math.random() < 0.5 then
				side = -side
			end
			if not state.arena:FloorAt(position + side * 8) then
				side = -side
			end
			if state.arena:FloorAt(position + side * 8) then
				brain.jukeUntil = os.clock() + 0.45
				humanoid:MoveTo(position + side * 10 + fromHolder.Unit * 3)
				if grounded then
					humanoid.Jump = true
				end
				return
			end
		end
	end
	if (brain.jukeUntil or 0) > os.clock() or not BotMind.Think(brain, mind) then
		return
	end
	if not holderRoot then
		-- no bomb out: spread out over safe floor toward the middle
		local spot = state.arena:SafeSpot(ORIGIN + Hex.Position(math.random(-2, 2), math.random(-2, 2), Bomber.Tile))
		humanoid:MoveTo(spot)
		return
	end
	local hurry = urgency()
	local danger = flat(position - holderRoot.Position).Magnitude
	-- how far away is far enough: further as the ticking quickens, further for the careful
	local want = Bomber.PassReach + 10 + hurry * (Bomber.BlastRadius + 4) * (0.6 + mind.Caution * 0.4)
	if danger > want + 10 then
		-- far enough: amble about on safe floor rather than freeze
		if (brain.wanderAt or 0) < os.clock() then
			brain.wanderAt = os.clock() + 1.5 + math.random()
			humanoid:MoveTo(state.arena:SafeSpot(position + Vector3.new(math.random(-12, 12), 0, math.random(-12, 12))))
		end
		return
	end
	-- the floor nearby that's far enough from the holder, not on an edge, reachable without
	-- crossing a hole or running past them, and (for the sly) with someone else in between
	local best, bestScore = nil, -math.huge
	for _, cell in state.arena:SolidCells() do
		local centre = cell.model:GetPivot().Position
		local fromMe = flat(centre - position).Magnitude
		if fromMe < 36 then
			local fromHolder = flat(centre - holderRoot.Position).Magnitude
			local score = math.min(fromHolder, want + 12) - fromMe * 0.3
			if state.arena:IsEdge(cell) then
				score -= 12 * mind.Caution
			end
			local toward = flat(centre - position)
			local holderWay = flat(holderRoot.Position - position)
			if toward.Magnitude > 0.1 and holderWay.Magnitude > 0.1 and toward.Unit:Dot(holderWay.Unit) > 0.4 then
				score -= 30
			end
			if mind.Hides then
				-- someone else nearer the holder, between it and this spot: they'll be caught first
				for _, other in state.ctx.Alive() do
					local otherRoot = other ~= participant and other ~= bomb.holder and rootOf(state.ctx.Character(other))
					if otherRoot then
						local mine = flat(centre - holderRoot.Position)
						local theirs = flat(otherRoot.Position - holderRoot.Position)
						if theirs.Magnitude < mine.Magnitude and mine.Magnitude > 0.1 and theirs.Magnitude > 0.1
							and theirs.Unit:Dot(mine.Unit) > 0.85 then
							score += 6
							break
						end
					end
				end
			end
			if score > bestScore and clearPath(position, centre) then
				best, bestScore = centre, score
			end
		end
	end
	if best then
		humanoid:MoveTo(best)
	end
end

-- Whether a bot uses its power-up now: the holder Turbos to catch someone; the rest Shield,
-- Turbo or Shockwave when the holder gets close.
local function botPowerUp(participant, root: BasePart)
	local power = participant.Power
	local stats = PowerUps.Ready(participant)
	local bomb = state.bomb
	local brain = state.bots[participant.Id]
	if not stats or not bomb or not bomb.holder or math.random() > 0.08 or (brain and (brain.calmUntil or 0) > os.clock()) then
		return
	end
	local holding = bomb.holder == participant
	local use = false
	if holding then
		if power.Id == "Turbo" and now() >= bomb.immuneUntil then
			for _, other in state.ctx.Alive() do
				local theirs = other ~= participant and rootOf(state.ctx.Character(other))
				local distance = theirs and flat(theirs.Position - root.Position).Magnitude
				if distance and distance > 6 and distance < 22 then
					use = true
				end
			end
		end
	else
		local holderRoot = rootOf(state.ctx.Character(bomb.holder))
		local danger = holderRoot and flat(holderRoot.Position - root.Position).Magnitude or math.huge
		if power.Id == "Shield" then
			use = danger < 9
		elseif power.Id == "Turbo" then
			use = danger < 14
		elseif power.Id == "Shockwave" then
			use = danger < stats.Radius * 0.6
		end
	end
	if use then
		PowerUps.Use(participant)
	end
end

local function botStep(participant, character: Model)
	local brain = state.bots[participant.Id]
	local root = rootOf(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not brain or not root or not humanoid or Ragdoll.IsDown(character) then
		return
	end
	if state.bomb and state.bomb.holder == participant then
		botHolding(participant, brain, root, humanoid)
	else
		botFleeing(participant, brain, root, humanoid)
	end
	botPowerUp(participant, root)
end

-- ═══ power-ups (Server/Rounds/PowerUps) ═══════════════════════════════════════════

-- Shockwave: a ripple through the tiles that shoves everyone in reach away (it never passes the
-- bomb, and a Shield shrugs it off).
function shockwave(participant, at: Vector3, reach: number)
	if not state then
		return
	end
	local centre = Vector3.new(at.X, ORIGIN.Y, at.Z)
	Remotes.Fx("Ripple", { Position = centre, Radius = reach, Speed = Pound.RippleSpeed, Height = Pound.RippleHeight })
	for _, other in state.ctx.Alive() do
		local character = state.ctx.Character(other)
		local theirs = rootOf(character)
		if other ~= participant and theirs then
			local offset = flat(theirs.Position - centre)
			if offset.Magnitude <= reach and math.abs(theirs.Position.Y - centre.Y) < 10 then
				task.delay(offset.Magnitude / Pound.RippleSpeed, function()
					if state and not other.Out and not PowerUps.Shielded(character) then
						local away = offset.Magnitude > 0.1 and offset.Unit or Vector3.new(0, 0, 1)
						knock(other, away * Bomber.PassPush * 2.2 + Vector3.new(0, 24, 0), true, participant, "shockwave")
					end
				end)
			end
		end
	end
end

-- Second Chance: back onto floor that will stay (with the bomb, if they had it).
function rescue(participant)
	if not state then
		return
	end
	local character = state.ctx.Character(participant)
	local root = rootOf(character)
	if not character or not root then
		return
	end
	local spot = state.arena:SafeSpot(ORIGIN) + Vector3.new(0, 8, 0)
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

function BomberGame.Setup(ctx)
	local arena = HexArena.new({ Origin = ORIGIN, Rings = Bomber.Rings, Tile = Bomber.Tile, Colors = RING_COLORS, Edges = RING_EDGES, Name = "BomberArena" })
	state = { ctx = ctx, arena = arena, folder = arena.folder, bots = {}, blown = {}, bomb = nil }
	BumpServer.SetBodyHitHandler(onBodyHit)
	PowerUps.SetGame({ Shockwave = shockwave, Rescue = rescue })
	ctx.SetNote("")
	-- the arena plays itself in on every client before anyone goes on it (RoundServer waits this)
	return HexArena.ShowSeconds(Bomber.Rings)
end

-- Once the arena has landed: everyone onto it.
function BomberGame.Place(ctx)
	local alive = ctx.Alive()
	local spots = Hex.Spread(math.max(Bomber.Rings - 2, 1), #alive, Bomber.Tile)
	for index, participant in alive do
		local spot = ORIGIN + spots[index] + Vector3.new(0, 4, 0)
		local cframe = CFrame.lookAt(spot, Vector3.new(ORIGIN.X, spot.Y, ORIGIN.Z))
		if participant.Bot then
			local model = ctx.SpawnBot(participant, cframe)
			model:SetAttribute(Ragdoll.Attribute, false)
			model:SetAttribute(Remotes.MoveAttr, "Run")
			state.bots[participant.Id] = { calmUntil = os.clock() + Rounds.Intro + 2.5 + math.random() * 3 }
		else
			local character = ctx.Character(participant)
			if character then
				character:SetAttribute(Ragdoll.Attribute, false)
				character:PivotTo(cframe)
			end
		end
	end
end

function BomberGame.OnEliminated(ctx, participant)
	if not state then
		return
	end
	if state.bomb and state.bomb.holder == participant then
		-- fell off holding it: it goes with them, and a new one comes
		removeBomb()
		state.nextBombAt = now() + Bomber.NextBomb
	end
	local character = ctx.Character(participant)
	if character then
		character:SetAttribute(RoundInfo.CarryingAttr, nil)
		character:SetAttribute(RoundInfo.SpeedAttr, nil)
	end
	local blownAt = state.blown[participant.Id]
	local stand = state.arena:StandSpot()
	local function away()
		if not state then
			return -- the game's over and cleaned up; the round puts everyone where they go
		end
		if participant.Bot then
			if participant.Model then
				participant.Model:Destroy()
				participant.Model = nil
			end
		elseif character and character.Parent then
			character:SetAttribute(Ragdoll.Attribute, false)
			character:SetAttribute(Remotes.MoveAttr, "Run")
			character:PivotTo(stand)
		end
	end
	if blownAt and character then
		-- popped (the user: "the character should just pop and disappear almost instantly ... a red
		-- highlight that fades into a sackboy level pop"): every client flashes the body red and
		-- pops it (PopFx); it stays hidden, held still, until it has been moved off the arena
		character:SetAttribute(Ragdoll.Attribute, false)
		character:SetAttribute(RoundInfo.PopAttr, true)
		local root = rootOf(character)
		if root then
			root.AssemblyLinearVelocity = Vector3.zero
			if participant.Bot then
				root.Anchored = true
			end
		end
		-- a player's knockout camera watches where they popped first (KnockoutCam)
		task.delay(participant.Bot and POP_HIDDEN or math.max(POP_HIDDEN, RoundInfo.KnockoutHold), function()
			away()
			-- seen again only once it's on the stand
			task.delay(0.3, function()
				if character.Parent then
					character:SetAttribute(RoundInfo.PopAttr, nil)
				end
			end)
		end)
	elseif participant.Bot then
		away()
	else
		-- a player's body keeps falling while their knockout camera watches it (KnockoutCam)
		task.delay(RoundInfo.KnockoutHold, away)
	end
end

function BomberGame.Run(ctx)
	local startedAt = now()
	state.nextBombAt = startedAt + Bomber.FirstBomb
	local floor = ORIGIN.Y - Bomber.FallDepth
	local lastTickUpdate = 0
	while true do
		RunService.Heartbeat:Wait()
		local alive = ctx.Alive()
		if #alive <= 1 or now() - startedAt >= SAFETY_LIMIT then
			break
		end
		-- a new bomb after a breath
		if not state.bomb and state.nextBombAt and now() >= state.nextBombAt then
			state.nextBombAt = nil
			giveBomb()
		end
		local bomb = state.bomb
		if bomb then
			local burnt = math.clamp((now() - bomb.lit) / bomb.fuse, 0, 1)
			if burnt >= 1 then
				explode()
				state.nextBombAt = now() + Bomber.NextBomb
				ctx.SetNote(#ctx.Alive() > 1 and "Next bomb coming..." or "")
			else
				-- the ticking quickens as it burns (a curve: it's in the last stretch you hear it)
				if os.clock() - lastTickUpdate > 0.2 then
					lastTickUpdate = os.clock()
					bomb.part:SetAttribute("TickEvery", Bomber.TickSlow + (Bomber.TickFast - Bomber.TickSlow) * burnt ^ 1.6)
				end
				checkTouchPass()
				local total = #ctx.Seats
				local out = total > 1 and (total - #ctx.Alive()) / (total - 1) or 0
				ctx.SetIntensity(math.max(burnt ^ 1.5, out * 0.7 + burnt * 0.3))
			end
		end
		for _, participant in ctx.Alive() do
			local character = ctx.Character(participant)
			local root = rootOf(character)
			if not character or not character.Parent or not root then
				ctx.Eliminate(participant, "no body")
			elseif root.Position.Y < floor then
				if not PowerUps.TryRescue(participant) then
					-- thrown off in the last few seconds: by whoever threw them
					local recent = os.clock() - (participant.LastHitAt or -100) < 4
					ctx.Eliminate(participant, recent and "knocked off" or "fell", recent and participant.LastHitBy or nil, recent and participant.LastHitHow or nil)
				end
			elseif participant.Bot then
				botStep(participant, character)
			end
		end
	end
	ctx.SetNote("")
end

function BomberGame.Cleanup(ctx)
	if not state then
		return
	end
	removeBomb()
	for _, participant in ctx.Seats do
		local character = ctx.Character(participant)
		if character then
			character:SetAttribute(Ragdoll.Attribute, false)
			character:SetAttribute(RoundInfo.CarryingAttr, nil)
			character:SetAttribute(RoundInfo.SpeedAttr, nil)
			character:SetAttribute(RoundInfo.PopAttr, nil)
		end
	end
	BumpServer.SetBodyHitHandler(nil)
	ctx.SetNote("")
	state.arena:Destroy()
	state = nil
end

return BomberGame
