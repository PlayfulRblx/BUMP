--!nonstrict
--[[
	How a ball rolls under its rider, the same on a player's client (who drives their own ball)
	and on the server (which drives the bots' balls). One step:

	    local planar = BallPhysics.Step(state, planarVelocity, input, dt)

	state carries what lasts between steps: Charging, Charge (0 to 1), DashReadyAt, Wobbling,
	Skrrt (true while skidding). input is the direction pushed (length 0 to 1, flat).
	Release a charge with BallPhysics.Release(state, planar, direction).

	The feel: it builds up slowly and is hard to stop. Letting go barely slows it; pulling hard
	against the roll skids it to a stop (a skrrt); charging a dash slows you down while you hold
	it, then launches you.
]]

local Tuning = require("@Shared/Movement/Tuning")

local Ball = Tuning.Of("Ball")

local BallPhysics = {}

local function towards(current: Vector3, target: Vector3, step: number): Vector3
	local delta = target - current
	local distance = delta.Magnitude
	if distance <= step or distance < 1e-4 then
		return target
	end
	return current + delta / distance * step
end

function BallPhysics.NewState()
	return { Charging = false, Charge = 0, DashReadyAt = 0, Wobbling = false, Skrrt = false }
end

function BallPhysics.Step(state, planar: Vector3, input: Vector3, dt: number): Vector3
	local speed = planar.Magnitude
	state.Skrrt = false
	if state.Charging then
		state.Charge = math.min(1, state.Charge + dt / Ball.ChargeTime)
		return towards(planar, Vector3.zero, Ball.ChargeDrag * dt)
	end
	local pushing = input.Magnitude > 0.1
	if pushing and speed > Ball.SkrrtMin and input.Unit:Dot(planar / speed) < Ball.SkrrtDot then
		state.Skrrt = true
		return towards(planar, Vector3.zero, Ball.SkrrtDecel * dt)
	end
	if speed > Ball.MaxSpeed then
		-- a dash's extra speed bleeds off; steering still bends it
		local bent = pushing and towards(planar, input.Unit * speed, Ball.Accel * dt) or planar
		return towards(bent, bent.Unit * Ball.MaxSpeed, Ball.OverDrag * dt)
	end
	if not pushing then
		return towards(planar, Vector3.zero, Ball.Drag * dt)
	end
	local share = state.Wobbling and Ball.WobbleSteer or 1
	return towards(planar, input * Ball.MaxSpeed, Ball.Accel * share * dt)
end

-- Starts charging, if the dash is ready.
function BallPhysics.BeginCharge(state, now: number): boolean
	if now < state.DashReadyAt or state.Charging then
		return false
	end
	state.Charging = true
	state.Charge = 0
	return true
end

-- Lets the charge go: the new planar velocity, or nil if it was too small to dash.
function BallPhysics.Release(state, planar: Vector3, direction: Vector3, now: number): Vector3?
	if not state.Charging then
		return nil
	end
	state.Charging = false
	local charge = state.Charge
	state.Charge = 0
	if charge < Ball.DashMin then
		return nil
	end
	state.DashReadyAt = now + Ball.DashCooldown
	if direction.Magnitude < 0.1 then
		direction = planar.Magnitude > 0.5 and planar or Vector3.new(0, 0, -1)
	end
	local speed = Ball.DashBase + Ball.DashBonus * charge
	return Vector3.new(direction.X, 0, direction.Z).Unit * math.max(speed, planar.Magnitude)
end

-- A Turbo power-up: a full dash straight away, no charging (scale 1 is a full charge's dash).
-- Drops any charge under way; the dash cooldown is left alone.
function BallPhysics.Boost(state, planar: Vector3, direction: Vector3, scale: number): Vector3
	state.Charging = false
	state.Charge = 0
	if direction.Magnitude < 0.1 then
		direction = planar.Magnitude > 0.5 and planar or Vector3.new(0, 0, -1)
	end
	local speed = (Ball.DashBase + Ball.DashBonus) * scale
	return Vector3.new(direction.X, 0, direction.Z).Unit * math.max(speed, planar.Magnitude)
end

-- The spin that makes a ball roll at this velocity without slipping.
function BallPhysics.Spin(planar: Vector3, radius: number): Vector3
	return Vector3.yAxis:Cross(planar) / radius
end

return BallPhysics
