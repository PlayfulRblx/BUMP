--!nonstrict
--[[
	The server's side of moving and bumping.

	- Declares the remotes and, in Studio, publishes the tuning numbers (Shared/Movement/Tuning).
	- Tags every character as a body that can be bumped, and copies each player's move ("Move")
	  onto their character so other clients can pose them.
	- Checks each "Bump" a client claims (close enough, not too often) and throws the target: a
	  player is told by their own client ("Knock"), since that client moves their body; a dummy
	  is thrown here. Everyone sees a pop.
	- Three practice dummies stand in the yard to bump. One that goes far or falls is put back.
	- Moves and flings bodies the engine's anti-cheat will let stand (BumpServer.Teleport,
	  BumpServer.AllowFast): in a live server its anti-teleport check snaps a player back from any
	  jump of 80+ studs in a second, server moves included (in Studio it only warns), so the games
	  put players on the arena and they were snapped straight back to the plaza (the user,
	  2026-11-14, in a live server: "I'm added to the games outside of the arena").
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local AntiCheatHandlerServer = require("@Engine/Server/EngineSystems/AntiCheat/AntiCheatHandlerServer")
local Remotes = require("@Shared/Movement/Remotes")
local Tuning = require("@Shared/Movement/Tuning")
local World = require("@Shared/World")
local Ragdoll = require("@Shared/Ragdoll")

local Bump = Tuning.Of("Bump")

local BumpServer = {}

local MOVES = {
	Run = true, Crouch = true, Fall = true, Jump = true, AirJump = true,
	Backflip = true, LongJump = true, PoundSpin = true, PoundFall = true, PoundLand = true,
	PoundJump = true, Dive = true, Slide = true, Rollout = true, Roll = true, Bump = true,
	WallCling = true, WallSlide = true, WallJump = true, Knocked = true, Shoved = true, LandRoll = true, Bonk = true,
	Ride = true, RideCharge = true, RideDash = true, RideSkrrt = true, RideWobble = true,
	Hero = true,
}

local KINDS = { Bump = true, Dive = true, Pound = true }
local REACH_SLACK = 6 -- studs of latency allowance on top of the client's reach
local MIN_GAP = 0.12 -- seconds between bumps from one player (a pound can hit several at once)

local DUMMY_SPOTS = {
	Vector3.new(-30, 3, 30),
	Vector3.new(-40, 3, 40),
	Vector3.new(-20, 3, 44),
}

local lastBumpAt = {} -- [Player] = os.clock()
local actHandlers = {} -- [action] = { function(player, ...) }: other systems' client actions
-- A game can take over a body hit (BUMP: hitting someone on a ball hits their ball instead):
-- function(attacker: Model, target: Model, kind: string, throw: Vector3, reach: number) -> true
-- if it dealt with it (it checks its own reach).
local bodyHitHandler = nil
local dummies = {} -- [Model] = home

local function rootOf(model: Model?): BasePart?
	local root = model and model:FindFirstChild("HumanoidRootPart")
	return root and root:IsA("BasePart") and root or nil
end

local function throwVector(kind: string, from: Vector3, to: Vector3): Vector3
	local away = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	away = away.Magnitude > 0.1 and away.Unit or Vector3.new(0, 0, 1)
	if kind == "Dive" then
		return away * Bump.DivePush + Vector3.new(0, Bump.DiveLift, 0)
	elseif kind == "Pound" then
		return away * Bump.PoundPush + Vector3.new(0, Bump.PoundLift, 0)
	end
	return away * Bump.Push + Vector3.new(0, Bump.Lift, 0)
end

local function knockDummy(model: Model, velocity: Vector3)
	local root = rootOf(model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return
	end
	-- knocked flat the same way a player is (Shared/Ragdoll follows the attribute)
	model:SetAttribute("BumpRagdoll", true)
	Ragdoll.Fling(model, velocity, Vector3.new(math.random() * 8 - 4, 0, math.random() * 8 - 4))
	model:SetAttribute(Remotes.MoveAttr, "Knocked")
	local mine = os.clock()
	model:SetAttribute("BumpKnockedAt", mine)
	task.delay(1.4, function()
		if model.Parent and model:GetAttribute("BumpKnockedAt") == mine then
			model:SetAttribute("BumpRagdoll", false)
			model:SetAttribute(Remotes.MoveAttr, "Run")
		end
	end)
end

local function onBump(player: Player, target, kind)
	if typeof(target) ~= "Instance" or not target:IsA("Model") or not KINDS[kind] then
		return
	end
	if not CollectionService:HasTag(target, Remotes.BodyTag) or target == player.Character then
		return
	end
	local now = os.clock()
	if now - (lastBumpAt[player] or 0) < MIN_GAP then
		return
	end
	local mine, theirs = rootOf(player.Character), rootOf(target)
	if not mine or not theirs then
		return
	end
	local reach = kind == "Pound" and Tuning.Of("Pound").ShockRadius or Bump.Reach
	local velocity = throwVector(kind, mine.Position, theirs.Position)
	-- a game gets first say, and checks its own reach (BUMP: to a rider's ball, not their body)
	if bodyHitHandler and bodyHitHandler(player.Character, target, kind, velocity, reach + REACH_SLACK) then
		lastBumpAt[player] = now
		return
	end
	if (mine.Position - theirs.Position).Magnitude > reach + REACH_SLACK then
		return
	end
	lastBumpAt[player] = now
	local victim = Players:GetPlayerFromCharacter(target)
	if kind == "Bump" then
		-- a shove staggers them back on their feet
		BumpServer.Shove(target, velocity)
	elseif victim then
		BumpServer.AllowFast(target, 2.5)
		Remotes.You(victim, "Knock", { Velocity = velocity, Kind = kind })
	elseif dummies[target] then
		knockDummy(target, velocity)
	end
	Remotes.Fx("Bump", { Position = (mine.Position + theirs.Position) / 2, Kind = kind })
end

local function spawnDummy(home: Vector3, index: number)
	local model = Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
	model.Name = "Dummy" .. index
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	humanoid.DisplayName = "Dummy"
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	model:PivotTo(CFrame.new(home))
	model.Parent = Workspace
	-- a description's colours don't reach the body: paint it (light grey, a practice dummy)
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			part.Color = (part.Name:find("Leg") or part.Name:find("Foot")) and Color3.fromRGB(120, 124, 132) or Color3.fromRGB(196, 200, 206)
		end
	end
	local root = rootOf(model)
	if root then
		root:SetNetworkOwner(nil)
	end
	CollectionService:AddTag(model, Remotes.BodyTag)
	dummies[model] = home
	humanoid.Died:Once(function()
		dummies[model] = nil
		task.delay(2, function()
			model:Destroy()
			spawnDummy(home, index)
		end)
	end)
end

local function watchDummies()
	while true do
		task.wait(1)
		for model, home in dummies do
			local root = rootOf(model)
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			if root and humanoid and model:GetAttribute("BumpRagdoll") ~= true then
				local far = (root.Position - home).Magnitude > 70 or root.Position.Y < home.Y - 33
				if far then
					root.AssemblyLinearVelocity = Vector3.zero
					model:PivotTo(CFrame.new(home))
				end
			end
		end
	end
end

local function characterAdded(character: Model)
	CollectionService:AddTag(character, Remotes.BodyTag)
	character:SetAttribute(Remotes.MoveAttr, "Run")
	-- the stock jump is off on the client; keep it short here too in case it slips through
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid then
		humanoid.UseJumpPower = true
		humanoid.JumpPower = 0
	end
end

-- Another system's client action on the shared "Act" stream ("Mount", "Dismount"...). Several
-- systems can listen for one ("Pound": BUMP's ripple and MELTDOWN's shake), each checking whether
-- its own game is running.
function BumpServer.OnAct(action: string, handler)
	actHandlers[action] = actHandlers[action] or {}
	table.insert(actHandlers[action], handler)
end

function BumpServer.SetBodyHitHandler(handler)
	bodyHitHandler = handler
end

-- Shoved (the user, 2026-11-13: the victim's reaction was "dull"): staggered back on their feet
-- rather than knocked about. A player's own client is told (Knock, Kind "Bump": it plays the
-- Shoved move); a server body (a bot, a dummy) is slid back here by a LinearVelocity that slows
-- with Bump.ShoveSkid, playing the same Stagger, and has itself back after Bump.ShoveTime.
function BumpServer.Shove(model: Model, velocity: Vector3)
	local player = Players:GetPlayerFromCharacter(model)
	if player then
		BumpServer.AllowFast(model, 1.5)
		Remotes.You(player, "Knock", { Velocity = velocity, Kind = "Bump" })
		return
	end
	local root = rootOf(model)
	if not root then
		return
	end
	local mine = os.clock()
	model:SetAttribute("BumpShovedAt", mine)
	model:SetAttribute(Remotes.MoveAttr, "Shoved")
	local old = root:FindFirstChild("BumpShoveSlide")
	if old then
		old:Destroy()
	end
	local attachment = root:FindFirstChild("RootAttachment") or root:FindFirstChildOfClass("Attachment")
	if not attachment then
		attachment = Instance.new("Attachment")
		attachment.Parent = root
	end
	local planar = Vector3.new(velocity.X, 0, velocity.Z)
	local slide = Instance.new("LinearVelocity")
	slide.Name = "BumpShoveSlide"
	slide.Attachment0 = attachment
	slide.RelativeTo = Enum.ActuatorRelativeTo.World
	slide.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	slide.PrimaryTangentAxis = Vector3.xAxis
	slide.SecondaryTangentAxis = Vector3.zAxis
	slide.PlaneVelocity = Vector2.new(planar.X, planar.Z)
	slide.MaxForce = 1e6
	slide.Parent = root
	root.AssemblyLinearVelocity = Vector3.new(planar.X, velocity.Y, planar.Z)
	task.spawn(function()
		local started = os.clock()
		while slide.Parent and os.clock() - started < Bump.ShoveTime do
			local dt = RunService.Heartbeat:Wait()
			local speed = math.max(0, planar.Magnitude - Bump.ShoveSkid * dt)
			planar = planar.Magnitude > 0.01 and planar.Unit * speed or Vector3.zero
			slide.PlaneVelocity = Vector2.new(planar.X, planar.Z)
		end
		slide:Destroy()
		if model.Parent and model:GetAttribute("BumpShovedAt") == mine and model:GetAttribute(Remotes.MoveAttr) == "Shoved" then
			model:SetAttribute(Remotes.MoveAttr, "Run")
		end
	end)
end

-- Lets a player's character move fast for `seconds` without the engine's anti-cheat (speed and
-- teleport checks) snapping it back: a throw, a ride on a ball. 0 ends it (with the anti-cheat's
-- own short grace after). Nothing for a bot, which the anti-cheat doesn't watch.
function BumpServer.AllowFast(model: Model?, seconds: number)
	if model and Players:GetPlayerFromCharacter(model) then
		AntiCheatHandlerServer.logLastHighSpeedMovementForCharacter(model, nil, seconds)
	end
end

-- Moves a body to `cframe`, telling the engine's anti-cheat it's the game's own move (it snaps
-- players back from long moves otherwise; in a live server, not in Studio).
function BumpServer.Teleport(model: Model?, cframe: CFrame)
	if not model then
		return
	end
	local player = Players:GetPlayerFromCharacter(model)
	if player then
		AntiCheatHandlerServer.logLastHighSpeedMovementForCharacter(model, cframe, 1.5)
	end
	model:PivotTo(cframe)
	if player then
		-- their own client turns them (and their camera) to face this way (Platformer)
		Remotes.You(player, "Placed", { CFrame = cframe })
	end
end

-- Throws a participant's body: a player's own client is told (it moves its body), a server
-- body (a bot, a dummy) is thrown here.
function BumpServer.Throw(model: Model, velocity: Vector3)
	local player = Players:GetPlayerFromCharacter(model)
	if player then
		BumpServer.AllowFast(model, 2.5)
		Remotes.You(player, "Knock", { Velocity = velocity })
		return
	end
	-- every part, so a body going limp right now still flies (Ragdoll.Fling)
	Ragdoll.Fling(model, velocity)
end

function BumpServer.init()
	Remotes.Declare()
	Tuning.Publish()
end

function BumpServer.start()
	Remotes.HookAct(function(player, action, a, b)
		if action == "Move" then
			local character = player.Character
			if character and type(a) == "string" and MOVES[a] then
				character:SetAttribute(Remotes.MoveAttr, a)
			end
		elseif action == "Bump" then
			onBump(player, a, b)
		elseif actHandlers[action] then
			for _, handler in actHandlers[action] do
				task.spawn(handler, player, a, b)
			end
		end
	end)

	local function playerAdded(player: Player)
		player.CharacterAdded:Connect(function(character)
			characterAdded(character)
		end)
		if player.Character then
			task.spawn(characterAdded, player.Character)
		end
	end
	Players.PlayerAdded:Connect(playerAdded)
	for _, player in Players:GetPlayers() do
		playerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastBumpAt[player] = nil
	end)

	for index, home in DUMMY_SPOTS do
		spawnDummy(World.YardOrigin + home, index)
	end
	task.spawn(watchDummies)
end

return BumpServer
