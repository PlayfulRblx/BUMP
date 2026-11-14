--!nonstrict

local require =
	require(game:GetService("ServerScriptService"):FindFirstChild("LoaderUtils", true).Parent).bootstrapStory(script)

local Jest = require("Jest")
local BallPhysics = require(script.Parent.BallPhysics)
local Tuning = require("@Shared/Movement/Tuning")

local describe = Jest.Globals.describe
local expect = Jest.Globals.expect
local it = Jest.Globals.it

local Ball = Tuning.Of("Ball")
local DT = 1 / 60
local EAST = Vector3.new(1, 0, 0)

local function run(state, planar, input, seconds)
	local top = 0
	for _ = 1, math.round(seconds / DT) do
		planar = BallPhysics.Step(state, planar, input, DT)
		top = math.max(top, planar.Magnitude)
	end
	return planar, top
end

describe("BallPhysics", function()
	it("builds up to top speed and no further", function()
		local planar, top = run(BallPhysics.NewState(), Vector3.zero, EAST, 10)
		expect(planar.Magnitude).toBeCloseTo(Ball.MaxSpeed, 3)
		expect(top <= Ball.MaxSpeed + 1e-6).toBe(true)
	end)

	it("barely slows when you let go", function()
		local planar = run(BallPhysics.NewState(), EAST * Ball.MaxSpeed, Vector3.zero, 1)
		expect(planar.Magnitude).toBeCloseTo(Ball.MaxSpeed - Ball.Drag, 3)
	end)

	it("skids when you pull back hard against the roll", function()
		local state = BallPhysics.NewState()
		local planar = BallPhysics.Step(state, EAST * Ball.MaxSpeed, -EAST, DT)
		expect(state.Skrrt).toBe(true)
		expect(planar.Magnitude).toBeCloseTo(Ball.MaxSpeed - Ball.SkrrtDecel * DT, 3)
	end)

	it("charges a dash while slowing you, then launches at full charge", function()
		local state = BallPhysics.NewState()
		expect(BallPhysics.BeginCharge(state, 0)).toBe(true)
		expect(BallPhysics.BeginCharge(state, 0)).toBe(false) -- already charging
		local planar = run(state, EAST * 20, EAST, Ball.ChargeTime + 0.1)
		expect(state.Charge).toBe(1)
		expect(planar.Magnitude < 20).toBe(true)
		local dashed = BallPhysics.Release(state, planar, EAST, 0)
		expect(dashed.Magnitude).toBeCloseTo(Ball.DashBase + Ball.DashBonus, 3)
		expect(state.Charging).toBe(false)
		-- and not again until the cooldown is over
		expect(BallPhysics.BeginCharge(state, Ball.DashCooldown * 0.5)).toBe(false)
		expect(BallPhysics.BeginCharge(state, Ball.DashCooldown + 0.01)).toBe(true)
	end)

	it("lets a charge too small to count go without a dash", function()
		local state = BallPhysics.NewState()
		BallPhysics.BeginCharge(state, 0)
		state.Charge = Ball.DashMin * 0.5
		expect(BallPhysics.Release(state, EAST * 10, EAST, 0)).toBe(nil)
	end)

	it("spins a ball so it rolls without slipping", function()
		local spin = BallPhysics.Spin(EAST * 10, 4)
		expect(spin.Magnitude * 4).toBeCloseTo(10, 5)
		expect(spin.Y).toBe(0)
	end)
end)
