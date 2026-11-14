--!nonstrict
--[[
	Full-body animation for every body (players and dummies), on every client, from clips authored
	in Blender (animation/README.md). Nothing is uploaded and nothing replicates: each client
	plays every body's clip itself, from the move that body is in.

	Your own move comes straight from Platformer, so a jump animates the frame you press it.
	Everyone else's comes from the "BumpMove" attribute the server copies onto their character.
	Every change of move is also handed to BumpFx, so dust and stars play for every body.

	Each frame, after Roblox's own Animate script has run, every joint the chosen clip names is
	pulled toward it (Motor6D.Transform); a joint no clip names is left to Animate. Clips that
	end (a flip, a dive) hold their last pose while the move lasts, and the jumps hand over to
	Jump or Fall once they finish.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Clips = require("@Shared/Movement/Clips")
local Remotes = require("@Shared/Movement/Remotes")
local Tuning = require("@Shared/Movement/Tuning")
local Platformer = require("@Client/Systems/Platformer")
local RoundInfo = require("@Shared/Rounds/RoundInfo")

local BumpFx = require("@Client/Systems/BumpFx")
local Ragdoll = require("@Shared/Ragdoll")
local Pound = Tuning.Of("Pound")
local Roll = Tuning.Of("Roll")
local Crouch = Tuning.Of("Crouch")
local BigFall = Tuning.Of("BigFall")
local Bonk = Tuning.Of("Bonk")
local Ball = Tuning.Of("Ball")

local Animator = {}

local JOINTS = {
	Root = { "LowerTorso", "Root" },
	Waist = { "UpperTorso", "Waist" },
	Neck = { "Head", "Neck" },
	RS = { "RightUpperArm", "RightShoulder" },
	RE = { "RightLowerArm", "RightElbow" },
	RW = { "RightHand", "RightWrist" },
	LS = { "LeftUpperArm", "LeftShoulder" },
	LE = { "LeftLowerArm", "LeftElbow" },
	LW = { "LeftHand", "LeftWrist" },
	RH = { "RightUpperLeg", "RightHip" },
	RK = { "RightLowerLeg", "RightKnee" },
	RA = { "RightFoot", "RightAnkle" },
	LH = { "LeftUpperLeg", "LeftHip" },
	LK = { "LeftLowerLeg", "LeftKnee" },
	LA = { "LeftFoot", "LeftAnkle" },
}

-- Clips are authored on a rig with its hips this high; how far a clip lowers the hips is scaled
-- to the real rig's legs, or a crouch on shorter legs puts the feet through the floor.
local AUTHORED_HIP_HEIGHT = 2.2
-- Studs per second: over this a standing body starts running, under STOP_SPEED a running one stops.
local MOVING_SPEED = 4
local STOP_SPEED = 1.5
-- Landings from these play the full Land crouch, even moving.
local BIG_LANDINGS = { Backflip = "LandBig", PoundJump = "Land", WallJump = "Land" }
-- Clips stretched so their Land marker meets the real landing (your own body; others play as
-- authored). The jump is one continuous clip, take-off to landing, sides alternating.
local TIMED_FLIPS = { Backflip = "Backflip", Jump = "JumpSingle" }
local SIDED = { Jump = true }
local AIR_SPEED = 7
-- Run plays as authored at this speed, faster above it. Was 14.4 (where The Scramble's feet
-- stayed planted), which played it twice as fast at BUMP's top speed of 28; the user found the
-- sprint "too fast for the speed the player's running at" (2026-11-13), so the stride now
-- lengthens more than it quickens: 1.33 times at top speed. Past MAX_STRIDE it stops quickening.
local RUN_STRIDE_SPEED = 21
local MAX_STRIDE = 1.8
-- How fast joints chase a new clip, per second, rising to TRACK_RATE once it has been playing a
-- moment, so a fast clip (a flip) isn't rounded off.
local ARRIVE_RATE = 40
local TRACK_RATE = 160
local SETTLE_SECONDS = 0.1

-- Moves played as one clip, held at its last pose when it ends.
local HELD = {
	LongJump = "LongJump",
	Dive = "Dive",
	PoundLand = "PoundLand",
	Bump = "Shove",
	Shoved = "Stagger", -- staggering back from someone's shove
	Hero = "HeroPose", -- your moment in a game's intro (RoundIntro)
	WallCling = "WallCling",
}
-- Moves played as one clip, then handed to Jump or Fall when it ends.
local THEN_AIR = {
	PoundJump = "PoundJump",
	WallJump = "WallLeap",
	Rollout = "Flip",
}
-- Riding a ball: running on top of it, the feet keeping pace with the ball (the user: "it should
-- look like the player's running matching momentum with the ball and trying to maintain their
-- balance"). One full stride (both feet) per this many studs the ball rolls, plus a slow shuffle
-- when it's barely moving.
local BALL_STRIDE_STUDS = 6
local BALL_SHUFFLE = 1.6 -- strides a second standing still on it: never calm, always scrambling
local RIDE_LOOPS = { RideSkrrt = "BallSkrrt", RideWobble = "BallWobble", RideDash = "BallDash" }
-- Moves played as a loop.
local LOOPS = {
	AirJump = "AirRun", -- running on air while jump is held
	PoundFall = "PoundFall",
	Slide = "BellySlide",
	WallSlide = "WallSlideDown",
}
local GROUNDED = {
	Run = true, Crouch = true, PoundLand = true, Slide = true, Roll = true, LandRoll = true, Bump = true, Bonk = true,
}

local player = Players.LocalPlayer
local entries = {} -- [Model] = entry

local function hipScale(model: Model, rootMotor): number
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not rootMotor then
		return 1
	end
	return (humanoid.HipHeight + root.Size.Y / 2 + rootMotor.C0.Y) / AUTHORED_HIP_HEIGHT
end

local function airClip(velocityY: number)
	return Clips.Get(velocityY > AIR_SPEED and "Jump" or "Fall")
end

-- The clip for a body and where in it to sample, from its move, how long it has been in it, and
-- how it is really moving.
-- How a body is really moving, from how far it went since last frame (smoothed). A rider's body
-- is pinned on its ball by a rigid AlignPosition and reports no velocity of its own, which kept
-- the ride's steps and balance at a standstill whatever the ball did.
local function measuredVelocity(entry, root: BasePart, dt: number): Vector3
	local position = root.Position
	local last = entry.LastPosition
	entry.LastPosition = position
	if not last or dt <= 0 then
		return root.AssemblyLinearVelocity
	end
	local moved = (position - last) / dt
	if moved.Magnitude > 200 then
		moved = root.AssemblyLinearVelocity -- a teleport
	end
	entry.Velocity = (entry.Velocity or moved):Lerp(moved, 1 - math.exp(-dt * 20))
	return entry.Velocity
end

local RIDING = { Ride = true, RideCharge = true, RideDash = true, RideSkrrt = true, RideWobble = true }

local function choose(entry, move: string, t: number, root: BasePart, dt: number)
	local velocity = RIDING[move] and entry.Velocity or root.AssemblyLinearVelocity -- (nil before the first measurement falls back)
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local now = os.clock()

	if move == "Ride" then
		local clip = Clips.Get("BallBalance")
		local strides = BALL_SHUFFLE + speed / BALL_STRIDE_STUDS -- strides a second
		entry.Phase = (entry.Phase + dt * strides) % 1
		return clip, entry.Phase * clip.Seconds
	elseif move == "RideCharge" then
		-- running on the spot, quicker as the charge builds (to three times as fast at full)
		local clip = Clips.Get("BallCharge")
		local charge = math.clamp(t / Ball.ChargeTime, 0, 1)
		entry.Phase = (entry.Phase + dt / clip.Seconds * (1 + 2 * charge)) % 1
		return clip, entry.Phase * clip.Seconds
	elseif RIDE_LOOPS[move] then
		return Clips.Get(RIDE_LOOPS[move]), t
	elseif move == "Run" then
		-- standing or running, with some give, so pushing into a wall doesn't flicker
		if entry.Moving and speed < STOP_SPEED then
			entry.Moving = false
		elseif not entry.Moving and speed > MOVING_SPEED then
			entry.Moving = true
		end
		-- a big jump lands into a crouch whatever the speed; a small one only when stopping
		local land = Clips.Get(BIG_LANDINGS[entry.LandedFrom] or "LandSoft")
		local sinceLanding = now - entry.LandedAt
		if sinceLanding < land.Seconds and (BIG_LANDINGS[entry.LandedFrom] or not entry.Moving) then
			return land, sinceLanding
		elseif not entry.Moving then
			return Clips.Get("Idle"), now
		end
		local run = Clips.Get("Run")
		entry.Phase = (entry.Phase + dt / run.Seconds * math.min(speed / RUN_STRIDE_SPEED, MAX_STRIDE)) % 1
		return run, entry.Phase * run.Seconds
	elseif move == "Crouch" then
		if speed < 1.5 then
			return Clips.Get("Crouch"), now
		end
		local walk = Clips.Get("CrouchWalk")
		entry.Phase = (entry.Phase + dt / walk.Seconds * speed / Crouch.Speed) % 1
		return walk, entry.Phase * walk.Seconds
	elseif move == "Roll" or move == "LandRoll" then
		local roll = Clips.Get("Roll")
		local length = move == "Roll" and Roll.Time or BigFall.Time
		return roll, math.min(t / length * roll.Seconds, roll.Seconds)
	elseif move == "Bonk" then
		-- Sunshine Valley's bonk, in Smash Arena's clips: down on your backside, seeing stars, up
		if t < Bonk.FallTime then
			local fall = Clips.Get("WallBonk")
			return fall, t / Bonk.FallTime * fall.Seconds
		elseif t < Bonk.FallTime + Bonk.DazeTime then
			return Clips.Get("Dazed"), t - Bonk.FallTime
		end
		local up = Clips.Get("DazeUp")
		return up, math.min((t - Bonk.FallTime - Bonk.DazeTime) / Bonk.GetUpTime * up.Seconds, up.Seconds)
	elseif move == "PoundSpin" then
		local spin = Clips.Get("PoundSpin")
		return spin, math.min(t / Pound.Hang * spin.Seconds, spin.Seconds)
	elseif move == "Knocked" then
		local isPlayer = Players:GetPlayerFromCharacter(entry.Model) ~= nil
		return Clips.Get(isPlayer and "Tumble" or "Flail"), t
	elseif TIMED_FLIPS[move] then
		local clip = Clips.Get(TIMED_FLIPS[move] .. (SIDED[move] and entry.Side or ""))
		local land = clip.Markers.Land or clip.Seconds
		local airTime = entry.Model == player.Character and Platformer.AirTime() or 0
		local scale = airTime > 0.2 and land / airTime or 1
		return clip, math.min(t * scale, clip.Seconds)
	elseif HELD[move] then
		local clip = Clips.Get(HELD[move])
		return clip, math.min(t, clip.Seconds)
	elseif THEN_AIR[move] then
		local clip = Clips.Get(THEN_AIR[move])
		if t < clip.Seconds then
			return clip, t
		end
		return airClip(velocity.Y), now
	elseif LOOPS[move] then
		return Clips.Get(LOOPS[move]), t
	end
	-- Jump, Fall, and anything unknown
	return airClip(velocity.Y), now
end

-- Holding something overhead (Bomber Bloxians' bomb, RoundInfo.CarryingAttr): the arms play the
-- library's Carry clip whatever the rest of the body is doing.
local CARRY_JOINTS = { "RS", "RE", "RW", "LS", "LE", "LW" }

local function carryOver(entry)
	local clip = Clips.Get("Carry")
	if not clip then
		return
	end
	local t = os.clock() % clip.Seconds
	for _, joint in CARRY_JOINTS do
		local track = clip.Tracks[joint]
		if track and entry.Motors[joint] then
			entry.Target[joint] = Clips.SampleTrack(track, t)
		end
	end
end

local function sampleInto(entry, clip, t: number)
	table.clear(entry.Target)
	if clip.Loop and clip.Seconds > 0 then
		t %= clip.Seconds
	end
	for joint, track in pairs(clip.Tracks) do
		if entry.Motors[joint] then
			local pose = Clips.SampleTrack(track, t)
			if joint == "Root" then
				pose = pose.Rotation + pose.Position * entry.HipScale
			end
			entry.Target[joint] = pose
		end
	end
end

local function apply(entry, dt: number, rate: number)
	local alpha = 1 - math.exp(-dt * rate)
	for joint, motor in pairs(entry.Motors) do
		local goal = entry.Target[joint]
		local weight = entry.Weight[joint] or 0
		weight += ((goal and 1 or 0) - weight) * alpha
		entry.Weight[joint] = weight
		if goal then
			entry.Current[joint] = (entry.Current[joint] or goal):Lerp(goal, alpha)
		end
		local current = entry.Current[joint]
		if current and weight > 0.01 and motor.Parent then
			motor.Transform = motor.Transform:Lerp(current, weight)
		end
	end
end

-- ═══ flair: springy secondary motion on top of every clip ═════════════════════════
-- The user (2026-11-13) found the animation "stiff or robotic". Each body leans into speeding
-- up and back when braking, banks into turns, and dips and rebounds on landing, all on springs
-- that overshoot a little, read from how the body really moves (so it works on every body).
-- Applied to the Root and Waist joints after the clip, only while a clip drives them.

local FLAIR_SKIP = {
	Ride = true, RideCharge = true, RideDash = true, RideSkrrt = true, RideWobble = true, Roll = true, LandRoll = true,
	Bonk = true, Knocked = true, Shoved = true, PoundSpin = true, PoundFall = true, PoundLand = true, Backflip = true,
	WallCling = true, WallSlide = true, Slide = true, Rollout = true, Hero = true,
}
local AIRBORNE_FLAIR = { AirJump = true, Jump = true, Fall = true, LongJump = true, Dive = true, WallJump = true, PoundJump = true }
local LEAN_STIFF, LEAN_DAMP = 150, 15 -- springs a little under critical: a small overshoot
local DIP_STIFF, DIP_DAMP = 320, 20

local function spring(x: number, v: number, target: number, stiff: number, damp: number, dt: number): (number, number)
	local a = (target - x) * stiff - v * damp
	v += a * dt
	return x + v * dt, v
end

-- Fighting to stay on a rolling ball (move Ride). The user (2026-11-13): "It should look intense
-- as if the player is trying for dear god to stay on the ball. Extremely cartoonish-exaggerated".
-- On loose springs that overshoot: the whole body keeps tipping one way and over-correcting the
-- other (a restless sway that grows with speed), turns throw it outward, and every second or two a
-- random lurch knocks it off balance before it catches itself. The arms see-saw hard against the
-- tip (on top of the clip's windmilling), swing back as the ball speeds up and forward as it slows,
-- and the chest and head fight to stay level. Angles in degrees, added in the body's own axes.
local STRUGGLE_STIFF, STRUGGLE_DAMP = 55, 5

local function rideBalance(entry, f, look: Vector3, speed: number, dt: number)
	local now = os.clock()
	local seed = (entry.Seed or 0)
	-- a lurch now and then: a hard shove to the sway, either way
	if now >= (f.NextLurch or 0) then
		f.NextLurch = now + 0.9 + math.random() * 1.6
		if f.Sway then
			f.SwayV = (f.SwayV or 0) + (math.random() < 0.5 and -1 or 1) * (260 + math.random() * 220)
			f.TipV = (f.TipV or 0) + (math.random() - 0.5) * 160
		end
	end
	local restless = (math.sin(now * 2.6 + seed) * 0.6 + math.sin(now * 4.4 + seed * 2) * 0.4) * (12 + speed * 0.5)
	local swayTarget = math.clamp(-f.YawRate * speed * 0.7, -60, 60) + restless
	local swingTarget = math.clamp(-f.Acc:Dot(look) * 0.4, -50, 50)
	local tipTarget = math.sin(now * 3.3 + seed) * 6 + math.clamp(f.Acc:Dot(look) * 0.08, -12, 12)
	f.Sway, f.SwayV = spring(f.Sway or 0, f.SwayV or 0, swayTarget, STRUGGLE_STIFF, STRUGGLE_DAMP, dt)
	f.Swing, f.SwingV = spring(f.Swing or 0, f.SwingV or 0, swingTarget, STRUGGLE_STIFF, STRUGGLE_DAMP, dt)
	f.Tip, f.TipV = spring(f.Tip or 0, f.TipV or 0, tipTarget, STRUGGLE_STIFF, STRUGGLE_DAMP, dt)
	f.Sway = math.clamp(f.Sway, -70, 70)
	local motors, target = entry.Motors, entry.Target
	local sway, swing, tip = math.rad(f.Sway), math.rad(f.Swing), math.rad(f.Tip)
	-- the body tips with the sway (falling that way) and pitches forward and back
	if motors.Root and target.Root then
		motors.Root.Transform = CFrame.Angles(-tip * 0.6, 0, sway * 0.32) * motors.Root.Transform
	end
	-- the chest and head fight back toward level
	if motors.Waist and target.Waist then
		motors.Waist.Transform = CFrame.Angles(tip * 0.3 - swing * 0.15, 0, -sway * 0.55) * motors.Waist.Transform
	end
	if motors.Neck and target.Neck then
		motors.Neck.Transform = CFrame.Angles(0, 0, -sway * 0.35) * motors.Neck.Transform
	end
	-- the arms see-saw hard against the tip: the arm on the falling side flung up
	if motors.RS and target.RS then
		motors.RS.Transform = CFrame.Angles(swing, 0, -sway * 1.1) * motors.RS.Transform
	end
	if motors.LS and target.LS then
		motors.LS.Transform = CFrame.Angles(swing, 0, -sway * 1.1) * motors.LS.Transform
	end
end

local function flair(entry, move: string, root: BasePart, dt: number)
	local f = entry.Flair
	local velocity = RIDING[move] and (entry.Velocity or Vector3.zero) or root.AssemblyLinearVelocity
	local planar = Vector3.new(velocity.X, 0, velocity.Z)
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	look = look.Magnitude > 1e-3 and look.Unit or Vector3.new(0, 0, -1)
	dt = math.clamp(dt, 1 / 240, 1 / 20)
	-- how it's really moving: acceleration and turning, smoothed
	local acc = f.LastPlanar and (planar - f.LastPlanar) / dt or Vector3.zero
	if acc.Magnitude > 400 then
		acc = acc.Unit * 400 -- a launch or a teleport, not a lean
	end
	f.Acc = f.Acc:Lerp(acc, 1 - math.exp(-dt * 16))
	local yaw = 0
	if f.LastLook then
		yaw = math.atan2(f.LastLook:Cross(look).Y, f.LastLook:Dot(look)) / dt
	end
	f.YawRate += (math.clamp(yaw, -12, 12) - f.YawRate) * (1 - math.exp(-dt * 12))
	f.LastPlanar, f.LastLook, f.LastVY = planar, look, velocity.Y

	local pitchTarget, rollTarget = 0, 0
	local speed = planar.Magnitude
	if move == "Ride" then
		rideBalance(entry, f, look, speed, dt)
	end
	if FLAIR_SKIP[move] then
		pitchTarget, rollTarget = 0, 0
	elseif AIRBORNE_FLAIR[move] then
		-- in the air: bank into air turns, tip forward a touch as the fall gathers
		rollTarget = math.clamp(f.YawRate * speed * 0.004, -0.3, 0.3)
		pitchTarget = math.clamp(-velocity.Y * 0.0025, -0.12, 0.1)
	else
		-- on the ground: lean into speeding up, back when braking, bank into turns
		pitchTarget = math.clamp(-f.Acc:Dot(look) * 0.0028, -0.24, 0.2)
		rollTarget = math.clamp(f.YawRate * speed * 0.0055, -0.32, 0.32)
	end
	f.Pitch, f.PitchV = spring(f.Pitch, f.PitchV, pitchTarget, LEAN_STIFF, LEAN_DAMP, dt)
	f.Roll, f.RollV = spring(f.Roll, f.RollV, rollTarget, LEAN_STIFF, LEAN_DAMP, dt)
	f.Dip, f.DipV = spring(f.Dip, f.DipV, 0, DIP_STIFF, DIP_DAMP, dt)
	f.Dip = math.clamp(f.Dip, -1.4, 0.35)

	-- the lean goes mostly into the waist when the clip drives it, else all into the hips
	local rootMotor, waist = entry.Motors.Root, entry.Motors.Waist
	local waistShare = (waist and entry.Target.Waist) and 0.65 or 0
	if rootMotor and entry.Target.Root then
		rootMotor.Transform = rootMotor.Transform * CFrame.new(0, f.Dip * entry.HipScale, 0) * CFrame.Angles(f.Pitch * (1 - waistShare), 0, f.Roll)
	end
	if waistShare > 0 then
		waist.Transform = waist.Transform * CFrame.Angles(f.Pitch * waistShare, 0, f.Roll * 0.3)
	end
end

local function moveOf(entry): (string, number)
	if entry.Model == player.Character then
		return Platformer.Move(), Platformer.MoveTime()
	end
	return entry.Move, os.clock() - entry.MoveAt
end

local function noteMove(entry, move: string)
	if move ~= entry.LastMove then
		local previous = entry.LastMove
		if GROUNDED[move] and previous ~= "" and not GROUNDED[previous] then
			entry.LandedAt = os.clock()
			entry.LandedFrom = previous
			-- the body gives under the landing: harder the faster it came down
			local fell = math.max(-(entry.Flair.LastVY or 0), 0)
			entry.Flair.DipV -= math.clamp(fell * 0.09, 1.5, 9)
		end
		entry.LastMove = move
		if move == "Jump" then
			entry.Side = entry.Side == "R" and "L" or "R"
		end
		if previous ~= "" then
			-- effects never stop the animation: an error in one is reported and passed over
			local ok, err = pcall(BumpFx.OnMove, entry.Model, move, previous)
			if not ok then
				warn("[Animator] BumpFx." .. move .. ":", err)
			end
		end
	end
end

local function step(_, dt: number)
	for model, entry in entries do
		local root = model:FindFirstChild("HumanoidRootPart")
		if not model.Parent or not root then
			entries[model] = nil
		elseif Ragdoll.IsDown(model) then
			-- knocked flat: the joints are loose and physics has the body. The root joint stays
			-- on, so drop whatever pose it was holding (a tumble's spin) or the hips stay twisted.
			if entry.Clip then
				entry.Clip = nil
				table.clear(entry.Current)
				table.clear(entry.Weight)
				if entry.Motors.Root then
					entry.Motors.Root.Transform = CFrame.identity
				end
			end
		else
			local move, t = moveOf(entry)
			measuredVelocity(entry, root, dt)
			noteMove(entry, move)
			local clip, at = choose(entry, move, t, root, dt)
			if clip then
				if clip ~= entry.Clip then
					entry.Clip = clip
					entry.ClipSince = os.clock()
				end
				sampleInto(entry, clip, at)
				if model:GetAttribute(RoundInfo.CarryingAttr) then
					carryOver(entry)
				end
				local settled = math.clamp((os.clock() - entry.ClipSince) / SETTLE_SECONDS, 0, 1)
				apply(entry, dt, ARRIVE_RATE + (TRACK_RATE - ARRIVE_RATE) * settled)
				flair(entry, move, root, dt)
			end
		end
	end
end

local function register(model: Model)
	if entries[model] or not model:IsA("Model") then
		return
	end
	local motors = {}
	for name, path in pairs(JOINTS) do
		local part = model:WaitForChild(path[1], 5)
		local joint = part and (part:FindFirstChild(path[2]) or part:WaitForChild(path[2], 2))
		-- newer avatars have an AnimationConstraint where the Motor6D was; both carry Transform
		if joint and (joint:IsA("Motor6D") or joint:IsA("AnimationConstraint")) then
			motors[name] = joint
		end
	end
	if not motors.Root or not model.Parent then
		return
	end
	local entry = {
		Model = model,
		Motors = motors,
		HipScale = hipScale(model, motors.Root),
		Target = {},
		Current = {},
		Weight = {},
		Phase = math.random(),
		Seed = math.random() * 10, -- so no two riders sway in step
		Move = model:GetAttribute(Remotes.MoveAttr) or "Run",
		MoveAt = os.clock(),
		LastMove = "",
		LandedAt = -math.huge,
		LandedFrom = "",
		Moving = false,
		Side = "L", -- the next jump punches with the right
		Clip = nil,
		ClipSince = 0,
		Flair = { Pitch = 0, PitchV = 0, Roll = 0, RollV = 0, Dip = 0, DipV = 0, Acc = Vector3.zero, YawRate = 0 },
	}
	model:GetAttributeChangedSignal(Remotes.MoveAttr):Connect(function()
		entry.Move = model:GetAttribute(Remotes.MoveAttr) or "Run"
		entry.MoveAt = os.clock()
	end)
	entries[model] = entry
end

function Animator.start()
	CollectionService:GetInstanceAddedSignal(Remotes.BodyTag):Connect(function(model)
		task.spawn(register, model)
	end)
	for _, model in CollectionService:GetTagged(Remotes.BodyTag) do
		task.spawn(register, model)
	end
	-- every machine loosens a knocked body's joints itself (Shared/Ragdoll)
	Ragdoll.Watch(Remotes.BodyTag)
	RunService.Stepped:Connect(step)
end

return Animator
