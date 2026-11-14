--!nonstrict
--[[
	MELTDOWN's bots: climbing the tower ahead of the lava, and getting in each other's way.

	A bot's body is a stock Humanoid that jumps about 5 studs, half a player's; so its jumps are
	assisted: it walks to the edge of the platform it's on facing the next one (from the layout's
	links, Shared/Minigames/MeltLayout), then leaps on a ballistic arc worked out to land on it,
	steering at just the right speed (the Humanoid's air control holds WalkSpeed toward MoveTo).
	Its aim is off by its skill, so the clumsy ones sometimes miss. A bounce pad throws it up to the
	pad's platform; a chimney it climbs in timed kicks from wall to wall.

	How it climbs is its mind's (BotMind): how far above the lava it likes to stay (Cowards race
	ahead, Bullies hang back to fight), which way up it picks (higher, emptier, a shortcut if it's
	sharp enough, never where a fireball or chunk is about to land), and what it does with time to
	spare: Bullies shove and dive at whoever is near, Opportunists pound a platform with others on
	it to shake them off, Wildcards a bit of everything.

	    MeltBots.Bind({ Tower, Layout, Marks, Ctx, OnBodyHit, Shake })   -- nil when the game ends
	    MeltBots.NewBrain(participant)
	    MeltBots.Step(participant, brain, character, root, lava)        -- every frame, each bot
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local BotMind = require("@GameServer/Rounds/BotMind")
local PowerUps = require("@GameServer/Rounds/PowerUps")
local Ragdoll = require("@Shared/Ragdoll")
local Remotes = require("@Shared/Movement/Remotes")
local RoundInfo = require("@Shared/Rounds/RoundInfo")
local Tuning = require("@Shared/Movement/Tuning")
local MeltLayout = require("@Shared/Minigames/MeltLayout")
local FloorUnder = require("@Shared/Movement/FloorUnder")

local Bump = Tuning.Of("Bump")

local MeltBots = {}

local WALK = 24 -- Bots.lua's walking speed
local JUMP_POWER = 45 -- and its jump
local ROOT_UP = 3 -- a standing body's root is this far above the floor
local LAUNCH_NEAR = 1.6 -- this close to the launch point and it jumps
local SHOVE_EVERY = 1.3
local POUND_EVERY = 4.5
local KICK_RISE = 6.5 -- a chimney climb gains this much a hop

local env = nil
local occupancy, occupancyAt = {}, -1

local function gravity(): number
	return Workspace.Gravity
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function rootOf(model: Model?): BasePart?
	local root = model and model:FindFirstChild("HumanoidRootPart")
	return root and root:IsA("BasePart") and root or nil
end

function MeltBots.Bind(environment)
	env = environment
	occupancy, occupancyAt = {}, -1
	if not env then
		return
	end
	-- how many links each platform is from the summit (counted back from it), so a bot always
	-- knows which way is really up: with only "higher is better" they hopped back and forth
	-- between two platforms with no way on
	local into = {}
	for id, platform in env.Layout.Platforms do
		for _, link in platform.Links do
			into[link.To] = into[link.To] or {}
			table.insert(into[link.To], id)
		end
	end
	local hops = { [env.Layout.Summit] = 0 }
	local queue = { env.Layout.Summit }
	while #queue > 0 do
		local id = table.remove(queue, 1)
		for _, from in into[id] or {} do
			if hops[from] == nil then
				hops[from] = hops[id] + 1
				table.insert(queue, from)
			end
		end
	end
	env.Hops = hops
end

function MeltBots.NewBrain(participant)
	local mind = BotMind.Of(participant)
	return {
		-- how far above the lava it likes to keep: the careful far, the pushy close
		margin = 8 + mind.Caution * 20 + math.random() * 4,
		startDelay = 0.15 + mind.Reaction * 2 + math.random() * 0.3,
		-- no shoving or pounding for the first few seconds of the climb
		calm = 7 + math.random() * 5,
		progressY = -math.huge,
		progressAt = os.clock(),
	}
end

-- Who stands on which platform right now ([entry] = { participant }), worked out once a tenth of
-- a second for every bot to share.
local function whoIsWhere()
	local clock = os.clock()
	if clock - occupancyAt < 0.1 then
		return occupancy
	end
	occupancyAt = clock
	occupancy = {}
	for _, participant in env.Ctx.Alive() do
		local root = rootOf(env.Ctx.Character(participant))
		local entry = root and env.Tower:PlatformUnder(root.Position)
		if entry then
			occupancy[entry] = occupancy[entry] or {}
			table.insert(occupancy[entry], participant)
		end
	end
	return occupancy
end

local function markedNear(position: Vector3, extra: number): (boolean, Vector3?)
	for _, mark in env.Marks() do
		local offset = flat(position - mark.Position)
		if offset.Magnitude < mark.Radius + extra and math.abs(position.Y - mark.Position.Y) < 7 then
			return true, mark.Position
		end
	end
	return false, nil
end

local function setMove(character: Model, move: string)
	if character:GetAttribute(Remotes.MoveAttr) ~= move then
		character:SetAttribute(Remotes.MoveAttr, move)
	end
end

local function walkTo(brain, humanoid: Humanoid, point: Vector3, speed: number?)
	humanoid.WalkSpeed = speed or WALK
	local clock = os.clock()
	if not brain.walkPoint or (brain.walkPoint - point).Magnitude > 0.5 or clock - (brain.walkAt or 0) > 0.6 then
		brain.walkPoint, brain.walkAt = point, clock
		humanoid:MoveTo(point)
	end
end

-- A leap that lands the root on `landing` (a root height, about ROOT_UP over the floor), peaking
-- `extra` over the higher end. Flown exactly, frame by frame along the arc (fly, below): a stock
-- Humanoid steered by physics clipped platform edges and bounced off them. A clumsy bot sometimes
-- misjudges one (`short`): the arc ends a few studs shy and it's let go to fall, as anyone would.
local function leap(brain, character: Model, humanoid: Humanoid, root: BasePart, landing: Vector3, extra: number, move: string?, short: boolean?)
	local g = gravity()
	local from = root.Position
	local rise = landing.Y - from.Y
	local peak = math.max(rise, 0) + extra
	local up = math.sqrt(2 * g * peak)
	local flight = (up + math.sqrt(math.max(up * up - 2 * g * rise, 0))) / g
	humanoid.WalkSpeed = 0
	humanoid:Move(Vector3.zero)
	brain.walkPoint = nil
	setMove(character, move or "Jump")
	brain.flying = { at = os.clock(), flight = flight, from = from, landing = landing, up = up, short = short }
end

local function landed(brain, character: Model, humanoid: Humanoid, mind)
	brain.flying = nil
	-- a beat on the ground before the next leap (the sharp ones are quicker): chained straight on,
	-- bots were up the tower in seconds
	brain.restUntil = os.clock() + 0.45 + (mind and (1 - mind.Skill) * 0.7 or 0.3) + math.random() * 0.4
	humanoid.JumpPower = JUMP_POWER
	humanoid.WalkSpeed = WALK
	setMove(character, "Run")
end

-- One frame of a leap: the root put where the arc says (moving as the arc does, so it animates and
-- replicates as a jump). True while it's still in the air.
local function fly(brain, character: Model, humanoid: Humanoid, root: BasePart): boolean
	local leapNow = brain.flying
	local t = os.clock() - leapNow.at
	local g = gravity()
	local across = flat(leapNow.landing - leapNow.from)
	local facing = across.Magnitude > 0.1 and across.Unit or flat(root.CFrame.LookVector)
	if leapNow.short and t >= leapNow.flight * 0.8 then
		-- misjudged: let go, short of the edge, to fall
		brain.flying = nil
		root.AssemblyLinearVelocity = facing * 4 + Vector3.new(0, leapNow.up - g * t, 0)
		humanoid.WalkSpeed = WALK
		setMove(character, "Fall")
		return true
	end
	if t >= leapNow.flight then
		root.CFrame = CFrame.lookAt(leapNow.landing, leapNow.landing + facing)
		root.AssemblyLinearVelocity = facing * 6
		landed(brain, character, humanoid, brain.mind)
		return false
	end
	local u = t / leapNow.flight
	local at = leapNow.from + across * u + Vector3.new(0, leapNow.up * t - g * t * t / 2, 0)
	root.CFrame = CFrame.lookAt(at, at + facing)
	root.AssemblyLinearVelocity = across / leapNow.flight + Vector3.new(0, leapNow.up - g * t, 0)
	if u > 0.55 and character:GetAttribute(Remotes.MoveAttr) == "Jump" then
		setMove(character, "Fall")
	end
	return true
end

-- Where a platform's top will be by the time a leap gets there (a mover keeps moving).
local function landingOn(entry, root: BasePart, mind)
	local tower = env.Tower
	local centre = tower:Centre(entry)
	local spec = entry.spec
	if spec.Mover then
		centre += MeltLayout.MoverVelocity(spec.Mover, Workspace:GetServerTimeNow()) * 0.5
	end
	-- off by its aim, a little toward the middle of the tower (a miss falls short, not long)
	local angle = math.random() * math.pi * 2
	local miss = (1 - mind.Skill) * spec.Size * 0.9 * math.random()
	local inward = flat(centre - root.Position).Magnitude > 1 and flat(centre - root.Position).Unit or Vector3.zero
	return centre + Vector3.new(math.cos(angle), 0, math.sin(angle)) * miss + inward * 0.5 + Vector3.new(0, ROOT_UP, 0)
end

-- Where on the start ring to leap from: straight in from where it stands, the last point with a
-- tile under it before the gap (scanning inward, so a notch in the jagged inner edge stops it).
local floorRay = RaycastParams.new()
floorRay.FilterType = Enum.RaycastFilterType.Include
local function baseLaunch(root: BasePart): Vector3
	local tower = env.Tower
	local out = flat(root.Position - tower.origin)
	local radius = out.Magnitude
	out = radius > 0.1 and out.Unit or Vector3.new(1, 0, 0)
	floorRay.FilterDescendantsInstances = { tower.folder }
	local last = root.Position
	for r = radius, env.Layout.BaseInner - 6, -0.75 do
		local spot = tower.origin + out * r
		local hit = Workspace:Raycast(spot + Vector3.new(0, 4, 0), Vector3.new(0, -8, 0), floorRay)
		if not hit or not hit.Instance.Parent or hit.Instance.Parent:GetAttribute("Ring") ~= 0 then
			break
		end
		last = spot + Vector3.new(0, ROOT_UP, 0)
	end
	-- a step back from the very edge
	return last + out * 1.2
end

-- The links out of where it stands.
local function linksFrom(here)
	if here == env.Tower.Base then
		local list = {}
		for _, id in env.Layout.StartLinks do
			table.insert(list, { To = id, Kind = "Jump" })
		end
		return list
	end
	return here.spec.Links or {}
end

-- The best way up from here, by its mind.
local function chooseLink(participant, brain, mind, here, lava: number, root: BasePart)
	local tower = env.Tower
	local who = whoIsWhere()
	local hereY = here == tower.Base and tower.origin.Y or tower:Centre(here).Y
	local best, bestScore = nil, -math.huge
	for _, link in linksFrom(here) do
		local entry = tower:Entry(link.To)
		if entry and entry.state == "Solid" then
			local top = tower:Centre(entry)
			local rise = top.Y - hereY
			-- the way on to the summit first (fewest links left), then height
			local score = -(env.Hops[link.To] or 60) * 5 + rise * 0.3
			if rise < 0 then
				score -= 8 -- down only if it's really the way on
			end
			if link.Kind == "Pad" then
				score += 8 * mind.Skill
			elseif link.Kind == "Chimney" then
				score += mind.Skill > 0.7 and 14 or -40
			end
			if entry.spec.Kind == "Crumble" then
				score -= 2 * mind.Caution
			elseif entry.spec.Kind == "Mover" then
				score -= 3 * (1 - mind.Skill)
			end
			-- crowds: the shy avoid them, bullies like company
			local crowd = who[entry] and #who[entry] or 0
			score -= crowd * (mind.Hides and 4 or mind.Aggro > 0.9 and -1 or 2)
			if markedNear(top, 2) then
				score -= 25
			end
			if top.Y - lava < 3 then
				score -= 30
			end
			if here == tower.Base then
				-- off the start ring: the one nearest (walking far round it, it might cut across the gap)
				score -= flat(top - root.Position).Magnitude * 0.4
			end
			score += math.random() * 3 * (0.5 + mind.Random)
			if score > bestScore then
				best, bestScore = link, score
			end
		end
	end
	return best
end

-- Someone close enough to shove, on the same level.
local function nearestRival(participant, root: BasePart, within: number)
	local best, bestDistance = nil, within
	for _, other in env.Ctx.Alive() do
		if other ~= participant then
			local character = env.Ctx.Character(other)
			local theirs = rootOf(character)
			if theirs and not PowerUps.Shielded(character) and math.abs(theirs.Position.Y - root.Position.Y) < 3 then
				local distance = flat(theirs.Position - root.Position).Magnitude
				if distance < bestDistance then
					best, bestDistance = other, distance
				end
			end
		end
	end
	return best, bestDistance
end

local function usePowerUp(participant, brain, root: BasePart, margin: number)
	local power = participant.Power
	local stats = PowerUps.Ready(participant)
	-- not in the calm start (a Shockwave on the crowded first tiers threw five bots in at once)
	if not stats or not power or math.random() > 0.05 or os.clock() - (brain.startedAt or 0) < brain.calm then
		return
	end
	local use = false
	if power.Id == "Turbo" then
		use = margin < 7
	elseif power.Id == "Shield" then
		use = markedNear(root.Position, 2) or (nearestRival(participant, root, 5) ~= nil and math.random() < 0.3)
	elseif power.Id == "Shockwave" then
		local count = 0
		for _, other in env.Ctx.Alive() do
			local theirs = other ~= participant and rootOf(env.Ctx.Character(other))
			if theirs and flat(theirs.Position - root.Position).Magnitude < stats.Radius * 0.5 and math.abs(theirs.Position.Y - root.Position.Y) < 4 then
				count += 1
			end
		end
		use = count >= 2
	end
	if use then
		PowerUps.Use(participant)
	end
end

-- A chimney climb: hop after hop from wall to wall, each a little higher, then a leap out onto
-- the platform by its top.
local function climbChimney(brain, character: Model, humanoid: Humanoid, root: BasePart, mind)
	local climb = brain.chimney
	if os.clock() - climb.started > 6 then
		brain.chimney = nil
		return
	end
	if root.Position.Y >= climb.top - 1 then
		brain.chimney = nil
		local exit = env.Tower:Entry(climb.exit)
		if exit and exit.state == "Solid" then
			leap(brain, character, humanoid, root, landingOn(exit, root, mind), 2.5)
		end
		return
	end
	climb.side = -climb.side
	local next = climb.centre + climb.across * climb.side * (climb.gap / 2 - 1.6)
	next = Vector3.new(next.X, math.min(root.Position.Y + KICK_RISE, climb.top), next.Z)
	leap(brain, character, humanoid, root, next, 1.2, "WallJump")
end

-- A ground pound on its own platform: up, a spin, down hard, and the platform shakes.
local function pound(participant, brain, character: Model, humanoid: Humanoid, root: BasePart)
	local move = brain.pounding
	local clock = os.clock()
	local t = clock - move.started
	if t < 0.32 then
		return
	elseif not move.falling then
		move.falling = true
		setMove(character, "PoundFall")
		root.AssemblyLinearVelocity = Vector3.new(0, -70, 0)
	elseif humanoid.FloorMaterial ~= Enum.Material.Air or t > 1.6 then
		brain.pounding = nil
		setMove(character, "PoundLand")
		local entry = env.Tower:PlatformUnder(root.Position)
		if entry then
			env.Shake(entry, participant, root.Position - Vector3.new(0, ROOT_UP, 0))
		end
		task.delay(0.35, function()
			if character.Parent and character:GetAttribute(Remotes.MoveAttr) == "PoundLand" then
				setMove(character, "Run")
			end
		end)
	end
end

function MeltBots.Step(participant, brain, character: Model, root: BasePart, lava: number)
	if not env or not brain then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local move = character:GetAttribute(Remotes.MoveAttr)
	if character:GetAttribute(Ragdoll.Attribute) or move == "Shoved" or move == "Knocked" then
		brain.flying, brain.chimney, brain.pounding = nil, nil, nil
		humanoid.JumpPower = JUMP_POWER
		return
	end
	local mind = BotMind.Of(participant)
	brain.mind = mind
	local clock = os.clock()
	brain.startedAt = brain.startedAt or clock
	if clock - brain.startedAt < brain.startDelay then
		return
	end
	local airborne = humanoid.FloorMaterial == Enum.Material.Air

	-- mid-move
	if brain.flying then
		if brain.flying.physics then
			-- a dive: physics flies it; done once it lands (or after a while)
			local t = clock - brain.flying.at
			if (not airborne and t > 0.2) or t > brain.flying.flight + 1 then
				landed(brain, character, humanoid)
			else
				return
			end
		elseif fly(brain, character, humanoid, root) then
			return
		end
	end
	if brain.chimney then
		climbChimney(brain, character, humanoid, root, mind)
		return
	end
	if brain.pounding then
		pound(participant, brain, character, humanoid, root)
		return
	end
	if airborne then
		if root.AssemblyLinearVelocity.Y < -20 then
			setMove(character, "Fall")
		end
		return
	end
	if move ~= "Run" and move ~= "Bump" and move ~= "PoundLand" then
		setMove(character, "Run")
	end

	local tower = env.Tower
	local here = tower:PlatformUnder(root.Position)
	-- down in the pit (fallen early, before the lava came): back up onto the ring, straight out
	if here == tower.Pit then
		if clock >= (brain.restUntil or 0) then
			local out = flat(root.Position - tower.origin)
			out = out.Magnitude > 0.1 and out.Unit or Vector3.new(1, 0, 0)
			local spot = tower.origin + out * (env.Layout.BaseInner + 11) + Vector3.new(0, ROOT_UP, 0) -- past the jagged edge
			brain.link = nil
			leap(brain, character, humanoid, root, spot, 2.5)
		end
		return
	end
	local hereTop = here == nil and root.Position.Y - ROOT_UP or here == tower.Base and tower.origin.Y or tower:Centre(here).Y
	local margin = hereTop - lava
	usePowerUp(participant, brain, root, margin)

	-- progress: stuck at one height too long, it'll take any way on
	if hereTop > brain.progressY + 2 then
		brain.progressY, brain.progressAt = hereTop, clock
	end
	local stuck = clock - brain.progressAt > 7

	-- standing somewhere with no platform (a wall's top, the core): leap to the nearest platform
	if not here then
		local best, bestDistance = nil, math.huge
		for id in env.Layout.Platforms do
			local entry = tower:Entry(id)
			if entry and entry.state == "Solid" then
				local centre = tower:Centre(entry)
				local distance = (centre - root.Position).Magnitude
				if distance < bestDistance and centre.Y < root.Position.Y + 6 then
					best, bestDistance = entry, distance
				end
			end
		end
		if best then
			leap(brain, character, humanoid, root, landingOn(best, root, mind), 2.5)
		end
		return
	end

	-- standing on a platform that's going: off it, now
	if here ~= tower.Base and here.state == "Warning" then
		brain.leapNow = true
	end
	-- a fireball or chunk about to land here: get off this spot, or off this platform
	local danger, from = markedNear(root.Position, 1.5)
	if danger and from then
		local out = flat(root.Position - from)
		out = out.Magnitude > 0.1 and out.Unit or Vector3.new(1, 0, 0)
		local spot = root.Position + out * 6
		if here ~= tower.Base and flat(spot - tower:Centre(here)).Magnitude > here.spec.Size * 0.8 then
			brain.link = nil -- off this platform then: the next one up, now
			brain.leapNow = true
		else
			walkTo(brain, humanoid, spot)
			return
		end
	end

	-- with time in hand: trouble for someone (not in the first seconds: a shove off the low tiers
	-- straight into the lava ended games in a few seconds)
	local spare = margin > brain.margin + 4 and not stuck and clock - brain.startedAt > brain.calm
	if spare and BotMind.Think(brain, mind) then
		local rival, distance = nearestRival(participant, root, 12)
		if rival then
			local theirs = rootOf(env.Ctx.Character(rival))
			if not theirs or tower:PlatformUnder(theirs.Position) ~= here then
				rival = nil -- only someone on its own platform (a chase across a gap ends in the lava)
			end
		end
		local who = whoIsWhere()
		local company = here ~= tower.Base and who[here] and #who[here] - 1 or 0
		if company > 0 and (mind.Style == "Opportunist" or mind.Style == "Wildcard") and clock - (brain.poundedAt or 0) > POUND_EVERY and math.random() < mind.Aggro then
			brain.poundedAt = clock
			brain.pounding = { started = clock }
			humanoid.JumpPower = math.sqrt(2 * gravity() * 4.5)
			humanoid.Jump = true
			root.AssemblyLinearVelocity = Vector3.new(0, humanoid.JumpPower, 0)
			setMove(character, "PoundSpin")
			return
		end
		if rival and math.random() < mind.Aggro * (mind.HumanBias > 0.5 and rival.Player and 1.2 or 0.8) then
			brain.chase = { who = rival, untilAt = clock + 2.5 }
		end
	end
	local chase = brain.chase
	if chase and (clock > chase.untilAt or chase.who.Out or not spare) then
		brain.chase, chase = nil, nil
	end
	if chase then
		local theirs = rootOf(env.Ctx.Character(chase.who))
		if theirs and math.abs(theirs.Position.Y - root.Position.Y) < 4 then
			local offset = flat(theirs.Position - root.Position)
			if offset.Magnitude < 4.5 and clock - (brain.shovedAt or 0) > SHOVE_EVERY then
				brain.shovedAt = clock
				brain.chase = nil
				setMove(character, "Bump")
				local push = offset.Unit * Bump.Push + Vector3.new(0, Bump.Lift, 0)
				env.OnBodyHit(character, env.Ctx.Character(chase.who), "Bump", push, Bump.Reach + 2)
				task.delay(0.3, function()
					if character.Parent and character:GetAttribute(Remotes.MoveAttr) == "Bump" then
						setMove(character, "Run")
					end
				end)
				return
			elseif offset.Magnitude < 11 and offset.Magnitude > 6 and mind.Style == "Bully" and clock - (brain.shovedAt or 0) > SHOVE_EVERY * 2 then
				-- a dive across at them
				brain.shovedAt = clock
				brain.chase = nil
				local target = env.Ctx.Character(chase.who)
				local direction = offset.Unit
				humanoid.Jump = true
				setMove(character, "Dive")
				root.AssemblyLinearVelocity = direction * 46 + Vector3.new(0, 20, 0)
				brain.flying = { at = clock, flight = 0.6, landing = theirs.Position, physics = true }
				task.delay(0.22, function()
					if env and character.Parent and not participant.Out then
						env.OnBodyHit(character, target, "Dive", direction * Bump.DivePush + Vector3.new(0, Bump.DiveLift, 0), Bump.BodyReach + 3)
					end
				end)
				return
			end
			walkTo(brain, humanoid, theirs.Position)
			return
		end
		brain.chase = nil
	end

	-- the climb: pick the way up (sticky until it's reached or gone), walk to the edge, leap
	local link = brain.link
	local target = link and tower:Entry(link.To)
	if link and (link.from ~= here or not target or target.state ~= "Solid") then
		link, target = nil, nil
	end
	if not link or stuck then
		link = chooseLink(participant, brain, mind, here, lava, root)
		if stuck then
			brain.progressAt = clock - 3 -- another go in a few seconds if this way doesn't work either
		end
		if link then
			-- well clear of the lava, no hurry: it climbs with the lava, not away from it
			local ahead = margin - brain.margin
			local wait = ahead > 14 and (0.8 + math.random() * 1.6) or spare and (0.3 + math.random() * 1.0) or 0
			link = { To = link.To, Kind = link.Kind, from = here, wait = clock + wait }
		end
		brain.link = link
		target = link and tower:Entry(link.To)
	end
	if not link or not target then
		if RunService:IsStudio() then
			character:SetAttribute("MeltBrain", string.format("on %s nowhere (%d links)", tostring(here.spec.Id), #linksFrom(here)))
		end
		-- nowhere to go: mill about the platform's middle
		if here ~= tower.Base then
			walkTo(brain, humanoid, tower:Centre(here) + Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * here.spec.Size)
		end
		return
	end
	local hereCentre = if here == tower.Base then nil else tower:Centre(here)
	if link.Kind == "Pad" then
		local pad = FloorUnder(character, root)
		if pad and pad:GetAttribute(RoundInfo.BounceAttr) and clock >= (brain.restUntil or 0) then
			leap(brain, character, humanoid, root, landingOn(target, root, mind), 3, "PoundJump")
			return
		end
		walkTo(brain, humanoid, hereCentre + Vector3.new(0, ROOT_UP, 0))
		return
	elseif link.Kind == "Chimney" then
		local chimney = nil
		for _, each in env.Layout.Chimneys do
			if each.From == here.spec.Id then
				chimney = each
			end
		end
		if chimney and flat(root.Position - hereCentre).Magnitude < 1.5 then
			brain.chimney = {
				started = clock,
				nextKick = clock,
				side = 1,
				across = chimney.Across,
				gap = chimney.Gap,
				centre = hereCentre + Vector3.new(0, ROOT_UP, 0),
				top = hereCentre.Y + chimney.Height + ROOT_UP,
				exit = chimney.To,
			}
			return
		end
		walkTo(brain, humanoid, hereCentre + Vector3.new(0, ROOT_UP, 0))
		return
	end
	-- a jump: from the edge nearest it
	local targetCentre = tower:Centre(target)
	local launch
	if here == tower.Base then
		-- the inner edge straight in from here (worked out once per way up)
		link.launch = link.launch or baseLaunch(root)
		launch = link.launch
	else
		local toward = flat(targetCentre - hereCentre)
		toward = toward.Magnitude > 0.1 and toward.Unit or Vector3.new(1, 0, 0)
		launch = hereCentre + toward * here.spec.Size * 0.6 + Vector3.new(0, ROOT_UP, 0)
	end
	local close = flat(launch - root.Position).Magnitude < LAUNCH_NEAR
	if brain.leapNow or (close and clock >= link.wait and clock >= (brain.restUntil or 0)) then
		brain.leapNow = nil
		brain.link = nil
		-- now and then the clumsy misjudge one (a skill of 0.55 misses about one leap in eight)
		local short = math.random() < (1 - mind.Skill) * 0.28
		leap(brain, character, humanoid, root, landingOn(target, root, mind), 2 + (mind.Skill > 0.8 and 0 or 0.8), nil, short)
		return
	end
	walkTo(brain, humanoid, launch)
	if RunService:IsStudio() then
		character:SetAttribute("MeltBrain", string.format("on %s to %s (%s) d%.1f wait%.1f margin%.0f", tostring(here.spec.Id), tostring(link.To), link.Kind, flat(launch - root.Position).Magnitude, link.wait - clock, margin))
	end
end

return MeltBots
