--!nonstrict
--[[
	The whole HUD, playing against a fake round, at desktop and phone sizes. This is the real
	HUD root (Components/Hud/BumpHud): only the round behind it is made up.

	Scenario picks a moment of a session. With Play off it holds a still of that moment; with
	Play on it runs a short loop of it.
]]

local StoryDeps = require("@Client/UIFusion/Stories/StoryDeps")
local StoryKit = require("@Client/UIFusion/Stories/StoryKit")
local FakeRound = require("@UIFusion/Kit/FakeRound")

local Fusion = StoryDeps.Fusion
local UILabs = StoryDeps.UILabs

local controls = StoryKit.Controls({
	Scenario = UILabs.Choose(FakeRound.Scenarios, 3),
	Play = UILabs.Boolean(true),
	Device = UILabs.Choose(StoryKit.DeviceNames, 1),
})

return {
	name = "HUD",
	summary = "The whole HUD on a fake round: lobby count, a game's intro card, the status bar and seats while playing, knocked out, results with gold, and the final standings.",
	fusion = Fusion,
	controls = controls,
	story = function(props)
		local round = FakeRound.new()
		local built = 0
		local asked = 0
		local function play()
			asked += 1
			local mine = asked
			task.defer(function()
				if asked == mine then
					round.Play(Fusion.peek(props.controls.Scenario), Fusion.peek(props.controls.Play))
				end
			end)
		end

		StoryKit.Stage(props, function(scope, stage)
			built += 1
			local mine = built
			local hud = scope:BumpHud({
				Source = round,
				Device = stage.Device,
				Viewport = stage.Viewport,
			})
			if built == mine then
				play()
			end
			return hud
		end)

		local scope = props.scope
		scope:Observer(props.controls.Scenario):onChange(play)
		scope:Observer(props.controls.Play):onChange(play)

		return function()
			round.Stop()
		end
	end,
}
