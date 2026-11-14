--!nonstrict
--[[
	Riding a ball (BUMP), on your own client: you drive the ball you ride, so it answers at once.

	Getting on: land on top of a free ball (within Ball.MountReach of its top) and this asks the
	server ("Mount"); the server says yes by setting the ball's Rider to you and handing you its
	physics. Then the platformer hands your body over (Platformer.SetExternal): your body is held
	on top of the ball, facing the way it rolls, and the buttons drive the ball:

	    move        roll; it builds up slowly and is hard to stop
	    pull back   skrrt: skid hard to a stop
	    hold click  charge a dash (slows you), let go to launch
	    Space       hop off

	Hit while riding, you wobble (steering weakens) and the server sends the shove ("BallHit");
	hit again while wobbling and the server knocks you off: it clears the Rider and throws you,
	and the platformer takes your body back.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local BallPhysics = require("@Shared/Minigames/BallPhysics")
local Remotes = require("@Shared/Movement/Remotes")
local RoundInfo = require("@Shared/Rounds/RoundInfo")
local Tuning = require("@Shared/Movement/Tuning")
local Ragdoll = require("@Shared/Ragdoll")
local Platformer = require("@Client/Systems/Platformer")
local RoundClient = require("@Client/Systems/RoundClient")

local Ball = Tuning.Of("Ball")

local BallRider = {}

local BALL_TAG = "BumpBall"
local RIDER_ATTR = "Rider"
local WOBBLE_ATTR = "BumpWobbleUntil"
local DASH_POSE = 0.45 -- seconds the launch pose holds after a dash
local RIDE_BANK = 0.006 -- lean into turns: radians per (radian a second of turning x stud a second)
local RIDE_BANK_MAX = math.rad(22)
-- Speed felt (the user: the ball game "seems a little too slow"): the view widens with speed
-- and punches out on a hit; a wind trail streams off you when you're really going.
local FOV_GAIN = 16 -- degrees wider at top dash speed
local FOV_PUNCH = 10 -- degrees out on the hardest hit, easing back
local TRAIL_SPEED = 40 -- studs a second before the wind trail shows

local player = Players.LocalPlayer
local myId = tostring(player.UserId)

local ride = nil -- { ball, physics, attachment, hold, upright, facing, pauseUntil, pauseVelocity, follow, trail }
local baseFov = nil -- the camera's field of view before riding
local punch = 0 -- the hit's extra field of view, easing back
local askedAt = 0

local function radius(ball: BasePart): number
	return ball.Size.X / 2
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function setSolid(character: Model, riding: boolean)
	for _, part in character:GetDescendants() do
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

-- ═══ getting off ══════════════════════════════════════════════════════════════════

local function stop(hop: boolean)
	if not ride then
		return
	end
	local current = ride
	ride = nil
	RoundClient.Set("Charge", 0)
	if current.trail then
		current.trail:Destroy()
	end
	local camera = Workspace.CurrentCamera
	if camera and baseFov then
		camera.FieldOfView = baseFov
	end
	for _, thing in { current.hold, current.upright, current.attachment } do
		if thing then
			thing:Destroy()
		end
	end
	local body = Platformer.Body()
	if body then
		setSolid(body.character, false)
		body.humanoid.WalkSpeed = 16
	end
	if hop then
		Platformer.SetExternal(nil)
		Platformer.Hop(flat(current.ball.AssemblyLinearVelocity) * 0.6, 6)
	end
end

-- ═══ the handler the platformer hands the body to ═════════════════════════════════

local handler = {}

function handler.Input(id: string, phase: string)
	if not ride then
		return
	end
	if id == "BumpJump" and phase == "Begin" then
		Remotes.Act("Dismount")
		stop(true)
	elseif id == "BumpAttack" then
		local nowClock = os.clock()
		if phase == "Begin" then
			BallPhysics.BeginCharge(ride.physics, nowClock)
		else
			local body = Platformer.Body()
			local input = body and flat(body.humanoid.MoveDirection) or Vector3.zero
			local planar = flat(ride.ball.AssemblyLinearVelocity)
			local dashed = BallPhysics.Release(ride.physics, planar, input.Magnitude > 0.1 and input or ride.facing, nowClock)
			if dashed then
				ride.ball.AssemblyLinearVelocity = Vector3.new(dashed.X, ride.ball.AssemblyLinearVelocity.Y, dashed.Z)
				ride.dashUntil = nowClock + DASH_POSE -- the launch pose (and its effects) while the dash carries
			end
		end
	end
end

function handler.Hint(id: string): (string, boolean)
	if id == "BumpJump" then
		return "Hop Off", true
	elseif id == "BumpAttack" then
		if ride and ride.physics.Charging then
			return "Release to Dash", true
		end
		return "Charge Dash", ride ~= nil and os.clock() >= ride.physics.DashReadyAt
	end
	return "Crouch", false
end

-- Knocked off by the platformer taking the body back.
function handler.Stop()
	stop(false)
end

-- ═══ getting on ═══════════════════════════════════════════════════════════════════

local function start(ball: BasePart)
	local body = Platformer.Body()
	if not body or ride then
		return
	end
	local root = body.root
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
	upright.Responsiveness = 40
	upright.MaxTorque = 1e7
	upright.Parent = root
	setSolid(body.character, true)
	-- not PlatformStand: Roblox's controls stop reporting the stick (MoveDirection) under it.
	-- The rigid hold keeps the body on the ball; walking speed 0 stops the Humanoid pushing.
	body.humanoid.WalkSpeed = 0
	local look = flat(root.CFrame.LookVector)
	ride = {
		ball = ball,
		physics = BallPhysics.NewState(),
		attachment = attachment,
		hold = hold,
		upright = upright,
		facing = look.Magnitude > 0.1 and look.Unit or Vector3.new(0, 0, -1),
	}
	-- the wind trail, off the body (the ball spins): two points either side at the ball's middle
	local height = radius(ball) + body.humanoid.HipHeight + root.Size.Y / 2
	local left, right = Instance.new("Attachment"), Instance.new("Attachment")
	left.Position = Vector3.new(-radius(ball) * 0.9, -height, 0)
	right.Position = Vector3.new(radius(ball) * 0.9, -height, 0)
	left.Parent, right.Parent = root, root
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = left, right
	trail.Color = ColorSequence.new(Color3.new(1, 1, 1))
	trail.Transparency = NumberSequence.new(0.6, 1)
	trail.Lifetime = 0.22
	trail.LightEmission = 0.4
	trail.Enabled = false
	trail.Parent = root
	ride.trail = trail
	local camera = Workspace.CurrentCamera
	baseFov = baseFov or (camera and camera.FieldOfView) or 70
	Platformer.SetExternal(handler)
	Platformer.SetExternalMove("Ride")
end

-- While on foot in a game: land on top of a free ball and ask to ride it.
local function lookForBall()
	local body = Platformer.Body()
	if not body or Ragdoll.IsDown(body.character) or os.clock() - askedAt < 0.3 then
		return
	end
	local root = body.root
	for _, ball in CollectionService:GetTagged(BALL_TAG) do
		if ball:IsA("BasePart") and (ball:GetAttribute(RIDER_ATTR) or "") == "" then
			local r = radius(ball)
			local top = ball.Position + Vector3.new(0, r, 0)
			local feet = root.Position - Vector3.new(0, body.humanoid.HipHeight + root.Size.Y / 2, 0)
			local above = feet.Y > ball.Position.Y + r * 0.4
			if above and (feet - top).Magnitude <= Ball.MountReach then
				askedAt = os.clock()
				Remotes.Act("Mount", ball)
				return
			end
		end
	end
end

-- ═══ every frame ══════════════════════════════════════════════════════════════════

local function step(dt: number)
	-- the server's word on whose ball is whose
	if ride then
		if not ride.ball.Parent or ride.ball:GetAttribute(RIDER_ATTR) ~= myId then
			stop(false)
			Platformer.SetExternal(nil)
			return
		end
	else
		for _, ball in CollectionService:GetTagged(BALL_TAG) do
			if ball:GetAttribute(RIDER_ATTR) == myId then
				start(ball)
				break
			end
		end
		if not ride then
			lookForBall()
			return
		end
	end

	local body = Platformer.Body()
	if not body then
		return
	end
	local ball = ride.ball
	local r = radius(ball)
	local physics = ride.physics
	-- a hit's freeze: held still a beat, then away again (carried through, if we hit them)
	if ride.pauseUntil then
		if os.clock() < ride.pauseUntil then
			ball.AssemblyLinearVelocity = Vector3.new(0, ball.AssemblyLinearVelocity.Y, 0)
			ball.AssemblyAngularVelocity = Vector3.zero
			ride.hold.Position = ball.Position + Vector3.new(0, r + body.humanoid.HipHeight + body.root.Size.Y / 2, 0)
			return
		end
		local resume = ride.follow or ride.pauseVelocity or Vector3.zero
		ball.AssemblyLinearVelocity = Vector3.new(resume.X, ball.AssemblyLinearVelocity.Y, resume.Z)
		ride.pauseUntil, ride.pauseVelocity, ride.follow = nil, nil, nil
	end
	local folder = ReplicatedStorage:FindFirstChild(RoundInfo.Folder)
	local frozen = folder and folder:GetAttribute("Frozen") == true
	local input = frozen and Vector3.zero or flat(body.humanoid.MoveDirection)
	if input.Magnitude > 1 then
		input = input.Unit
	end
	physics.Wobbling = (body.character:GetAttribute(WOBBLE_ATTR) or 0) > serverNow()

	local velocity = ball.AssemblyLinearVelocity
	local planar = BallPhysics.Step(physics, flat(velocity), input, dt)
	ball.AssemblyLinearVelocity = Vector3.new(planar.X, velocity.Y, planar.Z)
	ball.AssemblyAngularVelocity = BallPhysics.Spin(planar, r)

	-- facing: the way it rolls, or the way you push when slow
	local facedBefore = ride.facing
	if planar.Magnitude > 3 then
		ride.facing = ride.facing:Lerp(planar.Unit, math.min(1, 8 * dt)).Unit
	elseif input.Magnitude > 0.1 then
		ride.facing = ride.facing:Lerp(input.Unit, math.min(1, 8 * dt)).Unit
	end
	local height = r + body.humanoid.HipHeight + body.root.Size.Y / 2
	ride.hold.Position = ball.Position + Vector3.new(0, height, 0)
	-- lean into the roll, back on a skrrt
	local lean = math.clamp(planar.Magnitude / Ball.MaxSpeed, 0, 1.4) * math.rad(physics.Skrrt and -18 or 10)
	-- and bank into turns, the harder the faster (smoothed so it sways in and out)
	local turn = math.atan2(facedBefore:Cross(ride.facing).Y, facedBefore:Dot(ride.facing)) / math.max(dt, 1 / 240)
	local bankTarget = math.clamp(turn * planar.Magnitude * RIDE_BANK, -RIDE_BANK_MAX, RIDE_BANK_MAX)
	ride.bank = (ride.bank or 0) + (bankTarget - (ride.bank or 0)) * math.min(1, 6 * dt)
	ride.upright.CFrame = CFrame.lookAt(Vector3.zero, ride.facing) * CFrame.Angles(-lean, 0, ride.bank)

	-- the view widens with speed and punches out on a hit; the trail shows when really going
	local camera = Workspace.CurrentCamera
	if camera and baseFov then
		punch = math.max(0, punch - dt * 30)
		local fast = math.clamp((planar.Magnitude - Ball.MaxSpeed * 0.6) / (Ball.DashBase + Ball.DashBonus - Ball.MaxSpeed * 0.6), 0, 1)
		local goal = baseFov + fast * FOV_GAIN + punch
		camera.FieldOfView += (goal - camera.FieldOfView) * math.min(1, dt * 8)
	end
	if ride.trail then
		ride.trail.Enabled = planar.Magnitude > TRAIL_SPEED
	end
	RoundClient.Set("Charge", physics.Charging and physics.Charge or 0)
	local move = physics.Charging and "RideCharge"
		or os.clock() < (ride.dashUntil or 0) and "RideDash"
		or physics.Skrrt and "RideSkrrt"
		or physics.Wobbling and "RideWobble"
		or "Ride"
	if Platformer.Move() ~= move then
		Platformer.SetExternalMove(move)
	end
end

function BallRider.Riding(): BasePart?
	return ride and ride.ball or nil
end

function BallRider.Speed(): number
	return ride and flat(ride.ball.AssemblyLinearVelocity).Magnitude or 0
end

function BallRider.start()
	Remotes.HookYou(function(name, data)
		if name == "BallHit" and ride and data and typeof(data.Impulse) == "Vector3" then
			if ride.pauseUntil then
				ride.pauseVelocity = (ride.pauseVelocity or Vector3.zero) + data.Impulse
			else
				ride.ball.AssemblyLinearVelocity += data.Impulse
			end
		elseif name == "Turbo" and ride and data and type(data.Scale) == "number" then
			-- a Turbo power-up: a full dash the way you're pushing (or rolling)
			local body = Platformer.Body()
			local input = body and flat(body.humanoid.MoveDirection) or Vector3.zero
			local planar = flat(ride.ball.AssemblyLinearVelocity)
			local dashed = BallPhysics.Boost(ride.physics, planar, input.Magnitude > 0.1 and input or ride.facing, data.Scale)
			ride.ball.AssemblyLinearVelocity = Vector3.new(dashed.X, ride.ball.AssemblyLinearVelocity.Y, dashed.Z)
			ride.dashUntil = os.clock() + DASH_POSE
		end
	end)
	-- a ball hit with my ball in it: freeze a beat and punch the view; carry on through if I hit
	Remotes.HookFx(function(name, data)
		if name ~= "BallHit" or not ride or type(data) ~= "table" then
			return
		end
		local hitter, hit = data.Hitter == ride.ball, data.Hit == ride.ball
		if not hitter and not hit then
			return
		end
		local strength = tonumber(data.Strength) or 0
		ride.pauseUntil = os.clock() + (tonumber(data.Pause) or 0.06)
		ride.pauseVelocity = ride.ball.AssemblyLinearVelocity
		if hitter and typeof(data.Follow) == "Vector3" then
			ride.follow = data.Follow
		end
		punch = math.max(punch, FOV_PUNCH * (0.4 + 0.6 * strength))
	end)
	player.CharacterAdded:Connect(function()
		ride = nil
	end)
	RunService.PreSimulation:Connect(step)
end

return BallRider
