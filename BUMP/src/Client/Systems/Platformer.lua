--!nonstrict
--[[
	The platformer controls: how your character runs, jumps and bumps. Client side, on your own
	character only (Roblox lets each client move its own body).

	The Humanoid still stands you up and walks you up steps, but this module owns your speed and
	facing:
	- a LinearVelocity in the ground plane sets your horizontal speed every frame (so you speed
	  up, skid, and keep your momentum in the air, which a stock Humanoid can't);
	- an AlignOrientation turns you;
	- jumps are written straight into your vertical speed, and the stock jump is switched off.

	Moves (numbers in Shared/Movement/MoveConfig):
	    Jump                  single; again just after landing for a double, then a triple flip.
	                          A press just before landing, or just after running off an edge, counts
	    Crouch + Jump         standing: backflip, arcing well back. Running: long jump
	    Crouch in the air     ground pound; jump just after it lands for a high jump
	    Attack in the air     dive (also out of a ground pound); land in a belly slide, jump to hop out
	    Crouch + Attack       roll, on the ground while moving
	    Attack on the ground  BUMP: a shove that throws whoever it hits
	    Into a wall in the air  cling, then slide down faster and faster, then let go. Jump to
	                          kick off it; crouch or push away to drop
	    A big fall            lands in a forward roll
	    A roll into a wall    bonk: bounced off, down on your backside seeing stars, then up

	Keys: Space jump, C crouch, left click or E attack. Gamepad: A jump, L2/R2
	crouch, X/B attack. Touch: Roblox's jump button, plus Crouch and Attack in the engine's ring.
	Each button shows the engine's input chip, labelled with what it would do right now
	("Float Jump", "Backflip", "Ground Pound", "Wall Jump"...).

	Every move you are in is sent to the server (Remotes "Move"), which puts it on your character
	so every client can animate you (Animator). Hits are found here and sent as "Bump"; the server
	checks them and throws the target.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local InputHandler = require("@Engine/Shared/Handlers/InputHandler")
local Ragdoll = require("@Shared/Ragdoll")
local Remotes = require("@Shared/Movement/Remotes")
local RoundInfo = require("@Shared/Rounds/RoundInfo")
local PowerUpInfo = require("@Shared/PowerUps/PowerUpInfo")
local Tuning = require("@Shared/Movement/Tuning")

local Run = Tuning.Of("Run")
local Crouch = Tuning.Of("Crouch")
local Air = Tuning.Of("Air")
local Jump = Tuning.Of("Jump")
local AirJump = Tuning.Of("AirJump")
local Backflip = Tuning.Of("Backflip")
local LongJump = Tuning.Of("LongJump")
local Pound = Tuning.Of("Pound")
local Dive = Tuning.Of("Dive")
local Roll = Tuning.Of("Roll")
local BigFall = Tuning.Of("BigFall")
local Bonk = Tuning.Of("Bonk")
local Wall = Tuning.Of("Wall")
local Bump = Tuning.Of("Bump")

local Platformer = {}

local player = Players.LocalPlayer

-- Moves that are on the ground. Everything else is in the air.
local GROUND_MOVES = {
	Run = true, Crouch = true, PoundLand = true, Slide = true, Roll = true, LandRoll = true, Bump = true, Bonk = true,
	Hero = true,
}
-- Moves you can't act out of until they end.
local LOCKED = { Knocked = true, Bonk = true, Shoved = true, Hero = true }

local LEAVE_GROUND_GRACE = 0.12 -- after a jump, ignore the floor this long

-- ═══ state ════════════════════════════════════════════════════════════════════════

local body = nil -- { character, root, humanoid, mover, aligner }
local move = "Run"
local moveAt = 0
local landedAt = -math.huge
local leftGroundAt = -math.huge
local walkedOffAt = -math.huge -- when you last ran off an edge without jumping (coyote time)
local jumpPressedAt = -math.huge -- the last jump press not yet used (the buffer)
local facing = Vector3.new(0, 0, -1)
local wallNormal = nil
local wallBlock = nil -- { normal, until }: the wall you just left, not to be caught again yet
local steerLockedUntil = 0
local airDived = false
local lastKnock = nil -- { velocity, at }: the last knock, re-applied if the body goes limp with it
local airJumped = false -- the one floaty air jump has been used since the ground or a wall
local jumpHeld = false
local touchHeldUntil = 0 -- a touch screen's jump button repeats JumpRequest while held
local airPeakY = 0
local bumpReadyAt = 0
local hitThisMove = {}

local crouchHeld = false
local touchJumpLatch = false

local listeners = {} -- functions(move, previous) told of every move change
local airTime = 0 -- how long the jump just launched will be in the air (jump clips are timed to it)
local launchY = 0 -- the height it left from
-- Something else driving the body (riding a ball): { Input = function(id, phase), Hint =
-- function(id) -> (label, enabled), Stop = function() }. While set, this module only forwards
-- buttons and hints to it.
local external = nil
local standing = true -- false while knocked flat (ragdoll): the movers are off
local poseFor = 0 -- how long the Hero pose (Platformer.Pose) holds

-- While the round says so (a game's intro), nobody moves.
local function frozen(): boolean
	local folder = game:GetService("ReplicatedStorage"):FindFirstChild(RoundInfo.Folder)
	return folder ~= nil and folder:GetAttribute("Frozen") == true
end

local function now(): number
	return os.clock()
end

local function gravity(): number
	return Workspace.Gravity
end

-- The launch speed that reaches `height` under the rising gravity (Air.RiseGravity).
local function riseFor(height: number): number
	return math.sqrt(2 * gravity() * Air.RiseGravity * height)
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function unit(v: Vector3, fallback: Vector3): Vector3
	return v.Magnitude > 1e-3 and v.Unit or fallback
end

local function towards(current: Vector3, target: Vector3, step: number): Vector3
	local delta = target - current
	local distance = delta.Magnitude
	if distance <= step or distance < 1e-4 then
		return target
	end
	return current + delta / distance * step
end

local function setMove(name: string)
	if move == name then
		return
	end
	local previous = move
	move = name
	moveAt = now()
	table.clear(hitThisMove)
	Remotes.Act("Move", name)
	for _, listener in listeners do
		task.spawn(listener, name, previous)
	end
end

local function since(): number
	return now() - moveAt
end

-- ═══ the body ═════════════════════════════════════════════════════════════════════

local function attach(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not humanoid or not root then
		return
	end
	humanoid.AutoRotate = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)

	-- No friction on the body: this module owns every speed, and a body pressed into a wall
	-- would otherwise stick to it (a limb against the wall pinned a wall slide dead).
	local function slippery(part)
		if part:IsA("BasePart") then
			local base = PhysicalProperties.new(part.Material)
			part.CustomPhysicalProperties = PhysicalProperties.new(base.Density, 0, 0, 100, 1)
		end
	end
	for _, part in character:GetDescendants() do
		slippery(part)
	end
	character.DescendantAdded:Connect(slippery)

	local attachment = Instance.new("Attachment")
	attachment.Name = "BumpMover"
	attachment.Parent = root

	local mover = Instance.new("LinearVelocity")
	mover.Name = "BumpPlanar"
	mover.Attachment0 = attachment
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	mover.PrimaryTangentAxis = Vector3.xAxis
	mover.SecondaryTangentAxis = Vector3.zAxis
	mover.MaxForce = 1e6
	mover.Parent = root

	local aligner = Instance.new("AlignOrientation")
	aligner.Name = "BumpFacing"
	aligner.Mode = Enum.OrientationAlignmentMode.OneAttachment
	aligner.Attachment0 = attachment
	aligner.Responsiveness = 60
	aligner.MaxTorque = 1e7
	aligner.Parent = root

	facing = unit(flat(root.CFrame.LookVector), Vector3.new(0, 0, -1))
	body = { character = character, root = root, humanoid = humanoid, mover = mover, aligner = aligner }
	move = ""
	setMove("Run")
end

local function alive(): boolean
	return body ~= nil and body.character.Parent ~= nil and body.humanoid.Health > 0
end

local function grounded(): boolean
	if now() - leftGroundAt < LEAVE_GROUND_GRACE then
		return false
	end
	return body.humanoid.FloorMaterial ~= Enum.Material.Air
end

-- How long a jump launched upward at `up` stays in the air before it is back at the height it
-- left, under this module's gravity rules (rising and falling heavier than the world's).
local function predictAirTime(up: number, fromHeight: number?): number
	local g = gravity()
	local y, v, t, dt = fromHeight or 0, up, 0, 1 / 240
	repeat
		local share = v < 0 and Air.FallGravity or Air.RiseGravity
		v -= g * share * dt
		y += v * dt
		t += dt
	until y <= 0 or t > 4
	return t
end

local function launch(planar: Vector3, up: number)
	local root = body.root
	root.AssemblyLinearVelocity = Vector3.new(planar.X, up, planar.Z)
	body.mover.PlaneVelocity = Vector2.new(planar.X, planar.Z)
	leftGroundAt = now()
	walkedOffAt = -math.huge
	jumpPressedAt = -math.huge
	airPeakY = root.Position.Y
	launchY = root.Position.Y
	airTime = predictAirTime(up)
	body.humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
end

local function setVertical(up: number)
	local v = body.root.AssemblyLinearVelocity
	body.root.AssemblyLinearVelocity = Vector3.new(v.X, up, v.Z)
end

local function rayParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	-- the lobby's invisible pit wall stops you but isn't a wall to cling to or bonk on
	local wall = Workspace:FindFirstChild("LobbyFx")
	wall = wall and wall:FindFirstChild("PitWall")
	params.FilterDescendantsInstances = wall and { body.character, wall } or { body.character }
	return params
end

-- ═══ bumping others ═══════════════════════════════════════════════════════════════

local function bodies(): { Model }
	local list = {}
	for _, tagged in CollectionService:GetTagged(Remotes.BodyTag) do
		if tagged:IsA("Model") and tagged ~= body.character and tagged:IsDescendantOf(Workspace) then
			table.insert(list, tagged)
		end
	end
	return list
end

-- Anyone within `reach` (and, with a cone, in front of you) gets bumped, once per move.
-- The ball someone is riding (BUMP), if any: a ball tagged BumpBall whose Rider is their Id.
local function ballRiddenBy(model: Model): BasePart?
	local id = model:GetAttribute(RoundInfo.IdAttr)
	if not id then
		local rider = Players:GetPlayerFromCharacter(model)
		id = rider and tostring(rider.UserId)
	end
	if not id then
		return nil
	end
	for _, ball in CollectionService:GetTagged("BumpBall") do
		if ball:IsA("BasePart") and ball:GetAttribute("Rider") == id then
			return ball
		end
	end
	return nil
end

-- `cone`: how far round from straight ahead counts (a dot product), or nil for all round.
local function hitAround(kind: string, reach: number, cone: number?): boolean
	local origin = body.root.Position
	local hitAny = false
	for _, other in bodies() do
		if not hitThisMove[other] then
			local otherRoot = other:FindFirstChild("HumanoidRootPart")
			if otherRoot then
				local offset = otherRoot.Position - origin
				local planar = flat(offset)
				local inFront = not cone or planar.Magnitude < 1.5 or planar.Unit:Dot(facing) > cone
				local close = offset.Magnitude <= reach and math.abs(offset.Y) < 5
				-- someone riding a ball stands high on it: hitting their ball, or their body at
				-- any height, counts
				local ball = ballRiddenBy(other)
				if ball then
					local toBall = ball.Position - origin
					local surface = toBall.Magnitude - ball.Size.X / 2
					local towards = flat(toBall)
					-- in front, or your own movement is carrying you into it
					local moving = flat(body.root.AssemblyLinearVelocity)
					inFront = not cone
						or towards.Magnitude < 1.5
						or towards.Unit:Dot(facing) > 0.2
						or moving:Dot(towards.Unit) > 6
					close = surface <= reach or offset.Magnitude <= reach + 1.5
				end
				if close and inFront then
					hitThisMove[other] = true
					hitAny = true
					Remotes.Act("Bump", other, kind)
				end
			end
		end
	end
	return hitAny
end

-- ═══ walls ════════════════════════════════════════════════════════════════════════

-- A wall in `direction` within `reach`: its normal, if it is upright and solid.
local function wallIn(direction: Vector3, reach: number): Vector3?
	if direction.Magnitude < 1e-3 then
		return nil
	end
	direction = direction.Unit
	local params = rayParams()
	for _, height in { -0.5, 1 } do
		local origin = body.root.Position + Vector3.new(0, height, 0)
		local hit = Workspace:Raycast(origin, direction * reach, params)
		if hit and math.abs(hit.Normal.Y) < 0.3 and hit.Instance.Anchored and hit.Instance.CanCollide then
			return flat(hit.Normal).Unit
		end
	end
	return nil
end

-- Takes out the part of `planar` that runs into a wall right in front, so pushing into one
-- leaves you standing (or falling) still against it instead of shoving at it.
local function alongWalls(planar: Vector3): Vector3
	local normal = wallIn(planar, 1.9)
	if normal and planar:Dot(normal) < 0 then
		return planar - normal * planar:Dot(normal)
	end
	return planar
end

local function blocked(normal: Vector3): boolean
	return wallBlock ~= nil and now() < wallBlock.untilTime and wallBlock.normal:Dot(normal) > 0.9
end

local function letGoOfWall(push: number)
	if wallNormal then
		wallBlock = { normal = wallNormal, untilTime = now() + Wall.RegrabDelay }
		local planar = wallNormal * push
		body.root.AssemblyLinearVelocity = Vector3.new(planar.X, body.root.AssemblyLinearVelocity.Y, planar.Z)
	end
	-- a controlled slide down a wall doesn't count toward a big fall
	airPeakY = body.root.Position.Y
	setMove("Fall")
end

-- ═══ moves ════════════════════════════════════════════════════════════════════════

-- Every ground jump is a single: the second jump is in the air (startAirJump).
local function startJump(planar: Vector3)
	launch(planar, riseFor(Jump.Single))
	setMove("Jump")
end

local function startGroundJump()
	local planar = flat(body.root.AssemblyLinearVelocity)
	if move == "PoundLand" then
		launch(Vector3.zero, riseFor(Pound.JumpHeight))
		setMove("PoundJump")
		return
	end
	if move == "Slide" then
		launch(planar * 0.5, riseFor(Dive.RolloutHeight))
		setMove("Rollout")
		return
	end
	if move == "Roll" or move == "LandRoll" then
		launch(facing * math.max(planar.Magnitude, Roll.Speed), riseFor(Roll.JumpHeight))
		setMove("LongJump")
		return
	end
	if crouchHeld then
		if planar.Magnitude >= LongJump.MinSpeed then
			launch(facing * math.max(planar.Magnitude, LongJump.Speed), riseFor(LongJump.Height))
			setMove("LongJump")
		else
			launch(-facing * Backflip.BackSpeed, riseFor(Backflip.Height))
			setMove("Backflip")
		end
		return
	end
	startJump(planar)
end

-- Tries the jump that is waiting in the buffer. True if one happened.
-- Moves you can float-jump out of.
local AIR_JUMP_FROM = { Jump = true, Fall = true, Backflip = true, LongJump = true, WallJump = true, Rollout = true, PoundJump = true }

-- The air jump: running on air. A small kick up, keeping your speed; while jump is held the
-- legs keep you rising slowly (the vertical part is in the step, under move == "AirJump").
local function startAirJump()
	airJumped = true
	local planar = flat(body.root.AssemblyLinearVelocity)
	launch(planar, math.max(body.root.AssemblyLinearVelocity.Y, 0) * 0.3 + AirJump.Kick)
	airPeakY = body.root.Position.Y
	setMove("AirJump")
end

local function tryJump(): boolean
	if now() - jumpPressedAt > Jump.Buffer or LOCKED[move] then
		return false
	end
	if move == "WallCling" or move == "WallSlide" then
		if wallNormal then
			airDived = false
			facing = wallNormal
			wallBlock = { normal = wallNormal, untilTime = now() + Wall.RegrabDelay }
			launch(wallNormal * Wall.JumpOut, riseFor(Wall.JumpHeight))
			steerLockedUntil = now() + Wall.LockTime
			setMove("WallJump")
			return true
		end
		return false
	end
	if move == "PoundLand" and since() > Pound.JumpWindow then
		return false
	end
	local coyote = move == "Fall" and now() - walkedOffAt <= Jump.Coyote
	if (GROUND_MOVES[move] and grounded()) or coyote then
		startGroundJump()
		return true
	end
	if AIR_JUMP_FROM[move] and not airJumped and not grounded() then
		startAirJump()
		return true
	end
	return false
end

local function onJumpPressed()
	jumpHeld = true
	if not alive() then
		return
	end
	jumpPressedAt = now()
	tryJump()
end

local function onJumpReleased()
	jumpHeld = false
	if not alive() then
		return
	end
	if move == "Jump" then
		local up = body.root.AssemblyLinearVelocity.Y
		if up > 0 then
			setVertical(up * Air.CutJump)
			-- a shorter hop: re-time the jump clip to the flight that's left
			airTime = (now() - leftGroundAt) + predictAirTime(up * Air.CutJump, body.root.Position.Y - launchY)
		end
	end
end

local function onCrouchPressed()
	if not alive() or LOCKED[move] then
		return
	end
	if move == "WallCling" or move == "WallSlide" then
		letGoOfWall(Wall.LetGoPush)
		return
	end
	if not GROUND_MOVES[move] and move ~= "PoundSpin" and move ~= "PoundFall" and move ~= "Dive" then
		body.root.AssemblyLinearVelocity = Vector3.zero
		setMove("PoundSpin")
	end
end

local function onAttackPressed()
	if not alive() or LOCKED[move] then
		return
	end
	local planar = flat(body.root.AssemblyLinearVelocity)
	if GROUND_MOVES[move] then
		if move ~= "Run" and move ~= "Crouch" then
			return
		end
		if crouchHeld and planar.Magnitude > 4 then
			setMove("Roll")
			return
		end
		if now() < bumpReadyAt then
			return
		end
		bumpReadyAt = now() + Bump.Cooldown
		-- a snap toward the nearest body in front (or the way you push), so shoves connect
		local input = flat(body.humanoid.MoveDirection)
		local aim = input.Magnitude > 0.3 and input.Unit or facing
		local best, bestDistance = nil, Bump.Assist
		for _, other in bodies() do
			local otherRoot = other:FindFirstChild("HumanoidRootPart")
			if otherRoot then
				local offset = flat(otherRoot.Position - body.root.Position)
				local distance = offset.Magnitude
				if distance > 0.5 and distance < bestDistance and math.abs(otherRoot.Position.Y - body.root.Position.Y) < 6
					and (offset.Unit:Dot(aim) > Bump.AssistDot or offset.Unit:Dot(facing) > Bump.AssistDot) then
					best, bestDistance = offset.Unit, distance
				end
			end
		end
		if best then
			facing = best
		elseif input.Magnitude > 0.3 then
			facing = input.Unit
		end
		setMove("Bump")
		return
	end
	if not airDived and move ~= "WallCling" and move ~= "WallSlide" then
		airDived = true
		local speed = math.max(planar.Magnitude, Dive.Speed)
		launch(facing * speed, Dive.Up)
		setMove("Dive")
	end
end

-- Someone bumped you: the server says how hard.
-- Thrown by someone else. A shove ("Bump") staggers you back on your feet (Shoved); anything
-- else knocks you about (Knocked).
local function onKnocked(velocity: Vector3, kind: string?)
	if not alive() then
		return
	end
	if external then
		local stopping = external
		external = nil
		stopping.Stop()
		body.mover.Enabled = true
		body.aligner.Enabled = true
	end
	airDived = false
	local planar = flat(velocity)
	if planar.Magnitude > 1 then
		facing = -planar.Unit
	end
	launch(planar, velocity.Y)
	setMove(kind == "Bump" and "Shoved" or "Knocked")
	-- if this knock also goes limp, the loose limbs would drag the throw to a stop: throw every
	-- part now, and again the moment the ragdoll takes hold (the step's knocked-flat branch)
	lastKnock = { velocity = velocity, at = now() }
	Ragdoll.Fling(body.character, velocity)
end

-- Rolled square into a wall.
local function startBonk(normal: Vector3)
	facing = -normal
	launch(normal * Bonk.BounceSpeed, Bonk.BounceUp)
	setMove("Bonk")
end

-- ═══ every frame ══════════════════════════════════════════════════════════════════

local function onLanded()
	landedAt = now()
	airDived = false
	airJumped = false
	local drop = airPeakY - body.root.Position.Y
	if move == "PoundFall" or move == "PoundSpin" then
		setMove("PoundLand")
		hitAround("Pound", Pound.ShockRadius, nil)
		-- the ground felt it: a game may send a ripple out from here (BUMP's tiles)
		Remotes.Act("Pound", body.root.Position)
		return
	end
	if move == "Dive" then
		setMove("Slide")
		return
	end
	if drop >= BigFall.Height and move ~= "Knocked" then
		local planar = flat(body.root.AssemblyLinearVelocity)
		facing = unit(planar, facing)
		setMove("LandRoll")
		return
	end
	if move == "Jump" then
		setMove(crouchHeld and "Crouch" or "Run")
	else
		setMove(crouchHeld and "Crouch" or "Run")
	end
end

-- Air steering: push and you turn toward it; let go and your speed carries, with a little drag.
local function steer(planar: Vector3, input: Vector3, dt: number, share: number?): Vector3
	if now() < steerLockedUntil then
		return planar
	end
	share = share or 1
	if input.Magnitude < 0.1 then
		return towards(planar, Vector3.zero, Air.Drag * dt)
	end
	local speed = planar.Magnitude
	local target = input * math.max(Air.Speed, speed)
	return towards(planar, target, Air.Accel * share * dt)
end

-- Turning in the air, the Nintendo way: push a direction and your body turns toward it at a set
-- rate, and your speed turns with it, so the arc bends where you steer rather than sliding
-- sideways. Moving, it is your direction of travel that turns toward the push (a backflip's
-- backward arc swings the way you push and the body keeps its back to it); standing, your body
-- turns. Pulling straight back doesn't turn you: steer() brakes instead. `share` scales the rate.
local function airTurn(planar: Vector3, input: Vector3, dt: number, share: number): Vector3
	if input.Magnitude < 0.1 or now() < steerLockedUntil then
		return planar
	end
	local wanted = input.Unit
	local moving = planar.Magnitude > 4
	local heading = moving and planar.Unit or facing
	local angle = math.atan2(heading:Cross(wanted).Y, heading:Dot(wanted))
	if moving and math.abs(angle) > math.rad(150) then
		return planar
	end
	local limit = Air.TurnRate * share * dt
	local turn = CFrame.fromAxisAngle(Vector3.yAxis, math.clamp(angle, -limit, limit))
	facing = unit(flat(turn:VectorToWorldSpace(facing)), facing)
	if moving then
		return turn:VectorToWorldSpace(planar)
	end
	return planar
end

local function turnFacing(toward: Vector3, rate: number, dt: number)
	if toward.Magnitude > 0.1 then
		local blended = facing:Lerp(toward.Unit, math.min(1, rate * dt))
		facing = unit(blended, facing)
	end
end

-- Rolling along the ground (a roll or a big-fall roll): bodies in the way are bumped, and a
-- wall met square on bonks you.
local function rollAlong(speed: number): Vector3
	hitAround("Bump", Bump.BodyReach, 0.35)
	local normal = wallIn(facing, Bonk.Reach)
	if normal then
		if facing:Dot(-normal) >= Bonk.Square then
			startBonk(normal)
			return flat(body.root.AssemblyLinearVelocity)
		end
		-- glancing: slide along it
		local along = facing - normal * facing:Dot(normal)
		facing = unit(along, facing)
	end
	return facing * speed
end

local function step(dt: number)
	if not alive() then
		return
	end
	local root, humanoid = body.root, body.humanoid
	if external then
		return
	end
	-- knocked flat: the body is loose, nothing here drives it until it's up again
	if Ragdoll.IsDown(body.character) then
		if standing then
			standing = false
			body.mover.Enabled = false
			body.aligner.Enabled = false
			setMove("Knocked")
			if lastKnock and now() - lastKnock.at < 0.5 then
				Ragdoll.Fling(body.character, lastKnock.velocity)
			end
		end
		return
	elseif not standing then
		standing = true
		body.mover.Enabled = true
		body.aligner.Enabled = true
		facing = unit(flat(root.CFrame.LookVector), facing)
		setMove("Fall")
	end
	local velocity = root.AssemblyLinearVelocity
	local planar = flat(velocity)
	local input = flat(humanoid.MoveDirection)
	if input.Magnitude > 1 then
		input = input.Unit
	end
	if frozen() then
		input = Vector3.zero
		jumpPressedAt = -math.huge
	end
	local onGround = grounded()
	local t = since()

	-- landing and leaving the ground
	if GROUND_MOVES[move] then
		if not onGround and move ~= "PoundLand" and move ~= "Bonk" then
			walkedOffAt = now()
			airPeakY = root.Position.Y
			setMove("Fall")
		end
	elseif onGround and t > LEAVE_GROUND_GRACE and move ~= "PoundSpin" and move ~= "Shoved" then
		onLanded()
	end
	if not onGround then
		airPeakY = math.max(airPeakY, root.Position.Y)
	end

	-- a jump pressed just before landing goes now
	if now() - jumpPressedAt <= Jump.Buffer and tryJump() then
		velocity = root.AssemblyLinearVelocity
		planar = flat(velocity)
		onGround = false
		t = 0
	end

	-- the move itself
	if move == "Run" or move == "Crouch" then
		if crouchHeld and move == "Run" then
			setMove("Crouch")
		elseif not crouchHeld and move == "Crouch" then
			setMove("Run")
		end
		if move == "Crouch" then
			if planar.Magnitude > Crouch.Speed then
				planar = towards(planar, planar.Unit * Crouch.Speed, Crouch.SlideFriction * dt)
			else
				planar = towards(planar, input * Crouch.Speed, Run.Accel * dt)
			end
		else
			-- a game can make you faster (Bomber Bloxians: whoever holds the bomb)
			local scale = body.character:GetAttribute(RoundInfo.SpeedAttr)
			scale = type(scale) == "number" and scale or 1
			-- and a Turbo power-up on foot, for a few seconds
			if (body.character:GetAttribute(PowerUpInfo.BoostAttr) or 0) > workspace:GetServerTimeNow() then
				scale *= body.character:GetAttribute(PowerUpInfo.BoostScaleAttr) or 1
			end
			local target = input * Run.Speed * scale
			local rate = Run.Accel
			if input.Magnitude < 0.1 then
				rate = Run.Friction
			elseif planar.Magnitude > 8 and input:Dot(planar.Unit) < -0.3 then
				rate = Run.Skid
			end
			planar = towards(planar, target, rate * dt)
		end
		planar = alongWalls(planar)
		turnFacing(input, Run.TurnRate, dt)
	elseif move == "Bump" then
		if t < Bump.WindUp then
			-- coiling back: you stop where you are
			planar = towards(planar, Vector3.zero, Bump.Brake * dt)
		elseif t < Bump.WindUp + Bump.Time then
			planar = facing * Bump.Lunge
			hitAround("Bump", Bump.Reach, Bump.Cone)
		else
			-- the burst stops dead; the hit still counts a moment after
			planar = towards(planar, Vector3.zero, Bump.Brake * dt)
			if t < Bump.WindUp + Bump.Time + 0.05 then
				hitAround("Bump", Bump.Reach, Bump.Cone)
			end
			if t > Bump.WindUp + Bump.Time + 0.12 then
				setMove(crouchHeld and "Crouch" or "Run")
			end
		end
	elseif move == "Roll" or move == "LandRoll" then
		local length = move == "Roll" and Roll.Time or BigFall.Time
		local speed = move == "Roll" and Roll.Speed or math.max(BigFall.Speed, planar.Magnitude)
		turnFacing(input, 4, dt)
		planar = rollAlong(speed)
		if move ~= "Bonk" and t > length then
			setMove(crouchHeld and "Crouch" or "Run")
		end
	elseif move == "Bonk" then
		if onGround and t > 0.15 then
			planar = towards(planar, Vector3.zero, Run.Friction * dt)
		end
		if t > Bonk.FallTime + Bonk.DazeTime + Bonk.GetUpTime then
			setMove("Run")
		end
	elseif move == "Slide" then
		planar = towards(planar, Vector3.zero, Dive.SlideFriction * dt)
		if t > Dive.SlideMin and planar.Magnitude < 2 then
			setMove(crouchHeld and "Crouch" or "Run")
		end
	elseif move == "PoundLand" then
		planar = Vector3.zero
		if t > Pound.LandLock then
			setMove(crouchHeld and "Crouch" or "Run")
		end
	elseif move == "PoundSpin" then
		planar = Vector3.zero
		root.AssemblyLinearVelocity = Vector3.zero
		if t > Pound.Hang then
			setMove("PoundFall")
		end
	elseif move == "PoundFall" then
		planar = Vector3.zero
		setVertical(-Pound.FallSpeed)
	elseif move == "Dive" then
		planar = airTurn(planar, input, dt, Air.DiveTurn)
		planar = steer(planar, input, dt, 0.25)
		hitAround("Dive", Bump.BodyReach, 0.35)
	elseif move == "LongJump" then
		planar = airTurn(planar, input, dt, Air.LongJumpTurn)
		planar = steer(planar, input, dt, 0.4)
	elseif move == "Backflip" then
		planar = airTurn(planar, input, dt, Air.FlipTurn)
		planar = steer(planar, input, dt, Backflip.Steer)
	elseif move == "Knocked" then
		if t > Bump.KnockTime then
			setMove("Fall")
		end
	elseif move == "Hero" then
		-- a pose struck in the intro (Platformer.Pose): stand still, then back to normal
		planar = Vector3.zero
		if t > poseFor then
			setMove("Run")
		end
	elseif move == "Shoved" then
		-- staggering back from a shove: the slide slows, then you have yourself back
		planar = towards(planar, Vector3.zero, Bump.ShoveSkid * dt)
		if t > Bump.ShoveTime then
			setMove(onGround and "Run" or "Fall")
		end
	elseif move == "WallCling" or move == "WallSlide" then
		local normal = wallNormal and wallIn(-wallNormal, Wall.Reach + 0.6)
		local pushingAway = input.Magnitude > 0.1 and wallNormal and input:Dot(wallNormal) > 0.6
		if not normal then
			setMove("Fall")
		elseif pushingAway and t > 0.12 then
			letGoOfWall(Wall.LetGoPush)
		elseif move == "WallCling" and t > Wall.Cling then
			setMove("WallSlide")
		elseif move == "WallSlide" and t + Wall.Cling > Wall.Hold then
			letGoOfWall(Wall.LetGoPush)
		else
			wallNormal = normal
			facing = -normal
			planar = -normal * 0.5 -- just touching it
			if move == "WallCling" then
				setVertical(gravity() * dt * 0.85) -- about cancels this step's gravity: held still
			else
				local down = math.min(Wall.SlideMax, t * Wall.SlideAccel)
				setVertical(-down)
			end
		end
	else -- Jump, AirJump, WallJump, PoundJump, Rollout, Fall
		planar = airTurn(planar, input, dt, 1)
		planar = steer(planar, input, dt, move == "AirJump" and AirJump.Steer or Air.SteerShare)
		if move == "AirJump" then
			-- running on air, you face where you run: the way you push, or the way you're going
			turnFacing(input.Magnitude > 0.1 and input or planar, AirJump.FaceRate, dt)
		end
		if move ~= "WallJump" then
			planar = alongWalls(planar)
		end
	end

	-- catch a wall: in the air, moving or pushing into it, not rising fast
	if not onGround and (move == "Jump" or move == "AirJump" or move == "Fall"
		or move == "WallJump" or move == "LongJump" or move == "Rollout" or move == "PoundJump") then
		local into = input.Magnitude > 0.1 and input or planar
		local normal = wallIn(into, Wall.Reach)
		if normal and not blocked(normal) and root.AssemblyLinearVelocity.Y < Wall.GrabRise then
			local pushing = input.Magnitude > 0.1 and input:Dot(-normal) > 0.5
			local moving = planar:Dot(-normal) > Wall.GrabSpeed
			if pushing or moving then
				wallNormal = normal
				airDived = false
				airJumped = false
				facing = -normal
				airPeakY = root.Position.Y
				setMove("WallCling")
				setVertical(0)
				planar = -normal * 0.5
			end
		end
	end

	-- heavier rising and falling than the world's gravity, and a cap on the fall
	local onWall = move == "WallCling" or move == "WallSlide"
	if not onGround and move ~= "PoundSpin" and move ~= "PoundFall" and not onWall then
		local up = root.AssemblyLinearVelocity.Y
		if move == "AirJump" then
			-- running on air: pulled toward a slow rise while jump is held, the lift giving out
			-- toward the end; let go (or run out) and it's an ordinary fall
			local t = since()
			local holding = jumpHeld or now() < touchHeldUntil
			if t > AirJump.Duration or (not holding and t > AirJump.MinTime) then
				setMove("Fall")
			else
				local tired = math.clamp((t / AirJump.Duration - AirJump.Tire) / (1 - AirJump.Tire), 0, 1)
				local target = AirJump.RiseSpeed + (AirJump.TiredSpeed - AirJump.RiseSpeed) * tired
				-- this step's gravity is cancelled first, so the pull alone sets the speed
				up += gravity() * dt
				up += (target - up) * (1 - math.exp(-AirJump.Pull * dt))
			end
		elseif up < 0 then
			up -= gravity() * (Air.FallGravity - 1) * dt
		else
			up -= gravity() * (Air.RiseGravity - 1) * dt -- rising is heavier too: snappy, not floaty
		end
		if up < -Air.MaxFall then
			up = -Air.MaxFall
		end
		setVertical(up)
	end

	humanoid.WalkSpeed = math.max(planar.Magnitude, 1)
	body.mover.PlaneVelocity = Vector2.new(planar.X, planar.Z)
	body.aligner.CFrame = CFrame.lookAt(Vector3.zero, facing)
end

-- ═══ input ════════════════════════════════════════════════════════════════════════

-- Bound through the engine's InputHandler, so each button gets the engine's input chip (the key
-- and what it does) and, on touch, a button in the engine's ring round Roblox's jump button.
-- Jump on touch is Roblox's own jump button. Each chip's label follows what the button would do
-- right now (refreshHints); one that would do nothing is dimmed.
local BINDING_PRIORITY = 3
local BUTTONS = {
	{
		Id = "BumpJump", Order = 1,
		Keys = { DESKTOP = { Enum.KeyCode.Space }, GAMEPAD = { Enum.KeyCode.ButtonA } },
		Press = function() onJumpPressed() end,
		Release = function() onJumpReleased() end,
	},
	{
		Id = "BumpCrouch", Order = 2,
		Keys = {
			DESKTOP = { Enum.KeyCode.C },
			GAMEPAD = { Enum.KeyCode.ButtonL2, Enum.KeyCode.ButtonR2 },
			MOBILE = { "primary2" },
		},
		Press = function()
			crouchHeld = true
			onCrouchPressed()
		end,
		Release = function()
			crouchHeld = false
		end,
	},
	{
		Id = "BumpAttack", Order = 3,
		Keys = {
			DESKTOP = { Enum.UserInputType.MouseButton1, Enum.KeyCode.E },
			GAMEPAD = { Enum.KeyCode.ButtonX, Enum.KeyCode.ButtonB },
			MOBILE = { "primary1" },
		},
		Press = function()
			if UserInputService:GetFocusedTextBox() then
				return
			end
			onAttackPressed()
		end,
	},
}

local hints = {} -- [id] = { handle, label, enabled }

-- What each button would do right now: (label, enabled).
local function jumpHint(): (string, boolean)
	if not alive() or LOCKED[move] then
		return "Jump", false
	end
	if move == "WallCling" or move == "WallSlide" then
		return "Wall Jump", true
	end
	if move == "PoundLand" then
		return "High Jump", since() <= Pound.JumpWindow
	end
	if move == "Slide" then
		return "Hop Out", true
	end
	if move == "Roll" or move == "LandRoll" then
		return "Long Jump", true
	end
	if move == "Run" or move == "Crouch" then
		local speed = flat(body.root.AssemblyLinearVelocity).Magnitude
		if crouchHeld then
			return speed >= LongJump.MinSpeed and "Long Jump" or "Backflip", true
		end
		return "Jump", true
	end
	if AIR_JUMP_FROM[move] then
		return "Float Jump", not airJumped
	end
	return "Jump", false
end

local function crouchHint(): (string, boolean)
	if not alive() or LOCKED[move] then
		return "Crouch", false
	end
	if move == "WallCling" or move == "WallSlide" then
		return "Let Go", true
	end
	if GROUND_MOVES[move] then
		return "Crouch", move == "Run" or move == "Crouch"
	end
	if move == "PoundSpin" or move == "PoundFall" or move == "Dive" then
		return "Ground Pound", false
	end
	return "Ground Pound", true
end

local function attackHint(): (string, boolean)
	if not alive() or LOCKED[move] then
		return "Bump", false
	end
	if GROUND_MOVES[move] then
		local moving = flat(body.root.AssemblyLinearVelocity).Magnitude > 4
		if move == "Run" or move == "Crouch" then
			if crouchHeld and moving then
				return "Roll", true
			end
			return "Bump", now() >= bumpReadyAt
		end
		return "Bump", false
	end
	if move == "WallCling" or move == "WallSlide" then
		return "Dive", false
	end
	return "Dive", not airDived
end

local HINTS = { BumpJump = jumpHint, BumpCrouch = crouchHint, BumpAttack = attackHint }

-- A plain jump needs no chip (the user, 2026-11-13: "we don't need a hint for Jump"); the jump
-- chip shows only when Space does something special: Float Jump, Backflip, Wall Jump...
local function shown(id: string, label: string): boolean
	return not (id == "BumpJump" and label == "Jump")
end

local function refreshHints()
	for id, entry in hints do
		local label, enabled
		if external and external.Hint then
			label, enabled = external.Hint(id)
		else
			label, enabled = HINTS[id]()
		end
		local visible = shown(id, label)
		if label ~= entry.label or enabled ~= entry.enabled or visible ~= entry.visible then
			entry.label, entry.enabled, entry.visible = label, enabled, visible
			entry.handle:Update({ Label = label, Enabled = enabled, Visible = visible })
		end
	end
end

local function bindButtons()
	for _, button in BUTTONS do
		local label = HINTS[button.Id]()
		InputHandler:BindInput(button.Id, button.Keys, BINDING_PRIORITY, function(state)
			local begin = state == Enum.UserInputState.Begin
			local finish = state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel
			if external then
				if begin or finish then
					external.Input(button.Id, begin and "Begin" or "End")
				end
				return
			end
			if begin and frozen() then
				return
			end
			if begin then
				button.Press()
			elseif finish and button.Release then
				button.Release()
			end
		end, { Hint = { Label = label, Group = "Moves", Order = button.Order } })
		-- the same Id merges with the binding's chip, and lets the label change
		local handle = InputHandler:RegisterInputHint({
			Id = button.Id, InputName = button.Id, Label = label, Group = "Moves", Order = button.Order,
			Visible = shown(button.Id, label),
		})
		if handle then
			hints[button.Id] = { handle = handle, label = label, enabled = true, visible = shown(button.Id, label) }
		end
	end

	-- Touch: the stock jump button sets JumpRequest, which also fires for the keys above, so only
	-- listen to it on a touch screen with no keyboard.
	UserInputService.JumpRequest:Connect(function()
		if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
			touchHeldUntil = now() + 0.3
			if not touchJumpLatch then
				touchJumpLatch = true
				onJumpPressed()
				jumpHeld = false -- touch has no release: held is touchHeldUntil
				task.delay(0.2, function()
					touchJumpLatch = false
				end)
			end
		end
	end)
end

-- ═══ system ═══════════════════════════════════════════════════════════════════════

function Platformer.Move(): string
	return move
end

function Platformer.MoveTime(): number
	return since()
end

-- How long the jump you are in will be in the air, predicted when it launched.
function Platformer.AirTime(): number
	return airTime
end

-- Hands the body to something else (riding a ball), or with nil takes it back. While handed
-- over, this module's movers are off, buttons go to handler.Input(id, "Begin" | "End") and chips
-- ask handler.Hint(id). handler.Stop() is called if this module takes the body back itself
-- (knocked off).
function Platformer.SetExternal(handler)
	if not body then
		return
	end
	external = handler
	body.mover.Enabled = handler == nil
	body.aligner.Enabled = handler == nil
	if handler == nil then
		facing = unit(flat(body.root.CFrame.LookVector), facing)
	end
end

-- The move to show for the body while something else drives it ("Ride", "RideCharge"...).
function Platformer.SetExternalMove(name: string)
	setMove(name)
end

-- Strikes a pose (move `name`, an Animator HELD clip; "Hero" in a game's intro) for `seconds`,
-- standing still and locked, then back to Run. Others see it through the move as usual. Only
-- on foot and standing.
function Platformer.Pose(name: string, seconds: number)
	if not alive() or external or not standing or LOCKED[move] then
		return
	end
	poseFor = seconds
	setMove(name)
end

-- A hop up off something (a ball), keeping `planar` speed.
function Platformer.Hop(planar: Vector3, height: number)
	if not alive() then
		return
	end
	launch(flat(planar), riseFor(height))
	setMove("Jump")
end

-- The character's body parts, for something else to hold on to.
function Platformer.Body()
	return body
end

-- Calls `listener(move, previous)` on every change of your own move, the moment it happens.
function Platformer.OnMove(listener)
	table.insert(listeners, listener)
end

function Platformer.start()
	bindButtons()
	Remotes.HookYou(function(name, data)
		if name == "Knock" and data and typeof(data.Velocity) == "Vector3" then
			onKnocked(data.Velocity, data.Kind)
		end
	end)
	player.CharacterAdded:Connect(function(character)
		body = nil
		task.spawn(attach, character)
	end)
	if player.Character then
		task.spawn(attach, player.Character)
	end
	RunService.PreSimulation:Connect(step)
	RunService.Heartbeat:Connect(refreshHints)
end

return Platformer
