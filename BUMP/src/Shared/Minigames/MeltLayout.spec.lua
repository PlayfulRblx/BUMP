--!nonstrict

local require =
	require(game:GetService("ServerScriptService"):FindFirstChild("LoaderUtils", true).Parent).bootstrapStory(script)

local Jest = require("Jest")
local MeltLayout = require(script.Parent.MeltLayout)

local describe = Jest.Globals.describe
local expect = Jest.Globals.expect
local it = Jest.Globals.it

local OPTIONS = { Tiers = 14, TierGap = 7.5, BaseInner = 52, BaseOuter = 82, BounceHeight = 26, PitDrop = 10 }

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

describe("MeltLayout", function()
	it("builds a tower whose summit can be reached from the base, seed after seed", function()
		for seed = 1, 25 do
			local layout = MeltLayout.Build(seed, OPTIONS)
			expect(MeltLayout.SummitReachable(layout)).toBe(true)
			expect(#layout.StartLinks > 0).toBe(true)
			expect(layout.Platforms[layout.Summit].Kind).toBe("Summit")
		end
	end)

	it("keeps the tower inside the start ring and the start ring inside the pit", function()
		for seed = 1, 10 do
			local layout = MeltLayout.Build(seed, OPTIONS)
			for _, platform in layout.Platforms do
				local reach = flat(platform.Position).Magnitude + platform.Size + (platform.Mover and platform.Mover.Amp or 0)
				expect(reach < 60).toBe(true)
				if platform.Position.Y < 9.5 then
					-- low enough to hit your head on from the base: clear of its tiles' corners
					expect(reach < OPTIONS.BaseInner - MeltLayout.BaseTile * 0.5 - 1).toBe(true)
				end
			end
			for _, tile in layout.Pit do
				-- the pit floor is clear of the first tier's underside by a float jump
				expect(OPTIONS.TierGap + OPTIONS.PitDrop >= MeltLayout.HeadClear).toBe(true)
				expect(tile.Y).toBe(-OPTIONS.PitDrop)
			end
			for _, tile in layout.Base do
				expect(tile.Magnitude - MeltLayout.BaseTile * 0.5 >= OPTIONS.BaseInner).toBe(true)
				expect(tile.Magnitude + MeltLayout.BaseTile < 100).toBe(true) -- the pit's wall
			end
		end
	end)

	it("never puts a platform within a float jump over another one's head", function()
		for seed = 1, 10 do
			local layout = MeltLayout.Build(seed, OPTIONS)
			for _, a in layout.Platforms do
				for _, b in layout.Platforms do
					local dy = math.abs(a.Position.Y - b.Position.Y)
					if a ~= b and dy > 0.5 and dy < MeltLayout.HeadClear and not a.Mover and not b.Mover then
						expect(flat(a.Position - b.Position).Magnitude >= a.Size + b.Size + MeltLayout.HeadMargin - 1e-6).toBe(true)
					end
				end
			end
		end
	end)

	it("links only jumps a bot can make, and pads and chimneys to their targets", function()
		local layout = MeltLayout.Build(3, OPTIONS)
		for _, platform in layout.Platforms do
			for _, edge in platform.Links do
				local to = layout.Platforms[edge.To]
				expect(to ~= nil).toBe(true)
				if edge.Kind == "Jump" then
					expect(MeltLayout.CanJump(platform, to)).toBe(true)
				elseif edge.Kind == "Pad" then
					expect(platform.Pad.To).toBe(edge.To)
				end
			end
		end
	end)

	it("is the same tower from the same seed", function()
		local a, b = MeltLayout.Build(11, OPTIONS), MeltLayout.Build(11, OPTIONS)
		local count = 0
		for id, platform in a.Platforms do
			count += 1
			expect((platform.Position - b.Platforms[id].Position).Magnitude < 1e-6).toBe(true)
		end
		expect(count > 30).toBe(true)
	end)

	it("moves a mover back and forth along its axis, round in its period", function()
		local mover = { Axis = Vector3.new(1, 0, 0), Amp = 5, Period = 4, Phase = 0.3 }
		for _, t in { 0, 0.7, 2.2, 3.9 } do
			local now, later = MeltLayout.MoverOffset(mover, t), MeltLayout.MoverOffset(mover, t + mover.Period)
			expect((now - later).Magnitude < 1e-6).toBe(true)
			expect(now.Magnitude <= 5 + 1e-6).toBe(true)
			expect(math.abs(now.Y) + math.abs(now.Z) < 1e-9).toBe(true)
		end
		-- the velocity is the offset's rate of change
		local dt = 1e-4
		local numeric = (MeltLayout.MoverOffset(mover, 1 + dt) - MeltLayout.MoverOffset(mover, 1)) / dt
		expect((numeric - MeltLayout.MoverVelocity(mover, 1)).Magnitude < 1e-2).toBe(true)
	end)
end)
