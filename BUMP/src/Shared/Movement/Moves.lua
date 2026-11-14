--!nonstrict
--[[
	Which moves are which, and what each button would do from a move: the part of the platformer
	(Client/Systems/Platformer) that needs no body, so it can be read and tested on its own.

	The input chips (the engine's key hints) are labelled with what the button would do right now
	("Float Jump", "Backflip", "Ground Pound", "Roll"...) and dimmed when it would do nothing. Each
	hint takes a view of the controller's state:

	    { Alive, Move, SinceMove, Speed (horizontal), CrouchHeld, AirJumped, AirDived, BumpReady }

	and returns (label, enabled).
]]

local Tuning = require("@Shared/Movement/Tuning")

local Pound = Tuning.Of("Pound")
local LongJump = Tuning.Of("LongJump")

local Moves = {}

-- Moves that are on the ground. Everything else is in the air.
Moves.Ground = table.freeze({
	Run = true, Crouch = true, PoundLand = true, Slide = true, Roll = true, LandRoll = true, Bump = true, Bonk = true,
	Hero = true,
})

-- Moves you can't act out of until they end.
Moves.Locked = table.freeze({ Knocked = true, Bonk = true, Shoved = true, Hero = true })

-- Moves you can float-jump out of (once per flight).
Moves.AirJumpFrom = table.freeze({
	Jump = true, Fall = true, Backflip = true, LongJump = true, WallJump = true, Rollout = true, PoundJump = true,
})

-- How fast you have to be going for crouch + attack to be a roll rather than a shove.
local ROLL_SPEED = 4

function Moves.JumpHint(view): (string, boolean)
	local move = view.Move
	if not view.Alive or Moves.Locked[move] then
		return "Jump", false
	end
	if move == "WallCling" or move == "WallSlide" then
		return "Wall Jump", true
	end
	if move == "PoundLand" then
		return "High Jump", view.SinceMove <= Pound.JumpWindow
	end
	if move == "Slide" then
		return "Hop Out", true
	end
	if move == "Roll" or move == "LandRoll" then
		return "Long Jump", true
	end
	if move == "Run" or move == "Crouch" then
		if view.CrouchHeld then
			return view.Speed >= LongJump.MinSpeed and "Long Jump" or "Backflip", true
		end
		return "Jump", true
	end
	if Moves.AirJumpFrom[move] then
		return "Float Jump", not view.AirJumped
	end
	return "Jump", false
end

function Moves.CrouchHint(view): (string, boolean)
	local move = view.Move
	if not view.Alive or Moves.Locked[move] then
		return "Crouch", false
	end
	if move == "WallCling" or move == "WallSlide" then
		return "Let Go", true
	end
	if Moves.Ground[move] then
		return "Crouch", move == "Run" or move == "Crouch"
	end
	if move == "PoundSpin" or move == "PoundFall" or move == "Dive" then
		return "Ground Pound", false
	end
	return "Ground Pound", true
end

function Moves.AttackHint(view): (string, boolean)
	local move = view.Move
	if not view.Alive or Moves.Locked[move] then
		return "Bump", false
	end
	if Moves.Ground[move] then
		if move == "Run" or move == "Crouch" then
			if view.CrouchHeld and view.Speed > ROLL_SPEED then
				return "Roll", true
			end
			return "Bump", view.BumpReady
		end
		return "Bump", false
	end
	if move == "WallCling" or move == "WallSlide" then
		return "Dive", false
	end
	return "Dive", not view.AirDived
end

-- By button id (Platformer's bindings).
Moves.Hints = table.freeze({ BumpJump = Moves.JumpHint, BumpCrouch = Moves.CrouchHint, BumpAttack = Moves.AttackHint })

-- A plain jump needs no chip (the user, 2026-11-13: "we don't need a hint for Jump"); the jump
-- chip shows only when Space does something special: Float Jump, Backflip, Wall Jump...
function Moves.HintShown(id: string, label: string): boolean
	return not (id == "BumpJump" and label == "Jump")
end

return Moves
