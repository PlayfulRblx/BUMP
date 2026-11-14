--!nonstrict
--[[
	The hex-tile platform the minigames play on (BUMP, Bomber Bloxians), in the lobby's pit
	(World.ArenaOrigin): rings of hexagonal cells round a centre cell, and the floor's
	bookkeeping, cell by cell. The knocked out go back to the plaza and watch from there.

	    local arena = HexArena.new({ Origin = Vector3, Rings = 7, Tile = 7, Colors = { [ring] = Color3 }, Edges = { [ring] = Color3 } })
	    -- with Edges, each tile is a dark top on a neon outline in its ring's edge colour
	    arena:FloorAt(position)        -- floor there that will stay? (a warning cell counts as gone)
	    arena:DropCell(cell, warn)     -- shake and flash for `warn` seconds, then fall
	    arena:Crater(position, radius, warn)   -- every cell within radius
	    arena:SafeSpot(from)           -- the nearest floor that isn't on the edge
	    arena:StandSpot()              -- a spot on the lobby plaza, facing the platform
	    arena:Destroy()

	Cells are { model, q, r, ring, state = "Solid" | "Warning" | "Gone" }, keyed by Hex.Key(q, r).
	A falling cell's model carries the attribute "Falling", so clients leave it alone (ripples).
]]

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Hex = require("@Shared/Minigames/Hex")
local World = require("@Shared/World")

local HexArena = {}
HexArena.__index = HexArena

local TILE_HEIGHT = 2.5
local WARN_COLOR = Color3.fromRGB(255, 70, 70)

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

function HexArena.new(options)
	local self = setmetatable({}, HexArena)
	self.Origin = options.Origin
	self.Rings = options.Rings
	self.Tile = options.Tile
	self.cells = {}
	self.cellCount = 0
	local colors = options.Colors
	local edges = options.Edges

	local folder = Instance.new("Folder")
	folder.Name = options.Name or "BumpArena"
	for _, tile in Hex.Tiles(self.Rings) do
		local position = self.Origin + Hex.Position(tile.q, tile.r, self.Tile) - Vector3.new(0, TILE_HEIGHT / 2, 0)
		local color = colors[tile.ring] or colors[#colors]
		-- every other tile a shade lighter, a checker you can read speed against
		if (tile.q + tile.r * 2) % 2 == 0 then
			color = color:Lerp(Color3.new(1, 1, 1), 0.18)
		end
		local edge = edges and (edges[tile.ring] or edges[#edges]) or nil
		local model = Hex.BuildTile(self.Tile * 0.97, TILE_HEIGHT, CFrame.new(position), color, nil, edge)
		model.Name = string.format("Tile_%d_%d", tile.q, tile.r)
		model:SetAttribute("Ring", tile.ring)
		model.Parent = folder
		self.cells[Hex.Key(tile.q, tile.r)] = { model = model, q = tile.q, r = tile.r, ring = tile.ring, state = "Solid" }
		self.cellCount += 1
	end

	-- every client plays the arena's build-in show when this appears (Client/Systems/ArenaShow)
	folder:SetAttribute("HexArena", true)
	folder.Parent = Workspace
	self.folder = folder
	return self
end

function HexArena:CellAt(position: Vector3)
	local q, r = Hex.FromPosition(position.X - self.Origin.X, position.Z - self.Origin.Z, self.Tile)
	return self.cells[Hex.Key(q, r)]
end

function HexArena:FloorAt(position: Vector3): boolean
	local cell = self:CellAt(position)
	return cell ~= nil and cell.state == "Solid"
end

function HexArena:IsEdge(cell): boolean
	for _, neighbour in Hex.Neighbours(cell.q, cell.r) do
		local other = self.cells[Hex.Key(neighbour[1], neighbour[2])]
		if not other or other.state ~= "Solid" then
			return true
		end
	end
	return false
end

function HexArena:SolidCells()
	local list = {}
	for _, cell in self.cells do
		if cell.state == "Solid" then
			table.insert(list, cell)
		end
	end
	return list
end

-- Shake and flash for `warn` seconds (faster at the end), then fall.
function HexArena:DropCell(cell, warn: number)
	if cell.state ~= "Solid" then
		return
	end
	cell.state = "Warning"
	local model = cell.model
	model:SetAttribute("Falling", true)
	local shakeUntil = os.clock() + warn
	task.spawn(function()
		local flip = false
		while os.clock() < shakeUntil and model.Parent do
			flip = not flip
			for _, part in model:GetChildren() do
				if part:IsA("BasePart") then
					local base = part:GetAttribute("BaseColor") or part.Color
					part:SetAttribute("BaseColor", base)
					part.Color = flip and WARN_COLOR or base
					part:SetAttribute("BaseCFrame", part:GetAttribute("BaseCFrame") or part.CFrame)
					local jitter = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * 0.35
					part.CFrame = part:GetAttribute("BaseCFrame") + jitter
				end
			end
			task.wait(shakeUntil - os.clock() < 0.8 and 0.06 or 0.14)
		end
		cell.state = "Gone"
		for _, part in model:GetChildren() do
			if part:IsA("BasePart") then
				part.Color = WARN_COLOR
				part.Anchored = false
				part.AssemblyLinearVelocity = Vector3.new(0, -8, 0)
				part.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * 2
				TweenService:Create(part, TweenInfo.new(1.5), { Transparency = 1 }):Play()
			end
		end
		Debris:AddItem(model, 2)
	end)
end

-- Drops every cell whose centre is within `radius` of `position`; how many it dropped.
function HexArena:Crater(position: Vector3, radius: number, warn: number): number
	local count = 0
	for _, cell in self.cells do
		if cell.state == "Solid" then
			local centre = cell.model:GetPivot().Position
			if flat(centre - position).Magnitude <= radius then
				self:DropCell(cell, warn)
				count += 1
			end
		end
	end
	return count
end

-- The nearest floor that isn't on the edge (or any floor, failing that).
function HexArena:SafeSpot(from: Vector3): Vector3
	local best, bestDistance = nil, math.huge
	local fallback, fallbackDistance = nil, math.huge
	for _, cell in self.cells do
		if cell.state == "Solid" then
			local centre = cell.model:GetPivot().Position
			local distance = flat(centre - from).Magnitude
			if distance < fallbackDistance then
				fallback, fallbackDistance = centre, distance
			end
			if distance < bestDistance and not self:IsEdge(cell) then
				best, bestDistance = centre, distance
			end
		end
	end
	return best or fallback or self.Origin
end

function HexArena:StandSpot(): CFrame
	return World.LobbySpot()
end

-- Leaving: clients fly the tiles away (ArenaShow), so it lingers a moment before it goes. It stops
-- being solid at once and takes a different name, so the next arena's lookups never find it.
local LEAVE_SECONDS = 1.6
HexArena.LeaveSeconds = LEAVE_SECONDS

-- How long the clients' build-in show takes for an arena of `rings` rings (keep in step with
-- Client/Systems/ArenaShow: a ring every 0.2 s, a 0.16 s sweep, a 0.42 s fall and a 0.2 s
-- bounce), plus a breath for the finale.
function HexArena.ShowSeconds(rings: number): number
	return rings * 0.2 + 0.16 + 0.42 + 0.2 + 0.6
end

function HexArena:Destroy()
	local folder = self.folder
	for _, part in folder:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
		end
	end
	folder.Name = folder.Name .. "_Leaving"
	folder:SetAttribute("Leaving", true)
	task.delay(LEAVE_SECONDS, function()
		folder:Destroy()
	end)
end

return HexArena
