--!nonstrict

local require =
	require(game:GetService("ServerScriptService"):FindFirstChild("LoaderUtils", true).Parent).bootstrapStory(script)

local Jest = require("Jest")
local Moves = require(script.Parent.Moves)
local Tuning = require("@Shared/Movement/Tuning")

local describe = Jest.Globals.describe
local expect = Jest.Globals.expect
local it = Jest.Globals.it

local LongJump = Tuning.Of("LongJump")

-- A controller's state: standing still on the ground, nothing used yet, unless told otherwise.
local function view(changes)
	local v = {
		Alive = true, Move = "Run", SinceMove = 1, Speed = 0,
		CrouchHeld = false, AirJumped = false, AirDived = false, BumpReady = true,
	}
	for key, value in changes or {} do
		v[key] = value
	end
	return v
end

local function hint(fn, changes)
	local label, enabled = fn(view(changes))
	return label, enabled
end

describe("Moves", function()
	it("hides the plain jump's chip and names the special ones", function()
		local label = hint(Moves.JumpHint)
		expect(label).toBe("Jump")
		expect(Moves.HintShown("BumpJump", label)).toBe(false)
		expect((hint(Moves.JumpHint, { CrouchHeld = true }))).toBe("Backflip")
		expect((hint(Moves.JumpHint, { CrouchHeld = true, Speed = LongJump.MinSpeed }))).toBe("Long Jump")
		expect(Moves.HintShown("BumpJump", "Backflip")).toBe(true)
	end)

	it("offers the float jump once a flight", function()
		local label, enabled = hint(Moves.JumpHint, { Move = "Jump" })
		expect(label).toBe("Float Jump")
		expect(enabled).toBe(true)
		local _, again = hint(Moves.JumpHint, { Move = "Fall", AirJumped = true })
		expect(again).toBe(false)
	end)

	it("turns the buttons into wall moves on a wall", function()
		expect((hint(Moves.JumpHint, { Move = "WallCling" }))).toBe("Wall Jump")
		expect((hint(Moves.CrouchHint, { Move = "WallSlide" }))).toBe("Let Go")
		local label, enabled = hint(Moves.AttackHint, { Move = "WallCling" })
		expect(label).toBe("Dive")
		expect(enabled).toBe(false)
	end)

	it("rolls instead of shoving when crouched and moving, and waits out the shove's cooldown", function()
		expect((hint(Moves.AttackHint, { CrouchHeld = true, Speed = 10 }))).toBe("Roll")
		local label, enabled = hint(Moves.AttackHint, { BumpReady = false })
		expect(label).toBe("Bump")
		expect(enabled).toBe(false)
	end)

	it("dives once in the air and ground pounds from the air", function()
		local _, first = hint(Moves.AttackHint, { Move = "Jump" })
		local _, second = hint(Moves.AttackHint, { Move = "Jump", AirDived = true })
		expect(first).toBe(true)
		expect(second).toBe(false)
		expect((hint(Moves.CrouchHint, { Move = "Fall" }))).toBe("Ground Pound")
	end)

	it("dims everything while knocked, posing or out", function()
		for _, changes in { { Move = "Knocked" }, { Move = "Hero" }, { Alive = false } } do
			for _, fn in { Moves.JumpHint, Moves.CrouchHint, Moves.AttackHint } do
				local _, enabled = hint(fn, changes)
				expect(enabled).toBe(false)
			end
		end
	end)
end)
