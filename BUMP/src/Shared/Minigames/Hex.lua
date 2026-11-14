--!nonstrict
--[[
	A flat-topped hex grid in axial coordinates (q, r). Ring 0 is the centre tile; ring n has 6n
	tiles. A tile is three boxes of size (R, h, R*sqrt3) turned 0, 60 and 120 degrees, which
	together make a regular hexagon of corner radius R with no mesh.
]]

local Hex = {}

local SQRT3 = math.sqrt(3)
local DIRECTIONS = { { 1, 0 }, { 1, -1 }, { 0, -1 }, { -1, 0 }, { -1, 1 }, { 0, 1 } }

function Hex.Ring(q: number, r: number): number
	return (math.abs(q) + math.abs(r) + math.abs(q + r)) // 2
end

-- Every tile out to `rings`, as { q, r, ring }.
function Hex.Tiles(rings: number)
	local tiles = {}
	for q = -rings, rings do
		for r = math.max(-rings, -q - rings), math.min(rings, -q + rings) do
			table.insert(tiles, { q = q, r = r, ring = Hex.Ring(q, r) })
		end
	end
	return tiles
end

-- A tile's centre on the ground plane, for corner radius R.
function Hex.Position(q: number, r: number, R: number): Vector3
	return Vector3.new(R * 1.5 * q, 0, R * SQRT3 * (r + q / 2))
end

-- The tile a ground-plane point (relative to the grid's centre) is on: axial q, r, rounded.
function Hex.FromPosition(x: number, z: number, R: number): (number, number)
	local fq = (2 / 3) * x / R
	local fr = z / (SQRT3 * R) - fq / 2
	-- round in cube coordinates so the nearest tile wins
	local fs = -fq - fr
	local q, r, s = math.round(fq), math.round(fr), math.round(fs)
	local dq, dr, ds = math.abs(q - fq), math.abs(r - fr), math.abs(s - fs)
	if dq > dr and dq > ds then
		q = -r - s
	elseif dr > ds then
		r = -q - s
	end
	return q, r
end

-- The six tiles touching (q, r).
function Hex.Neighbours(q: number, r: number): { { number } }
	local list = {}
	for _, direction in DIRECTIONS do
		table.insert(list, { q + direction[1], r + direction[2] })
	end
	return list
end

function Hex.Key(q: number, r: number): string
	return q .. "," .. r
end

-- How far a ring's outer edge reaches from the centre (the flat side, the near edge).
function Hex.Reach(rings: number, R: number): number
	return (rings + 0.5) * R * SQRT3
end

-- Evenly spread points on ring `ring`, `count` of them.
function Hex.Spread(ring: number, count: number, R: number): { Vector3 }
	local points = {}
	if ring == 0 then
		points[1] = Vector3.zero
		return points
	end
	local cells = {}
	local q, r = DIRECTIONS[5][1] * ring, DIRECTIONS[5][2] * ring
	for side = 1, 6 do
		for _ = 1, ring do
			table.insert(cells, { q, r })
			q += DIRECTIONS[side][1]
			r += DIRECTIONS[side][2]
		end
	end
	for index = 1, count do
		local cell = cells[math.floor((index - 1) * #cells / count) + 1]
		table.insert(points, Hex.Position(cell[1], cell[2], R))
	end
	return points
end

-- Builds one tile as a Model of three boxes, centred on `cframe`.
-- A hex tile of three slabs. With `edge`, the slabs are that colour and a darker top sits
-- inset on them, so the tile reads as a coloured outline (once Neon; the user found the
-- glowing floor drowned out the players).
function Hex.BuildTile(R: number, height: number, cframe: CFrame, color: Color3, material: Enum.Material?, edge: Color3?): Model
	local model = Instance.new("Model")
	if edge then
		for index = 0, 2 do
			local glow = Instance.new("Part")
			glow.Name = "Edge" .. index
			glow.Anchored = true
			glow.Size = Vector3.new(R, height, R * SQRT3)
			glow.CFrame = cframe * CFrame.Angles(0, math.rad(60 * index), 0)
			glow.Color = edge
			glow.Material = Enum.Material.SmoothPlastic -- coloured, not glowing: players come first
			glow.TopSurface = Enum.SurfaceType.Smooth
			glow.BottomSurface = Enum.SurfaceType.Smooth
			glow.Parent = model
		end
		-- a thin outline: the floor shouldn't outshine the players on it
		R *= 0.9
		cframe += Vector3.new(0, 0.06, 0)
	end
	for index = 0, 2 do
		local part = Instance.new("Part")
		part.Name = "Slab" .. index
		part.Anchored = true
		part.Size = Vector3.new(R, height, R * SQRT3)
		part.CFrame = cframe * CFrame.Angles(0, math.rad(60 * index), 0)
		part.Color = color
		part.Material = material or Enum.Material.SmoothPlastic
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Parent = model
	end
	model.PrimaryPart = model:FindFirstChild("Slab0")
	return model
end

return Hex
