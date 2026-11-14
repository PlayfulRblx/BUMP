--!nonstrict
--[[
	Knocked flat (BUMP: thrown off a ball, run over). Ported from The Scramble's limp bodies,
	which had already been tuned in play there; BUMP drives it with one attribute: the server
	sets "BumpRagdoll" on a character (true, then false) and every machine follows it
	(Ragdoll.Watch, once on the server and on each client), so the body looks the same
	everywhere and its owner puts its Humanoid in the Physics state with no round trip.

	The Scramble's notes follow.

	Limp bodies, for R15 rigs. Each limb joint gets a matching ball socket, switched off until
	needed; going limp swaps the motors for the sockets and back. The Root joint stays on, so
	the hips stay one unit with the HumanoidRootPart and network ownership never changes hands.

	Sockets limit around their attachments' X axis, so they use the rig's own joint
	attachments, whose axes suit each joint, plus purpose-built shoulder attachments with X
	down the arm. Limits and friction are Roblox's standard R15 ragdoll values.

	Hard limits alone leave a body that flops to the end of every joint and lies there straight
	and splayed. So each joint also gets a weak muscle, an AlignOrientation between its two parts,
	pulling it towards a neutral body posture (the pose a body takes with nothing to do: knees
	and elbows bent, arms a little out, head and hips forward). It is weaker than gravity, so it
	shapes how the body falls and settles rather than holding it up, and it softens the limits:
	a limb is drawn back before it slams into its stop. Strength is `Ragdoll.Tension`, a share of
	the weight hanging off each joint, read whenever a body goes limp.

	Whoever simulates a character (the owning client, or the server for a bot) has to put the
	Humanoid in the Physics state. The server also switches everyone's characters so other
	clients see it; the owner switches first, so a launch goes limp with no round trip.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CollectionService = game:GetService("CollectionService")

local Tuning = require("@Shared/Movement/Tuning")

local Ragdoll = {}

local REFERENCE_GRAVITY = 196.2
local SOCKET_NAME = "BumpRagdollSocket"
local TENSION_NAME = "BumpRagdollTension"
local Settings = Tuning.Of("Ragdoll")

Ragdoll.Attribute = "BumpRagdoll"

local NECK = { 45, -40, 40, 15, 1.02 }
local WAIST = { 20, -40, 20, 750, 2.86 }
local SHOULDER = { 110, -85, 85, 0.5, 0.91 }
local ELBOW = { 20, 5, 120, 0.5, 0.7 }
local WRIST = { 30, -10, 10, 1, 0.69 }
local HIP = { 40, -5, 80, 0.5, 1.92 }
local KNEE = { 5, -120, -5, 0.5, 0.65 }
local ANKLE = { 10, -10, 10, 0.5, 0.44 }

-- Part0, Part1, attachment both share, motor (found on Part1), limits as { cone, twist low,
-- twist high, friction torque, reference mass }.
local RIG = {
	{ "UpperTorso", "Head", "NeckRigAttachment", "Neck", NECK },
	{ "LowerTorso", "UpperTorso", "WaistRigAttachment", "Waist", WAIST },
	{ "UpperTorso", "LeftUpperArm", "LeftShoulderRagdollAttachment", "LeftShoulder", SHOULDER },
	{ "LeftUpperArm", "LeftLowerArm", "LeftElbowRigAttachment", "LeftElbow", ELBOW },
	{ "LeftLowerArm", "LeftHand", "LeftWristRigAttachment", "LeftWrist", WRIST },
	{ "UpperTorso", "RightUpperArm", "RightShoulderRagdollAttachment", "RightShoulder", SHOULDER },
	{ "RightUpperArm", "RightLowerArm", "RightElbowRigAttachment", "RightElbow", ELBOW },
	{ "RightLowerArm", "RightHand", "RightWristRigAttachment", "RightWrist", WRIST },
	{ "LowerTorso", "LeftUpperLeg", "LeftHipRigAttachment", "LeftHip", HIP },
	{ "LeftUpperLeg", "LeftLowerLeg", "LeftKneeRigAttachment", "LeftKnee", KNEE },
	{ "LeftLowerLeg", "LeftFoot", "LeftAnkleRigAttachment", "LeftAnkle", ANKLE },
	{ "LowerTorso", "RightUpperLeg", "RightHipRigAttachment", "RightHip", HIP },
	{ "RightUpperLeg", "RightLowerLeg", "RightKneeRigAttachment", "RightKnee", KNEE },
	{ "RightLowerLeg", "RightFoot", "RightAnkleRigAttachment", "RightAnkle", ANKLE },
}

-- Neutral body posture, per motor: degrees about the parent part's own axes (X right, Y up, Z
-- back) as { pitch, yaw, roll }, and the lever in studs the weight below it acts through.
-- Positive pitch swings a hanging limb forward (and tips a head or chest back); positive roll
-- swings it towards +X, so a right limb out is +roll and a left one is -roll.
local NEUTRAL = {
	Neck = { -15, 0, 0, 0.6 },
	Waist = { -8, 0, 0, 1.0 },
	RightShoulder = { 15, 0, 35, 1.2 },
	LeftShoulder = { 15, 0, -35, 1.2 },
	RightElbow = { 45, 0, 0, 0.6 },
	LeftElbow = { 45, 0, 0, 0.6 },
	RightWrist = { 10, 0, 0, 0.2 },
	LeftWrist = { 10, 0, 0, 0.2 },
	RightHip = { 30, 0, 8, 1.5 },
	LeftHip = { 30, 0, -8, 1.5 },
	RightKnee = { -45, 0, 0, 0.8 },
	LeftKnee = { -45, 0, 0, 0.8 },
	RightAnkle = { -20, 0, 0, 0.3 },
	LeftAnkle = { -20, 0, 0, 0.3 },
}

local DOWN, LEFT, RIGHT, UP = -Vector3.yAxis, -Vector3.xAxis, Vector3.xAxis, Vector3.yAxis

-- Shoulders swing further than any other joint, so their cone has to run down the arm.
local SHOULDER_ATTACHMENTS = {
	{ "UpperTorso", "RightShoulderRagdollAttachment", CFrame.fromMatrix(Vector3.zero, RIGHT, UP), "RightShoulderRigAttachment" },
	{ "RightUpperArm", "RightShoulderRagdollAttachment", CFrame.fromMatrix(Vector3.zero, DOWN, RIGHT), "RightShoulderRigAttachment" },
	{ "UpperTorso", "LeftShoulderRagdollAttachment", CFrame.fromMatrix(Vector3.zero, LEFT, UP), "LeftShoulderRigAttachment" },
	{ "LeftUpperArm", "LeftShoulderRagdollAttachment", CFrame.fromMatrix(Vector3.zero, DOWN, LEFT), "LeftShoulderRigAttachment" },
}

-- Parts close enough to catch on each other and jam the body up.
local NO_COLLIDES = {
	{ "LowerTorso", "LeftUpperArm" },
	{ "LeftUpperArm", "LeftHand" },
	{ "LowerTorso", "RightUpperArm" },
	{ "RightUpperArm", "RightHand" },
	{ "LeftUpperLeg", "RightUpperLeg" },
	{ "UpperTorso", "RightUpperLeg" },
	{ "RightUpperLeg", "RightFoot" },
	{ "UpperTorso", "LeftUpperLeg" },
	{ "LeftUpperLeg", "LeftFoot" },
	{ "UpperTorso", "LeftLowerLeg" },
	{ "UpperTorso", "RightLowerLeg" },
	{ "LowerTorso", "LeftLowerLeg" },
	{ "LowerTorso", "RightLowerLeg" },
	{ "UpperTorso", "LeftLowerArm" },
	{ "UpperTorso", "RightLowerArm" },
	{ "Head", "LeftUpperArm" },
	{ "Head", "RightUpperArm" },
}

Ragdoll.BodyParts = {
	"Head",
	"UpperTorso",
	"LowerTorso",
	"LeftUpperArm",
	"LeftLowerArm",
	"LeftHand",
	"RightUpperArm",
	"RightLowerArm",
	"RightHand",
	"LeftUpperLeg",
	"LeftLowerLeg",
	"LeftFoot",
	"RightUpperLeg",
	"RightLowerLeg",
	"RightFoot",
}

local stateGuards = {} -- [Model] = connection holding the Humanoid in Physics

local function ensureAttachments(character: Model)
	for _, spec in ipairs(SHOULDER_ATTACHMENTS) do
		local part = character:FindFirstChild(spec[1])
		local base = part and part:FindFirstChild(spec[4])
		if base and not part:FindFirstChild(spec[2]) then
			local attachment = Instance.new("Attachment")
			attachment.Name = spec[2]
			attachment.CFrame = base.CFrame * spec[3]
			attachment.Parent = part
		end
	end
end

local function ensureSocket(character: Model, spec)
	local part0, part1 = character:FindFirstChild(spec[1]), character:FindFirstChild(spec[2])
	local attachment0 = part0 and part0:FindFirstChild(spec[3])
	local attachment1 = part1 and part1:FindFirstChild(spec[3])
	if not attachment0 or not attachment1 or part1:FindFirstChild(SOCKET_NAME) then
		return
	end
	local limits = spec[5]
	local socket = Instance.new("BallSocketConstraint")
	socket.Name = SOCKET_NAME
	socket.Attachment0 = attachment0
	socket.Attachment1 = attachment1
	socket.LimitsEnabled = true
	socket.UpperAngle = limits[1]
	socket.TwistLimitsEnabled = true
	socket.TwistLowerAngle = limits[2]
	socket.TwistUpperAngle = limits[3]
	socket.MaxFrictionTorque = limits[4] * (part1:GetMass() / limits[5]) * (Workspace.Gravity / REFERENCE_GRAVITY)
	socket.Enabled = false
	socket.Parent = part1
end

-- The mass of a part and every part hanging off it.
local function chainMass(character: Model, partName: string): number
	local part = character:FindFirstChild(partName)
	local mass = part and part:GetMass() or 0
	for _, spec in ipairs(RIG) do
		if spec[1] == partName then
			mass += chainMass(character, spec[2])
		end
	end
	return mass
end

-- The muscle: holds the motor's Part1 where the motor would with the neutral pose as its
-- Transform. AlignOrientation turns Attachment0 to match Attachment1, so Attachment0 sits on
-- Part1 at C1 and Attachment1 on Part0 at C0 turned by the neutral pose (in Part0's axes).
local function ensureTension(character: Model, spec)
	local part0, part1 = character:FindFirstChild(spec[1]), character:FindFirstChild(spec[2])
	local motor = part1 and part1:FindFirstChild(spec[4])
	local neutral = NEUTRAL[spec[4]]
	-- Rigs on Roblox's newer avatar joints have an AnimationConstraint where a Motor6D was; it
	-- has the same C0, C1 and Transform.
	local joint = motor and (motor:IsA("Motor6D") or motor:IsA("AnimationConstraint"))
	if not part0 or not joint or not neutral or part1:FindFirstChild(TENSION_NAME) then
		return
	end
	local turn = CFrame.Angles(math.rad(neutral[1]), math.rad(neutral[2]), math.rad(neutral[3]))
	local onChild = Instance.new("Attachment")
	onChild.Name = TENSION_NAME .. "Child"
	onChild.CFrame = motor.C1
	onChild.Parent = part1
	local onParent = Instance.new("Attachment")
	onParent.Name = TENSION_NAME .. "_" .. spec[2]
	onParent.CFrame = CFrame.new(motor.C0.Position) * turn * motor.C0.Rotation
	onParent.Parent = part0
	local align = Instance.new("AlignOrientation")
	align.Name = TENSION_NAME
	align.Mode = Enum.OrientationAlignmentMode.TwoAttachment
	align.Attachment0 = onChild
	align.Attachment1 = onParent
	align.RigidityEnabled = false
	align.ReactionTorqueEnabled = true
	align:SetAttribute("Load", chainMass(character, spec[2]) * neutral[4])
	align.Enabled = false
	align.Parent = part1
end

-- Builds the sockets, muscles and collision filters once. Safe to call again.
function Ragdoll.Prepare(character: Model)
	-- A loose neck kills a Humanoid by default, and a death breaks every joint: a knocked-flat
	-- player died and respawned (the engine's anti-cheat then threw on the new character). The
	-- Scramble sets both on its fighters; here it is part of getting a body ready.
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.RequiresNeck = false
		humanoid.BreakJointsOnDeath = false
	end
	ensureAttachments(character)
	for _, spec in ipairs(RIG) do
		ensureSocket(character, spec)
		ensureTension(character, spec)
	end
	for _, pair in ipairs(NO_COLLIDES) do
		local part0, part1 = character:FindFirstChild(pair[1]), character:FindFirstChild(pair[2])
		if part0 and part1 and not part1:FindFirstChild("NoCollide_" .. pair[1]) then
			local filter = Instance.new("NoCollisionConstraint")
			filter.Name = "NoCollide_" .. pair[1]
			filter.Part0 = part0
			filter.Part1 = part1
			filter.Parent = part1
		end
	end
end

-- Whether this machine simulates the character, and so decides its Humanoid state.
local function simulates(character: Model): boolean
	if RunService:IsClient() then
		return character == Players.LocalPlayer.Character
	end
	return Players:GetPlayerFromCharacter(character) == nil
end

-- Freed limbs become their own assemblies, and Roblox hands those to the nearest player. A bot
-- is the server's to simulate, so it takes each one back once the joints have let go.
local function keepOnServer(character: Model)
	if RunService:IsClient() or Players:GetPlayerFromCharacter(character) then
		return
	end
	task.defer(function()
		for _, name in ipairs(Ragdoll.BodyParts) do
			local part = character:FindFirstChild(name)
			if part and not part.Anchored and part:CanSetNetworkOwnership() then
				part:SetNetworkOwner(nil)
			end
		end
	end)
end

local function holdPhysicsState(character: Model, humanoid: Humanoid)
	local function hold()
		if humanoid.Health > 0 and humanoid:GetState() ~= Enum.HumanoidStateType.Dead then
			humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		end
	end
	if not stateGuards[character] then
		stateGuards[character] = humanoid.StateChanged:Connect(hold)
	end
	hold()
end

local function releasePhysicsState(character: Model, humanoid: Humanoid)
	if stateGuards[character] then
		stateGuards[character]:Disconnect()
		stateGuards[character] = nil
	end
	if humanoid.Health > 0 then
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
end

-- A Humanoid switches its Root joint off as it dies. The HumanoidRootPart, which collides with
-- nothing while limp, then drops through the floor alone, and whatever follows it goes too. Each
-- machine has its own copy of the Humanoid, so each one calls this for every character.
function Ragdoll.KeepRootJoint(character: Model)
	local hips = character:WaitForChild("LowerTorso")
	local joint = hips:WaitForChild("Root")
	joint:GetPropertyChangedSignal("Enabled"):Connect(function()
		if not joint.Enabled then
			joint.Enabled = true
		end
	end)
end

function Ragdoll.IsLimp(character: Model): boolean
	return character:GetAttribute(Ragdoll.Attribute) == true
end

-- BUMP's name for it.
Ragdoll.IsDown = Ragdoll.IsLimp

-- The joint angle that holds a motor's Part1 exactly where it is now.
function Ragdoll.PoseOf(motor: Motor6D): CFrame
	return motor.C0:Inverse() * motor.Part0.CFrame:ToObjectSpace(motor.Part1.CFrame) * motor.C1
end

-- Puts this machine's copy of the body down or up. The attribute is the server's to set;
-- Watch calls this when it changes.
function Ragdoll.Set(character: Model, limp: boolean)
	for _, spec in ipairs(RIG) do
		local part = character:FindFirstChild(spec[2])
		local motor = part and part:FindFirstChild(spec[4])
		local socket = part and part:FindFirstChild(SOCKET_NAME)
		local tension = part and part:FindFirstChild(TENSION_NAME)
		if motor then
			if not limp and motor.Part0 and motor.Part1 then
				-- Take up the pose the body is lying in, or the limbs snap back this frame.
				motor.Transform = Ragdoll.PoseOf(motor)
			end
			motor.Enabled = not limp
		end
		if socket then
			socket.Enabled = limp
		end
		if tension then
			local strength = Settings.Tension
			tension.MaxTorque = strength * (tension:GetAttribute("Load") or 0) * Workspace.Gravity
			tension.Responsiveness = Settings.Responsiveness
			tension.Enabled = limp and strength > 0
		end
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root then
		-- The body rests on its own limbs, not on the invisible box round the hips.
		root.CanCollide = not limp
	end
	-- Player heads spawn without collision, and a limp one sinks into the floor.
	local head = character:FindFirstChild("Head")
	if head and limp then
		head.CanCollide = true
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if limp then
		keepOnServer(character)
	end
	if humanoid and simulates(character) then
		if limp then
			holdPhysicsState(character, humanoid)
		else
			releasePhysicsState(character, humanoid)
		end
	end
end

-- Every machine: follow the attribute on every body with this tag.
-- Throws a whole body. Going limp loosens the joints, which splits the body into separate
-- assemblies; the limbs start at rest and drag a thrown torso to a stop (a dummy thrown at 76
-- studs a second was down to 18 a tenth of a second later and slid 6.8 studs). So every part is
-- given the speed, now and again over the next couple of frames once the ragdoll has taken hold.
function Ragdoll.Fling(character: Model, velocity: Vector3, spin: Vector3?)
	local function push()
		for _, part in character:GetDescendants() do
			if part:IsA("BasePart") and not part.Anchored then
				part.AssemblyLinearVelocity = velocity
				if spin then
					part.AssemblyAngularVelocity = spin
				end
			end
		end
	end
	push()
	task.spawn(function()
		for _ = 1, 3 do
			RunService.Heartbeat:Wait()
			if not character.Parent then
				return
			end
			push()
		end
	end)
end

function Ragdoll.Watch(tag: string)
	local function track(model)
		if not model:IsA("Model") then
			return
		end
		task.spawn(function()
			-- the joints arrive a moment after the model on other machines
			if not model:WaitForChild("LowerTorso", 10) or not model:WaitForChild("Humanoid", 10) then
				return
			end
			task.wait(0.2)
			Ragdoll.Prepare(model)
			task.spawn(Ragdoll.KeepRootJoint, model)
			model:GetAttributeChangedSignal(Ragdoll.Attribute):Connect(function()
				Ragdoll.Set(model, Ragdoll.IsLimp(model))
			end)
			if Ragdoll.IsLimp(model) then
				Ragdoll.Set(model, true)
			end
		end)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(track)
	for _, model in CollectionService:GetTagged(tag) do
		track(model)
	end
end

return Ragdoll
