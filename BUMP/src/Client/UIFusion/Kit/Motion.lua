--!nonstrict
--[[
	How the kit moves: the way the engine's input chips do. Things arrive with a slight
	overshoot, a press gives, and a value that changes pops a little bigger and settles. The
	spring presets are the engine's own (UiMotion.Springs), under the names the kit uses them
	by.

	Built on the engine's UiMotion, so the engine's reduced-motion signal (the player's setting,
	or a low frame rate) is respected: reduced, every value is simply where it is going.

	Studio drops to about 15 frames a second when its window is in the background, and the
	engine reads that as "reduce motion", so effects silently vanish in automated tests. Setting
	the ReplicatedStorage attribute Bump_ForceUiMotion to true (Studio only) ignores the
	engine's signal so they can be checked.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local UiMotion = require("@Engine/Client/UIFusion/EngineUtils/UiMotion")

local Motion = {}

local FORCE_ATTRIBUTE = "Bump_ForceUiMotion"

-- { speed, damping }.
Motion.Presets = table.freeze({
	-- A state change you caused: a slot selected, a button pressed.
	Snap = UiMotion.Springs.Press,
	-- Things arriving and leaving.
	Glide = UiMotion.Springs.Reveal,
	-- A value catching up, with no overshoot: a meter, a fade.
	Ease = UiMotion.Springs.Fade,
	-- Slow drains: the ghost of lost health.
	Drift = { 6, 1 },
	-- The pop on a number that changed.
	Pop = UiMotion.Springs.Pop,
})

local function forced(): boolean
	return RunService:IsStudio() and ReplicatedStorage:GetAttribute(FORCE_ATTRIBUTE) == true
end

-- A reactive "should this stop animating" flag for one component.
function Motion.Reduced(scope, props)
	local explicit = type(props) == "table" and props.ReduceMotion or nil
	return scope:Computed(function(use)
		if UiMotion.ReadBoolean(scope, use, explicit) then
			return true
		end
		if forced() then
			return false
		end
		return UiMotion.ReadBoolean(scope, use, scope.MenuReduceMotion)
	end)
end

-- `goal` (a state) eased with a preset; the bare goal while reduced.
function Motion.Spring(scope, goal, preset, reduced)
	return UiMotion.Spring(scope, goal, preset or Motion.Presets.Glide, reduced)
end

-- 0 or 1 from a boolean state, eased: the usual driver for showing and hiding.
function Motion.Shown(scope, shown, preset, reduced)
	return Motion.Spring(scope, scope:Computed(function(use)
		return if use(shown) then 1 else 0
	end), preset or Motion.Presets.Glide, reduced)
end

--[[
	A value that rests at 0, jumps to 1 when fired and eases back: the flash on a number that
	changed, a meter that took a hit. Returns { Value = state, Fire = function(amount?) }.
]]
function Motion.Flash(scope, reduced, preset)
	local kick = UiMotion.Kick(scope, reduced, preset or Motion.Presets.Ease)
	return {
		Value = kick.Value,
		Fire = function(amount: number?)
			kick.Pop(amount or 1)
		end,
	}
end

--[[
	A scale that rests at 1 and swells when fired, settling back through a small overshoot: the
	chips' echo. Returns { Scale = state, Fire = function(amount?) }; put Scale on a UIScale.
]]
function Motion.Pop(scope, reduced)
	local kick = UiMotion.Kick(scope, reduced, Motion.Presets.Pop)
	return {
		Scale = scope:Computed(function(use)
			return 1 + use(kick.Value)
		end),
		Fire = function(amount: number?)
			kick.Pop(amount or 0.1)
		end,
	}
end

-- Blend two numbers by a 0..1 share.
function Motion.Mix(a: number, b: number, share: number): number
	return a + (b - a) * share
end

return Motion
