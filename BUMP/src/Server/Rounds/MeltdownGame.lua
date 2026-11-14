--!nonstrict
--[[
	MELTDOWN, on the server: climb away from the rising lava.

	The user (2026-11-14): "Let's get a third gamemode in here. Probably something completely new,
	intense, and incredibly fun". Their choices: a climb up a tower of floating platforms with lava
	rising, last one standing; crumbling and moving platforms, bounce pads and wall-jump chimneys;
	lava fireballs, lava surges and falling debris.

	A tower (Server/Rounds/Tower, laid out by Shared/Minigames/MeltLayout) stands in the lobby's
	pit, a ring of start tiles round it. After a short grace the lava rises, quicker and quicker;
	every so often it surges (a rumble, "SURGE!", then a lurch up). Fireballs leap out of it onto
	platforms near people (a ring marks the spot) and stagger whoever is there; later, chunks fall
	from the sky (a shadow marks the spot), knocking people flat and cracking the platform they hit.
	Touch the lava and you're out. A ground pound shakes the platform you land on: everyone else on
	it staggers. When the lava nears the top it stops a few studs under the summit and the top tiers
	crumble one by one, so the last of them fight it out up there. Last one standing wins; a hidden
	time limit lets the survivors share first.

	The bots' brains are Server/Rounds/MeltBots. Every number is in MoveConfig.Melt.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local MeltLayout = require("@Shared/Minigames/MeltLayout")
local Ragdoll = require("@Shared/Ragdoll")
local Remotes = require("@Shared/Movement/Remotes")
local RoundInfo = require("@Shared/Rounds/RoundInfo")
local Tuning = require("@Shared/Movement/Tuning")
local World = require("@Shared/World")
local BumpServer = require("@GameServer/Systems/BumpServer")
local MeltBots = require("@GameServer/Rounds/MeltBots")
local PowerUps = require("@GameServer/Rounds/PowerUps")
local Tower = require("@GameServer/Rounds/Tower")

local Melt = Tuning.Of("Melt")
local Hits = Tuning.Of("BumpHits")

local MeltdownGame = {}

local ORIGIN = World.ArenaOrigin
local MELT_REACH = 40 -- a player's "I touched the lava" is believed if the server has them this close above it
local MELT_RESEND = 0.5

-- the running game: { ctx, tower, layout, bots = { [id] = brain }, marks = { { Position, Radius, Until } }, ... }
local state = nil
local shockwave, rescue -- power-up effects, further down

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

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * math.clamp(t, 0, 1)
end

local function participantOfModel(model: Model?)
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

local function participantOfPlayer(player: Player)
	if not state then
		return nil
	end
	for _, participant in state.ctx.Seats do
		if participant.Player == player then
			return participant
		end
	end
	return nil
end

-- Who did it, for the card if they go in the lava soon after (`by` nil: a fireball, debris).
local function blame(participant, by, how: string?)
	participant.LastHitAt = os.clock()
	participant.LastHitBy = by ~= participant and by or nil
	participant.LastHitHow = how
end

-- Thrown (and flattened, if `flatten`).
local function knock(participant, velocity: Vector3, flatten: boolean, by, how: string?)
	local character = state.ctx.Character(participant)
	if not character then
		return
	end
	blame(participant, by, how)
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

-- Staggered back on their feet (the shove's stagger).
local function stagger(participant, velocity: Vector3, by, how: string?)
	local character = state.ctx.Character(participant)
	if not character then
		return
	end
	blame(participant, by, how)
	BumpServer.Shove(character, velocity)
end

-- The start ring or the pit's floor (no one middle, never crumbles).
local function ground(entry): boolean
	return entry == Tower.Base or entry == Tower.Pit
end

local function away(from: Vector3, to: Vector3): Vector3
	local offset = flat(to - from)
	return offset.Magnitude > 0.1 and offset.Unit or Vector3.new(math.random() - 0.5, 0, math.random() - 0.5).Unit
end

-- ═══ the platforms ════════════════════════════════════════════════════════════════

-- A ground pound shakes the platform it lands on: everyone else on it staggers away from the
-- pound, and a crumbling one goes at once.
local function shake(entry, source, at: Vector3)
	if not state or not entry then
		return
	end
	local tower = state.tower
	local centre = if ground(entry) then at else tower:Centre(entry)
	Remotes.Fx("Shake", { Position = centre, Size = entry.spec.Size, Id = entry.spec.Id })
	for _, other in state.ctx.Alive() do
		local character = state.ctx.Character(other)
		local theirs = rootOf(character)
		if other ~= source and theirs and not PowerUps.Shielded(character) then
			local under = tower:PlatformUnder(theirs.Position)
			local near = not ground(entry) or (theirs.Position - at).Magnitude < 16
			if under == entry and near then
				stagger(other, away(at, theirs.Position) * Melt.ShakePush + Vector3.new(0, Melt.ShakeLift, 0), source, "pound")
			end
		end
	end
	if not ground(entry) and entry.spec.Kind == "Crumble" then
		tower:Crumble(entry, 0.25, Melt.CrumbleBack)
	end
end

-- A player's ground pound landing (Platformer sends "Pound" with where it landed).
local function onPound(player: Player, position)
	if not state or typeof(position) ~= "Vector3" then
		return
	end
	local participant = participantOfPlayer(player)
	local root = participant and not participant.Out and rootOf(state.ctx.Character(participant))
	if not root or (root.Position - position).Magnitude > 14 then
		return
	end
	shake(state.tower:PlatformUnder(position + Vector3.new(0, 0.5, 0)), participant, position)
end

-- BumpServer's body hits while this game runs: shoves stagger, dives throw (no flattening, so the
-- climb goes on), a pound's own hits are the shake's; a Shield shrugs them all off.
local function onBodyHit(attacker: Model?, target: Model, kind: string, throw: Vector3, reach: number): boolean
	if not state then
		return false
	end
	local from, to = participantOfModel(attacker), participantOfModel(target)
	local mine, theirs = rootOf(attacker), rootOf(target)
	if not from or not to or from.Out or to.Out or not mine or not theirs then
		return false
	end
	if kind == "Pound" then
		return true -- the platform's shake deals with everyone on it
	end
	if (theirs.Position - mine.Position).Magnitude > reach or PowerUps.Shielded(target) then
		return true
	end
	if kind == "Bump" then
		stagger(to, throw, from, "shove")
	else
		knock(to, throw * 0.8, false, from, "dive")
	end
	Remotes.Fx("Bump", { Position = (mine.Position + theirs.Position) / 2, Kind = kind })
	return true
end

-- ═══ the lava ═════════════════════════════════════════════════════════════════════

local function summitTop(): number
	return ORIGIN.Y + state.layout.Platforms[state.layout.Summit].Position.Y
end

-- Into the lava: out (unless a Second Chance catches them), by whoever knocked them in.
local function melt(participant)
	if participant.Out or participant.Melting then
		return
	end
	if PowerUps.TryRescue(participant) then
		return
	end
	local root = rootOf(state.ctx.Character(participant))
	local recent = os.clock() - (participant.LastHitAt or -100) < 4
	participant.Melting = true
	if root then
		Remotes.Fx("Melt", { Position = Vector3.new(root.Position.X, state.tower:Lava(), root.Position.Z), Seat = participant.Seat })
	end
	state.ctx.Eliminate(participant, "melted", recent and participant.LastHitBy or nil, recent and participant.LastHitHow or nil)
end

-- A player's own client saw them touch the lava (the server's copy of a falling body lags, so
-- this is sooner); believed if the server has them anywhere near it.
local function onMelted(player: Player)
	if not state then
		return
	end
	local participant = participantOfPlayer(player)
	if not participant or participant.Out then
		return
	end
	local clock = os.clock()
	if clock - (participant.MeltAskedAt or 0) < MELT_RESEND then
		return
	end
	participant.MeltAskedAt = clock
	local root = rootOf(state.ctx.Character(participant))
	if root and root.Position.Y < state.tower:Lava() + MELT_REACH then
		melt(participant)
	end
end

local function lavaRate(t: number): number
	if t < Melt.Grace then
		return 0
	end
	local rate = lerp(Melt.RiseStart, Melt.RiseMax, (t - Melt.Grace) / Melt.RiseRamp)
	local surge = state.surge
	if surge and t >= surge.from and t < surge.from + Melt.SurgeTime then
		rate += Melt.SurgeRise / Melt.SurgeTime
	end
	return rate
end

-- ═══ hazards ══════════════════════════════════════════════════════════════════════

-- A spot to drop something on near someone still climbing: on their platform, a little off them.
local function targetSpot(): (Vector3?, any)
	local alive = state.ctx.Alive()
	if #alive == 0 then
		return nil, nil
	end
	for _ = 1, 4 do
		local participant = alive[math.random(1, #alive)]
		local root = rootOf(state.ctx.Character(participant))
		if root then
			local entry = state.tower:PlatformUnder(root.Position, 9)
			if entry and not ground(entry) then
				local centre = state.tower:Centre(entry)
				local offset = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * entry.spec.Size
				return centre + offset, entry
			elseif entry then
				local offset = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * 8
				local floor = entry == Tower.Pit and ORIGIN.Y - Melt.PitDrop or ORIGIN.Y
				return Vector3.new(root.Position.X, floor, root.Position.Z) + offset, entry
			end
		end
	end
	return nil, nil
end

local function mark(position: Vector3, radius: number, seconds: number)
	table.insert(state.marks, { Position = position, Radius = radius, Until = os.clock() + seconds })
end

local function fireball()
	local to = targetSpot()
	if not to then
		return
	end
	local lava = state.tower:Lava()
	local angle = math.random() * math.pi * 2
	local from = Vector3.new(to.X, lava, to.Z) + Vector3.new(math.cos(angle), 0, math.sin(angle)) * (14 + math.random() * 10)
	local flight = Melt.FireballFlight
	Remotes.Fx("Fireball", { From = from, To = to, Flight = flight, Radius = Melt.FireballRadius })
	mark(to, Melt.FireballRadius + 1, flight + 0.2)
	state.fireballs = (state.fireballs or 0) + 1
	task.delay(flight, function()
		if not state then
			return
		end
		Remotes.Fx("FireballHit", { Position = to, Radius = Melt.FireballRadius })
		for _, participant in state.ctx.Alive() do
			local character = state.ctx.Character(participant)
			local root = rootOf(character)
			if root and not PowerUps.Shielded(character) then
				local above = root.Position.Y - to.Y
				if flat(root.Position - to).Magnitude < Melt.FireballRadius + 1 and above > -1.5 and above < 7 then
					stagger(participant, away(to, root.Position) * Melt.FireballPush + Vector3.new(0, Melt.FireballLift, 0), nil, "fireball")
				end
			end
		end
	end)
end

local function debris()
	local to, entry = targetSpot()
	if not to then
		return
	end
	local warn = Melt.DebrisWarn
	Remotes.Fx("Debris", { To = to, Warn = warn, Radius = Melt.DebrisRadius })
	mark(to, Melt.DebrisRadius + 1, warn + 0.2)
	state.debris = (state.debris or 0) + 1
	task.delay(warn, function()
		if not state then
			return
		end
		Remotes.Fx("DebrisHit", { Position = to, Radius = Melt.DebrisRadius })
		for _, participant in state.ctx.Alive() do
			local character = state.ctx.Character(participant)
			local root = rootOf(character)
			if root and not PowerUps.Shielded(character) then
				local above = root.Position.Y - to.Y
				if flat(root.Position - to).Magnitude < Melt.DebrisRadius + 1 and above > -1.5 and above < 8 then
					knock(participant, away(to, root.Position) * Melt.DebrisPush + Vector3.new(0, Melt.DebrisLift, 0), true, nil, "debris")
				end
			end
		end
		-- it cracks the platform it lands on
		if entry and not ground(entry) and entry.spec.Kind ~= "Summit" then
			state.tower:Crumble(entry, 0.9, Melt.CrumbleBack)
		end
	end)
end

-- ═══ power-ups (Server/Rounds/PowerUps) ═══════════════════════════════════════════

-- Shockwave: a boom that staggers everyone in reach on your own level away from you, and shakes
-- the crumbling platforms there loose.
function shockwave(participant, at: Vector3, reach: number)
	if not state then
		return
	end
	Remotes.Fx("Ripple", { Position = at - Vector3.new(0, 3, 0), Radius = reach, Speed = 70, Height = 1.6 })
	for _, other in state.ctx.Alive() do
		local character = state.ctx.Character(other)
		local theirs = rootOf(character)
		if other ~= participant and theirs and not PowerUps.Shielded(character) then
			-- on your own level only (it ran through the tiers above and below and cleared the tower)
			local offset = theirs.Position - at
			if flat(offset).Magnitude <= reach and math.abs(offset.Y) < 5 then
				stagger(other, away(at, theirs.Position) * 48 + Vector3.new(0, 20, 0), participant, "shockwave")
			end
		end
	end
	for id in state.layout.Platforms do
		local entry = state.tower:Entry(id)
		if entry and entry.spec.Kind == "Crumble" and (state.tower:Centre(entry) - at).Magnitude <= reach then
			state.tower:Crumble(entry, 0.4, Melt.CrumbleBack)
		end
	end
end

-- Second Chance: onto a solid platform well above the lava.
function rescue(participant)
	if not state then
		return
	end
	local character = state.ctx.Character(participant)
	local root = rootOf(character)
	if not character or not root then
		return
	end
	local spot = state.tower:SafeAbove(state.tower:Lava() + 10) or state.tower:Centre(state.tower:Entry(state.layout.Summit))
	spot += Vector3.new(0, 5, 0)
	participant.KnockedAt = nil
	participant.Melting = nil
	character:SetAttribute(Ragdoll.Attribute, false)
	character:SetAttribute(Remotes.MoveAttr, "Fall")
	root.AssemblyLinearVelocity = Vector3.zero
	BumpServer.Teleport(character, CFrame.new(spot) * character:GetPivot().Rotation)
	if participant.Player then
		Remotes.You(participant.Player, "Rescue", { Position = spot })
	end
end

-- ═══ the game ═════════════════════════════════════════════════════════════════════

function MeltdownGame.Init()
	BumpServer.OnAct("Pound", onPound)
	BumpServer.OnAct("Melted", onMelted)
end

function MeltdownGame.Setup(ctx)
	local seed = math.random(1, 1e6)
	local layout = MeltLayout.Build(seed, Melt)
	local tower = Tower.new(layout, ORIGIN)
	tower:SetLava(Melt.LavaStart, 0)
	state = { ctx = ctx, tower = tower, layout = layout, bots = {}, marks = {} }
	local count, chimneys, pads = 0, #layout.Chimneys, 0
	for _, platform in layout.Platforms do
		count += 1
		if platform.Pad then
			pads += 1
		end
	end
	print(string.format("[Melt] tower from seed %d: %d platforms, %d pads, %d chimneys", layout.Seed, count, pads, chimneys))
	BumpServer.SetBodyHitHandler(onBodyHit)
	PowerUps.SetGame({ Shockwave = shockwave, Rescue = rescue })
	MeltBots.Bind({
		Tower = tower,
		Layout = layout,
		Marks = function()
			return state and state.marks or {}
		end,
		Ctx = ctx,
		OnBodyHit = onBodyHit,
		Shake = shake,
	})
	ctx.SetNote("")
	return tower:ShowSeconds()
end

-- Once the tower has landed: everyone round the start ring, facing in.
function MeltdownGame.Place(ctx)
	local alive = ctx.Alive()
	local turn = math.random() * math.pi * 2
	for index, participant in alive do
		local angle = turn + (index - 1) / #alive * math.pi * 2
		local spot = ORIGIN + Vector3.new(math.cos(angle), 0, math.sin(angle)) * Melt.StartRadius + Vector3.new(0, 4, 0)
		local cframe = CFrame.lookAt(spot, Vector3.new(ORIGIN.X, spot.Y, ORIGIN.Z))
		participant.Melting = nil
		if participant.Bot then
			-- side by side: one bot's body slow to load (its avatar) mustn't hold the rest up
			state.bots[participant.Id] = MeltBots.NewBrain(participant)
			task.spawn(function()
				local model = ctx.SpawnBot(participant, cframe)
				model:SetAttribute(Ragdoll.Attribute, false)
				model:SetAttribute(Remotes.MoveAttr, "Run")
			end)
		else
			local character = ctx.Character(participant)
			if character then
				character:SetAttribute(Ragdoll.Attribute, false)
				BumpServer.Teleport(character, cframe)
			end
		end
	end
end

function MeltdownGame.OnEliminated(ctx, participant)
	if not state then
		return
	end
	local character = ctx.Character(participant)
	local stand = World.LobbySpot()
	local melted = participant.Melting
	participant.Melting = nil
	local function gone()
		if not state then
			return -- the round puts everyone where they go
		end
		if participant.Bot then
			if participant.Model then
				participant.Model:Destroy()
				participant.Model = nil
			end
		elseif character and character.Parent then
			character:SetAttribute(Ragdoll.Attribute, false)
			character:SetAttribute(Remotes.MoveAttr, "Run")
			BumpServer.Teleport(character, stand)
		end
	end
	if melted and character then
		-- a yelp up out of the lava, limp, smoking (MeltFx), Mario style
		character:SetAttribute(Ragdoll.Attribute, true)
		character:SetAttribute(Remotes.MoveAttr, "Knocked")
		character:SetAttribute("BumpMelted", true)
		local spin = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * 16
		BumpServer.Throw(character, Vector3.new(spin.X, 70, spin.Z))
	end
	if participant.Bot then
		task.delay(melted and 1.1 or 0.2, gone)
	else
		task.delay(RoundInfo.KnockoutHold, function()
			if character and character.Parent then
				character:SetAttribute("BumpMelted", nil)
			end
			gone()
		end)
	end
end

function MeltdownGame.Run(ctx)
	local tower = state.tower
	local startedAt = now()
	state.nextSurge = Melt.SurgeFirst
	state.nextFireball = Melt.FireballFirst
	state.nextDebris = Melt.DebrisFirst
	state.nextSummit = nil
	local lastRate, lastRateAt = -1, 0
	local stopped = false
	local surges, summitDrops = 0, 0
	ctx.SetNote("CLIMB!")
	task.delay(2.5, function()
		if state and state.ctx == ctx and not state.noteBusy then
			ctx.SetNote("")
		end
	end)
	while true do
		RunService.Heartbeat:Wait()
		local alive = ctx.Alive()
		local t = now() - startedAt
		if #alive <= 1 or t >= Melt.TimeLimit then
			break
		end
		local lava = tower:Lava()
		local top = summitTop()
		local cap = top - Melt.LavaStop

		-- the rise (sent to the clients only when it changes, they move the lava themselves)
		if not stopped then
			if lava >= cap then
				stopped = true
				tower:SetLava(cap, 0)
				lava = cap
			else
				local rate = lavaRate(t)
				if math.abs(rate - lastRate) > 0.05 or os.clock() - lastRateAt > 2 then
					lastRate, lastRateAt = rate, os.clock()
					tower:SetLava(lava, rate)
				end
			end
		end

		-- surges
		if not stopped and t >= state.nextSurge then
			surges += 1
			state.nextSurge = t + Melt.SurgeMin + math.random() * (Melt.SurgeMax - Melt.SurgeMin)
			state.surge = { from = t + Melt.SurgeWarn }
			state.noteBusy = true
			ctx.SetNote("SURGE!")
			Remotes.Fx("Surge", { Warn = Melt.SurgeWarn, Rise = Melt.SurgeRise, Time = Melt.SurgeTime })
			print(string.format("[Melt] surge %d at %.1f s, lava %.1f", surges, t, lava))
			task.delay(Melt.SurgeWarn + Melt.SurgeTime, function()
				if state and state.ctx == ctx then
					state.noteBusy = false
					ctx.SetNote("")
				end
			end)
		end

		-- the hotter it gets, the more comes at you
		local heat = math.clamp((t - Melt.Grace) / (Melt.RiseRamp + 10), 0, 1)
		if t >= state.nextFireball then
			fireball()
			state.nextFireball = t + lerp(Melt.FireballSlow, Melt.FireballFast, heat) * (0.7 + math.random() * 0.6)
		end
		if t >= state.nextDebris then
			debris()
			state.nextDebris = t + lerp(Melt.DebrisSlow, Melt.DebrisFast, heat) * (0.7 + math.random() * 0.6)
		end

		-- the summit's last stand: the top tiers crumble one by one, for good
		if lava >= top - Melt.SummitCrumble then
			if not state.nextSummit then
				state.nextSummit = t
				state.noteBusy = true
				ctx.SetNote("TO THE TOP!")
				task.delay(3, function()
					if state and state.ctx == ctx then
						state.noteBusy = false
						ctx.SetNote("")
					end
				end)
			end
			if t >= state.nextSummit then
				state.nextSummit = t + Melt.SummitEvery
				local choices = {}
				for _, platform in state.layout.Platforms do
					local entry = tower:Entry(platform.Id)
					if entry and entry.state == "Solid" and platform.Kind ~= "Summit" and platform.Tier >= state.layout.Tiers - 4 then
						table.insert(choices, entry)
					end
				end
				if #choices > 0 then
					summitDrops += 1
					tower:Crumble(choices[math.random(1, #choices)], 1.2, nil)
				end
			end
		end

		-- marks that have landed are gone
		for index = #state.marks, 1, -1 do
			if os.clock() > state.marks[index].Until then
				table.remove(state.marks, index)
			end
		end

		-- the platforms, then everyone
		local bodies = {}
		for _, participant in alive do
			local character = ctx.Character(participant)
			local root = rootOf(character)
			if root then
				table.insert(bodies, { model = character, root = root, bot = participant.Bot })
			end
		end
		tower:Step(now(), bodies, Melt.CrumbleWarn, Melt.CrumbleBack)
		local heights = {}
		for _, participant in alive do
			local character = ctx.Character(participant)
			local root = rootOf(character)
			if not character or not character.Parent or not root then
				-- a bot whose body is still loading gets a few seconds' grace
				if not (participant.Bot and t < 10) then
					ctx.Eliminate(participant, "no body")
				end
			elseif root.Position.Y < lava + 1 then
				melt(participant)
			else
				table.insert(heights, root.Position.Y)
				if participant.Bot then
					MeltBots.Step(participant, state.bots[participant.Id], character, root, lava)
				end
			end
		end

		-- intensity (the music): how close the lava is to the middle of the pack, and how many are out
		table.sort(heights)
		local middle = heights[math.max(1, math.ceil(#heights / 2))]
		local closeness = middle and math.clamp(1 - (middle - lava) / 45, 0, 1) or 1
		local total = #ctx.Seats
		local out = total > 1 and (total - #alive) / (total - 1) or 0
		ctx.SetIntensity(math.max(closeness, out * 0.8, heat * 0.6))
	end
	print(string.format("[Melt] over at %.1f s: %d surges, %d fireballs, %d debris, %d summit drops, lava at %.1f", now() - startedAt, surges, state.fireballs or 0, state.debris or 0, summitDrops, tower:Lava()))
	ctx.SetNote("")
end

function MeltdownGame.Cleanup(ctx)
	if not state then
		return
	end
	for _, participant in ctx.Seats do
		participant.Melting = nil
		local character = ctx.Character(participant)
		if character then
			character:SetAttribute(Ragdoll.Attribute, false)
			character:SetAttribute("BumpMelted", nil)
		end
	end
	BumpServer.SetBodyHitHandler(nil)
	MeltBots.Bind(nil)
	ctx.SetNote("")
	state.tower:Destroy()
	state = nil
end

return MeltdownGame
