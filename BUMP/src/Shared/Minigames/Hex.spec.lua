--!nonstrict

local require =
	require(game:GetService("ServerScriptService"):FindFirstChild("LoaderUtils", true).Parent).bootstrapStory(script)

local Jest = require("Jest")
local Hex = require(script.Parent.Hex)

local describe = Jest.Globals.describe
local expect = Jest.Globals.expect
local it = Jest.Globals.it

describe("Hex", function()
	it("lays out 1 + 3n(n+1) tiles out to ring n, 6n on ring n", function()
		expect(#Hex.Tiles(0)).toBe(1)
		expect(#Hex.Tiles(7)).toBe(169) -- BUMP's arena
		expect(#Hex.Tiles(6)).toBe(127) -- Bomber's
		local onRing = {}
		for _, tile in Hex.Tiles(5) do
			onRing[tile.ring] = (onRing[tile.ring] or 0) + 1
		end
		for ring = 1, 5 do
			expect(onRing[ring]).toBe(6 * ring)
		end
	end)

	it("finds every tile again from its own centre, and from near its edge", function()
		local R = 7
		for _, tile in Hex.Tiles(7) do
			local centre = Hex.Position(tile.q, tile.r, R)
			local q, r = Hex.FromPosition(centre.X, centre.Z, R)
			expect(q).toBe(tile.q)
			expect(r).toBe(tile.r)
			-- most of the way to a corner is still the same tile
			local q2, r2 = Hex.FromPosition(centre.X + R * 0.8, centre.Z, R)
			expect(q2).toBe(tile.q)
			expect(r2).toBe(tile.r)
		end
	end)

	it("gives six different neighbours, each one step away", function()
		local seen = {}
		for _, n in Hex.Neighbours(2, -1) do
			local key = Hex.Key(n[1], n[2])
			expect(seen[key]).toBe(nil)
			seen[key] = true
			expect(Hex.Ring(n[1] - 2, n[2] + 1)).toBe(1)
		end
	end)

	it("names a tile the same from just either side of zero (no \"-0\")", function()
		local R = 7
		local q1, r1 = Hex.FromPosition(-0.3, 0.2, R)
		local q2, r2 = Hex.FromPosition(0.3, -0.2, R)
		expect(Hex.Key(q1, r1)).toBe("0,0")
		expect(Hex.Key(q2, r2)).toBe("0,0")
		local q3, r3 = Hex.FromPosition(-0.2, 36, R)
		expect(Hex.Key(q3, r3)).toBe(Hex.Key(0, 3))
	end)

	it("keys tiles uniquely", function()
		local keys = {}
		for _, tile in Hex.Tiles(7) do
			local key = Hex.Key(tile.q, tile.r)
			expect(keys[key]).toBe(nil)
			keys[key] = true
		end
	end)
end)
